#!/usr/bin/env python3
"""Context gate (CONTEXT-WINDOW-CONTROL.md): nag to wrap up + /compact before the
harness compacts on its own, so open threads and state get noted before they vanish.

Wired as PostToolUse (all tools) + UserPromptSubmit. Reads the session transcript's
last assistant usage record; context = input + cache_read + cache_creation tokens.

Adapted from an internal PersonalAssistant hook of the same shape — the settings-
precedence handling (autoCompactWindow, PCT_OVERRIDE, the 1m-context clamp) and the
post-compaction stale-record guard are genuine Claude Code platform mechanics, kept
here because dropping them reintroduces bugs that were found the hard way. The parts
that are generalized: the reserve is "cost of wrapping up and noting state" rather
than a specific internal skill, and there is no fixed multi-step logging protocol to
point at — say what CONTEXT-WINDOW-CONTROL.md itself says: finish the atomic step,
summarize state, then /compact or start fresh.

Thresholds are set back from the COMPACTION POINT, then capped at absolute hygiene
ceilings:

    compact_at = min(model window, autoCompactWindow) * PCT_OVERRIDE/100
    hard       = min(HARD_ABS, max(compact_at * HARD_FRAC, compact_at - WRAP_RESERVE))
    warn       = min(WARN_ABS, max(compact_at * WARN_FRAC, hard - WARN_LEAD))

Compaction itself is survivable — a compacted session continues fine. Compaction
BEFORE state is noted is not, because open decisions never reach anywhere durable.
COMPACT_AT IS NOT THE MODEL WINDOW, AND NOT autoCompactWindow EITHER — several
independent harness inputs move the point where compaction really happens; see the
audit checklist in autocompact_window() before adding or trusting any new threshold.

Rate limiting: state file per session under .agent/tmp/. Re-fires on band entry,
then every +25k tokens in WARN band, every +5k in HARD band. Silent below WARN.
"""
import json
import os
import sys

WARN_FRAC = 0.50
HARD_FRAC = 0.60

# WRAP_RESERVE: headroom reserved so wrapping up a session (finishing the current
# step, writing down what's done/next/open) can complete before the harness
# compacts out from under it. 100k is a generous margin for a substantial wrap-up;
# a light session leaves far more. Do not cut this toward a tighter measurement —
# the margin is the feature, because near the ceiling a single large file read can
# spend it and lose the session's open state.
WRAP_RESERVE = 100_000
WARN_LEAD = 100_000

# ABSOLUTE CEILINGS — hygiene thresholds, not survival ones. The reserve rule above
# answers "how late can the gate fire and still let a wrap-up finish?" These answer
# a different question: "when should this session be recycled to keep reasoning
# sharp?" A 600k session reasons better than a 900k one, so the gate fires at a
# fixed point rather than scaling with the window. They CAP the computed values and
# never raise them — min(), not a plain override, so a small-window floor (e.g.
# Haiku 4.5 at 200k) survives intact rather than being pushed past its own ceiling.
WARN_ABS = 450_000
HARD_ABS = 600_000

# Reminder cadence, in absolute tokens rather than a fraction of the window, so a
# 1m session gets reminded as often per token as a 600k one.
WARN_STEP = 25_000
HARD_STEP = 5_000

# Fallback when the model is unknown/unlisted. Add a row below with recorded
# provenance (verified /context output, or the published model catalog) rather
# than guessing — a guessed window is exactly the bug class this file exists to
# prevent (a 200k guess against a real 1m model hard-blocks 5x too early).
DEFAULT_WINDOW = 1_000_000
MODEL_WINDOWS = {
    "claude-opus-5": 1_000_000,
    "claude-fable-5": 1_000_000,
    "claude-sonnet-5": 600_000,
    "claude-opus-4-8": 1_000_000,
    "claude-haiku-4-5": 200_000,  # the one current model below autoCompactWindow —
                                  # the model window, not the setting, is the cap
}
# settings.json lookup order — Claude Code precedence: project-local, project, user.
SETTINGS_RELPATHS = (
    (".claude", "settings.local.json"),
    (".claude", "settings.json"),
)
TAIL_BYTES = 262_144


