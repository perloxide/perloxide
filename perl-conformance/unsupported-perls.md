# Unsupported Perls

Observations from Perls that are not supported versions (`profile.md`), gathered here so that they appear nowhere else.
None of them demonstrates a fact: a fact rests on a supported version's blessing or model row, and these are the record
of what a convenient second Perl happened to show beside it.  When one of these versions becomes supported — the full
build set, a complete blessing — the observations below are the cross-check list for that work, and this file loses its
section for it.

## Perl 5.38.2

The Ubuntu 24.04 system `perl` (threaded, `x86_64-linux-gnu-thread-multi`, Scalar::Util 1.63), which was at hand during
the research and was run beside 5.44.0 as a difference detector.  It has no allocator-instrumented variants, so nothing
it produced can be classified, and it was never a target.  Where the reference's data files carry a 5.38.2 column or
output, that is where it came from.

**Observed differences from 5.44.0**, each a candidate `version-divergent` row once 5.38.x is supported:

- `Scalar::Util::isweak` runs no get-magic on 5.38.2 (ListUtil 1.63) and does on 5.44.0, where it is `builtin::is_weak`;
  so `isweak` on an unprimed tied-element proxy `FETCH`es a strong copy on 5.44.0 only.
  `probes/corpus/tied_03_unprimed_proxy_getmagic.pl`: a 5.38.2 run of that probe differs on exactly that row.
- After `setlocale(LC_NUMERIC, <comma locale>)` at file scope with no `use locale`, 5.38.2 stringifies `3.5` as `3,5`
  and 5.44.0 as `3.5`.  Recorded in `probes/research/value-flags/locale.5.038002.out` beside the 5.44.0 output.
- `shift @_` while two aliases into `@_` are held reads freed memory on both; the symptom is garbage on 5.38.2 and
  `SIGSEGV` on 5.44.0 (`undefined.md`, aliasing suite case A12).
- `Perl_sv_grow` on 5.38.2 does not round the first allocation up (no `expected_size`), so buffer `LEN` on a first
  allocation above 16 bytes differs (NV stringification 26 against 32, a 36-byte un-COW string 38 against 40), and
  `SvPV_shrink_to_cur` differs; the value-flags model follows 5.44.0 and this is the version-divergent group behind its
  5.38.2 len-only rows (`models/ValueFlags/README.md`, passes 14 onward; `models/ValueFlags/section.md`).
- Stringification: public `IOK`, or on 5.38.2 `IOKp` without `NOKp`, formats the integer
  (`models/ValueFlags/section.md`).
- `unpack "C0U*"` on malformed octets yields 0 on 5.38.2 and U+FFFD on 5.44.0; the UTF-8 flag model's 2,052 rows match
  1,900 on 5.38.2 against 1,903 on 5.44.0, and the 51 rows on which the two differ are
  `models/StringFlags/reports/version-differences.diff` (`models/StringFlags/README.md`,
  `models/StringFlags/section.md`).
- The reentry matrices (`suites/reentry-matrix`, `out538.txt`; `suites/reentry-6840`, `reentry-5.38.2.jsonl.gz`) and the
  pre-consolidation transition tables (`suites/transitions`) carry 5.38.2 recordings beside 5.44.0's: 0 value mismatches
  on comparable rows, the same 8 `SIGSEGV` cases in the 6,840-case matrix, and transition tables byte-identical between
  the two for every lane.
- The research probes were recorded on both: `probes/research/value-model/out/perl-5.38.2/` and the `*.5.038002.out`
  files under `probes/research/value-flags/`.  Probe 25 (`kill_backrefs_reentry`) is identical on both.
- The suites that are hand-blessed (`suites/aliasing`, `suites/readonly`) produced identical output on 5.38.2 for every
  runnable case at the time they were blessed; their 5.38.2 expected directories were removed when 5.38.2 was recorded
  as unsupported, and `./run.sh /usr/bin/perl` is the way to re-check.
