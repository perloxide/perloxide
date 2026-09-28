# Design-research probes, set 4 — value flags: correction, cross-validation, undefined windows (2026-09-22)

> Research record from the design sessions that produced this reference, kept verbatim except for its title.
> Where it describes what an implementation chooses to do in a window where perl has no defined behavior, that
> is not a fact about perl; the facts are in `undefined.md` and the choices belong to the implementation.

Oracles: /usr/bin/perl 5.38.2 (Ubuntu, threaded) and /usr/local/bin/perl 5.44.0 (tag v5.44.0).
Source citations are the perl 5.44.0 tree.

## 1. Correction accepted: P-seen (pp) is stdout-observable

Scalar::Util::isdual reads the PRIVATE flags: ListUtil.xs:1718 tests
(SvPOK(sv) || SvPOKp(sv)) && (SvNIOK(sv) || SvNIOKp(sv)). probes/23:

    array elem after `print for`  -> isdual 1     int after stringify -> 1
    float after stringify         -> isdual 0     inf NV stringified  -> 1
    numified string -> 1, dualvar -> 1            (identical, both perls)

The int/float/inf asymmetry independently confirms the flags-acceptance rules
(integer stringification caches pPOK; finite-NV stringification caches
nothing; the infnan branch caches pPOK at sv.c:3247). pp is a mandatory bit
of the marks byte, not an optional optimization.

## 2. Cross-validation, part B: my control flow over their 2,304-row matrix

xval/MF.pm is my transcription (the model_fatbody control flow) ported to the
shared cell vocabulary; xval/xval_gen.pl runs each cell three ways: perl
oracle (gen.pl's child, regenerated), their M.pm + gen.pl run_model, MF.pm.
Final line, byte-identical under both oracles:

    rows=2304 MF_values_ok=2154 MF_values_bad=0 MF_flag_bad=0 crash=114
    diverges_defined=150 theirM_ub=36 MF_vs_M_agree=2154 MF_vs_M_diff=0

The two independent transcriptions agree cell-for-cell on every comparable
row. Getting there caught four real MF bugs, each adjudicated by a source
line, not by copying M.pm:

1. sv_2nv ends with the SAME public-flag turn-off as S_sv_2iuv_common when
   grok returned 0 (sv.c, NV_PRESERVES_UV #else tail of Perl_sv_2nv_flags:
   `if (!numtype) SvFLAGS(sv) &= ~(SVf_IOK|SVf_NOK)`). My first source read
   stopped before the function tail; the strip also demotes a public IOK the
   handler itself installed.
2. Fill selection in the invalid window is `(UV)1<<53 > U_V(fabs(nv))`, and
   Perl_cast_uv(NaN) = 0, so NaN takes the SMALL fill: IV := cast_iv(NaN) = 0,
   no IsUV. My isnan() approximation had routed NaN to non_preserve.
3. pp_add's SvIV_please_nomg gates sv_2iv on a PUBLIC NOK or POK; with
   neither (undef holders) it never converts, falls to sv_2nv, and uses ITS
   RETURN VALUE — which is 0 after report_uninit regardless of what the
   handler wrote into the scalar. Post-hoc flag inspection is wrong;
   pp_bit_or likewise consumes sv_2uv's return.
4. String replacement (sv_setpv) preserves the IV/NV slot contents; my
   handler-replacement helper had zeroed them.

New window W3, discovered by the crash census: perl (both versions) crashes
when sv_2iuv_non_preserve runs over a REF holder with an infinite NV in the
IV window (Infx/ref/{iv,nv,none}/{add,bor}); the same shape with an ARRAY-ref
replacement survived in my 864 harness, so the trigger is referent-sensitive
and not root-caused — all of it is inside the design-defined divergence set.
All 150 perl-undefined rows (114 crash/timeout + 36 freed-PV reads) now carry
defined outputs, marked DIVERGES; the 12U/undef/*/spg timeouts are perl
infinite-warn loops that the design's redispatch terminates after the second
warning.

## 3. Cross-validation, part A: my flags() over their transition tables

partA/partA_flags.pl replays the gen2 op set through M.pm (depth 3 from all
18 starts, depth 4 from the strings), collects every reachable flag-relevant
word, and compares M.pm's projection with my synthesis word-by-word:

    distinct_words=45  projection_mismatches=0
    table_flag_strings=40  table_not_in_replay=0  replay_not_in_table=3

All 40 flag strings in the perl-verified tables are reproduced. The 3
replay-only states were put to both real perls (partA/witnesses.txt): perl
produces each of them exactly as the replay predicts, so the tables are
merely incomplete (gen2's seen-state frontier pruning) and both projections
are right on them. One is substantive: `iMax cat0 add nv` yields
IOK,POK,pIOK,pNOK,pPOK — the mN=1 no-roundtrip state (IV_MAX -> NV) that my
25-case synthesis suite never exercised.

## 4. Design-defined rows for the perl-undefined windows

Principle (per the redispatch rule): when the __WARN__ handler removed the
string face mid-conversion, resume by dispatching the interrupted conversion
on the CURRENT holder kind, with no additional warning; mark the row
divergent-by-design. model/model_fatbody.pl implements it; the regenerated
comparison (model/compare.*.txt, identical on both perls):

    match: 762   DIVERGES-defined-perl-segv: 51   DIVERGES-defined-perl-ubread: 51

W1 — numeric holder at the sv_2nv continuation (perl: SIGSEGV, Atof through
the freed PV). Spec row, e.g. `12e|N|I|g`:
    defined = [99, 99, 0, 99, 1]
    Int(99) redispatches: NV := (NV)99, N:priv+pub (round-trips), N_FROM_I;
    one warning total; "%g" -> "99"; stringify later sets P-seen.

W2 — ref holder at the same point (perl: reads the freed PV; observed n=0).
Spec row, e.g. `12x|R|0|g`:
    defined  = [REF, ADDR, 0, ADDR, 1]
    observed = [REF, 0,    0, ADDR, 1]
    Ref redispatches to the address-numification path; no marks cached
    (sv_2nv's ROK return does not cache), one warning total.

W3 — ref holder + infinite NV reaching non_preserve in the IV window (perl:
crash). Defined: the fill is slot arithmetic independent of holder kind;
IsUV on, UV slot := UV_MAX, publics stripped; outputs as MF computes
(e.g. Infx/ref/iv/bor -> n=18446744073709551615). Marked divergent.

## 5. Scope and non-verified items

The model's compatibility profile is double NVs + 64-bit IV/UV with
NV_PRESERVES_UV undefined (both oracles); long-double and quadmath builds are
untranscribed. NaN payload spellings ("nan(123)", signaling forms) were not
exercised by either matrix. W3's exact C-level trigger (why \1 crashes where
[] does not) is unidentified; both shapes sit inside design-defined rows.
MF.pm's final form is oracle-corrected by this session's fixes; the
independence claim that survives is MF-vs-M agreement AFTER each fix was
justified by a cited source line.
