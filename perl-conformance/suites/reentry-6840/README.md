# Numification reentry, 6,840-case generator

`reentry_matrix.pl` generates 18 inputs x 19 handler actions x 5 outer operations = 6,840 cases, each in its own
process, and records value and flag outcomes as JSON lines; `analyze_reentry.pl` and `catalog_results.pl` reduce them.
Results on 5.38.2 and 5.44.0 are `reentry-<ver>.jsonl.gz` (0 value mismatches on comparable rows; 8 SIGSEGV cases --
numeric replacement during direct NV conversion -- recorded in `crash_reproductions.json` and `undefined.md`), with the
per-version summaries and `matrix_findings.json.gz`.

The two reducers replace Python originals and print byte for byte what those printed (`PyFormat.pm` writes Python's
`repr` and `json.dumps` text): `perl analyze_reentry.pl` on the decompressed `reentry-5.44.0.jsonl.gz` reproduces
`reentry-5.44.0-summary.txt`.  `matrix_findings.json.gz` and `reentry-tied-warning-5.44.0-summary.txt` also needed the
raw `reentry-tied-warning-<ver>.jsonl` files, which were never committed, so they are kept as recorded; the reducer
matches its Python original on every input that is here.  `probe_manifest.json` pins every file of the research run as
it was then, the Python reducers and the uncommitted raw files included; the committed raw files and
`matrix_findings.json.gz`, decompressed, still match their pins.

`continuation_probes.pl` and its outputs are the continuation-rule probes: string numification's two parse moments, tied
FETCH, overloaded `""` in concatenation, nested autovivification, and `local` on a tied scalar.  `minimal_nv_reentry.pl`
is the smallest crash reproduction.  `probe_manifest.json` pins the Perl source tarball and the sha256 of every file;
`review.md` is the research record.
