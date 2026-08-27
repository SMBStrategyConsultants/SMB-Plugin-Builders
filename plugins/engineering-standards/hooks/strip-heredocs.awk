# Removes heredoc BODIES from a shell command, keeping the command lines.
#
# Used by destructive-command-guard.sh and secret-read-guard.sh for invocation
# detection only. Heredoc bodies are data, not commands: a markdown table row
# piped into a log file looks exactly like a shell pipeline (`| Supabase RLS |
# ... drop table ...`), which produced a real false positive on 2026-07-30
# when appending a lesson to Strategic_Log.md.
#
# The guard still runs its destructive-pattern match against the FULL original
# command, so `psql <<EOF / drop table users; / EOF` is unaffected — `psql`
# appears in the command portion and is detected there, then the body is
# matched for `drop table`.
#
# WHY TWO-PASS: a one-pass scan that opens a body-skip on any `<<TOKEN` match
# is unsound, because `<<` is not exclusively a heredoc redirection — it is
# also C++ stream insertion (`std::cout << msg`), a bash arithmetic shift
# (`$((size << bits))`), and appears inside ordinary quoted prose ("Redirect
# with << HEREDOC syntax"). A first attempt at this fix (2026-08-27) blacklisted
# one specific non-opener spelling (`<<<`, a herestring) rather than the actual
# invariant — a real heredoc opener's terminator token reappears alone on a
# later line to close it. That attempt still silently dropped every line after
# `std::cout << msg` and `$((size << bits))` from Gate 1's input, the same
# failure mode and blast radius as the herestring bug it was fixing.
#
# This version reads the whole command first, then for each apparent opener
# checks whether its terminator genuinely exists later in the input before
# treating it as a real heredoc start. No terminator found → treat the `<<` as
# ordinary text and keep scanning from the next line, same as the herestring
# and stream-operator cases. Fails SAFE: an ambiguous `<<` now keeps more
# lines visible to Gate 1 rather than fewer.

{ line[NR] = $0 }

END {
  n = NR
  i = 1
  while (i <= n) {
    print line[i]

    tmp = line[i]
    found = 0
    while (match(tmp, /<<-?[ \t]*["']?[A-Za-z_][A-Za-z0-9_]*["']?/)) {
      tok = substr(tmp, RSTART, RLENGTH)
      tmp = substr(tmp, RSTART + RLENGTH)
      found = 1
    }

    if (found) {
      sub(/^<<-?[ \t]*/, "", tok)
      gsub(/["']/, "", tok)

      close_at = 0
      for (j = i + 1; j <= n; j++) {
        l = line[j]
        sub(/^[ \t]+/, "", l)   # <<- allows a tab-indented terminator
        if (l == tok) { close_at = j; break }
      }

      if (close_at > 0) {
        # Genuine heredoc: print the body lines (they're still command text
        # for Gate 1's purposes up to and including the terminator line —
        # only the SKIPPED body between opener and terminator is omitted)
        # by advancing past them without printing.
        i = close_at + 1
        continue
      }
      # No terminator found anywhere in the rest of the input: not a real
      # heredoc (herestring, stream operator, arithmetic shift, or prose).
      # Fall through and advance one line, printing normally.
    }

    i++
  }
}
