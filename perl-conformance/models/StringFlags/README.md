# PV: the UTF-8 flag and taint

**Source.**  Transcribed from the perl5 repository at tag `v5.44.0`: sv.c (`sv_utf8_upgrade_flags_grow`,
`sv_utf8_downgrade_flags`, `sv_utf8_encode`, `sv_utf8_decode`, `sv_cmp_locale_flags`), utf8.c (`utf8_length`,
`utf8n_to_uvchr`), inline.h (`utf8_hop_back`), pp.c (`pp_substr`, `pp_reverse`), pp_hot.c (`pp_multiconcat`), pp_pack.c,
regcomp.c (the charsets) and the case-mapping and taint paths.  Validated by replay against the supported 5.44.0 builds;
results in `reports/`, with the 5.38.2 rows in the same factored table from the unsupported 5.38.2
(`../../unsupported-perls.md`).  Source-validated with `tools/source-validate.pl` against v5.38.2, v5.40.2, v5.42.0,
v5.44.0 (`source-validation.txt`): of the routines with a C definition, 1 is identical across all four tags and so
transcribed equally validly for each, 0 differ only by moved declarations or added assertions, and 6 differ in code at
one or more of the tags and must be read before any of those versions can be supported by this model — each such reading
ends either in a `source-equivalences.tsv` line (functionally neutral) or in a version check inside the model; 0 names
are the model's own labels, arms and helpers.  A replay mismatch on a supported version is therefore either a model gap
or a change in perl's own implementation since the transcribed tag, and the validation record says which routines could
carry the second kind.

`StringFlags.pm` transcribes the string-flag and taint semantics: `sv_utf8_upgrade_flags_grow`,
`sv_utf8_downgrade_flags`, `sv_utf8_encode`, `sv_utf8_decode`, `utf8_length` and the lenient, strict and decoding UTF-8
readers, `DO_UTF8` under `use bytes`, case mapping and the regex charsets under every context (the Unicode bug, the
feature, `use bytes`, and `use locale` with the runtime locale's character repertoire), `/aa`, `unpack` modes,
`pp_multiconcat`, `pp_substr`, both paths of `pp_reverse`, `sv_cmp_locale_flags` with the POSIX collating sequence, hash
keys, and taint propagation with the launder list.  Routines named after a C function transcribe it; the CamelCase
routines are glue.  Still open: the warning column is recorded but not compared, and the I/O flag boundary is described
from source rather than enumerated.

`generators/pv_gen.pl` enumerates seven string families x seven lexical contexts x tainted or not x 61 operations at
depth 1 (6,272 rows), observing bytes, flag, `length`, every character's `ord`, `tainted`, warnings and croaks; at depth
2 it runs every producer operation under one context and hands the result to every reader operation under another, for
every ordered pair of the five contexts that can differ (121,800 rows, untainted).  The `use locale` contexts select the
harness's compiled `ctype_utf8`, `ctype_latin1` and `posix` locales and the built-in `C` (`lib/Perl/Conformance/
Locales.pm`); a locale that cannot be selected is fatal, never a silently degraded row.

    PERL_CONFORMANCE_PERL=/path/to/perl TAG=<version> DEPTH=1 perl generators/pv_gen.pl   # rows=6272 ok=... bad=...
    PERL_CONFORMANCE_PERL=/path/to/perl TAG=<version> DEPTH=2 perl generators/pv_gen.pl   # rows=121800 ok=... bad=...
    REPLAY=1 TAG=<version> perl generators/pv_gen.pl           # the model against the table, no perl involved

Recorded (`reports/`): 6,272/6,272 at depth 1 on every 5.44.0 build (`pv.5.44.0.txt`, `pv.5.44.0-noreuse.txt`, ...) and
121,800/121,800 at depth 2 on the stock build.  Every depth-1 row at every version and build is in the factored table
`reports/table.tsv` (`lib/Perl/Conformance/Table.pm`, `../README.md` Tables and replay): one line per distinct result
with its set of contexts and set of versions, the six 5.44.0 builds agreeing on every row (`5.44.0-*`);
`perl-conformance table StringFlags expand|lookup|diff` expands, looks up and compares it, `perl-conformance replay
StringFlags` runs the model against it, and a depth-1 run whose `TAG` is a version merges itself into it.  The 5.38.2
rows differ from the 5.44.0 rows on 131 (`perl-conformance table StringFlags diff 5.38.2 5.44.0`: `unpack "C0U*"` on
malformed octets, 0 on 5.38 and U+FFFD on 5.44; `tr///` on a malformed string; a few readers' strictness); the model
follows 5.44, so `replay StringFlags --target 5.38.2` reports those 131 as its gaps there.  The depth-2 run is recorded
by its row count and the SHA-256 of its table in `reports/pv2.5.44.0.txt`.  Section text: `section.md`.  Open items are
listed in `status.md`.
