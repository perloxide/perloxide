# Readonly values suite

Four programs pinning which values are readonly and what a write to one does: the members of a foreach list that are the
readonly constant SV itself against those that are writable temporaries (R01), how the flag propagates through copies,
references and `Internals::SvREADONLY` and which operations refuse it (R02), which special variables are readonly (R03),
and the non-creatable negative subscript, a different message raised by every lvalue route and no rvalue route (R04).
Each line prints `ok` when the block ran or `dies:` with the message's location stripped, with expected output per Perl
and the exit status appended.

    ./run.sh /path/to/interpreter [expected-dir]

All four cases produce identical output on 5.38.2 and 5.44.0.  Blessed outputs never end a line in whitespace
(`tools/lint-blessed.sh`).
