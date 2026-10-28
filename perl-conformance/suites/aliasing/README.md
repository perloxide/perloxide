# Aliasing acceptance suite

28 programs exercising element aliasing through `for`, `map`, `grep`, `sort`, `@_`, `\$a[i]`, `local` on aliased
elements, and structural operations (`shift`, `splice`, `delete`, list assignment) on aliased containers, with expected
stdout per Perl and the exit status appended.

    ./run.sh /path/to/interpreter [VERSION]    # compares against expected/VERSION/, default the newest supported

Blessed on 5.44.0 (`expected/5.44.0/`).  The 26 runnable cases produce that output on all six 5.44.0 builds and on the
unsupported 5.38.2.  Two are `*_EXCLUDED` and skipped by the runner because Perl reads freed memory in them: A12 (`shift
@_` under two held aliases: garbage on 5.38.2, SIGSEGV on 5.44.0) and A26 (`values` aliasing with `delete`: order- and
memory-dependent).  Both are recorded in `undefined.md`.
