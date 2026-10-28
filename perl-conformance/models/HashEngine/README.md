# HV: the hash engine

**Source.**  Transcribed from the perl5 repository at tag `v5.44.0`: hv.c, hv_func.h, perl_siphash.h and sbox32_hash.h.
Validated by replay against the supported 5.44.0 builds; results in `reports/`, with the 5.38.2 observations in the same
factored table from the unsupported 5.38.2 (`../../unsupported-perls.md`).  Source-validated with
`tools/source-validate.pl` against v5.38.2, v5.40.2, v5.42.0, v5.44.0 (`source-validation.txt`): of the routines with a
C definition, 7 are identical across all four tags and so transcribed equally validly for each, 2 differ only by moved
declarations or added assertions, and 6 differ in code at one or more of the tags and must be read before any of those
versions can be supported by this model — each such reading ends either in a `source-equivalences.tsv` line
(functionally neutral) or in a version check inside the model; 3 names are the model's own labels, arms and helpers.  A
replay mismatch on a supported version is therefore either a model gap or a change in perl's own implementation since
the transcribed tag, and the validation record says which routines could carry the second kind.

`HashEngine.pm` (`../../lib/Perl/Conformance/Model/HashEngine.pm`) transcribes hv.c and hv_func.h for the profile in
`profile.md`: the seed expansion (`perl_siphash_seed_state`, `sbox32_seed_state128`), the two hash functions
(`perl_hash_siphash_1_3_with_state`, `sbox32_hash_with_state`), `hv_common` (head insertion, `DO_HSPLIT` gated on
collision), `hsplit`, `hv_auxinit`, `PERL_HASH_ITER_BUCKET`, `hv_iternext_flags` (including `HvLAZYDEL` and the
each-after-insert warning's `xhv_last_rand != xhv_rand` guard), `hv_delete_common`, `hv_clear`, `hv_undef_flags`,
`hfree_next_entry`'s raw-bucket destruction order, and key normalization.

`generators/hv_gen.pl` validates below program level against `Hash::Util::bucket_array`, `hash_traversal_mask`, and
`hash_value` for 5, 40, 700, and 5000 keys under seed 0, a nonzero seed with `PERL_PERTURB_KEYS=0`, and that seed in
DETERMINISTIC mode (`PERL_PERTURB_KEYS=2`, whose hash values are compared and whose masks and bucket arrays are recorded
but excluded by construction); and at program level for `keys`/`each` order, delete-current, delete-other, insert during
`each`, iterator reset, clear-and-refill versus undef-and-refill, and `DESTROY` order.  Each observation is one row
(lane, kind, item): `hash` per key of the 40-key set, `mask` and `buckets` per key count (bucket arrays in full up to 40
keys, as a SHA-256 for 700 and 5000), `hashes` as a SHA-256 of the 700- and 5000-key sets' hash values, and `program`
per program.

    PERL_CONFORMANCE_PERL=/path/to/perl TAG=<version> perl generators/hv_gen.pl   # rows=170 ok=... bad=... excluded=8
    REPLAY=1 TAG=<version> perl generators/hv_gen.pl                              # the model against the table, no perl

Recorded (`reports/hv.<version>.txt`): 162/162 compared rows on 5.38.2 and on every 5.44.0 build, 8 excluded.  Perl's
observations at every version are in the factored table `reports/table.tsv` (axes lane, kind, item, folded over lane; a
newline in a program's output written as `\n` and a backslash as `\\`; `../README.md`, Tables and replay).  Every row
holds for every version except the DETERMINISTIC lane's masks and bucket arrays, which differ even among the 5.44.0
builds, as that mode's layout depends on all the hash activity before it, the interpreter's startup included
(`perl-conformance table HashEngine diff 5.44.0 5.44.0-noreuse`).  Section text: `section.md`.  Open: the key has not
been audited against `HE`/`HV`/`xpvhv_aux` (`status.md`).
