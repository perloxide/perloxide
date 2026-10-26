# Facts

The prose index of the reference: every established fact about Perl's behavior, grouped by area, each entry naming the
rule, the Perl function that fixes it, and the probe or model row that demonstrates it on a supported Perl
(`profile.md`).  A fact appears here only with that demonstration; a rule without one is not admitted.  Dense areas
point at their model's section text instead of restating the transition function.

Every entry opens with its id in a code span, `area.slug`, and is cited from any document as `[fact:area.slug]` — no
space, so that a citation is one word that no paragraph rewrap can split.  The part before the dot is the area's prefix,
declared in brackets at the end of the area's heading and shared by every entry under it; the slug names the rule and
never changes, so an entry may be reordered or reworded without breaking its citations.  `bin/perl-conformance explain
ID` prints an entry with its evidence resolved to paths (`--run` also runs the cited probes and cases on the target
version); `explain` alone lists the areas, `explain AREA` lists one area's ids, `explain -a` every area's, and `explain
--grep RE` finds entries by id or text, one line each — `-v` expands any of these to full entries; and `cite-check
FILE...` verifies that every citation in a document names an entry here.

Every entry ends with the supported versions it is demonstrated on, in brackets: a single version (`[5.44.0]`), or a
range when the behavior is the same on every supported version from the first to the last named (`[5.40.0–5.44.0]`).  A
range demonstrated on its ends but not on every supported version between them is marked `gaps` (`[5.40.0–5.44.0,
gaps]`); an entry whose behavior differs between supported versions states each side with its versions instead of a
range.  The brackets are the only place an entry names a version; what an unsupported Perl showed is in
`unsupported-perls.md`.

Nothing here is about any implementation of Perl.  What an implementation does where Perl's behavior is undefined
(`undefined.md`) is that implementation's own record.

## Value flags [value-flags]

The string and numeric forms of a scalar, the per-value flags recording which forms have been derived (public or
private, `IsUV`, derived-from-integer, private-only, stringified), the copy-on-write state and buffer length that decide
later transitions, and the `Dual` case.

Section: `models/ValueFlags/section.md`.  Model: `models/ValueFlags/ValueFlags.pm`.  Verification:
`models/ValueFlags/reports/coverage.txt`.  Probes: `probes/research/value-flags/`, `probes/research/value-model/` (01,
07-11, 15, 17, 18, 22, 23).  Suites: `suites/reentry-matrix`, `suites/reentry-matrix-864`, `suites/reentry-6840`,
`suites/transitions`.

Entries (a transition row is cited as `start before --op--> after`, the four columns of a `raw_transitions.5.44.0.tsv`
line, with the flag set and the value as the suite prints them):

- `value-flags.record-and-derived-forms`: A scalar is one of five kinds — `Str`, `Int`, `Float`, `Ref`, `Undef` — and
  the kind fixes which form is authoritative: `Int` and `Float` own the number and any string form is derived, `Str`
  owns the bytes and any number is derived.  The value-flag record says, per form, whether that derivation has happened
  and how far it can be trusted — none, private (`SVp_IOK`, `SVp_NOK`, `SVp_POK`) or public (`SVf_IOK`, `SVf_NOK`,
  `SVf_POK`), a public flag never being set without its private one — plus `IsUV` (`SVf_IVisUV`), `UTF8`, and the
  copy-on-write state and buffer length that decide later transitions.  Every derivation is a pure function of the
  bytes, the `UTF8` flag, the value flags and the locale radix in effect, so a cached number is recomputable from the
  string except in the three `Dual` cases (a `__WARN__` handler that mutates the scalar mid-conversion, a non-C radix,
  and `"-0"` reached integer-first), each its own entry below.  `Perl_sv_2iv_flags`, `Perl_sv_2nv_flags`,
  `Perl_sv_2pv_flags`, `S_sv_2iuv_common`.  The lanes of `models/ValueFlags/reports/coverage.txt` (matrix, locale,
  core1, full1, walk1, copy); `probes/research/value-model/22_flags_synth.pl` (25 states synthesized from kind plus
  cache marks, 25 matched); the public-without-private assertion in `probes/corpus/flags_matrix.pl` never fires.
  [5.44.0]
- `value-flags.string-numeric-use`: Numeric use of a string classifies it with `grok_number` and caches the result in
  the slots.  On the integer path a clean integer, leading whitespace included, sets public `IOK` (`"10"` and `" 10"` →
  `IP`); a decimal or exponent string fills the NV slot with public `NOK` and the IV slot privately, public only when it
  round-trips (`"1.5"` → `iNP`, `"1e3"` → `INP`); `"Inf"` is public `NOK` with private `IOK` and `IsUV`; garbage with or
  without a numeric prefix (`"12x"`, `"abc"`) fills both slots private-only (`inP`) and warns `isn't numeric`, after
  which the cache is served and no later use warns; `"0 but true"` is matched by `memEQs` before the general parse and
  is a clean 0 with public `IOK`, no warning.  A float conversion (`sprintf "%g"`, `* 1.5`) of a decimal or small
  integer string sets public `NOK` alone (`"10"` → `NP`), of garbage private `NOK` alone, and of an integer string too
  large for an IV fills the integer slot instead (`"18446744073709551615"` → `InPU`).  A handler that dies out of the
  warning leaves no cache, so the next use warns again.  `S_sv_2iuv_common`, `Perl_sv_2nv_flags`,
  `Perl_grok_number_flags`, `S_not_a_number`.  Rows `$s + 0` and `sprintf "%g"` of `probes/corpus/flags_matrix.pl`;
  `probes/corpus/num_01_warn_handler.pl` (c, d); `suites/transitions/transitions/raw_transitions.5.44.0.tsv` rows `s10
  POK,pPOK|P:10 --iv--> IOK,POK,pIOK,pPOK|P:10`, `s1_5 POK,pPOK|P:1.5 --iv--> NOK,POK,pIOK,pNOK,pPOK|P:1.5`, `s12x
  POK,pPOK|P:12x --iv--> POK,pIOK,pNOK,pPOK|P:12x`, `sInf POK,pPOK|P:Inf --iv--> NOK,POK,pIOK,pNOK,pPOK,IsUV|P:Inf`;
  `probes/research/value-model/15_flags_peek.pl` (`plus10`, `dirty`, `pad`), `22_flags_synth.pl` (`clean_inf`,
  `zero_but_true`). [5.44.0]
- `value-flags.slot-derivation-and-uv`: The integer and float slots derive from each other and the publicity of the
  derived slot records whether the derivation was exact.  IV from NV: `IOKp` always, public `IOK` only if the value
  round-trips, lies within ±(2⁵³−1) and `NOK` is public (`3.0 | 0` → `IN`, `1.5 | 0` → `iN`, `1e19 | 0` → private `IOK`
  with `IsUV`); NV from IV: public `NOK` only if `IOK` is public and the value round-trips (`10` → `IN`, `IV_MAX` →
  private `NOK`).  `IsUV` marks an integer slot holding a UV: `"18446744073709551615"` numifies to `IPU`; `IV_MAX + 1`
  by addition is the exact UV `IOK,pIOK,IsUV`, not a float; `++` on `IV_MAX` crosses into UV space; `++` on a `UV_MAX`
  number gives `Float` 2⁶⁴, and only past `UV_MAX` does the promotion lose precision.  `S_sv_2iuv_common` (`got_nv`),
  `S_sv_2iuv_non_preserve`, `Perl_sv_2nv_flags`, `pp_add`, `Perl_sv_inc_nomg`.  Columns `float, $f|0`, `3.0, $f|0` and
  `UV_MAX str` of `probes/corpus/flags_matrix.pl`; `probes/research/value-flags/consumers.5.044000.out` rows `Float
  1e19, | 0`, `Int IV_MAX, ++`, `Float 3.0, | 0`; `22_flags_synth.pl` (`uv`, `iv_overflow`, `num_ivcache`);
  `suites/transitions/transitions/raw_transitions.5.44.0.tsv` rows `f3 NOK,pNOK|N:3 --iv--> IOK,NOK,pIOK,pNOK|N:3`,
  `f3_5 NOK,pNOK|N:1.5 --iv--> NOK,pIOK,pNOK|N:1.5`, `i10 IOK,pIOK|N:10 --nv--> IOK,NOK,pIOK,pNOK|N:10`, `sUV
  POK,pPOK|P:18446744073709551615 --iv--> IOK,POK,pIOK,pPOK,IsUV|P:18446744073709551615`, and the `iMax` rows `--inc-->
  IOK,pIOK,IsUV` and `--nv--> IOK,pIOK,pNOK`; `probes/corpus/consumers_01.pl` row 18 (`"18446744073709551615"` marked,
  then `++`: `1.84467440737096e+19`). [5.44.0]
- `value-flags.stringified-number`: Stringifying a number with public `IOK` formats the integer and caches it as a
  private string form (`stringified`, `SVp_POK` without `SVf_POK`); stringifying a finite float with public `NOK` only
  formats `%.15g` and caches nothing (the `USE_LOCALE_NUMERIC` branch), while an inf or nan NV takes the infnan branch
  and does cache `pPOK`.  Every read that only stringifies — `eq`, `cmp`, default `sort`, a hash key, `length` (not on
  `undef`), a `substr` read, `tr///` counting, `s///` with no match, `.` in either position, `%s`, pattern matching,
  `chomp` with nothing to remove — is `SvPV`-family and so leaves `stringified` on an integer and nothing on a string;
  boolean context and `!` (`SvTRUE_common` reads the flags), `local` and its restore, and a copy record nothing.  The
  mark is visible only through `isdual`.  `Perl_sv_2pv_flags`.
  `suites/transitions/transitions/raw_transitions.5.44.0.tsv` rows `i10 IOK,pIOK|N:10 --str--> IOK,pIOK,pPOK|N:10` and
  `f3 NOK,pNOK|N:3 --str--> NOK,pNOK|N:3`; rows `"$s"`, `$h{$s}`, `length $s`, `$s eq "10"`, `$s =~ /0/`, `sprintf
  "%s"`, `if ($s)`, `!$s` of `probes/corpus/flags_matrix.pl` (every string start unchanged; `int, "$i"` is `Ip`; `3.0,
  $f|0`, public `IOK`, becomes `INp`; `float, $f|0`, public `NOK` only, stays `iN`);
  `probes/corpus/consumers_02_numeric_starts.pl` rows `int 10, "$s"` (`isdual` 1, every other consumer unchanged) and
  `float 1.5, "$s"` (`isdual` 0); `probes/research/value-model/23_isdual_pseen.pl` (`array_elem` after `print`, `int`,
  `num`, `inf_nv_stringified`). [5.44.0]
