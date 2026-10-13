# Facts

The prose index of the reference: every established fact about Perl's behavior, grouped by area, each entry naming the
rule, the Perl function that fixes it, and the probe or model row that demonstrates it on the pinned Perl
(`profile.md`).  A fact appears here only with that demonstration; a rule without one is not admitted.  Dense areas
point at their model's section text instead of restating the transition function.

Nothing here is about any implementation of Perl.  What an implementation does where Perl's behavior is undefined
(`undefined.md`) is that implementation's own record.

## Value flags

The string and numeric forms of a scalar, the per-value flags recording which forms have been derived (public or
private, `IsUV`, derived-from-integer, private-only, stringified), the copy-on-write state and buffer length that decide
later transitions, and the `Dual` case.

Section: `models/VF/section.md`.  Model: `models/VF/VF.pm`.  Verification: `models/VF/reports/coverage.txt`.  Probes:
`probes/research/value-flags/`, `probes/research/value-model/` (01, 07-11, 15, 17, 18, 22, 23).  Suites:
`suites/reentry-matrix`, `suites/reentry-matrix-864`, `suites/reentry-6840`, `suites/transitions`.

Entries: to be filled from the section text.

## `local` and the save stack

Section: `models/SS/section.md`.  Model: `models/SS/SS.pm` (488 cells, both Perls; the 176 structural cells are the
`models/SS/reports/table.*.tsv` rows whose mutation is `keep`, `shift1`, `shift2`, `unshift1`, `pop1`, `push1`,
`splice_rm`, `splice_ins`, `fill_neg1`, `fill0` or `refill`).  Probes: `probes/research/value-model/` (01-03),
`probes/corpus/local_*`, `probes/corpus/tie_*`.

Entries:

- The save record for an element holds the element's SV, not its value: a reference taken before the `local` names that
  SV, reads the pre-`local` value throughout the scope, and a write through it is what the restore brings back.
  `Perl_save_aelem_flags`, `Perl_leave_scope` (`SAVEt_AELEM`).  Probe: `probes/corpus/local_elem_sv_identity.pl`.
- The SV that `local` installs is an ordinary element: a structural operation (`shift`, `unshift`, `splice`) moves it
  and may return it to the program, and it lives on afterward with the localized value; nothing reclaims it at scope
  exit.  Undocumented; the same probe, and every structural model row (the `E=` column is that SV's value after the
  scope, reached through a reference taken inside it).
- The restore is by the original index into whatever the array has become (`av_fetch(av, idx, 1)` in
  `Perl_leave_scope`): the saved SV goes back at that index whatever now occupies it, and an emptied array is extended
  to reach it.  perlsub documents the extension; the same probe.
- Whatever element has migrated into the original index is destroyed by the restore, not moved aside: after `unshift @a,
  7` the element that was at index 0 now sits at the localized index and is freed when the saved SV returns there
  (`plain/aeP/*/unshift1`: `7, 20, undef, 30` from `10, 20, 30`); after `shift @a` the element from above it is
  (`plain/aeP/*/shift1`: `undef, 20` from `10, 20, 30`, the `undef` being the SV `local` installed, now at index 0).
  `Perl_leave_scope` (`SAVEt_AELEM`, whose `restore_sv` arm stores the saved SV over the slot and `SvREFCNT_dec`s what
  was there).
- The extension leaves the skipped slots as holes (`exists` false), not undef elements (`av_store` fills intermediate
  entries with NULL).  perlsub says "filling in the skipped elements with `undef`", which is not what happens.  The same
  probe; `plain/aeP/*/fill_neg1`.
- `local` on an absent element records a deletion of the original index (`SAVEt_ADELETE`), and the restore is
  `av_delete(av, idx)` on whatever the array has become: a no-op if the array has shrunk below that index
  (`Perl_av_delete` returns at `key > AvFILLp`), so the SV the `local` vivified survives in the array wherever a `shift`
  moved it (`plain/aeA/*/shift1`: it is at index 4, `$#a` is 4); a `push` leaves it deleted at its index and the pushed
  element beyond (`plain/aeA/*/push1`: holes at 3-5, `$#a` 6); an `unshift` moves it beyond the deleted index, where it
  stays (`plain/aeA/*/unshift1`: at index 6).  `Perl_save_adelete`, `Perl_leave_scope` (`SAVEt_ADELETE`),
  `Perl_av_delete`.
- A `die` in the body changes none of this: the structural rows pair `ok` and `dieB` cells whose observations differ
  only in `$@`.