def window_for(model):
    """Context window for a model id, defaulting conservatively."""
    if not model:
        return DEFAULT_WINDOW
    if "[1m]" in model:
        return 1_000_000
    if model in MODEL_WINDOWS:
        return MODEL_WINDOWS[model]
    for prefix, size in MODEL_WINDOWS.items():
        if model.startswith(prefix):
            return size
    return DEFAULT_WINDOW


def _fmt(tokens):
    """Token count as a short window label: 600000 -> '600k', 1000000 -> '1m'."""
    if tokens >= 1_000_000 and tokens % 1_000_000 == 0:
        return f"{tokens // 1_000_000}m"
    return f"{tokens // 1000}k"


def _settings_files(project_dir):
    """Settings paths in Claude Code precedence order, highest first."""
    paths = [os.path.join(project_dir, *rel) for rel in SETTINGS_RELPATHS]
    paths.append(os.path.join(os.path.expanduser("~"), ".claude", "settings.json"))
    return paths


def _from_settings(project_dir, key, parse, env_key=None, env_parse=None):
    """First accepted value, env var first then settings files.

    `key=None` means there is no settings-file key at all (env-only inputs).
    `parse` reads a JSON-typed settings value; `env_parse` reads a string from the
    environment — kept separate because the harness rejects a stringified number
    in a settings file even though it accepts one from the environment. Env blocks
    inside settings files are also checked, so a value declared but not exported is
    still honoured. Any unreadable or malformed file is skipped, never raised —
    this hook runs on every tool call and a traceback degrades the harness.
    """
    env_parse = env_parse or parse
    if env_key:
        accepted = env_parse(os.environ.get(env_key))
        if accepted is not None:
            return accepted
    for path in _settings_files(project_dir):
        try:
            with open(path) as f:
                settings = json.load(f)
        except (OSError, json.JSONDecodeError, ValueError):
            continue
        if not isinstance(settings, dict):
            continue
        if key is not None:
            accepted = parse(settings.get(key))
            if accepted is not None:
                return accepted
        if env_key:
            env_block = settings.get("env")
            if isinstance(env_block, dict):
                accepted = env_parse(env_block.get(env_key))
                if accepted is not None:
                    return accepted
    return None


# autoCompactWindow is documented as "in tokens from 100000 to 1000000". Enforcing
# only `> 0` lets a dropped zero-group (`600` for `600000`) collapse hard/warn to 0,
# firing HARD on every tool call for the life of the session. Out-of-range falls
# back to the model window instead.
WINDOW_MIN = 100_000
WINDOW_MAX = 1_000_000


def _window_setting(raw):
    """autoCompactWindow from a settings file: a real int, in the documented range."""
    if isinstance(raw, bool) or not isinstance(raw, int):
        return None
    return raw if WINDOW_MIN <= raw <= WINDOW_MAX else None


def _window_env(raw):
    """CLAUDE_CODE_AUTO_COMPACT_WINDOW: a plain token count, same range."""
    if raw is None or isinstance(raw, bool):
        return None
    try:
        value = int(str(raw).strip())
    except (TypeError, ValueError):
        return None
    return value if WINDOW_MIN <= value <= WINDOW_MAX else None


def _bool_env(raw):
    """Documented harness boolean: 1/true on, 0/false off, any casing.

    Returns True, False, or None for "not set / unrecognised" — the three states
    must stay distinct, since collapsing False into None would let a
    lower-precedence "1" override a higher-precedence "0".
    """
    if raw is None:
        return None
    value = str(raw).strip().lower()
    if value in ("1", "true"):
        return True
    if value in ("0", "false"):
        return False
    return None