- `value-flags.niokp-dispatch`: Range and the string-or-numeric bitwise operators choose their numeric path by the
  private flags.  `RANGE_IS_NUMERIC` (`pp_flop`) is numeric if either operand is `SvNIOKp`, or is defined and not
  `SvPOKp`, or looks like a number and does not start with `0` followed by more characters; a numeric operand then gets
  `SvNV_nomg` unless it is already public `IOK`, then `SvIV_nomg`, and a string operand `SvPV_nomg`.  Without `feature
  'bitwise'`, `|`, `&` and `~` are numeric if either operand is `SvNIOKp` (converting with `SvUV_nomg`, and a READONLY
  operand has the value flags removed again by `SvNIOK_off`) and otherwise string (`SvPV_nomg_const`, so `stringified`
  on a number); with the feature, `|` and `~` always convert numerically and `|.` and `~.` always stringify.
  Smartmatch's numeric rule tests the public `NIOK`.  So a private mark left by an earlier numeric use turns `"10" ..
  $zz` from 90 strings into an empty numeric range and `~"10"` from a string complement into an integer.  `pp_flop`
  (`RANGE_IS_NUMERIC`, pp_ctl.c), `pp_bit_or`, `pp_bit_and`, `pp_complement`, `pp_sbit_or`, `do_smartmatch`.
  `probes/corpus/consumers_01.pl` rows 14, 15, 19 and 20 (`"09"` stays a string range of 91 elements, `"-0"` a
  one-element string range until marked); `probes/corpus/consts_01_literal_mark.pl` (a); rows `~$s` and `$s | 0` of
  `probes/corpus/flags_matrix.pl`; `suites/transitions/transitions/raw_transitions.5.44.0.tsv` rows `s10 POK,pPOK|P:10
  --rng--> IOK,NOK,POK,pIOK,pNOK,pPOK|P:10` and `s09 POK,pPOK|P:09 --rng--> POK,pPOK|P:09`;
  `probes/research/value-model/07_num_jsonpp.pl` (`"a" .. "e"` strings, `"0" .. "3"` numbers). [5.44.0]
- `value-flags.partner-typed-arithmetic`: Whether `+`, `-`, `*`, `==`, `!=`, `<`, `>`, `<=` and `>=` cache anything on
  an operand depends on the *partner's* public flags: each opens with a fast path — neither operand `SVf_IVisUV` or
  `SVs_GMG`, then `flags = svl->sv_flags & svr->sv_flags`, `SVf_IOK` → integer arithmetic, else `SVf_NOK` →
  `lossless_NV_to_IV` on both or NV arithmetic — on which neither operand is converted; only off it does
  `SvIV_please_nomg` run (`sv_2iv_flags` when the operand has no `I` flag and has public `NOK` or `POK`).  The visible
  case is an integral public-`NOK` operand: against a fresh integer literal it gains public `IOK`, against a literal
  that has itself acquired public `NOK` it gains nothing, which is what makes Data::Dumper print `3` for `3.0 + 1` in
  one program and `'3'` in another.  `/`, `%`, `**`, `<=>`, `sort { $a <=> $b }` and unary minus always run
  `SvIV_please_nomg` on both operands and are not partner-typed.  `pp_add`, `pp_subtract`, `pp_multiply`, `pp_eq`,
  `pp_ne`, `pp_lt`, `pp_gt`, `pp_le`, `pp_ge`, `do_ncmp`, `SvIV_please_nomg` (sv.h); the model's `pp_add_partner_gate`
  in `models/ValueFlags/ValueFlags.pm`.  `suites/transitions/transitions/raw_transitions.5.44.0.tsv` row `f3
  NOK,pNOK|N:3 --add--> IOK,NOK,pIOK,pNOK|N:3`; `probes/research/value-flags/consumers.5.044000.out` rows `Float 3.0, +
  1` and `Float 3.0, == 3` (`DDxs` from `'3'` to `3`); the fifteen-operator enumeration in
  `models/ValueFlags/section.md` (§9, partner-typed operators). [5.44.0]
- `value-flags.increment-decrement`: `++` first drops COW (`SvTHINKFIRST`), converts an `NOKp`-without-`IOKp` value
  through `SvIV`, and then: public `IOK`, or `IOKp` without `NOKp`, increments the integer and ends in `SvIOK_only`
  (clearing `NOK`, `stringified`, `UTF8` and `IsUV`; `UV_MAX` → `Float` 2⁶⁴, `IV_MAX` → UV); `NOKp` adds 1 to the NV
  under `SvNOK_only`; not `POKp`, or an empty string, becomes `Int` 1; a string matching `/^[a-zA-Z]*[0-9]*\z/` carries
  as a string with no numeric mark — pure digits included, so `"9"++` is the plain string `"10"` and `"Az"++` is `"Ba"`;
  anything else goes through `grok_number` with `PERL_SCAN_TRAILING`: a number converts with `SvIV_nomg` and takes the
  integer path if that produced public `IOK` (`"-0"` → `Int` 1), else the NV path, and garbage becomes `sv_setnv(Atof +
  1)` (`"12x"` → `Float` 13, no warning).  So `3.0++` is `Int` 4 while `3.0--` stays `Float` 2.0: `--` has no
  `NOKp`-to-IV pre-step, no empty-string test (`""--` → `Float` −1), no string carry (`"Az"--` → `Float` −1) and no
  trailing-garbage scan.  `Perl_sv_inc_nomg`, `Perl_sv_dec_nomg`.
  `suites/transitions/transitions/raw_transitions.5.44.0.tsv` rows `s10 POK,pPOK|P:10 --inc--> POK,pPOK|P:11`, `s10
  POK,pPOK|P:10 --dec--> IOK,pIOK|N:9`, `s09 POK,pPOK|P:09 --inc--> POK,pPOK|P:10`, `sAz POK,pPOK|P:Az --inc-->
  POK,pPOK|P:Ba`, `sAz POK,pPOK|P:Az --dec--> NOK,pNOK|N:-1`, `sEmpty POK,pPOK|P: --inc--> IOK,pIOK|N:1`, `sEmpty
  POK,pPOK|P: --dec--> NOK,pNOK|N:-1`, `s12x POK,pPOK|P:12x --inc--> NOK,pNOK|N:13`, `sNeg0 POK,pPOK|P:-0 --inc-->
  IOK,pIOK|N:1`, `f3 NOK,pNOK|N:3 --inc--> IOK,pIOK|N:4`, `f3_5 NOK,pNOK|N:3.5 --inc--> NOK,pNOK|N:4.5`, `s10
  IOK,POK,pIOK,pPOK|P:10 --inc--> IOK,pIOK|N:11`; rows `$s++` and `--$s` of `probes/corpus/flags_matrix.pl`;
  `probes/research/value-model/07_num_jsonpp.pl` and `15_flags_peek.pl` (`one_inc`, `nine_inc`, `az_inc`). [5.44.0]
- `value-flags.copy-carries-flags`: `sv_setsv_flags` carries every value flag unchanged — public and private
  `IOK`/`NOK`/`POK`, `IsUV`, `UTF8` — and shares a `POK` source's buffer copy-on-write; the copy differs from its source
  only in `IsCOW` (set on both) and in not carrying a stale buffer a numeric source still owns, and every stdout
  consumer reads the same from the copy as from the original.  So a numeric mark travels with the value: a copy of a
  numified `"10"` encodes as `10`.  On the destination side `SV_CHECK_THINKFIRST_COW_DROP` runs first: a destination
  that was sharing drops its buffer, and whether the incoming string is shared or copied is decided by the destination's
  own buffer length, which is why the same assignment can leave a holder COW-shared or not and decide a later append
  (`B`-only until then).  Assignment from a literal installs the literal's kind, a string literal COW-shared with the op
  tree's constant; `undef $x` clears every flag (`SvOK_off`).  `Perl_sv_setsv_flags`, `pp_undef`.  The copy lane of
  `models/ValueFlags/reports/coverage.txt` (3,096 states, 0 consumer differences); rows `copy (report $t)`, `$s = $s`,
  `$s = "20"` and `undef $s` of `probes/corpus/flags_matrix.pl`; every `--copy-->` row of
  `suites/transitions/transitions/raw_transitions.5.44.0.tsv` (for one, `s12x POK,pIOK,pNOK,pPOK|P:12x --copy-->
  POK,pIOK,pNOK,pPOK|P:12x`); `probes/research/value-model/07_num_jsonpp.pl` (`copy=[10]`). [5.44.0]
- `value-flags.content-writes-clear`: A write to the string content ends in `SvPOK_only` or `SvPOK_only_UTF8` and clears
  every value flag, turning a number into a plain string: 4-argument and lvalue `substr` (`sv_insert_flags`), lvalue
  `vec` (`do_vecset`, which also downgrades `UTF8`), `s///` with a match, `tr///` with a replacement, `chop` on a
  non-empty string (`SvPV` first, then the force and `SvNIOK_off`), and `utf8::upgrade` on anything but a `POK` string
  (it returns at once for `undef`, keeps the value flags of a `POK` string and only sets `UTF8` on it, and forces a
  number through `sv_pvn_force_flags`).  `utf8::encode` likewise leaves a plain string.  `Perl_sv_insert_flags`,
  `Perl_do_vecset`, `pp_subst`, `S_do_chomp`, `Perl_sv_pvn_force_flags`, `Perl_sv_utf8_upgrade_flags_grow`.  Rows
  `substr lvalue`, `substr 4-arg`, `vec lvalue`, `s/(.)/$1/`, `tr/1/2/`, `chop`, `utf8::upgrade` and `utf8::encode` of
  `probes/corpus/flags_matrix.pl` (`P/s` from every start, `P8/s` for the upgrade);
  `suites/transitions/transitions/raw_transitions.5.44.0.tsv` rows `i10 IOK,pIOK|N:10 --utf8--> POK,pPOK,UTF8|P:10`
  against `s10 IOK,POK,pIOK,pPOK|P:10 --utf8--> IOK,POK,pIOK,pPOK,UTF8|P:10`;
  `probes/corpus/consumers_02_numeric_starts.pl` row `int 10, utf8::upgrade` (`P`, JSON `"10"`, `created_as_number` 0).
  [5.44.0]
- `value-flags.append-cow-clear`: `$x .= ...` forces the target with `SvPV_force_nomg_nolen`, and `Perl_SvPV_helper`
  skips the force only for `SvPOK_pure_nogthink` — public `POK` with no public `IOK`/`NOK` and not `SvTHINKFIRST`.
  Public numeric flags are therefore cleared by every append.  Private numeric flags are cleared when the buffer is
  still copy-on-write-shared with its literal or with a copy (COW is `THINKFIRST`, so the force's `SvPOK_only_UTF8`
  runs) and kept when the scalar owns its buffer — after one earlier append, a `utf8::upgrade` (`S_sv_uncow`) or a
  `++`/`--` (`sv_force_normal_flags`).  The appended length is irrelevant: `.= ""` behaves like `.= "x"`.
  `pp_multiconcat`, `Perl_SvPV_helper` (sv_inline.h), `S_sv_uncow`.
  `suites/transitions/transitions/raw_transitions.5.44.0.tsv` rows `s12x POK,pIOK,pNOK,pPOK|P:12x --cat0-->
  POK,pPOK|P:12x` (still sharing the literal) against `s12x POK,pIOK,pNOK,pPOK|P:12xx --cat0-->
  POK,pIOK,pNOK,pPOK|P:12xx` (numified after one append; its `--catx-->` row keeps them too), and `s10
  IOK,POK,pIOK,pPOK|P:10 --cat0--> POK,pPOK|P:10`; rows `$s .= ""` and `$s .= "0"` of `probes/corpus/flags_matrix.pl`;
  `probes/corpus/consumers_02_numeric_starts.pl` row `int 10, $s .= ""` (`P`, JSON `"10"`). [5.44.0]
- `value-flags.warn-handler-dual`: A `__WARN__` handler that mutates the scalar under conversion is the first way a
  cached number can disagree with its string.  On the integer path `S_sv_2iuv_common` calls `S_sv_setnv` — the NV slot
  from `Atof` of the *pre-handler* string — before `not_a_number`, and rereads `SvNVX` afterward: the effective number
  is the NV slot as the handler left it (`"12x"` with a handler that assigns `"99"` and reads it as a float is 99; one
  that assigns `"99"` and reads it as an integer, or assigns `Int` 99, leaves 12, since `sv_setiv` does not write the NV
  slot), the public `IOK`/`NOK` bits are then stripped (`SvFLAGS &= ~(SVf_IOK|SVf_NOK)` for `numtype == 0`) whatever the
  handler installed, and the result is written onto the scalar whatever kind it now has — an `Int` gets its value
  overwritten with `I_V` of the effective NV and becomes private-only.  The cache is then served: `"3abc"` whose handler
  assigned `"7xyz"` reads `7xyz` as a string and 3 as a number on every later use.  On the float path `sv_2nv_flags`
  warns first and parses the *current* string, so no `Dual` arises; the same strip runs there.  A number whose only
  value flags are private stringifies as uninitialized (`sv_2pv_flags` dispatches on `SvPOKp`, then public `SvIOK`, then
  public `SvNOK`, else `report_uninit`) while `defined` is true and numeric use returns the number.  A handler that
  changes the scalar's kind on the float path, and a reference holder reaching `non_preserve` with an infinite NV, are
  windows with no defined behavior (`undefined.md`, W1-W3).  `S_sv_2iuv_common`, `S_sv_setnv`, `S_not_a_number`,
  `Perl_sv_2nv_flags`, `Perl_sv_2pv_flags`.  The matrix lane of `models/ValueFlags/reports/coverage.txt` (2,304 rows,
  150 excluded as undefined); `suites/reentry-matrix`; `probes/corpus/num_01_warn_handler.pl` (a, b),
  `probes/corpus/num_02_stale_cache.pl`; `probes/research/value-model/10_num_warnmut.pl`, `17_warnmut_rows.pl` (`str+nv`
  99, `str+iv` 12, `num` with the empty stringification), `18_warnmut_matrix.pl`. [5.44.0]
