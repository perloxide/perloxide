# Numification reentry matrix: recorded outputs

The `__WARN__`-handler matrix -- 18 inputs x 8 handler replacements x 4 then-actions x 4 outer operations, 2,304 rows,
one process per row -- as recorded on 5.38.2 (`matrix.5.38.2.txt`) and 5.44.0 (`matrix.5.44.0.txt`): 2,154 comparable
rows with 0 value and 0 flag mismatches against the value-flags model on both; 150 rows are excluded.  The record's 114
"crash" rows are 108 where Perl crashes (W1 in `undefined.md`) and 6 where the run completes and Perl then croaks
`panic: del_backref, svp=0` as the scalar is freed (W3, a deterministic outcome); the harness of the time counted any
exit status of 124 or more as a crash, and a croak's exit status is whatever `errno` held.  The other 36 are results
read through a reference (W2).  All three are bug `warn-handler-continuation` (`perl-bugs.md`).

The live generator for this matrix is `models/ValueFlags/generators/gen_vf.pl`, run by
`models/ValueFlags/generators/vf_gen.pl`, which records it in `models/ValueFlags/reports/matrix.tsv`; these files are
the blessed record of the pre-consolidation run.
