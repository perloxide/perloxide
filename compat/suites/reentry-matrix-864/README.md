# Numification reentry matrix, 864-cell form

`18_warnmut_matrix.pl` runs 18 inputs x {string, number, reference replacement} x {no then-action,
`+0`, `%.17g`, die} x {`+0`, `|0`, `%g`, `.""`} = 864 cells per perl, one process per cell.
`model_fatbody.pl` is an independent transcription of the reentry control flow (5.44.0 sv.c,
`NV_PRESERVES_UV` undefined) and `compare_matrix.pl` compares; `compare.<ver>.txt` are the
reports: 762 match, 0 mismatch, 51 cells where perl segfaults and 51 where it reads through the
RV union -- all recorded in `undefined.md`. `model.tsv` is the model's output per cell.

This transcription was reconciled cell for cell with the value-flags model (`models/VF`)
during the research; the value-flags model is the maintained one. The rows this model marks
`DIVERGES-defined` are outputs an implementation might choose in the undefined windows, not facts
about perl.
