# Design-research probes, set 2 (2026-09-17)

> Research record from the design sessions that produced this reference, kept verbatim except for its title.
> Where it describes what an implementation chooses to do in a window where perl has no defined behavior, that
> is not a fact about perl; the facts are in `undefined.md` and the choices belong to the implementation.

Interpreters: system perl 5.38.2 (`/usr/bin/perl`) and perl 5.44.0 built from the
`v5.44.0` tag (perlbrew, unthreaded, `-O2`, single core, ~10 min). Every probe was
run under both; **all outputs are identical across the two interpreters** except
the insert-during-each iteration counts, which are undefined behavior and vary by
seed and version (dups/skips occur under every combination). Probe 12 was
additionally run with `PERL_HASH_SEED=0` under both.

Layout:
- `probes/` — the 16 probe scripts
- `out/perl-5.38.2/`, `out/perl-5.44.0/` — stdout/stderr per probe
  (`12_each_semantics.seed0.*` are the `PERL_HASH_SEED=0` runs)
- `bench/bench.rs`, `bench/bench.results.txt` — rustc 1.91.1 `-O`, single core

## Probe -> claim map, with source citations (all from the v5.44.0 tree)

| Probe | Result | Source grounding |
|---|---|---|
| 01 | `local $x` installs a fresh SV at a new address; old refs keep the old cell; original address restored at exit; same for bare `local $x` | `S_save_scalar_at` scope.c:321 (`*sptr = newSV_type(SVt_NULL)`, `mg_localize`); `Perl_leave_scope` SAVEt_SV scope.c:1234 (`*a2.any_svp = a1.any_sv`) |
| 02 | `local $h{k}` rebinds the element (old ref keeps old SV, address restored); absent `local $a[5]` deleted on unwind (len 2->2; with `$b[7]=70`, len 8 and index 5 deleted); `@c=()` inside the scope: restore re-fetches by (av, idx) and resurrects the saved element there | SAVEt_AELEM restore scope.c:1675 (`av_fetch(a0.any_av, a1.any_iv, 1)` then `goto restore_sv`); `Perl_save_adelete` scope.c:926; SAVEt_ADELETE restore scope.c:1640 (`av_delete(..., G_DISCARD)`) |
| 03 | tied scalar holding 10: `{ local $x; }` -> `FETCH(10) STORE(undef)` at entry, `STORE(10)` at exit | entry: `S_save_scalar_at` + `mg_localize`; exit: scope.c:1243-1253 `mg_set(a1.any_sv)` guarded by `SvSMAGICAL` (conditional in source; fires unconditionally for tied because the restored SV is the tied one) |
| 04 | non-temporaries die at refcount zero inside the op (`$x = 5`, `undef $x` both print `d` before the next statement) | sv_setsv/sv_clear refcount-drop path |
| 05, 16 | `if (o()) { ... }` prints `body d` (one **and** two statements in the block); `while (mk()) { ... }` prints `d body` | floor raise: `Perl_cx_pushblock` inline.h:4035 (`blk_old_tmpsfloor = PL_tmps_floor; PL_tmps_floor = PL_tmps_ix`), restore without drain inline.h:4062. `enterloop` pushes the loop context **before** the condition runs -> cond temp sits above the floor -> drained by the body's live `nextstate` (pp_hot.c:237 FREETMPS). `if`'s `enter` runs **after** the condition -> the temp is protected below the raised floor for the whole block; in the single-statement case there is additionally no drain site at all because `Perl_op_scope` op.c:4639-4651 converts the block to OP_SCOPE and `op_null`s its leading nextstate (B::Concise shows `ex-nextstate`) |
| 06 | `h3(), O->new("q")` prints `dq dh next`: void-context leavesub skips the drain, temps migrate to the caller's frame, LIFO at the caller's next FREETMPS | pp_leavesub pp_hot.c (`gimme == G_VOID` -> `rpp_popfree_to_NN` only, no `leave_adjust_stacks`); same pattern in pp_leave pp_ctl.c. Non-void exits drain via the unrolled FREETMPS in `Perl_leave_adjust_stacks` pp_hot.c:6204 |
| — | full FREETMPS site list found | pp_nextstate pp_hot.c:237, pp_unstack pp_hot.c:528, pp_grepwhile pp_hot.c:5795, pp_mapwhile pp_ctl.c (x2), pp_anywhile pp_ctl.c:1338, pp_dbstate pp_ctl.c:2510, pp_redo pp_ctl.c:3212, pp_goto pp_ctl.c:3408, Perl_die_unwind pp_ctl.c:1259/1271/1279, S_require_file pp_ctl.c:4719 |
| 07 | JSON::PP: `"10"` -> `["10"]` before `+0`, `[10]` after; the mark copies with the value (`copy=[10]`); `"Az"++` -> `"Ba"` plain; **`"1"++` -> `"2"` plain (string-carry path, no numeric marks)**; `"a".."e"` plain strings, `"0".."3"` marked numbers | `Perl_sv_inc_nomg` sv.c: `while (isALPHA(*d)) d++; while (isDIGIT(*d)) d++; if (d < SvEND(sv)) {numeric path}` — pure `[A-Za-z]*[0-9]*` strings, digits included, take the string-carry path |
| 08, 15 | Data::Dumper XS unquotes on **public** IOK plus a PV round-trip check: `"10"+0` -> `10`; `"10abc"+0` (pIOK/pNOK only) -> quoted; `" 10"+0` gets public IOK but stays quoted | `DD_is_integer(sv)` = `SvIOK(sv)` Dumper.xs:79; round-trip check Dumper.xs:1299-1305 ("string such as \" 0\""); public-IOK rule: `S_sv_2iuv_common` sv.c (`(numtype & (IS_NUMBER_IN_UV\|IS_NUMBER_NOT_INT)) == IS_NUMBER_IN_UV` -> `SvIOK_on`; trailing garbage -> `SvIOKp_on` only; leading whitespace is clean per grok_number) |
| 09, 15 | `"-0"`: integer read first -> IV 0, `%g` prints `0` forever (NV derived from IV); `%g` first -> NV −0.0, `%g` prints `-0` forever; `+ 0` prints `0` in both orders (IV face wins in pp_add) | `Perl_sv_2nv_flags` sv.c: `if (SvIOKp(sv)) SvNV_set(sv, ... (NV)SvIVX(sv))` — the NV face is derived from a cached IV when one exists |
| 10 | `__WARN__` handler assigning `$s = "999"` mid-conversion of `"10abc"`: conversion returns 10, `$s` reads "999", **next `$s + 0` returns 10** — the cached IV written after the mutation is served | warning raised from `S_not_a_number` sv.c:1863 inside the conversion; cache written on return |
| 11 | compiled constant `"10"`, aliased via `@_`: `["10"]` on first call, `[10]` on second — constants are mutable flag cells | per-op const SVs; `@_` aliases them |
| 12 | delete-current safe (10/10 returned); delete-other never returned; insert during `each` warns then duplicates and skips (both observed); `keys` resets the iterator; `scalar(%h)` and `exists` do not; **`PERL_HASH_SEED=0` suppresses the warning** | HvLAZYDEL hv.c:1475/2225/2531; warning hv.c:3106-3116, inside `#ifdef PERL_HASH_RANDOMIZE_KEYS`, guarded by `xhv_last_rand != xhv_rand` — seed 0 implies PERTURB_KEYS=0, the rand never changes, the guard never trips |
| 13 | `%h = ()` keeps the bucket array (HvMAX 255 -> 255); `undef %h` frees it (255 -> 7) | `Perl_hv_clear` hv.c non-readonly path: `hv_free_entries(hv)` only; hv_undef releases HvARRAY |
| 14 | pad SV reused across loop iterations when the ref was dropped (identical refaddr x3); fresh SV per iteration when a ref is kept | SAVEt_CLEARSV scope.c:1505 (`SvREFCNT(sv) == 1 && !SvOBJECT` -> clear in place) vs scope.c:1583 ("Someone has a claim on this, so abandon it") |