- `value-flags.negative-zero-order`: `"-0"` converted on the integer path stores IV 0, a later float conversion derives
  NV 0.0 from the IV (`sv_2nv_flags`, `SvIOKp` branch), and `%g` prints `0` forever; converted float-first it stores
  −0.0 and `%g` prints `-0` forever, while `+ 0` prints `0` in both orders because the integer slot wins in `pp_add`.
  Both orders end in `INP`; which came first is the third `Dual` case.  A `Float` −0.0 likewise prints `-0` under `%g`
  but `0` through JSON::PP and Data::Dumper.  `Perl_sv_2nv_flags`, `S_sv_2iuv_common`.
  `probes/research/value-model/09_num_neg0.pl`, `15_flags_peek.pl` (`gfirst`, `intfirst`), `22_flags_synth.pl`
  (`neg0_gfirst`, `neg0_intfirst`); column `"-0"` of `probes/corpus/flags_matrix.pl`; `probes/corpus/consumers_01.pl`
  row 13 (`sprintf "%g"` of `"-0"`: `-0` plain, `0` marked); `probes/corpus/consumers_02_numeric_starts.pl` rows `float
  -0.0` and `float -0.0, $s|0`. [5.44.0]
- `value-flags.locale-radix-frozen`: Under `use locale` with a non-C `LC_NUMERIC`, `grok_number_flags` and `my_atof3`
  accept `PL_numeric_radix_sv` as a decimal point in addition to `.` while `IN_LC(LC_NUMERIC)`; nothing else in the
  conversion chain consults the locale, and `sv_2pv_flags` never caches a float's string form, so stringification is
  locale-sensitive at output time only.  The parse result is cached in the slot: the cache freezes whichever radix
  parsed first, a copy carries it across scope boundaries, and nothing ever reparses a cached value — `"3,5"` numified
  under de_DE is 3.5 outside the scope and a copy made after the numification is 3.5 under C, while a copy made before
  it parses fresh under whatever radix is then in effect; the `Dual` records the number, not the radix.  Under de_DE
  `"3,5"` and `"3.5"` both parse as 3.5 with public `NOK`, `"3,5x"` as 3.5 with private flags only, and `"1e3,5"` as
  1000, the radix not being accepted after an exponent.  A `setlocale` inside the `__WARN__` handler does not change the
  integer-path result, whose `Atof` ran before the handler.  `Perl_grok_number_flags`, `Perl_my_atof3`,
  `Perl_sv_2pv_flags`, `S_sv_2iuv_common`.  The locale lane of `models/ValueFlags/reports/coverage.txt`;
  `suites/transitions/locale/raw_transitions.5.44.0.tsv` rows `c35 POK,pPOK|P:3,5 --de_add-->
  NOK,POK,pIOK,pNOK,pPOK|P:3,5` against `c35 POK,pPOK|P:3,5 --nl_add--> POK,pIOK,pNOK,pPOK|P:3,5`, `c35x POK,pPOK|P:3,5x
  --de_iv--> POK,pIOK,pNOK,pPOK|P:3,5x`, `e35 POK,pPOK|P:1e3,5 --de_iv--> POK,pIOK,pNOK,pPOK|P:1e3,5`, and the `c35
  NOK,POK,pIOK,pNOK,pPOK|P:3,5 --nl_iv-->` row, unchanged; `probes/research/value-flags/locale.pl` with
  `locale.5.044000.out`; `probes/research/value-model/20_locale_radix.pl`. [5.44.0]
- `value-flags.constants-mutable-cells`: A compiled constant is a mutable flag cell.  A literal reached through an alias
  or reference site (`f("10")`, `for ("10")`, `\"10"`) is one READONLY SV per op tree, so value flags left on it by a
  numeric use persist across executions of the same code: the first call of a sub that numifies `$_[0]` sees `["10"]`
  through JSON::PP and the second sees `[10]`, and `$lo .. "zz"` is a string range until one execution numifies the
  right-hand literal, after which the same line is a numeric range on every later execution.  Each op holds its own
  constant, so a mark on one `"20"` does not reach copies made from another `"20"` in the same program, and a constant
  sub's value is one SV shared by every site that inlines it.  Compile-time folding over such a constant leaves value
  flags on it before runtime.  The partner-typed operators read a literal partner's public flags, so a literal's drift
  changes what its partner caches.  Under ithreads a thread's clone of the op tree carries the parent's marks as they
  stood at creation and marks made afterward in either interpreter stay there.  `pp_flop` (`RANGE_IS_NUMERIC`,
  pp_ctl.c), `SvIV_please_nomg` on the aliased constant.  `probes/corpus/consts_01_literal_mark.pl` (a, b, c);
  `probes/corpus/threads_01_const_marks.pl` (threaded family: 1-4); `probes/research/value-model/11_num_constcell.pl`;
  the `our $ZZ` note in `probes/corpus/consumers_01.pl`. [5.44.0]
- `value-flags.consumers`: Everything a program observes about the value flags through stdout goes through these
  readers.  `Scalar::Util::isdual` reads the private flags: `(SvPOK || SvPOKp) && (SvNIOK || SvNIOKp)`, so it is true
  for a numified string, a stringified integer, a stringified inf NV and a `dualvar`, false for a stringified finite
  float.  Data::Dumper's XS `Dumper` unquotes on public `IOK` plus a PV round-trip (`DD_is_integer`): `"10" + 0` prints
  `10`, `"10abc" + 0` (private flags only) prints `'10abc'`, and `" 10" + 0` has public `IOK` yet prints `' 10'`; its
  pure-Perl path differs (`3.0` prints `3` there and `'3'` from XS until an integer use).  JSON::PP tests `"" & $v` then
  `0+$v eq $v`, so a string encodes as a number once it carries any numeric flag and an integer stays a number after
  stringification.  `builtin::created_as_number` is public `NIOK` without `POK` and `created_as_string` public `POK` and
  not a boolean, so neither sees a cache mark: a numified `"10"` is still created as a string and a stringified `10` as
  a number.  Storable serializes a public-`POK` scalar as a string and a stringified integer still as an integer.  Of
  every flag a stringified integer or an integer-used float can acquire, only `pPOK` on the integer (through `isdual`)
  and public `IOK` on an integral float (through Dumper) reach stdout; the private cache flags themselves are
  `B`/`Devel::Peek`-only, and no reader consults a stale buffer when `SvPOKp` is off.  `isdual` (ListUtil.xs),
  `DD_is_integer` (Dumper.xs), `store_scalar` (Storable.xs).  `probes/corpus/consumers_01.pl` (default variant),
  `probes/corpus/consumers_02_numeric_starts.pl`, `probes/corpus/flags_01_observable.pl`;
  `probes/research/value-flags/consumers.pl` with `consumers.5.044000.out`;
  `probes/research/value-model/08_num_dumper.pl`, `23_isdual_pseen.pl`; the copy lane of
  `models/ValueFlags/reports/coverage.txt` (consumers through the copy and on the original agree on every state).
  [5.44.0]
- `value-flags.pad-reuse`: A lexical's pad SV is reused across executions of its scope when nothing else holds it at
  scope exit (`SAVEt_CLEARSV` clears it in place when `SvREFCNT(sv) == 1` and it is not an object) and abandoned for a
  fresh SV when a reference or closure has claimed it, so `\$x` taken on three iterations is one address when the
  reference is dropped each time and three distinct addresses when it is kept, and a reference kept on one iteration
  alone gives the pattern `A A B`.  A reused SV keeps its body type and buffer across the clear (the harness rules of
  `models/ValueFlags/README.md`, pass 7), and a buffer-owning holder takes the plain-copy arm of `sv_setsv_flags` on its
  next string assignment where a fresh holder shares the literal, so which arm a given assignment takes depends on the
  holder's history.  `Perl_leave_scope` (`SAVEt_CLEARSV`), `Perl_sv_setsv_flags`.
  `probes/research/value-model/14_pad_reuse.pl`, `19_closure_rearm.pl` (`a1_ne_a2`, `a2_eq_a3`),
  `probes/research/value-flags/p2.pl`; the holder-freshness column of `models/ValueFlags/reports/coverage.txt` (every
  lane runs on a fresh holder for this reason). [5.44.0]

## `local` and the save stack [save-stack]

Section: `models/SaveStack/section.md`.  Model: `models/SaveStack/SaveStack.pm` (488 cells; the 176 structural cells are
the `models/SaveStack/reports/table.*.tsv` rows whose mutation is `keep`, `shift1`, `shift2`, `unshift1`, `pop1`,
`push1`, `splice_rm`, `splice_ins`, `fill_neg1`, `fill0` or `refill`).  Probes: `probes/research/value-model/` (01-03),
`probes/corpus/local_*`, `probes/corpus/tie_*`.

Entries:

- `save-stack.record-holds-sv`: The save record for an element holds the element's SV, not its value: a reference taken
  before the `local` names that SV, reads the pre-`local` value throughout the scope, and a write through it is what the
  restore brings back.  `Perl_save_aelem_flags`, `Perl_leave_scope` (`SAVEt_AELEM`).  Probe:
  `probes/corpus/local_elem_sv_identity.pl`.  [5.44.0]
- `save-stack.installed-sv-is-ordinary`: The SV that `local` installs is an ordinary element: a structural operation
  (`shift`, `unshift`, `splice`) moves it and may return it to the program, and it lives on afterward with the localized
  value; nothing reclaims it at scope exit.  Undocumented; the same probe, and every structural model row (the `E=`
  column is that SV's value after the scope, reached through a reference taken inside it). [5.44.0]
- `save-stack.restore-by-index`: The restore is by the original index into whatever the array has become (`av_fetch(av,
  idx, 1)` in `Perl_leave_scope`): the saved SV goes back at that index whatever now occupies it, and an emptied array
  is extended to reach it.  perlsub documents the extension; the same probe. [5.44.0]
- `save-stack.restore-destroys-migrant`: Whatever element has migrated into the original index is destroyed by the
  restore, not moved aside: after `unshift @a, 7` the element that was at index 0 now sits at the localized index and is
  freed when the saved SV returns there (`plain/aeP/*/unshift1`: `7, 20, undef, 30` from `10, 20, 30`); after `shift @a`
  the element from above it is (`plain/aeP/*/shift1`: `undef, 20` from `10, 20, 30`, the `undef` being the SV `local`
  installed, now at index 0).  `Perl_leave_scope` (`SAVEt_AELEM`, whose `restore_sv` arm stores the saved SV over the
  slot and `SvREFCNT_dec`s what was there). [5.44.0]
- `save-stack.extension-leaves-holes`: The extension leaves the skipped slots as holes (`exists` false), not undef
  elements (`av_store` fills intermediate entries with NULL).  perlsub says "filling in the skipped elements with
  `undef`", which is not what happens.  The same probe; `plain/aeP/*/fill_neg1`. [5.44.0]
- `save-stack.absent-element-delete`: `local` on an absent element records a deletion of the original index
  (`SAVEt_ADELETE`), and the restore is `av_delete(av, idx)` on whatever the array has become: a no-op if the array has
  shrunk below that index (`Perl_av_delete` returns at `key > AvFILLp`), so the SV the `local` vivified survives in the
  array wherever a `shift` moved it (`plain/aeA/*/shift1`: it is at index 4, `$#a` is 4); a `push` leaves it deleted at
  its index and the pushed element beyond (`plain/aeA/*/push1`: holes at 3-5, `$#a` 6); an `unshift` moves it beyond the
  deleted index, where it stays (`plain/aeA/*/unshift1`: at index 6).  `Perl_save_adelete`, `Perl_leave_scope`
  (`SAVEt_ADELETE`), `Perl_av_delete`. [5.44.0]
- `save-stack.die-changes-nothing`: A `die` in the body changes none of this: the structural rows pair `ok` and `dieB`
  cells whose observations differ only in `$@`. [5.44.0]
- `save-stack.tied-restore-is-store`: On a tied array the restore is one `STORE` at the original index, whatever the tie
  now holds there: after `shift` it overwrites the element that moved down into that index, after `unshift` the one that
  moved up into it, exactly as the plain array's restore does (`tied/aeP/*/shift1`: `undef, 20` from `10, 20, 30`;
  `tied/aeP/*/unshift1`: `7, 20, undef, 30`).  The `undef` is the entry `STORE` of the bare `local` (`S:1:u` in the
  trace), which the tie class keeps as an element.  `Perl_leave_scope` (`SAVEt_AELEM`), `Perl_magic_setpack`. [5.44.0]