- On a tied array the restore is one `STORE` at the original index, whatever the tie now holds there: after `shift` it
  overwrites the element that moved down into that index, after `unshift` the one that moved up into it, exactly as the
  plain array's restore does (`tied/aeP/*/shift1`: `undef, 20` from `10, 20, 30`; `tied/aeP/*/unshift1`: `7, 20, undef,
  30`).  The `undef` is the entry `STORE` of the bare `local` (`S:1:u` in the trace), which the tie class keeps as an
  element.  `Perl_leave_scope` (`SAVEt_AELEM`), `Perl_magic_setpack`.
- A reference to a tied element names the index, not an SV: `\$a[1]` is a proxy whose reads and writes go through
  `FETCH(1)` and `STORE(1)`, so after a structural move it reads whatever is at index 1 (the `E=` column of the tied
  rows: the reference captured inside the scope reads the restored value after it, where the plain rows' reads the
  installed SV wherever it went).  `Perl_av_fetch` on a magical array (av.c 271), `PERL_MAGIC_tiedelem`.
- A held proxy `FETCH`es once: `Perl_magic_getpack` sets `MGf_GSKIP` on every tied-element `FETCH` (mg.c 2240) and only
  a set through the proxy clears it (mg.c 287), so a second read returns the cached value, after a `shift` too, and a
  fresh `$a[1]` is a new proxy that `FETCH`es again.  The tied rows read their captured reference once, after the scope.
  Probe: `probes/research/value-model/26_weaken_tied_elem.pl` (C).
- `weaken` on a tied element acts on the proxy's own slot and runs no set magic: `weaken $a[0]` has no lasting effect
  (the proxy dies with the statement and the tie's slot stays strong), and a proxy held through `\$a[0]`, read once so
  its slot is filled, then weakened, is a weak holder whose set magic is the tie's `STORE`: when the referent dies the
  kill clears the proxy and runs `STORE(0, undef)`.  Same probe (A, B).
- An absent element localized on a tied array is deleted on unwind by `DELETE(idx)` with no `STORE`, and the tie's
  structural methods see only what was stored: a bare `local $a[5]` on a tied array of three stores nothing, so the tie
  never grows (`tied/aeA/bare/unshift1`: `7, 10, 20, 30`), while the assigned form stores `50` at 5 and a later `shift`
  or `unshift` moves it like any element (`tied/aeA/assign/shift1`: at index 4).  `Perl_save_adelete`, `Perl_av_delete`
  on a tied array (av.c 1071).
- On a `threads::shared` array the restore writes the saved value twice.  The element proxy carries tied-element magic
  addressing the aggregate by index and shared-scalar magic pointing at the shared element SV itself, and the exit
  `mg_set` runs both: the scalar magic stores into that SV wherever a `shift` or `unshift` has moved it, then the
  element magic stores at the original index.  `local $a[1] = 99; shift @a` on `(10, 20, 30)` leaves `(20, 20)` where a
  plain array leaves `(99, 20)`; the `unshift` form leaves `(0, 20, 20, 30)` against `(0, 20, 99, 30)`.  No second
  thread is involved.  `sharedsv_scalar_mg_set`, `sharedsv_elem_mg_STORE` and the magic ordering noted above it
  (dist/threads-shared/shared.xs).  Probes: `probes/corpus/local_03_shared_elem_move.pl` (threaded family) and
  `probes/research/value-model/24_local_shared_elem.pl`, which has the mechanism.
- `local` on a `threads::shared` variable, scalar or element, overwrites the shared cell in place: every other thread
  reads the localized value for as long as the scope lasts, and the saved value comes back when it ends.  `mg_localize`
  copies the shared-scalar magic onto the fresh proxy, so its entry `STORE` lands in the same shared cell.  Probe:
  `probes/corpus/threads_02_shared_local.pl` (A, F), with the threads handed off by condition variable so the
  interleaving is fixed.
- The two-address restore is the same whichever thread moved the array: a `shift`, `unshift` or `push` by another thread
  while the local is active leaves the same `(20, 20)` and `(0, 20, 20, 30, 40)` that one thread produces, seen by both
  threads.  The same probe (A, B, D).
- Two threads localizing the same shared element each write back their own saved value when their scope ends, in
  whatever order the scopes end: child `99` over `20`, main `7` over `99`, main exits and `99` returns, child exits and
  `20` returns.  There is no save stack across threads, only each thread's own.  The same probe (C).
- An absent element or key of a shared aggregate is never deleted on unwind, because it is never recorded as absent:
  `pp_aelem` and `pp_helem` consult `EXISTS` only when the tie class also has a `DELETE` method (`SvCANEXISTDELETE`,
  inline.h 1227), and `threads::shared::tie` has `EXISTS` but no `DELETE` (deletion goes through the element magic's
  clear), so the element counts as preeminent, `save_aelem`/`save_helem` record the fresh proxy's `undef`, and the
  restore `STORE`s that `undef` at the index.  `{ local $a[5] = 50 }` leaves a shared array of three six long with
  `$a[5]` existing and undef; `{ local $h{new} = 3 }` leaves `new` existing and undef; a present key deleted by the
  other thread during the local is restored by the same `STORE`.  The same probe (E, G);
  `probes/research/value-flags/p4.pl` for the single-thread hash form.

## Finalization and temporary lifetime

Section: `models/FZ/section.md`.  Model: `models/FZ/FZ.pm` (114 scenarios, both Perls).  Probes:
`probes/research/value-model/` (04-06, 16, 19, 21), `probes/corpus/destroy_*`, `probes/corpus/gd_*`.

Entries (the transition function is the section text; these are the weak-reference facts a reader looks for by name):

- Weak references to a dying object are cleared after its `DESTROY` returns, not before: inside the destructor every
  weak reference to the object is still defined.  `Perl_sv_clear` runs `S_curse` first and `Perl_sv_kill_backrefs` after
  it.  Probe: `probes/corpus/destroy_01_weak.pl`; model rows `undef.*`, `assign.*`, `cat.*` in
  `models/FZ/reports/traces.*.txt` (the `[1]` after each `D` is the weak holder, defined).
- If `DESTROY` resurrects the object (stores `$_[0]` somewhere), its weak references are not cleared: `S_curse` returns
  false when the count is still positive and `sv_clear` stops before the kill, so the weak references keep pointing at
  the live object and the next death runs `DESTROY` again.  Model rows `undef.K`, `assign.K`, `cat.K` (class `K` copies
  `$_[0]` into a global; the second `Da:K[1]` is the weak holder still defined at the next death).
- The clearing is a store with set magic: for each weak referrer, in backref-array order, `SvRV_set(referrer, 0)`,
  `SvROK_off`, `SvWEAKREF_off`, then `SvSETMAGIC`.  The array order is weaken order permuted by removals: `weaken`
  appends, and a holder that dies or is overwritten is removed by advancing the array start if it is first, shortening
  the array if it is last, and otherwise moving the last entry into its place (`Perl_sv_del_backref`; five holders with
  the second undefined are cleared first, fifth, third, fourth; FZ row `tiedweak.order`).  A tied holder therefore runs
  its `STORE(undef)` at the moment the referent dies, and a `STORE` that dies propagates out of the operation that
  killed the object, leaving the later referrers uncleared.  This is the only way the moment of clearing is observable
  from Perl; without set magic a weak reference is observed only when read.  `Perl_sv_kill_backrefs` (sv.c 6987-6990).
  Model rows `tiedweak.T`, `tiedweak.TX`.
- The clearing is visible in progress: a tied holder's `STORE(undef)` runs before the later holders are cleared, so from
  inside it a later weak reference to the same dying object is still defined and `isweak`; after the kill it is undef.
  The destructor has already run and committed (`S_curse` before the kill), and nothing rechecks the count after the
  kill: every way of reaching the object through that later holder from inside the `STORE`, a kept or transient strong
  copy, a new weak reference, a rebless, is a crash or a leaked freed SV, and undefining the later holder there croaks
  `panic: del_backref` (undefined window, `undefined.md`).  Probe:
  `probes/research/value-model/25_kill_backrefs_reentry.pl` (identical on 5.38.2 and 5.44.0).

## The hash engine

Section: `models/HV/section.md`.  Model: `models/HV/HV.pm` (bucket-level and program-level lanes, both Perls).  Probes:
`probes/research/value-model/` (12, 13), `probes/corpus/each_*`, `probes/corpus/order_*`.

## The UTF-8 flag and taint

Section: `models/PV/section.md`.  Model: `models/PV/PV.pm` (in progress; `status.md`).

## Element aliasing

Suite: `suites/aliasing` (27 cases, 25 identical on both Perls, 2 undefined in Perl).

## Arrays

Entries:

- `shift` and `pop` return the element's SV itself, not a copy: a reference taken to the returned value has the address
  the element had in the array.  So does `splice` in list context for every element it removes; in scalar context it
  returns the last removed one and frees the rest at once.  `Perl_av_shift`, `Perl_av_pop`, `pp_splice`.  Probe:
  `probes/corpus/local_elem_sv_identity.pl`; model rows `models/SS/reports/table.*.tsv` with mutation `shift1`, `pop1`,
  `splice_rm` (the second `E=` reference).
- What `unshift`, `push` and `splice` insert are fresh copies of their arguments (`newSVsv` in `pp_unshift`, `pp_push`
  and `pp_splice`), never the argument SVs.  The same rows with mutation `unshift1`, `push1`, `splice_ins`.
- `pop` of the top element does not trim holes below it (`Perl_av_pop` only clears the top slot), whereas `delete` of
  the top element does (`Perl_av_delete` walks `AvFILLp` down past contiguous NULL slots).  Rows `plain/aeA/*/pop1`
  (`$#a` stays 4 above the two holes) against `plain/aeA/*/keep` (the restore deletes the vivified top element and `$#a`
  falls back to 2).
- An array's storage is an array of `SV*` and a NULL entry is a hole: `delete` on a middle element, `$#a =` growth, and
  a store past the end all leave holes, which `exists` reports as absent while `scalar(@a)` counts them. Lvalue-context
  access -- `\$a[i]`, `\(@a)`, `foreach` aliasing, passing `$a[i]` to a sub -- vivifies a hole into a fresh SV
  (`Perl_av_fetch` with `lval`). The same probe.

## Address identity, literal cells, and global destruction

Probes: `probes/corpus/addr_*`, `probes/corpus/consts_*`, `probes/corpus/gd_*`, `probes/research/value-model/` (14),
each cited in `harness/sources.md`.
