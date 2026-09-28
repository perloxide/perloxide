# Design-research probes, set 3 — reentrancy, locale, closures, flags, spawn walk

> Research record from the design sessions that produced this reference, kept verbatim except for its title.
> Where it describes what an implementation chooses to do in a window where perl has no defined behavior, that
> is not a fact about perl; the facts are in `undefined.md` and the choices belong to the implementation.

Same environment as bundle 1: system perl 5.38.2 and the 5.44.0 tag build.
Every probe below ran under both; outputs are identical across the two
interpreters everywhere, including all 864 matrix cells (TSV diff: 0 lines).
de_DE.UTF-8 generated via the locales package for probe 20.

## Ask 1 — two-slot reentrancy

- 17_warnmut_rows: all four stated rows reproduce (99:99:99 / 99:12:12 /
  99.5:99.5:99.5 / n=12 with empty stringification), and the excluded
  %.17g-with-numeric-handler segfault reproduces (SIG11, both perls).
- Source (5.44.0 sv.c, x86-64 so NV_PRESERVES_UV is NOT defined — the #else
  branches execute):
  - IV path, invalid string: `S_sv_setnv` (NV slot := Atof(pv), pre-handler)
    -> `not_a_number` (handler) -> refill from SvNVX as the handler left it
    (|NV| < 2^53: IV := I_V(NVX), public NOK/IOK by exactness; else
    `S_sv_2iuv_non_preserve`) -> **`if (!numtype) SvFLAGS(sv) &=
    ~(SVf_IOK|SVf_NOK)`** — the final strip removes ALL public numeric flags,
    including any the handler set. Private-only numerics stringify as empty
    (sv_2pv derives from public flags only) — that is row 4's empty `$x`.
  - NV path (`Perl_sv_2nv_flags` POKp branch): grok_number **pre-handler**
    decides flags; `not_a_number`; then `SvNV_set(sv, Atof(SvPVX_const(sv)))`
    — a fresh parse of the **current** (post-handler) string. No strip.
  - `grok_number` without PERL_SCAN_TRAILING returns 0 for ANY trailing
    garbage including 'infx'/'nanx' — those take the ordinary invalid window
    with Atof = ±Inf/NaN (model v1 mismatch that taught this; `nanx|0` = 0
    because Perl_cast_uv(NaN) = 0 here).
- 18_warnmut_matrix: 18 inputs x {S,N,R replacement} x {none, +0, %.17g, die}
  x {+0, |0, %g, .""} = 864 cells per perl, forked per cell.
  Cross-perl: identical. Model (model_fatbody.pl, a transcription of the
  verified control flow) vs perl: **762 match, 0 mismatch**, 51 segfault
  cells all predicted as the excluded perl bug (numeric replacement under an
  sv_2nv outer op), 51 cells declined as UB (ref replacement under an sv_2nv
  outer: Atof reads the RV pointer through the svu union; observed stable as
  n=0, re=ADDR, but memory-layout-dependent). Comparison reports:
  matrix_compare_5.44.txt / matrix_compare_5.38.txt.

## Ask 3 — closure/pad oracle (19_closure_rearm)

it1_imm=10, it1_mut=111 (the captured cell is live until scope exit),
it3_sees=111 (frozen at abandonment), addr1 != addr2, addr2 == addr3
(iteration-2 cell unclaimed -> reused in iteration 3). With refs kept:
closure sees 10, all three addresses distinct.

## Ask 4 — locale (20_locale_radix) and sub-op DESTROY (21_destroy_subop)

- de-first: "1,5" -> 1.5; reread and %g under C stay 1.5. C-first: 1 (one
  warning); reread under de stays 1. Copy before numification parses fresh
  under the current locale (2.5, displayed "2,5" because NV stringification
  is itself locale-sensitive at output time); copy after numification
  carries the cache across locales (3). setlocale(de) inside the warning
  handler: w1=4 — the pre-handler Atof ran under C and the slot is served
  afterward. **Frozen at first parse is the whole rule; no radix field.**
- DESTROY triggered by `$x = 5` observes $x == 5; by `$h{k} = 7` observes 7;
  by `undef $y` observes undef; by `delete $h{d}` observes the key gone.
  New state installed first, then teardown — both perls.

## Ask 5 — flags synthesis (22_flags_synth)

v1 (kept as *.v1-discovery.out): 20/25, the five mismatches being the
discovered rules: integer stringification caches P:priv (not pub); NV
stringification caches no P mark at all; builtin bools carry I, N, and P all
public; and **IV_MAX + 1 lands in IOK|pIOK|IsUV — addition overflows into UV
space exactly; lossy NV promotion begins past UV_MAX** (this falsifies the
constraints summary's "IV_MAX+1 silently promotes to a double" for
addition). With the corrected rules: **25/25, both perls.**

## Ask 2 — spawn-walk measurement

walk_stash.pl (system perl, vendor modules): Mojolicious + Mojo::UserAgent +
Mojo::DOM + Moose + Moose::Meta::Class + DateTime loaded ->
**nodes=188,338 edges=232,346** reachable from the stash roots (globs and
their four slots, container contents, ref targets, CV pads as a
capture-superset), pure-perl walk 258 ms (graph-size calibration only).
bench_walk.rs (rustc 1.91.1 -O, randomized layout): flip-walk of that graph
**13.0 ms (69 ns/node)**; 1M-node scaling point 86.3 ms.

## Not verified

- 'nan' payload forms ("nan(123)", "-nan") and long-double/quadmath
  configurations: the model is specified for double NVs with 64-bit UVs only.
- The R-replacement UB cells: observed stable, deliberately not specified.