def autocompact_window(project_dir):
    """The autoCompact ceiling, or None when unset/unreadable.

    Env var FIRST: CLAUDE_CODE_AUTO_COMPACT_WINDOW takes precedence over the
    command, the flag, and the setting, and is the documented knob for scripts and
    headless environments.

    ┌─ AUDIT CHECKLIST — inputs to the harness's compaction decision ──────────────┐
    │ READ   settings.autoCompactWindow ......... every file, precedence order      │
    │ READ   CLAUDE_CODE_AUTO_COMPACT_WINDOW .... env, wins over the setting        │
    │ READ   CLAUDE_AUTOCOMPACT_PCT_OVERRIDE .... see autocompact_pct()             │
    │ READ   CLAUDE_CODE_DISABLE_1M_CONTEXT ..... clamps 1m models to 200k          │
    │ UNREAD CLAUDE_CODE_MAX_CONTEXT_TOKENS ..... declares the window for gateway / │
    │        ...................................  custom model ids; overrides the   │
    │        ...................................  quantity window_for() guesses     │
    │ UNREAD DISABLE_COMPACT .................... kills compaction entirely, so     │
    │        ...................................  "before the harness compacts" is  │
    │        ...................................  FALSE and the session hits a      │
    │        ...................................  context-limit error instead       │
    │ UNREAD platform: Bedrock / Vertex / Foundry  200K window, compacts at 200K —  │
    │        ...................................  the 1m MODEL_WINDOWS rows are     │
    │        ...................................  wrong there — silent to 450k      │
    │ UNREAD ANTHROPIC_BASE_URL at a gateway .... may budget a model below its      │
    │        ...................................  normal window                     │
    │ UNREAD --autocompact CLI flag ............. not visible from a hook           │
    └──────────────────────────────────────────────────────────────────────────────┘
    Adding a row here when a new input is found is not optional — every silent-gate
    failure this class of hook has had came from an input nobody read.
    """
    return _from_settings(
        project_dir,
        "autoCompactWindow",
        _window_setting,
        env_key="CLAUDE_CODE_AUTO_COMPACT_WINDOW",
        env_parse=_window_env,
    )


def one_m_context_disabled(project_dir):
    """True when CLAUDE_CODE_DISABLE_1M_CONTEXT holds 1m-native models to 200k."""
    return _from_settings(
        project_dir,
        None,
        _bool_env,
        env_key="CLAUDE_CODE_DISABLE_1M_CONTEXT",
    ) is True


def autocompact_pct(project_dir):
    """CLAUDE_AUTOCOMPACT_PCT_OVERRIDE as an int 1-100, or None when unset/invalid.

    This is a percentage OF autoCompactWindow, not of the model window, so the
    point where the harness actually compacts is window * pct/100 — every
    threshold below is set back from THAT, not from the raw window.

    This variable cannot RAISE a threshold: values above the model's own default
    percentage are ignored by the harness, so a read of 100 does not guarantee
    compaction at exactly 100% of the window.
    """
    def _pct(raw):
        if isinstance(raw, bool):
            return None
        try:
            pct = int(str(raw).strip())
        except (TypeError, ValueError):
            return None
        return pct if 1 <= pct <= 100 else None

    return _from_settings(
        project_dir,
        None,
        _pct,
        env_key="CLAUDE_AUTOCOMPACT_PCT_OVERRIDE",
    )


def read_context_tokens(transcript_path):
    """Newest usage record, or (None, None) when the newest one predates a compaction.

    Compaction resets the live context but writes no usage record of its own, so
    for the first prompt after /compact the newest record in the transcript is the
    LAST PRE-COMPACT turn. Reporting it reads as live and is wildly inflated. The
    reverse scan therefore stops at the compaction boundary and stays silent rather
    than quoting a dead number; the next assistant turn writes a real record that
    shadows the marker.
    """
    size = os.path.getsize(transcript_path)
    with open(transcript_path, "rb") as f:
        f.seek(max(0, size - TAIL_BYTES))
        tail = f.read().decode("utf-8", "replace")
    for line in reversed(tail.splitlines()):
        if '"isCompactSummary":true' in line or '"compactMetadata"' in line:
            return None, None
        if '"cache_read_input_tokens"' not in line:
            continue
        try:
            rec = json.loads(line)
        except json.JSONDecodeError:
            continue
        message = rec.get("message") or {}
        usage = message.get("usage") or {}
        if "input_tokens" in usage:
            ctx = (
                (usage.get("input_tokens") or 0)
                + (usage.get("cache_read_input_tokens") or 0)
                + (usage.get("cache_creation_input_tokens") or 0)
            )
            return ctx, message.get("model")
    return None, None


