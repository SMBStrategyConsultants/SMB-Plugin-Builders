#!/usr/bin/env bash
# ANCHOR: secret-read-guard | role: Hook | refs: destructive-command-guard, protected-files-guard
#
# PreToolUse guard: commands that PRINT SECRET VALUES to stdout are denied.
#
# Born from a real incident: an agent ran `netlify env:list --plain` intending
# to list variable NAMES; `--plain` prints values, and a batch of real secrets
# landed in the transcript in one call, despite a prose rule saying not to that
# the agent had read and quoted less than an hour earlier. Prose rules do not
# bind under time pressure; hooks do.
#
# The distinction this enforces: listing NAMES is fine, printing VALUES is not.
#
# Escape hatch, deliberately narrow: a value-printing command IS allowed when the
# same command line reduces it to names in-shell (awk -F= '{print $1}' or
# cut -d= -f1). Values still transit the pipe but never reach the transcript.
# The filter must be part of the command, not applied to its output afterward —
# that ordering is exactly what failed.
#
# Not a proof, a strong net: a command building its invocation from variables, or
# a script file that reads secrets internally, will not match. Reads of secrets
# into a file the agent never prints are also invisible here. Verification by
# BEHAVIOUR (does the app work?) remains the standard.
#
# ALL grep matching below uses a herestring (`grep ... <<< "$var"`), never a
# `printf | grep` pipe — same reason as destructive-command-guard.sh: `grep -q`
# exits the instant it matches, and under `set -o pipefail` a producer killed
# by the resulting SIGPIPE reports a NON-ZERO pipeline status even though grep
# itself matched. Here that silently turns a `deny` into an allow — found
# 2026-08-27 as the sibling of the same bug in destructive-command-guard.sh,
# reachable the same way (a secret-reading command followed by enough trailing
# text in the same Bash call — measured: as little as ~32KB for some patterns
# here, since the pipeline is one stage shorter than the destructive guard's).
# A herestring has no concurrent producer process to kill, so exiting early
# costs nothing.
set -uo pipefail

payload="$(cat)"
tool="$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)"

case "$tool" in
  Bash|run_shell_command|shell|execute_command) ;;
  *) exit 0 ;;
esac

cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -z "$cmd" ] && exit 0

# Strip heredoc bodies so a secret-shaped string inside a commit message or a
# document being written does not trip the matcher. Same helper the
# destructive-command guard uses. (awk reads its whole input before producing
# output — no early-exit, so no SIGPIPE risk from this particular pipe.)
STRIPPER="$(dirname "${BASH_SOURCE[0]}")/strip-heredocs.awk"
if [ -f "$STRIPPER" ]; then
  scan="$(printf '%s' "$cmd" | awk -f "$STRIPPER" 2>/dev/null || printf '%s' "$cmd")"
else
  scan="$cmd"
fi

# Blank the payload of message-bearing flags. Documenting this rule must not trip
# it: `git commit -m "never run cat .env"` is prose about a command, not the
# command. Only the quoted argument to -m/--message/--body is blanked, so a real
# read with a quoted path (cat "/srv/.env") still matches. (sed processes its
# whole input before producing output — no early-exit, no SIGPIPE risk.)
scan="$(printf '%s' "$scan" | sed -E \
  -e "s/(-m|--message|--body|--title|--description)([[:space:]]+|=)'[^']*'/\1 ''/g" \
  -e "s/(-m|--message|--body|--title|--description)([[:space:]]+|=)\"[^\"]*\"/\1 \"\"/g")"

deny() {
  jq -n --arg reason "$1" --arg ctx "$2" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason,
      additionalContext: $ctx
    },
    systemMessage: ("🛑 Secret-read blocked: " + $reason)
  }'
  exit 0
}

CTX='SECRET VALUES MUST NOT BE PRINTED. This command would write secret values into the transcript, where they cannot be un-leaked and force a rotation.
Do this instead, in order of preference:
1. VERIFY BY BEHAVIOUR. To answer "is X configured?", exercise the thing and read its error. A deploy returning "storage is not configured" answers the question with zero exposure. This is the standard.
2. LIST NAMES ONLY, filtered IN-SHELL (not after the fact):
     netlify env:list --plain | awk -F= "{print \$1}"
     netlify env:list --plain | cut -d= -f1
   The filter must be part of this command. Piping later does not help — the unfiltered output has already been captured.