- `save-stack.tied-ref-names-index`: A reference to a tied element names the index, not an SV: `\$a[1]` is a proxy whose
  reads and writes go through `FETCH(1)` and `STORE(1)`, so after a structural move it reads whatever is at index 1 (the
  `E=` column of the tied rows: the reference captured inside the scope reads the restored value after it, where the
  plain rows' reads the installed SV wherever it went).  `Perl_av_fetch` on a magical array (av.c 271),
  `PERL_MAGIC_tiedelem`. [5.44.0]
- `save-stack.tied-local-is-value`: So `local` on a tied element is save-and-restore of a value, not substitution of an
  SV: the tie has one slot per index, the SV `local` installs is one more proxy for it (its set magic runs on
  installation, the `STORE` of undef before the `STORE` of the value), and a write through a reference taken before the
  `local` lands in that slot, overwriting the localized value for every reader, until the restore overwrites it in turn.
  On a plain array the same write lands in the parked SV and is what the restore brings back.  Model rows
  `tied/aeP/*/preref` (trace `S:1:77` inside the scope, `S:1:20` at exit, final `20`) against `plain/aeP/*/preref`
  (final `77`). [5.44.0]
- `save-stack.held-proxy-fetches-once`: A held proxy `FETCH`es once: `Perl_magic_getpack` sets `MGf_GSKIP` on every
  tied-element `FETCH` (mg.c 2240) and only a set through the proxy clears it (mg.c 287), so a second read returns the
  cached value, after a `shift` too, and a fresh `$a[1]` is a new proxy that `FETCH`es again.  A write through the proxy
  `STORE`s at the index and re-arms the `FETCH`.  `local $a[1]` saves and restores through proxies of its own, so a held
  proxy is not invalidated by the restore: first read before the `local`, it reports the pre-`local` value inside the
  scope and after it; first read inside the scope, it keeps reporting the localized value after the scope ends.  The
  tied rows read their captured reference once, after the scope.  Probes:
  `probes/research/value-model/27_tied_elem_proxy_cache.pl`, `26_weaken_tied_elem.pl` (C). [5.44.0]
- `save-stack.tied-iteration-and-args`: A tied array under `foreach` is read by index with `FETCHSIZE` consulted before
  every iteration and once more at exit, so `shift`, `push` and `$#a = 0` in the body give the same visible element
  sequence as on a plain array (`pp_iter` calls `av_fetch(av, ix, FALSE)` on a magical array).  Flattening `@a` into a
  sub call or a `foreach` list is one `FETCHSIZE` and one proxy per element with no `FETCH` until a read, and a read of
  `$_[2]` twice is one `FETCH`; `my @copy = @a` and `"@a"` `FETCH` every element; `f($a[0])` runs nothing.  Every
  syntactic `$a[0]`, two in one list, one expression or one argument list included, is its own proxy with its own
  once-only `FETCH` and a different address.  A tied hash flattened into a call or into `foreach (values %h)` is a key
  walk (`FIRSTKEY`, `NEXTKEY`) with one value proxy per key and no `FETCH` until a read; `my @copy = %h` `FETCH`es every
  value; `f($h{k})` runs nothing.  Probe: `probes/corpus/tied_01_iteration_and_args.pl` (lane A). [5.44.0]
- `save-stack.proxy-acquires-magic`: A tied-element proxy can acquire a second magic.  `tie $a[0], ...` on the temporary
  proxy is lost with it and a fresh `$a[0]` goes to the array's class alone.  On a held proxy the magics chain in
  attachment order and `MGf_GSKIP` is per magic (`Perl_mg_get` tests it on each entry, mg.c 188): a scalar tie's `FETCH`
  runs on every read while the element's `FETCH` runs once, a write runs both `STORE`s (scalar tie first) and re-arms
  the element `FETCH`, and the kill of a weakened doubly magical proxy runs both `STORE(undef)`s.  Probe:
  `probes/corpus/tied_02_proxy_acquires_magic.pl` (lane A). [5.44.0]
- `save-stack.weaken-unprimed-proxy`: `weaken` on a held proxy whose slot has never been read is a silent no-op
  (`Perl_sv_rvweaken` returns on `!SvOK`), so a later read primes the proxy with a *strong* copy and the referent cannot
  die while the proxy lives; primed first, the same proxy is a weak holder cleared at death.  Which `Scalar::Util`
  functions `FETCH` an unprimed proxy: `blessed`, `reftype`, `refaddr`, `readonly` and `isweak` do — `isweak` is
  `builtin::is_weak` since 5.40, and `pp_is_weak` runs `SvGETMAGIC` — while `weaken` and `unweaken` never do
  (`pp_weaken` calls `sv_rvweaken` with no get-magic).  Probe: `probes/corpus/tied_03_unprimed_proxy_getmagic.pl` (lane
  A). [5.44.0]
- `save-stack.weaken-tied-element`: `weaken` on a tied element acts on the proxy's own slot and runs no set magic:
  `weaken $a[0]` has no lasting effect (the proxy dies with the statement and the tie's slot stays strong), and a proxy
  held through `\$a[0]`, read once so its slot is filled, then weakened, is a weak holder whose set magic is the tie's
  `STORE`: when the referent dies the kill clears the proxy and runs `STORE(0, undef)`.  Same probe (A, B). [5.44.0]
- `save-stack.tied-absent-delete`: An absent element localized on a tied array is deleted on unwind by `DELETE(idx)`
  with no `STORE`, and the tie's structural methods see only what was stored: a bare `local $a[5]` on a tied array of
  three stores nothing, so the tie never grows (`tied/aeA/bare/unshift1`: `7, 10, 20, 30`), while the assigned form
  stores `50` at 5 and a later `shift` or `unshift` moves it like any element (`tied/aeA/assign/shift1`: at index 4).
  `Perl_save_adelete`, `Perl_av_delete` on a tied array (av.c 1071). [5.44.0]
- `save-stack.tied-absent-preref`: A proxy taken before `local` and written through inside the scope changes nothing
  about the unwind: on a present index or key the `STORE` reaches the tie and the restore writes the saved value over it
  (the held proxy keeps reporting what it last stored); on an index past the end or an absent key the `STORE` reaches
  the tie too, the unwind still `DELETE`s, because `local` recorded the element's absence when it ran
  (`SAVEADELETE`/`SAVEHDELETE` on `!preeminent`, pp_hot.c), and the held proxy reads undef afterward.  Probe:
  `probes/corpus/local_04_tied_absent_preref.pl` (lane A).  [5.44.0]
- `save-stack.shared-restore-twice`: On a `threads::shared` array the restore writes the saved value twice.  The element
  proxy carries tied-element magic addressing the aggregate by index and shared-scalar magic pointing at the shared
  element SV itself, and the exit `mg_set` runs both: the scalar magic stores into that SV wherever a `shift` or
  `unshift` has moved it, then the element magic stores at the original index.  `local $a[1] = 99; shift @a` on `(10,
  20, 30)` leaves `(20, 20)` where a plain array leaves `(99, 20)`; the `unshift` form leaves `(0, 20, 20, 30)` against
  `(0, 20, 99, 30)`.  No second thread is involved.  `sharedsv_scalar_mg_set`, `sharedsv_elem_mg_STORE` and the magic
  ordering noted above it (dist/threads-shared/shared.xs).  Probes: `probes/corpus/local_03_shared_elem_move.pl`
  (threaded family) and `probes/research/value-model/24_local_shared_elem.pl`, which has the mechanism. [5.44.0]
- `save-stack.shared-local-in-place`: `local` on a `threads::shared` variable, scalar or element, overwrites the shared
  cell in place: every other thread reads the localized value for as long as the scope lasts, and the saved value comes
  back when it ends.  `mg_localize` copies the shared-scalar magic onto the fresh proxy, so its entry `STORE` lands in
  the same shared cell.  Probe: `probes/corpus/threads_02_shared_local.pl` (A, F), with the threads handed off by
  condition variable so the interleaving is fixed. [5.44.0]
- `save-stack.shared-restore-any-thread`: The two-address restore is the same whichever thread moved the array: a
  `shift`, `unshift` or `push` by another thread while the local is active leaves the same `(20, 20)` and `(0, 20, 20,
  30, 40)` that one thread produces, seen by both threads.  The same probe (A, B, D). [5.44.0]
- `save-stack.shared-two-threads`: Two threads localizing the same shared element each write back their own saved value
  when their scope ends, in whatever order the scopes end: child `99` over `20`, main `7` over `99`, main exits and `99`
  returns, child exits and `20` returns.  There is no save stack across threads, only each thread's own.  The same probe
  (C). [5.44.0]
- `save-stack.shared-absent-never-deleted`: An absent element or key of a shared aggregate is never deleted on unwind,
  because it is never recorded as absent: `pp_aelem` and `pp_helem` consult `EXISTS` only when the tie class also has a
  `DELETE` method (`SvCANEXISTDELETE`, inline.h 1227), and `threads::shared::tie` has `EXISTS` but no `DELETE` (deletion
  goes through the element magic's clear), so the element counts as preeminent, `save_aelem`/`save_helem` record the
  fresh proxy's `undef`, and the restore `STORE`s that `undef` at the index.  `{ local $a[5] = 50 }` leaves a shared
  array of three six long with `$a[5]` existing and undef; `{ local $h{new} = 3 }` leaves `new` existing and undef; a
  present key deleted by the other thread during the local is restored by the same `STORE`.  The same probe (E, G);
  `probes/research/value-flags/p4.pl` for the single-thread hash form. [5.44.0]

## Finalization and temporary lifetime [finalization]

Section: `models/Finalization/section.md`.  Model: `models/Finalization/Finalization.pm` (114 scenarios).  Probes:
`probes/research/value-model/` (04-06, 16, 19, 21), `probes/corpus/destroy_*`, `probes/corpus/gd_*`.

Entries (the transition function is the section text; these are the weak-reference facts a reader looks for by name):

- `finalization.weak-cleared-after-destroy`: Weak references to a dying object are cleared after its `DESTROY` returns,
  not before: inside the destructor every weak reference to the object is still defined.  `Perl_sv_clear` runs `S_curse`
  first and `Perl_sv_kill_backrefs` after it.  Probe: `probes/corpus/destroy_01_weak.pl`; model rows `undef.*`,
  `assign.*`, `cat.*` in `models/Finalization/reports/traces.*.txt` (the `[1]` after each `D` is the weak holder,
  defined). [5.44.0]
- `finalization.resurrection-keeps-weak`: If `DESTROY` resurrects the object (stores `$_[0]` somewhere), its weak
  references are not cleared: `S_curse` returns false when the count is still positive and `sv_clear` stops before the
  kill, so the weak references keep pointing at the live object and the next death runs `DESTROY` again.  Model rows
  `undef.K`, `assign.K`, `cat.K` (class `K` copies `$_[0]` into a global; the second `Da:K[1]` is the weak holder still
  defined at the next death). [5.44.0]
- `finalization.weak-flag-on-holder`: The weak flag belongs to the holder SV, never to the value: a copy of a weak
  reference by assignment, list assignment, `shift` or `pop` of a weak element, a sub's return, or a hash value read out
  is a strong reference that keeps the referent alive, while the holder it was copied from stays weak and is cleared at
  death wherever it has moved to (the element SV `shift` returns keeps its flag).  `Perl_sv_setsv_flags` sets the new RV
  without `SvWEAKREF`.  Probe: `probes/corpus/weak_03_copy_is_strong.pl` (lane A). [5.44.0]
- `finalization.kill-backrefs-order`: The clearing is a store with set magic: for each weak referrer, in backref-array
  order, `SvRV_set(referrer, 0)`, `SvROK_off`, `SvWEAKREF_off`, then `SvSETMAGIC`.  The array order is weaken order
  permuted by removals: `weaken` appends, and a holder that dies or is overwritten is removed by advancing the array
  start if it is first, shortening the array if it is last, and otherwise moving the last entry into its place
  (`Perl_sv_del_backref`; five holders with the second undefined are cleared first, fifth, third, fourth; finalization
  model row `tiedweak.order`, and every arm in `probes/corpus/weak_02_backref_order.pl`: removing the first clears `b c
  d e`, the last `a b c d`, a middle one `a e c d`, two middles `a e d`, and all but the middle leaves `c`).  A tied
  holder therefore runs its `STORE(undef)` at the moment the referent dies, and a `STORE` that dies propagates out of
  the operation that killed the object, leaving the later referrers uncleared.  This is the only way the moment of
  clearing is observable from Perl; without set magic a weak reference is observed only when read.
  `Perl_sv_kill_backrefs` (sv.c 6987-6990).  Model rows `tiedweak.T`, `tiedweak.TX`. [5.44.0]
- `finalization.kill-in-progress-visible`: The clearing is visible in progress: a tied holder's `STORE(undef)` runs
  before the later holders are cleared, so from inside it a later weak reference to the same dying object is still
  defined and `isweak`; after the kill it is undef.  The destructor has already run and committed (`S_curse` before the
  kill, which also runs `SvOBJECT_off`), and nothing rechecks the count after the kill.  Reads through that later holder
  from inside the `STORE` are defined: `ref`, `reftype`, `refaddr` and the elements are intact, the elements are
  writable, and the object is already unblessed — `blessed` is undef and a method call dies `Can't call method ... on
  unblessed reference`.  Every *upgrade* of the holder — a kept or transient strong copy, a new weak reference, a
  rebless — is a crash or a leaked freed SV, and undefining the later holder there croaks `panic: del_backref`
  (undefined window, `undefined.md`).  Probes: `probes/corpus/weak_01_death_window_reads.pl` (the defined side; lane A),
  `probes/research/value-model/25_kill_backrefs_reentry.pl` (the upgrades). [5.44.0]
- `finalization.shared-weak-per-thread`: Under ithreads a weak reference to a `threads::shared` object is per thread:
  each thread reaches the shared referent through its own proxy SV, the weak reference is to that proxy, and it is
  cleared when the thread's last strong reference dies even though the referent lives on in another thread.  The
  referent dies, and `DESTROY` runs, in whichever thread drops the last proxy.  So a thread cannot hold only a weak
  reference to a shared object, and no thread can resurrect a shared object from another thread's `DESTROY`: its weak
  references are undef before that `DESTROY` can begin.  Probe: `probes/corpus/threads_03_shared_weak.pl` (lane A,
  threaded family). [5.44.0]

## The hash engine [hash-engine]

Section: `models/HashEngine/section.md`.  Model: `models/HashEngine/HashEngine.pm` (bucket-level and program-level
lanes).  Probes: `probes/research/value-model/` (12, 13), `probes/corpus/each_*`, `probes/corpus/order_*`.

Entries:

- `hash-engine.hash-function-by-length`: A key's hash is a function of the seed and the key bytes alone, computed by one
  of two functions chosen by length: SBOX32 for a key of at most `SBOX32_MAX_LEN` = 24 bytes (the seeded initial word
  XORed with one table word per byte position, no mixing), SipHash-1-3 for a longer one (one `SIPROUND` per 8-byte
  block, the tail packed under `len << 56`, `v2 ^= 0xff`, three final rounds, the two 32-bit halves XORed together).
  `Perl_get_hash_seed` fills the 32-byte seed from the hex digits of `PERL_HASH_SEED` (a value of `0` is thirty-two zero
  bytes); `PVT_PERL_HASH_SEED_STATE` expands its first sixteen bytes into the SipHash state and its last sixteen into
  the SBOX32 table.  `Perl_get_hash_seed`, `PVT_PERL_HASH_WITH_STATE`, `sbox32_hash_with_state`,
  `S_perl_hash_siphash_1_3_with_state`, `sbox32_seed_state128`, `S_perl_siphash_seed_state`.  Model rows
  `structure.seed0.*` and `structure.seedX_perturb0.*` of `models/HashEngine/generators/hv_gen.pl` (5, 40, 700 and 5,000
  keys, one key in seven longer than 24 bytes), every key's `Hash::Util::hash_value` against the model, 28 of 28 in
  `models/HashEngine/reports/hv.5.44.0.txt`; the `EXCLUDED structure.seedX_perturb2.*` lines of the same report, where
  the hash values still match while the buckets do not.  [5.44.0]
- `hash-engine.perturbation-modes`: `PERL_HASH_SEED=0` implies `PERL_PERTURB_KEYS=0` unless overridden, and under
  `PERL_PERTURB_KEYS=0` the perturbation value `PL_hash_rand_bits` never changes from its seed-derived start (the
  constant `0xbe49d17f` with the leading seed bytes folded in through `ROTL_UV(…, 8)`), so chain placement, split points
  and traversal are functions of the seed and the hash's own operations alone, unaffected by any other hash activity in
  the process.  Any other seed without an override is DETERMINISTIC mode (`PERL_PERTURB_KEYS=2`): every colliding insert
  and every split advances the value through `PERL_XORSHIFT64_A`, so the layout of a hash depends on every hash
  operation the process performed before it, the interpreter's own startup included, and does not match across
  interpreters or builds.  `Perl_get_hash_seed`, `UPDATE_HASH_RAND_BITS_KEY`, `MAYBE_UPDATE_HASH_RAND_BITS`.  Probe:
  `probes/corpus/order_02_modes.pl` (lane A; its `noise0`, `noise3` and `noise50` variants, which fill an unrelated hash
  with 0, 3 or 50 keys first, print the same 16-key order at seed 0, on the other family's build too, while the seed
  ladder does not agree with seed 0, `also_lane_b` 0); the `EXCLUDED structure.seedX_perturb2.*` lines of
  `models/HashEngine/reports/hv.5.44.0.txt`, whose buckets differ from the model's while every per-key hash value
  matches.  [5.44.0]
- `hash-engine.seed0-reproducible`: Under `PERL_HASH_SEED=0`, and under any explicit seed with `PERL_PERTURB_KEYS=0`,
  iteration order, chain order, split points, the traversal mask and destruction order are reproduced exactly by the
  transcription in `models/HashEngine/HashEngine.pm` for the profile (64-bit, `PERL_HASH_FUNC_SIPHASH13` with `SBOX32`,
  `PERL_HASH_RANDOMIZE_KEYS`, `PERL_HASH_DEFAULT_HvMAX` = 7).  `Perl_hv_common`, `S_hsplit`, `S_hv_auxinit`,
  `Perl_hv_iternext_flags`.  Every `structure.*` and `program.*` row of `models/HashEngine/generators/hv_gen.pl` in both
  lanes, `ok=28 bad=0` in `models/HashEngine/reports/hv.5.44.0.txt`; probe `probes/corpus/order_01_model.pl` (lane A).
  [5.44.0]
- `hash-engine.head-insert-and-split`: A hash is an array of `HvMAX + 1` buckets, 8 to begin with, each a singly linked
  chain, and `Perl_hv_common` links a new entry at the head of its bucket (`HeNEXT(entry) = *oentry; *oentry = entry`).
  The insert then tests `DO_HSPLIT`, `keys + keys/2 > max`, and only when it collided with an occupied bucket
  (`in_collision`), so a hash whose keys all land in distinct buckets is not split by count alone.  `S_hsplit` doubles
  the array, walks the old buckets in index order and each chain from its head, and pushes every entry whose hash has
  the new bit set onto the head of its new bucket, so moved entries end up in reverse of their previous order while
  entries that stay keep theirs.  `Perl_hv_common`, `DO_HSPLIT`, `S_hsplit`.  Model rows `structure.seed0.*` and
  `structure.seedX_perturb0.*` (`Hash::Util::bucket_array` against the model, chain order included, through the splits
  up to 5,000 keys); probe `probes/corpus/order_01_model.pl` (lane A: 5, 40 and 700 keys occupy 8, 64 and 2,048
  buckets).  [5.44.0]
- `hash-engine.traversal-is-bucket-xor-mask`: The iterator lives in `HvAUX`, allocated on first use with `riter` -1, no
  current entry, and `xhv_rand` taken from `PL_hash_rand_bits` as a 32-bit value.  `Perl_hv_iternext_flags` continues
  from `HeNEXT` of the current entry, else advances `riter` until bucket `(riter ^ xhv_rand) & max` is non-empty, so the
  order `keys`, `values` and `each` deliver is bucket order permuted by XOR with the mask, each chain head to tail; past
  `max` it sets `riter` back to -1 and returns nothing, and the next `each` starts over.
  `Hash::Util::hash_traversal_mask` returns `xhv_rand`, which under seed 0 is `0xbe49d17f` for every hash.
  `S_hv_auxinit`, `PERL_HASH_ITER_BUCKET`, `Perl_hv_iternext_flags`.  Probe: `probes/corpus/order_01_model.pl` (lane A:
  for 5, 40 and 700 keys the walk over `bucket_array` at `(riter ^ mask) & max` equals `keys`, and the mask prints the
  same at every size); `probes/corpus/each_04_reset.pl` (lane A: after exhaustion the next `each` returns a key again);
  model rows `structure.*` (the mask), `program.*.keys20`, `program.*.each20`.  [5.44.0]
- `hash-engine.keys-values-reset-iterator`: `keys` and `values` reset the iterator before and after their walk, in void,
  scalar and list context alike, and so does flattening the hash in list context (`my %copy = %h`): the next `each`
  returns the first key again.  `scalar(%h)`, `%h` in boolean context, `exists`, a fetch, a store to an existing key and
  a `delete` of another key leave the iterator where it was.  `Perl_hv_iterinit` (which also frees a lazily deleted
  current entry).  Probe: `probes/corpus/each_04_reset.pl` (lane A, the same on the seed ladder); model rows
  `program.*.reset`; `probes/research/value-model/12_each_semantics.pl` (`keys_resets=1`, `scalar_exists_preserve=1`).
  [5.44.0]
- `hash-engine.delete-current-is-lazy`: Deleting the key `each` just returned is safe: `S_hv_delete_common` unlinks the
  entry from its chain but flags it `HvLAZYDEL` and keeps it alive, the next `Perl_hv_iternext_flags` continues from its
  `HeNEXT` and then frees it, so a `while (my ($k) = each %h) { delete $h{$k} }` visits every key exactly once and
  leaves the hash empty.  `S_hv_delete_common`, `Perl_hv_iternext_flags`.  Probe:
  `probes/corpus/each_01_delete_current.pl` (lane A, the same on the seed ladder: 52 keys, 52 visited, no duplicate,
  none left); model rows `program.*.delcur`; `probes/research/value-model/12_each_semantics.pl` (`delcur: iters=10
  left=0`).  [5.44.0]
- `hash-engine.delete-other-unlinks-now`: Deleting any other key during an `each` walk unlinks it at once and the walk
  is otherwise unaffected: a not-yet-visited key is never returned and the remaining keys come in the order a prior
  `keys` gave them.  Deleting the lazily deleted current entry's chain successor patches `HeNEXT` of the lazy entry, so
  deleting the current key and another key in the same iteration still visits each key at most once and empties the
  hash.  `S_hv_delete_common`.  Probe: `probes/corpus/each_02_delete_other.pl` (lane A: `unvisited-deleted skipped,
  remaining order preserved: yes`; 2,000 keys with the current key and its numeric successor deleted each step, no
  duplicate, none left); model rows `program.*.delother`; `probes/research/value-model/12_each_semantics.pl` (`delother:
  victim_returned=0`).  [5.44.0]
- `hash-engine.insert-during-each-revisits`: Inserting during an `each` walk may split the array, and `S_hsplit` relinks
  entries into buckets the walk has already passed or not yet reached, so keys can be visited twice or never; this
  happens at seed 0 as well, where the result is deterministic.  `Perl_hv_common`, `DO_HSPLIT`, `S_hsplit`.  Probe:
  `probes/corpus/each_03_insert.pl` (lane A: from 5 keys, inserting one new key at every step, the walk ends after 13
  steps having returned 9 distinct keys with 4 duplicates while the hash holds 18); model rows `program.*.inseach`;
  `probes/research/value-model/12_each_semantics.pl` (`dups` and `missed` both nonzero at seed 0 and in the default
  mode).  [5.44.0]
- `hash-engine.insert-warning-needs-perturbation`: The warning `Use of each() on hash after insertion without resetting
  hash iterator results in undefined behavior` is emitted by `Perl_hv_iternext_flags` when `xhv_last_rand != xhv_rand`
  while `riter != -1`, and an insert changes `xhv_rand` only under perturbation (a colliding insert or a split advances
  `PL_hash_rand_bits`, and `Perl_hv_common` copies it into the aux struct).  Under `PERL_HASH_SEED=0` `xhv_rand` never
  changes, so inserts during `each` are silent; in the default (RANDOM) mode and under a nonzero seed the same program
  warns on the `each` after the insert.  `Perl_hv_iternext_flags`, `Perl_hv_common`, `UPDATE_HASH_RAND_BITS_KEY`.
  Probes: `probes/corpus/order_03_insert_warn_modes.pl` (lane A: `done` with no `WARN` at seed 0) and
  `probes/corpus/each_03_insert.pl` (lane A: no warning across its 13 inserts at seed 0), with their default-mode and
  `PERL_HASH_SEED=12345678` runs in `probes/research/foundations/out/` (`WARN` on every `each` after an insert);
  `probes/research/value-model/12_each_semantics.pl` (`warned=1` in the default mode, `warned=0` at seed 0).  [5.44.0]
- `hash-engine.clear-keeps-array-undef-releases`: `%h = ()` frees the entries and resets the iterator but keeps the
  bucket array at its current size, so a refill goes into the grown array; `undef %h` releases the array as well, so a
  refill starts again at 8 buckets and splits as it grows.  The two therefore give the same refilled key set different
  orders.  `Perl_hv_clear`, `Perl_hv_undef_flags`.  Probe: `probes/corpus/each_05_clear.pl` (lane A: a 1,000-key hash
  cleared and refilled with three keys is `3/2048` where a fresh hash is `3/8` and the `keys` orders differ, `2 3 1`
  against `3 1 2`; the same hash undefined and refilled is `3/8`; `each` after a clear and refill visits all 10 keys);
  `probes/research/value-model/13_hash_clear_peek.pl` (`HvMAX` 255 kept by `%h = ()`, 7 after `undef %h`); model rows
  `program.*.clearfill`, `program.*.undeffill`.  [5.44.0]
- `hash-engine.destroy-in-raw-bucket-order`: When a hash is freed its entries go in raw bucket order, index 0 upward,
  each chain head to tail, and `DESTROY` on the values follows that order: not the traversal permutation, and unchanged
  by a prior `keys` or `each`.  `Perl_hfree_next_entry`.  Probe: `probes/corpus/destroy_02_order.pl` (lane A: eight
  objects keyed `a`..`h`, `keys` order `h f e c d b g a`, destruction order `a g d b f e c h`); model rows
  `program.*.destroy`, `program.*.destroy_after_iter`.  [5.44.0]
- `hash-engine.tied-each-method-calls`: On a tied hash `each` in scalar context is one `FIRSTKEY` or `NEXTKEY(last key)`
  and no `FETCH`; in list context the key call is followed by one `FETCH` of that key.  `keys` in void context calls no
  method at all (`Perl_hv_iterinit` resets the iterator without one), and the next `each` starts over with `FIRSTKEY`;
  `keys` in scalar context is a full `FIRSTKEY`/`NEXTKEY` walk; `scalar(%t)` and `%t` in boolean context call `SCALAR`;
  `%t = ()` is one `CLEAR`, and `%t = (x => 1)` is `CLEAR` then `STORE(x, 1)`.  Deleting the current key during the walk
  is `DELETE(b)` and then `NEXTKEY(b)`, the deleted key still handed to the tie as the last key
  (`Perl_hv_iternext_flags` keeps one synthetic `HE` per magical hash and frees it through `HvLAZYDEL`).
  `Perl_hv_iternext_flags`, `Perl_hv_iterinit`.  Probes: `probes/corpus/each_06_tied.pl` and
  `probes/corpus/each_07_tied_keys_void.pl` (lane A, the same on the seed ladder: `each`, `each`, `keys` in void
  context, `each` logs `FIRSTKEY NEXTKEY(a) FIRSTKEY` and the third key is `a` again).  [5.44.0]

## The UTF-8 flag and taint [string-flags]

Section: `models/StringFlags/section.md`.  Model: `models/StringFlags/StringFlags.pm` (in progress; `status.md`).

Entries (model rows only; the model is in progress and only rows that match are cited, `status.md`):

- `string-flags.flag-is-interpretation`: The UTF-8 flag (`SVf_UTF8`) is a claim about how to read a string's bytes, not
  a property of its content: with it off each byte is one character whose code point is the byte value; with it on the
  bytes are decoded as UTF-8 (`utf8n_to_uvchr`, `Perl_utf8_length`), and `length`, `substr`, `reverse`, `chop`, `ord`,
  `index`, `split //` and `tr///` operate on the decoded characters, their string results keeping the flag.  The same
  bytes under different flags are different strings: `"\xC2\xB5\xC3\xA9"` flagged is the two characters U+00B5 U+00E9,
  unflagged it is four.  Model rows `models/StringFlags/reports/table.5.44.0.tsv`, named `family.context.taint.op`
  (families `A` `"abc"`, `B` `"\xB5\xE9"`, `L` the same upgraded, `H` `"a\x{100}"`, `M` `"\xC3\x28"` flagged by
  `Encode::_utf8_on`, `E` `""`; context `none`, `feature` for `unicode_strings`, or `locale`; `U` untainted or `T`
  tainted; columns bytes, flag, length, ords, tainted): `L.none.U.copy` (bytes `c2b5c3a9`, flag 1, length 2, ords
  181,233) against `L.none.U.enc` (the same bytes, flag 0, length 4, ords 194,181,195,169); `L.none.U.sub1`,
  `L.none.U.rev`, `L.none.U.chop`, `L.none.U.tr` and `L.none.U.split` work character by character and return flagged
  strings, `B.none.U.sub1`, `B.none.U.rev`, `B.none.U.chop` and `B.none.U.tr` byte by byte and return bytes. [5.44.0]
- `string-flags.malformed-lenient-readers`: The claim need not be true: `Encode::_utf8_on` can flag malformed bytes, and
  the lenient readers accept them.  `Perl_utf8_length` advances by the `UTF8SKIP` of the lead byte, so a malformed
  sequence counts as one character, `ord` of it reads 0 (`utf8n_to_uvchr`), and its bytes travel with the character
  unchanged through `substr` and concatenation.  Rows `M.none.U.len` (1), `M.none.U.ord` (0), `M.none.U.sub1` (`c328`,
  flag 1, one character), `M.none.U.split` (one field, ord 0), `M.none.U.catb` (`c328c2b5`, ords 0,181); `utf8::encode`
  hands the bytes back as they are (`M.none.U.enc`: `c328`, flag 0, length 2). [5.44.0]
- `string-flags.equality-by-code-point`: Two strings are `eq`, and `cmp` 0, when their code point sequences are equal
  whatever their flags, and `index` finds an unflagged needle in a flagged string: `"\xB5\xE9"` unflagged equals its
  upgrade both ways, and `index($s, "\xB5")` is 0 on either form.  `Perl_sv_eq_flags`, `Perl_sv_cmp_flags` (a flag
  mismatch is resolved by comparing code points, not bytes).  Rows `B.none.U.eql`, `L.none.U.eqb` (1), `B.none.U.cmpb`,
  `L.none.U.cmpb` (0), `B.none.U.idx`, `L.none.U.idx` (0); `H.none.U.eqb` (0). [5.44.0]
- `string-flags.upgrade-downgrade`: `utf8::upgrade` (`sv_utf8_upgrade_flags_grow`) re-encodes each byte as a UTF-8
  character and sets the flag without changing the character sequence, on an empty string too, and does nothing to a
  string already flagged; `utf8::downgrade` (`sv_utf8_downgrade_flags`) replaces each character by its byte and clears
  the flag, and a character above 0xFF, or a malformed sequence, makes it die `Wide character in subroutine entry`, or
  under `utf8::downgrade($s, 1)` leave the string unchanged.  Neither touches taint.  Rows `B.none.U.up` (`c2b5c3a9`,
  flag 1, ords 181,233 as before), `A.none.U.up`, `E.none.U.up` (empty, flag 1), `L.none.U.up` and `H.none.U.up`
  (unchanged); `L.none.U.down` (`b5e9`, flag 0), `H.none.U.down` and `M.none.U.down` (the croak), `H.none.U.downok` and
  `M.none.U.downok` (unchanged); the `T` rows of each keep tainted 1. [5.44.0]
- `string-flags.encode-decode`: `utf8::encode` (`sv_utf8_encode`) upgrades and then clears the flag (`SvUTF8_off`), so
  the bytes become the UTF-8 encoding and `length` counts them; `utf8::decode` (`sv_utf8_decode`) first downgrades
  (`sv_utf8_downgrade(sv, TRUE)`), so a flagged Latin-1 string comes back as its bytes, and then sets the flag only if
  the bytes are valid UTF-8 containing a high byte: neither ASCII-only bytes nor the invalid `"\xB5\xE9"` are flagged by
  it, and a string that cannot be downgraded is left as it is.  Rows `B.none.U.enc` and `L.none.U.enc` (both `c2b5c3a9`,
  flag 0, length 4), `H.none.U.enc` (`61c480`, length 3); `L.none.U.dec` (`b5e9`, flag 0), `A.none.U.dec` and
  `B.none.U.dec` (unchanged, flag 0), `H.none.U.dec` and `M.none.U.dec` (unchanged, flag 1). [5.44.0]
- `string-flags.concat-flag-union`: Concatenation reads the flags of all operands (`pp_multiconcat`, `S_do_concat`): if
  any is flagged the result is flagged and every unflagged operand is upgraded for the copy, so `"\xB5\xE9" . "\x{100}"`
  is three characters whose first two are U+00B5 U+00E9; if none is flagged the result is bytes.  `.=` applies the rule
  to the target in place, so appending a flagged string to an unflagged target, an empty one included, upgrades the
  target.  `join` and `x` follow concatenation; `sprintf "%s"`, `pack "a*"` and `pack "A*"` copy the argument's flag;
  `chr` and `sprintf "%c"` give an unflagged byte for a code point at most 0xFF (`pp_chr`, `Perl_sv_vcatpvfn_flags`),
  while `pack "U"` always flags (`pp_pack`).  Rows `B.none.U.catu` (`c2b5c3a9c480`, flag 1, ords 181,233,256),
  `B.none.U.catl` (a flagged `"\xB5"` appended: flag 1), `H.none.U.catb` (the unflagged `"\xB5"` becomes U+00B5),
  `B.none.U.catb` (`b5e9b5`, flag 0); `B.none.U.apu`, `B.none.U.apl`, `E.none.U.apl` (`c2b5`, flag 1), `B.none.U.apb`
  (flag 0); `B.none.U.joinu` (flag 1) and `B.none.U.joinb` (flag 0), `H.none.U.rep` and `B.none.U.rep`, `L.none.U.sps`
  and `B.none.U.sps`, `L.none.U.packa` and `L.none.U.packA`; `B.none.U.chr` and `B.none.U.spc` (`b5`, flag 0),
  `B.none.U.packU` (`c2b5`, flag 1) and `A.none.U.packU` (`61`, flag 1). [5.44.0]
- `string-flags.unicode-bug`: Whether a character in 0x80–0xFF has a case mapping or belongs to `\w` depends on the
  string's flag unless something else decides.  With no feature an unflagged string gets ASCII rules — `uc("\xB5\xE9")`
  is unchanged and `"\xB5\xE9" !~ /\w/` — and a flagged one Unicode rules; under `use feature 'unicode_strings'` the
  unflagged string gets Latin-1 rules, `uc("\xB5\xE9")` is U+039C U+00C9 and the result is flagged, `fc` maps U+00B5 to
  U+03BC, and `"\xB5\xE9" =~ /\w/`; under `use locale` with a UTF-8 locale the case functions use Unicode rules on the
  unflagged string too.  `pp_uc`, `pp_lc`, `pp_ucfirst`, `pp_lcfirst`, `pp_fc`.  Rows `B.none.U.uc` (`b5e9`, flag 0)
  against `B.feature.U.uc`, `B.locale.U.uc` and `L.none.U.uc` (all `ce9cc389`, flag 1, ords 924,201); `B.none.U.fc`
  (unchanged) against `B.feature.U.fc` and `L.none.U.fc` (ords 956,233); `B.none.U.ucf` against `B.feature.U.ucf`
  (924,233); `B.none.U.rew` (0) against `B.feature.U.rew` and `L.none.U.rew` (1). [5.44.0]
- `string-flags.regex-charset-modifiers`: The regex charset modifiers override the string's flag: `/u` applies Unicode
  rules to unflagged bytes, and `/a` restricts `\w` to ASCII on a flagged string and under the feature alike.  A pattern
  containing a code point above 0xFF is compiled under Unicode rules, so `/\x{39C}/i` matches `"\xB5\xE9"` flagged or
  not, with or without the feature (the fold of U+00B5 and U+039C is U+03BC), and `/a` does not disable that fold.
  `Perl_re_op_compile` (regcomp.c, `RExC_uni_semantics`).  Rows `B.none.U.rewu` (1), `B.feature.U.rewa` and
  `L.none.U.rewa` (0); `B.none.U.rei`, `B.feature.U.rei`, `L.none.U.rei`, `B.none.U.reia`, `L.none.U.reia` and
  `B.none.U.reiu` (all 1). [5.44.0]
- `string-flags.unpack-modes`: `unpack "U*"` reads the characters of the string as they are, flagged or not; `"U0C*"`
  gives the bytes of the UTF-8 encoding, upgrading an unflagged string to get them; and `"C*"` on a flagged Latin-1
  string gives the code points, not the encoding bytes, the same as on the unflagged form.  `pp_unpack`.  Rows
  `B.none.U.unpU` and `L.none.U.unpU` (181,233), `H.none.U.unpU` (97,256); `B.none.U.unpU0C` and `L.none.U.unpU0C`
  (194,181,195,169), `H.none.U.unpU0C` (97,196,128); `B.none.U.unpC` and `L.none.U.unpC` (181,233). [5.44.0]
- `string-flags.hash-keys-and-captures`: A flagged key whose characters all fit Latin-1 is stored downgraded with
  `HVhek_WASUTF8` and returned by `keys` upgraded again; a key that does not fit stays flagged; an unflagged key stays
  bytes.  So `"\xB5\xE9"` and its upgrade are one key, and the flagged `"\xB5\xE9"` and its UTF-8 encoding
  `"\xC2\xB5\xC3\xA9"` are two.  A regex capture inherits the flag of the string matched against.  `Perl_hv_common`
  (`models/HashEngine/section.md` §1), `pp_match`.  Rows `L.none.U.hkey` (the key read back is `c2b5c3a9`, flag 1),
  `H.none.U.hkey` (flag 1), `B.none.U.hkey` (flag 0); `B.none.U.hkey2` and `A.none.U.hkey2` (1 key), `L.none.U.hkey2`
  and `H.none.U.hkey2` (2); `L.none.U.cap` (flag 1), `B.none.U.cap` (flag 0), `H.none.U.cap` (flag 1). [5.44.0]
- `string-flags.taint-propagates`: Taint is a bit on the value (`SVs_TAINT`), copied with the value — `my $c = $t` is
  tainted — and propagated by every operation that builds a string or number from a tainted operand: concatenation and
  `.=`, `join`, `x`, `sprintf "%s"`, `substr`, `reverse`, `chop`, `chomp`, the case functions, `tr///` and its count,
  `length` and arithmetic on it, `index`, `split`'s fields, `unpack`, `pack "a*"`, upgrade, downgrade, encode, decode,
  and the three-way `cmp`.  `PL_tainted` is a per-statement accumulator, set by every read of a tainted value and
  cleared by `pp_nextstate` (`TAINT_NOT`), and `SvTAINT` marks each result built while it is set.  Every `T` row of
  families `A`, `B` and `L` for `copy`, `catb`, `catu`, `apb`, `joinb`, `rep`, `sps`, `sub1`, `rev`, `chop`, `chomp`,
  `uc`, `lc`, `fc`, `tr`, `trcnt`, `len`, `arith`, `idx`, `split`, `unpU`, `unpU0C`, `packa`, `up`, `down`, `enc`, `dec`
  and `cmpb` has tainted 1 (`A.none.T.copy`, `B.none.T.catu`, `L.none.T.sub1`, `B.none.T.len`, `B.none.T.cmpb` among
  them), as do the `H` rows of every operation that does not croak on it (`H.none.T.len`, `H.none.T.rev`).  [5.44.0]
- `string-flags.taint-launder`: Results that carry no taint from a tainted string: a hash key read back by `keys` after
  being stored from it (the key lives in a `HEK`, and `Perl_hv_iterkeysv` builds a fresh SV from it), a regex capture of
  it (`pp_match`; `RXp_MATCH_TAINTED` is not set by a tainted target alone), and `chr(ord $t)` (`pp_chr` taints
  nothing).  Rows `B.none.T.hkey`, `L.none.T.hkey` and `H.none.T.hkey` (tainted 0), `A.none.T.cap`, `B.none.T.cap` and
  `L.none.T.cap` (0), `A.none.T.chr`, `B.none.T.chr` and `L.none.T.chr` (0). [5.44.0]

## Element aliasing [aliasing]

Suite: `suites/aliasing` (28 cases, 26 runnable, 2 undefined in Perl).

Entries:

- `aliasing.foreach-by-index`: `foreach` over an array walks it by index against the live array: each iteration reads
  `AvFILL` and takes whatever SV now sits at the next index, so elements pushed in the body are visited (`1 2 11 12`
  from `(1, 2)` with `push @a, $_ + 10`), an element removed from ahead of the cursor is never seen (`splice(@a, 1, 1)`
  at index 0 visits `1 3 4`), and a `shift` in the body skips the element that moved down into the current index (`s=1
  _=1 [2 3 4] | s=2 _=3 [3 4]`).  `pp_iter` (`ix > AvFILL(av)` ends the loop, `AvARRAY(av)[ix]` is the alias).  Cases
  `A01_shift_in_loop`, `A07_push_in_loop`, `A08_splice_mid`, `A13_nested_aliases`, `A19_unshift_once`. [5.44.0]
- `aliasing.loop-holds-the-element`: The loop variable is the element SV itself, and the loop holds a reference count on
  it, so an element removed from the array while it is the current alias stays alive and readable through the alias
  until the next iteration: `splice(@a, 0, 1)` at index 0 still prints `1` then visits `3` (`1 3 | 2 3`), `pop @a` at
  the last index prints the popped `3`, `@a = ()` at index 1 prints `2` and the loop ends, `$#a = 0` likewise, and `@a =
  (7, 8, 9)` at index 0 prints the old `1` and then the new `8`, `9`.  `pp_iter` (`SvREFCNT_inc_simple_void_NN(sv)` on
  the alias; a freed alias is `Use of freed value in iteration`).  Cases `A09_splice_aliased`, `A15_pop_aliased`,
  `A16_clear_in_loop`, `A17_sort_assign`, `A18_truncate`, `A23_reassign_in_loop`. [5.44.0]
- `aliasing.ref-to-alias-is-element`: `\$_` under `foreach`, and `\$_[0]` inside a sub, is a reference to the aliased SV
  itself: it has the element's or the argument's address, a write through it lands in the container or the caller's
  variable, and the reference keeps that SV alive after the caller's lexical has left its scope (`mk($y)` returns a
  closure over `\$_[0]`, which still reads `1` after `$y`'s block ends).  `pp_entersub` places the argument SVs in `@_`
  unchanged; `Perl_leave_scope` (`SAVEt_CLEARSV`) abandons a pad SV whose reference count is above one to its holders
  instead of clearing it.  Cases `A02_ref_to_alias`, `A04_ref_arg_outlives`, `A20_args_ref_escapes`. [5.44.0]
- `aliasing.lexical-loop-variable-is-the-element`: `for my $x (@a)` aliases the pad slot to the element SV for the
  iteration, so a closure that captures `$x` captures the element: after the loop, `$a[0] = 99` is seen by the first
  closure (`99,2,3`).  `pp_iter` stores the element SV in the pad slot (`*itersvp = sv`); `Perl_cv_clone` captures the
  SV currently in the outer pad slot.  Case `A03_closure_over_alias`. [5.44.0]
- `aliasing.args-alias-through-calls`: `@_` elements are the caller's SVs, not copies: `$_[0] = "g"` writes the caller's
  variable, through `goto &sub` (which hands the same `@_` to the callee) and through a nested call made with an aliased
  `$_`; a write made before a `die` stays made; and two arguments naming one variable are the same SV twice (`two($a[0],
  $a[0])` with `.= "x"` and `.= "y"` gives `1xy`).  `pp_entersub`, `pp_goto` (the `@_` of the frame is reused).  Cases
  `A05_goto_sub`, `A06_die_through_alias`, `A11_two_aliases`, `A22_alias_passed_on`. [5.44.0]
- `aliasing.args-escape-reified`: A reference to `@_` that outlives the call keeps the argument SVs as its elements:
  `sub keep { \@_ }` returns an array whose first element is the caller's `$x` itself (same address, reads `2` after `$x
  = 2`).  `cx_popsub_args` abandons an `@_` whose reference count is above one (`Perl_clear_defarray`), and
  `Perl_av_reify` makes its elements owned.  Case `A20_args_ref_escapes`. [5.44.0]
- `aliasing.absent-element-deferred`: Passing an absent hash element to a sub passes a deferred element: the key is
  created only if the sub assigns to `$_[0]` (`hk($h{nokey})` with `$_[0] = 5` creates `nokey`), and a sub that only
  reads it leaves the hash untouched (`other` stays absent).  `pp_helem` with `OPpLVAL_DEFER` makes a
  `PERL_MAGIC_defelem` proxy; `Perl_magic_setdefelem` and `Perl_vivify_defelem` create the element on the first store.
  Case `A14_defelem`. [5.44.0]
- `aliasing.local-on-alias-rebinds-the-glob`: `local $_` inside `foreach` saves the glob's scalar slot and installs a
  fresh SV: the body sees the local value, the array element is untouched (`L L | 1 2`), and when the block ends the
  alias to the element is back, still alive even if the element was shifted out of the array in the meantime (`{ local
  $_ = "L"; shift @a }` then `$_` reads `1`).  `Perl_save_scalar` (`SAVEt_SV`), `Perl_leave_scope`.  Cases
  `A10_local_underscore`, `A10b_local_then_shift`. [5.44.0]
- `aliasing.values-are-aliases`: `values %h` returns the hash's value SVs themselves, so `$_ *= 10 for values %h` writes
  every value in place (`a=10,b=20`).  `Perl_hv_pushkv` pushes `HeVAL(entry)`.  Case `A25_values_alias`. [5.44.0]
- `aliasing.weaken-alias-ref-is-harmless`: Weakening a reference to an aliased element leaves the element in place: the
  array still owns it, the weak reference merely stops counting, and the loop and the array read `1 2 3` unchanged.
  `Perl_sv_rvweaken`.  Case `A21_weaken_alias`. [5.44.0]
- `aliasing.pad-slot-reuse`: A `my` variable in a loop body is the same SV on every iteration while nothing else holds
  it (three iterations, one address), gets a fresh SV for the next iteration once a reference to it has escaped (three
  references, three addresses), and the switch happens at the scope exit that finds the reference: with the reference
  kept only from the second iteration the addresses are `A A B`.  `Perl_leave_scope` (`SAVEt_CLEARSV`,
  `SAVEt_CLEARPADRANGE`: a pad SV with one reference is cleared in place, one with more is abandoned and replaced).
  Case `A27_pad_reuse_addresses`. [5.44.0]
- `aliasing.undefined-windows`: Two aliasing shapes read freed memory in Perl and are excluded from the suite rather
  than blessed: `shift @_` while two aliases into `@_` are held (`@_` is not a reified array, so its elements are not
  owned by it), and `delete` on a key whose value is aliased by `values`.  Both are in `undefined.md`.  Cases
  `A12_shift_two_aliases_EXCLUDED`, `A26_values_delete_EXCLUDED`. [5.44.0]

## Arrays [arrays]

Entries:

- `arrays.shift-pop-return-sv`: `shift` and `pop` return the element's SV itself, not a copy: a reference taken to the
  returned value has the address the element had in the array.  So does `splice` in list context for every element it
  removes; in scalar context it returns the last removed one and frees the rest at once.  `Perl_av_shift`,
  `Perl_av_pop`, `pp_splice`.  Probe: `probes/corpus/local_elem_sv_identity.pl`; model rows
  `models/SaveStack/reports/table.*.tsv` with mutation `shift1`, `pop1`, `splice_rm` (the second `E=` reference).
  [5.44.0]
- `arrays.insert-copies`: What `unshift`, `push` and `splice` insert are fresh copies of their arguments (`newSVsv` in
  `pp_unshift`, `pp_push` and `pp_splice`), never the argument SVs.  The same rows with mutation `unshift1`, `push1`,
  `splice_ins`. [5.44.0]
- `arrays.pop-keeps-holes`: `pop` of the top element does not trim holes below it (`Perl_av_pop` only clears the top
  slot), whereas `delete` of the top element does (`Perl_av_delete` walks `AvFILLp` down past contiguous NULL slots).
  Rows `plain/aeA/*/pop1` (`$#a` stays 4 above the two holes) against `plain/aeA/*/keep` (the restore deletes the
  vivified top element and `$#a` falls back to 2). [5.44.0]
- `arrays.null-is-hole`: An array's storage is an array of `SV*` and a NULL entry is a hole: `delete` on a middle
  element, `$#a =` growth, and a store past the end all leave holes, which `exists` reports as absent while `scalar(@a)`
  counts them. Lvalue-context access -- `\$a[i]`, `\(@a)`, `foreach` aliasing, passing `$a[i]` to a sub -- vivifies a
  hole into a fresh SV (`Perl_av_fetch` with `lval`). The same probe. [5.44.0]
- `arrays.returned-lists-alias`: The lists returned by `sort` (bare, with a block, a named sub or a sub reference, and
  under `reverse`), by `reverse`, and by `grep` in both its block and expression forms are the argument SVs themselves,
  so a `for`, `map` or `grep` over such a list writes through to the originals.  The list returned by `map` is copies in
  every form — `map { $_ }`, `map {; $_ }`, `map($_, ...)` — because `pp_mapwhile` copies every result that is not
  already a temporary (`sv_mortalcopy`), while `$_` inside the block or expression still aliases the element.  `pp_sort`
  copies only pad temporaries, and only when a sort block is present (`copytmps`); `pp_grepwhile` and `pp_reverse` keep
  the stack SVs.  List assignment copies, which is where the aliasing stops.  Case `A28_returned_lists_alias` (identity
  by `refaddr` read through `@_`, and the write-through for each builtin and form). [5.44.0]

## Readonly values [readonly]

Suite: `suites/readonly` (4 cases).  A write to a readonly scalar croaks `Modification of a read-only value attempted`;
the message is the same for every writing operation.

- `readonly.foreach-literal-members`: A foreach list hands out the readonly constant SV itself for a literal number or
  string, `qw()`, `undef`, the boolean results `1==1` and `!1`, `__PACKAGE__`, a `use constant` scalar in every call
  form (`K`, `K()`, `&K`), the repetition `(1) x 2`, and a literal passed as a sub argument; and `sort`, `grep` and
  `reverse` pass such SVs through (`pp_sort` copies only pad temporaries).  It hands out a writable temporary for a
  range (`1..2`, `'a'..'b'`), a folded constant (`1 + 1`, `'a' . 'b'`), an interpolated string, `keys`, a `use constant`
  list, an inlinable `sub () { 10 }`, the return of an ordinary sub, and the copies `map` returns — so `$_++ for sort {
  $a <=> $b } map $_, 3, 1, 2` runs where the same without `map` croaks.  A write to such a temporary never reaches the
  next execution of the same code.  Case `R01_literal_list_members`. [5.44.0]

- `readonly.flag-on-sv`: The flag belongs to the SV, not the value: a copy by assignment or list assignment is writable;
  a reference to the readonly SV (`\$_` under the alias, or `\1`) refuses a write through the dereference;
  `Internals::SvREADONLY($x, 1)` makes a lexical refuse writes until `($x, 0)` clears it, and reads `1` on a literal
  alias and `0` on a range element.  Every mutating operation refuses — assignment, `++`, `+=`, `.=`, `chop`, `undef
  $_`, `s///` and `tr///` even when nothing matches, `chomp` even with nothing to remove, and `bless` of a reference to
  it — while `tr///r`, `local $_`, `pos($_) =`, `study`, `utf8::upgrade`, `utf8::downgrade` and every rvalue use are
  allowed.  Case `R02_propagation_and_operations`. [5.44.0]

- `readonly.special-variables`: Readonly special variables: `$1` and the other capture variables, `$&`, the prematch and
  postmatch variables, `$+`, the elements of `@-` and `@+`, `$]` and `$^V`; a copy of `$1` is writable, an alias to it
  (`for ($1)`, `f($1)`) is not, and `f("$1")` passes a copy.  Writable: `$0` (assignment and `.=`), `$$`, `$^O`, `$^T`,
  `$^W`, `$;`, `%ENV` and `@ARGV` elements.  Case `R03_special_variables`. [5.44.0]

- `readonly.non-creatable-elements`: A negative subscript below the array's first element is *non-creatable*: `$b[-3] =
  1`, `$b[-3] //= 1`, `$e[-1] = 1` on an empty array, `\$b[-3]`, `for ($b[-3])`, `f($b[-3])` and `splice(@b, -3)` all
  croak `Modification of non-creatable array value attempted, subscript -3`, whereas the same routes with a subscript
  past the end grow the array, `$#b = -2` and `$#b = -1` are accepted, and the rvalue, `exists` and `delete` forms are
  silent.  `pp_aelem`, `Perl_av_fetch` with `lval`.  Case `R04_non_creatable_elements`. [5.44.0]

## Address identity, literal cells, and global destruction [identity]

Probes: `probes/corpus/addr_*`, `probes/corpus/consts_*`, `probes/corpus/gd_*`, `probes/research/value-model/` (14),
each cited in `sources.md`.

Entries (what Perl does here is mostly what it does not promise; the entries say which outcomes are properties of the
allocator rather than of the language):

- `identity.one-head-free-list`: SV heads of every type come from one LIFO free list: `plant_SV` pushes a freed head
  onto `PL_sv_root` and `uproot_SV` pops the next allocation from it, whatever kind of SV either one is, so a freed
  scalar, array, hash, object or closure can hand its address to the very next SV allocated, and `refaddr` and a
  stringified reference recur immediately.  Which allocation gets which freed head is a property of the allocator and
  the surrounding allocations, not of the program: the probe is `allocator-sensitive`, its answers changing under the
  no-reuse and descending builds.  Probe `probes/corpus/addr_01_reuse.pl`. [5.44.0]
- `identity.reuse-is-observable`: Ordinary code sees the reuse without printing an address: a seen-set keyed by
  stringified references over hashes made fresh per iteration reports duplicates, stringified fresh hashes across
  iterations compare equal, and an inside-out attribute keyed by `refaddr` without cleanup reads a dead object's value
  on a fresh object at the same address (`42` on the stock build, `undef` on the no-reuse build).
  `Hash::Util::FieldHash` is immune: its keys go with the object, and a fresh object at the same address starts without
  the attribute on every build.  Probes `probes/corpus/addr_02_observable.pl` (`perl-nondeterministic`: a hash keyed by
  stringified references orders its keys by address bits and seed), `probes/corpus/addr_03_insideout_warm.pl`
  (`allocator-sensitive`). [5.44.0]
- `identity.address-order-is-not-allocation-order`: Ordering references by address — `sort { refaddr($a) <=> refaddr($b)
  }`, `sort keys` of a registry keyed by stringified references, or `$r1 < $r2` on numified references — does not order
  them by allocation even with no frees at all: `S_sv_add_arena` threads each new arena's free list in ascending order
  on the stock build and the descending build reverses it, and every earlier free interleaves the list.  Probe
  `probes/corpus/addr_04_order_nofree.pl` (`allocator-sensitive`). [5.44.0]
- `identity.global-destruction-order`: Global destruction is an arena walk, not a traversal of the program's data:
  `Perl_sv_clean_objs` runs `S_visit` over every arena (`PL_sv_arenaroot`, newest arena first, ascending within each) in
  four passes — references to objects, glob scalar slots, IO slots, then a curse pass — and in the first pass a weak
  reference is cleared without a decrement while a strong one is decremented, so an object's `DESTROY` runs when the
  walk reaches the holder that drops its last count, wherever that holder's head sits.  Every object reachable only from
  package variables, a blessed glob scalar, and an object with no holder at all is destroyed in phase `DESTRUCT`; the
  order among them depends on head positions, which allocation history before the holders decides.  Probe
  `probes/corpus/gd_01_order.pl` (variants `plain` and `prime`, which scrambles the free list first: both `lane-B-only`,
  the set of `DESTROY`s fixed, their order not). [5.44.0]
- `identity.resurrection-in-global-destruction-croaks`: A `DESTROY` that stores its invocant somewhere during the
  object-cleaning pass of global destruction dies with `DESTROY created new reference to dead object 'Obj' during global
  destruction`: `S_curse` refuses a resurrection while `PL_in_clean_objs` is set, where the same store during normal
  lifetime would keep the object alive.  Probe `probes/corpus/gd_01_order.pl` (variant `resurrect`;
  `allocator-sensitive`, since which object the walk reaches first decides which `DESTROY` runs before the croak).
  [5.44.0]
