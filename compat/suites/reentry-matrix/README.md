# Numification reentry matrix: recorded outputs

The `__WARN__`-handler matrix -- 18 inputs x 8 handler replacements x 4 then-actions x 4 outer operations, 2,304 rows,
one process per row -- as recorded on 5.38.2 (`out538.txt`) and 5.44.0 (`out544.txt`): 2,154 comparable rows with 0
value and 0 flag mismatches against the value-flags model on both; 114 rows where Perl crashes and 36 where it reads a
freed PV are excluded and are the windows W1-W3 in `undefined.md`.

The live generator for this matrix is `models/VF/generators/gen_vf.pl`, which `models/VF/vf_suite.pl` runs as its
`matrix` lane; these files are the blessed record of the pre-consolidation run.