3. Ask the client to read or set the value themselves. Credentials are theirs to handle.
If you genuinely need a value to complete a task, STOP and ask the client. Do not route around this guard by reformatting the command.'

# --- Value-printing secret reads -------------------------------------------------
# Each pattern targets an invocation that emits VALUES, not names.

# Netlify: `--plain` and `--json` both include values; `env:get` prints one value.
if grep -qE 'netlify[[:space:]].*env:list[^|]*(--plain|--json)' <<< "$scan"; then
  # Narrow allowance: name-only reduction on the same command line.
  if grep -qE "awk[[:space:]]+-F=?[[:space:]]*'?\{?[[:space:]]*print[[:space:]]+\\\$1" <<< "$scan" ||
     grep -qE 'cut[[:space:]]+-d=[[:space:]]*-f[[:space:]]*1' <<< "$scan"; then
    exit 0
  fi
  deny "netlify env:list --plain/--json prints values, not just names" "$CTX"
fi
grep -qE 'netlify[[:space:]].*env:get' <<< "$scan" &&
  deny "netlify env:get prints a secret value" "$CTX"

# Vercel / Supabase / Heroku / Doppler / Railway
grep -qE 'vercel[[:space:]].*env[[:space:]]+(pull|ls[^|]*--sensitive)' <<< "$scan" &&
  deny "vercel env pull/ls --sensitive exposes values" "$CTX"
grep -qE 'supabase[[:space:]].*secrets[[:space:]]+(list|get)' <<< "$scan" &&
  deny "supabase secrets list/get prints values" "$CTX"
grep -qE 'heroku[[:space:]]+config(:get)?([[:space:]]|$)' <<< "$scan" &&
  deny "heroku config prints all config values" "$CTX"
grep -qE 'doppler[[:space:]]+secrets([[:space:]]+(get|download))?([[:space:]]|$)' <<< "$scan" &&
  deny "doppler secrets prints values" "$CTX"
grep -qE 'railway[[:space:]]+variables([[:space:]]|$)' <<< "$scan" &&
  deny "railway variables prints values" "$CTX"

# Cloud secret stores
grep -qE 'aws[[:space:]].*secretsmanager[[:space:]].*get-secret-value' <<< "$scan" &&
  deny "aws secretsmanager get-secret-value returns the plaintext secret" "$CTX"
grep -qE 'aws[[:space:]].*ssm[[:space:]].*get-parameters?[^|]*--with-decryption' <<< "$scan" &&
  deny "aws ssm get-parameter --with-decryption returns plaintext" "$CTX"
grep -qE 'gcloud[[:space:]].*secrets[[:space:]].*versions[[:space:]]+access' <<< "$scan" &&
  deny "gcloud secrets versions access prints the secret" "$CTX"
grep -qE 'kubectl[[:space:]].*get[[:space:]]+secrets?[^|]*-o[[:space:]]*(json|yaml)' <<< "$scan" &&
  deny "kubectl get secret -o json/yaml exposes base64 values" "$CTX"

# Local dotfiles and raw environment dumps
# Placeholder-only files by convention (.env.example/.sample/.template/.dist,
# any casing) hold no real values and are the first thing anyone reads on a
# fresh clone — an external build team does this repeatedly. Excluded by
# suffix so the real .env / .env.production / .env.local forms still match.
if grep -qE '(cat|bat|less|more|head|tail|strings|xxd)[[:space:]]+([^|;&]*[[:space:]])?[^[:space:]|;&]*\.env(\.[A-Za-z0-9_.-]+)?([[:space:]]|$)' <<< "$scan" &&
   ! grep -qiE '\.env(\.[A-Za-z0-9_.-]*)?\.(example|sample|template|dist)([[:space:]]|$)' <<< "$scan"; then
  deny "printing a .env file exposes every value in it" "$CTX"
fi
grep -qE '(^|[;&|][[:space:]]*)(printenv|env)([[:space:]]*$|[[:space:]]*\|[[:space:]]*(grep|rg|awk|sed|sort|head|tail))' <<< "$scan" &&
  deny "printenv/env dumps the whole environment, secrets included" "$CTX"

exit 0
