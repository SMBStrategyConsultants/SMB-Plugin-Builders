# Removes heredoc BODIES from a shell command, keeping the command lines.
#
# Used by aws-destructive-guard.sh for invocation detection only. Heredoc bodies are
# data, not commands: a markdown table row piped into a log file looks exactly like a
# shell pipeline (`| Supabase RLS | ... drop table ...`), which produced a real false
# positive on 2026-07-30 when appending a lesson to Strategic_Log.md.
#
# The guard still runs its destructive-pattern match against the FULL original command,
# so `psql <<EOF / drop table users; / EOF` is unaffected — `psql` appears in the
# command portion and is detected there, then the body is matched for `drop table`.
#
# Herestrings (<<<) are intentionally not treated as heredocs.

BEGIN { inbody = 0 }

inbody {
  l = $0
  sub(/^[ \t]+/, "", l)          # <<- allows a tab-indented terminator
  if (l == term) { inbody = 0 }
  next
}

{
  print

  # Find the LAST heredoc opener on this line — `cmd <<A <<B` reads A then B, but for
  # our purposes any body start is enough to begin skipping.
  tmp = $0
  found = 0
  while (match(tmp, /<<-?[ \t]*["']?[A-Za-z_][A-Za-z0-9_]*["']?/)) {
    tok = substr(tmp, RSTART, RLENGTH)
    tmp = substr(tmp, RSTART + RLENGTH)
    found = 1
  }

  if (found) {
    sub(/^<<-?[ \t]*/, "", tok)
    gsub(/["']/, "", tok)
    term = tok
    inbody = 1
  }
}
