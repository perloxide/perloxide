# Numification reentry, 6,840-case generator

`reentry_matrix.pl` generates 18 inputs x 19 handler actions x 5 outer operations = 6,840 cases, each in its own
process, and records value and flag outcomes as JSON lines; `analyze_reentry.py` and `catalog_results.py` reduce them.
Results on 5.38.2 and 5.44.0 are `reentry-<ver>.jsonl.gz` (0 value mismatches on comparable rows; 8 SIGSEGV cases --
    numeric replacement during direct NV conversion -- recorded in `crash_reproductions.json` and `undefined.md`), with the
per-version summaries and `matrix_findings.json.gz`.

`continuation_probes.pl` and its outputs are the continuation-rule probes: string numification's two parse moments, tied
FETCH, overloaded `""` in concatenation, nested autovivification, and `local` on a tied scalar.  `minimal_nv_reentry.pl`
is the smallest crash reproduction.  `probe_manifest.json` pins the Perl source tarball and the sha256 of every file;
`review.md` is the research record.
