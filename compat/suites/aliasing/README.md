# Aliasing acceptance suite

27 programs exercising element aliasing through `for`, `map`, `grep`, `sort`, `@_`, `\$a[i]`, `local` on aliased
elements, and structural operations (`shift`, `splice`, `delete`, list assignment) on aliased containers, with expected
stdout per Perl and the exit status appended.

    ./run.sh /path/to/interpreter [expected-dir]

25 cases produce identical output on 5.38.2 and 5.44.0.  Two are `*_EXCLUDED` and skipped by the runner because Perl
reads freed memory in them: A12 (`shift @_` under two held aliases: garbage on 5.38.2, SIGSEGV on 5.44.0) and A26
(`values` aliasing with `delete`: order- and memory-dependent).  Both are recorded in `undefined.md`.