## Amendments to the stated facts

1. leave_scope's exit `mg_set` is conditional on `SvSMAGICAL` of the restored SV
   (scope.c:1243), not literally unconditional; for a tied variable the restored SV
   is the tied one, so it always fires there.
2. The FREETMPS site list is longer than stated: add pp_anywhile, pp_dbstate,
   pp_redo, pp_goto, and S_require_file.
3. `"1"++` produces a **plain string** "2" (no numeric mark) — the string-carry
   path covers pure-digit strings too (probe 15: `one_inc: (POK,pPOK)`,
   `nine_inc: (POK,pPOK) val=10`).
4. Data::Dumper's rule is public IOK **and** a PV round-trip match, not public
   IOK alone (`" 10"` carries public IOK yet stays quoted).

## Not verified here

- Biased-refcount DESTROY-timing slip: a design-level claim about a Rust runtime;
  perl runs one thread per interpreter, so there is nothing to probe.
- `use locale` radix interaction with the numeric cache: no non-C locales
  installed in the container.
- Intra-op interleaving detail of (a): whether DESTROY triggered by `$x = 5`
  observes `$x` already holding 5 (statement-level timing verified; sub-op
  ordering not probed).

## Bench results (rustc 1.91.1 -O, single core)

```
tmps heap-temp:   baseline=12.01 ns/iter  floored=12.42 ns/iter  delta=0.41
tmps inline-temp: baseline=0.34 ns/iter  floored=2.73 ns/iter  delta=2.39
rc pair:          plain=1.52 ns  atomic=14.62 ns  ratio=9.6x
ptr store:        plain=0.69 ns  shared-checked=1.07 ns  delta=0.38
```
