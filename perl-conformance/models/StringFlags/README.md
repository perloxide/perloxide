# PV: the UTF-8 flag and taint

**Source.**  Transcribed from the perl5 repository at tag `v5.44.0`: sv.c (`sv_utf8_upgrade_flags_grow`,
`sv_utf8_downgrade_flags`), utf8.c, pp_pack.c and the case-mapping and taint paths.  Validated by replay against the
supported 5.44.0 builds; results in `reports/`; the 5.38.2 run and `reports/version-differences.diff` beside them are
from the unsupported 5.38.2 (`../../unsupported-perls.md`).  A transcription is of one version's C, so a replay mismatch
on a supported version is either a model gap or a change in perl's own implementation between the transcribed tag and
that version; `version-divergent` rows name the second kind, and the tag above is what a reader diffs against when one
appears.

`PV.pm` transcribes the string-flag and taint semantics: `sv_utf8_upgrade_flags_grow`, `sv_utf8_downgrade_flags`,
encode/decode, the lenient and strict UTF-8 readers, case mapping under the Unicode-bug table (no feature,
`unicode_strings`, `use locale`), regex charset modifiers, `unpack` modes, concatenation, hash keys, and taint
propagation with the launder list.  It is **in progress**: it predates the C-name convention (one `op` dispatcher with
model-invented names and an override block for the strict readers), the warning column is recorded but not compared,
depth 2 is implemented but unrun, and the I/O flag boundary is described from source rather than enumerated.

`generators/pv_gen.pl` enumerates six string families x three lexical contexts x tainted or not x 57 operations (2,052
rows per Perl), observing bytes, flag, `length`, every character's `ord`, `tainted`, and croaks. The `use locale`
context needs a UTF-8 locale with a comma radix (`profile.md`).

    ORACLE=/path/to/perl TAG=<tag> DEPTH=1 perl generators/pv_gen.pl   # rows=2052 ok=... bad=...

Recorded (`reports/`): 1,865/2,052 on 5.38.2 and the corresponding 5.44.0 run in this bundle; the 51 rows on which the
two Perls differ are in `reports/version-differences.diff` (chiefly `unpack "C0U*"` on malformed octets: 0 on 5.38,
U+FFFD on 5.44); the model follows 5.44.  Section text: `section.md`. Open items are listed in `status.md`.