def main():
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return
    transcript = data.get("transcript_path") or ""
    session_id = data.get("session_id") or "unknown"
    event = data.get("hook_event_name") or "PostToolUse"
    if not transcript or not os.path.isfile(transcript):
        return
    ctx, model = read_context_tokens(transcript)
    if ctx is None:
        return
    project_dir = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    native_window = window_for(model)
    one_m_off = one_m_context_disabled(project_dir) and native_window > 200_000
    model_window = 200_000 if one_m_off else native_window
    cap = autocompact_window(project_dir)
    window = min(model_window, cap) if cap else model_window
    pct_override = autocompact_pct(project_dir)
    compact_at = max(1, int(window * pct_override / 100)) if pct_override else window
    hard = min(HARD_ABS, max(int(compact_at * HARD_FRAC), compact_at - WRAP_RESERVE))
    warn = min(WARN_ABS, max(int(compact_at * WARN_FRAC), hard - WARN_LEAD))
    warn = max(0, min(warn, hard - 1))
    if ctx < warn:
        return

    state_dir = os.path.join(project_dir, ".agent", "tmp")
    os.makedirs(state_dir, exist_ok=True)
    state_file = os.path.join(state_dir, f"ctx-gate-{session_id}")
    last = 0
    try:
        with open(state_file) as f:
            last = int(f.read().strip())
    except (OSError, ValueError):
        pass

    same_band = (last >= hard) == (ctx >= hard)
    if ctx >= hard:
        step = min(HARD_STEP, max(1_000, (compact_at - hard) // 4))
    else:
        step = min(WARN_STEP, max(1_000, (hard - warn) // 4))
    if last and same_band and ctx - last < step:
        return
    with open(state_file, "w") as f:
        f.write(str(ctx))

    k = ctx // 1000
    hard_k = hard // 1000
    warn_k = warn // 1000
    pct = round(100 * ctx / compact_at)
    if compact_at < window:
        ceiling_desc = f"{_fmt(compact_at)} compaction point"
        if pct_override:
            ceiling_desc += f" (PCT_OVERRIDE={pct_override}% of {_fmt(window)})"
    elif cap and cap < model_window:
        ceiling_desc = (
            f"{_fmt(window)} enforced window "
            f"(model {_fmt(native_window)}, autoCompact {_fmt(cap)})"
        )
    else:
        ceiling_desc = f"{_fmt(window)} window"
    if one_m_off:
        ceiling_desc += f" — 1M context disabled, model is natively {_fmt(native_window)}"
    if ctx >= hard:
        headroom = max(0, compact_at - ctx)
        if headroom <= WRAP_RESERVE:
            tail = (
                f"only {_fmt(headroom)} remains before the harness compacts. Do NOT start new "
                "tasks, large reads, or long tool runs first — that headroom is sized for "
                "wrapping up alone, and a single large read can spend it, losing the session's "
                "open decisions."
            )
        else:
            tail = (
                f"{_fmt(headroom)} remains before the harness would compact, so the session is "
                "not at risk — this is a recycle point, not a rescue. Running on past here costs "
                "reasoning quality, not data. Finish the current step, note open state, then "
                "start clean."
            )
        context_msg = (
            f"CONTEXT GATE — HARD LIMIT (CONTEXT-WINDOW-CONTROL.md): context is {k}k tokens = "
            f"{pct}% of the {ceiling_desc} (hard limit {hard_k}k). "
            "Finish ONLY the current atomic step, summarize what's done/next/open for whoever "
            f"(or whatever session) picks this up, then /compact or start a fresh session. {tail}"
        )
        system_msg = f"🔴 Context {k}k >= {hard_k}k hard limit — wrap up now, then /compact or fresh session."
    else:
        context_msg = (
            f"CONTEXT GATE — WARNING (CONTEXT-WINDOW-CONTROL.md): context is {k}k tokens = "
            f"{pct}% of the {ceiling_desc} (warn {warn_k}k / hard {hard_k}k). "
            f"Wrap up the current workstream and plan how you'll note state before {hard_k}k. "
            "Route heavy reads and wide exploration through a subagent; avoid loading large "
            "files into this session directly."
        )
        system_msg = f"🟡 Context {k}k = {pct}% >= {warn_k}k — plan your wrap-up before {hard_k}k."

    print(json.dumps({
        "systemMessage": system_msg,
        "hookSpecificOutput": {"hookEventName": event, "additionalContext": context_msg},
    }))


if __name__ == "__main__":
    main()
