# Facts

The prose index of the reference: every established fact about Perl's behavior, grouped by area, each entry naming the
rule, the Perl function that fixes it, and the probe or model row that demonstrates it on a supported Perl
(`profile.md`).  A fact appears here only with that demonstration; a rule without one is not admitted.  Dense areas
point at their model's section text instead of restating the transition function.

Every entry opens with its id in a code span, `area.slug`, and is cited from any document as `[fact:area.slug]` — no
space, so that a citation is one word that no paragraph rewrap can split.  The part before the dot is the area's prefix,
the same for every entry under one heading; the slug names the rule and never changes, so an entry may be reordered or
reworded without breaking its citations.  `harness/bin/perl-conformance explain ID` prints an entry with its evidence
resolved to paths (`--run` also runs the cited probes and cases on the target version); `explain` alone lists the areas,
`explain AREA` lists one area's ids, and `explain --grep RE` finds entries by id or text, one line each — `-v` expands
any of these to full entries; and `cite-check FILE...` verifies that every citation in a document names an entry here.

Every entry ends with the supported versions it is demonstrated on, in brackets: a single version (`[5.44.0]`), or a
range when the behavior is the same on every supported version from the first to the last named (`[5.40.0–5.44.0]`).  A
range demonstrated on its ends but not on every supported version between them is marked `gaps` (`[5.40.0–5.44.0,
gaps]`); an entry whose behavior differs between supported versions states each side with its versions instead of a
range.  The brackets are the only place an entry names a version; what an unsupported Perl showed is in
`unsupported-perls.md`.

Nothing here is about any implementation of Perl.  What an implementation does where Perl's behavior is undefined
(`undefined.md`) is that implementation's own record.

## Value flags

The string and numeric forms of a scalar, the per-value flags recording which forms have been derived (public or
private, `IsUV`, derived-from-integer, private-only, stringified), the copy-on-write state and buffer length that decide
later transitions, and the `Dual` case.

Section: `models/ValueFlags/section.md`.  Model: `models/ValueFlags/ValueFlags.pm`.  Verification:
`models/ValueFlags/reports/coverage.txt`.  Probes: `probes/research/value-flags/`, `probes/research/value-model/` (01,
07-11, 15, 17, 18, 22, 23).  Suites: `suites/reentry-matrix`, `suites/reentry-matrix-864`, `suites/reentry-6840`,
`suites/transitions`.

Entries: to be filled from the section text.

## `local` and the save stack

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

## Finalization and temporary lifetime

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

## The hash engine

Section: `models/HashEngine/section.md`.  Model: `models/HashEngine/HashEngine.pm` (bucket-level and program-level
lanes).  Probes: `probes/research/value-model/` (12, 13), `probes/corpus/each_*`, `probes/corpus/order_*`.

## The UTF-8 flag and taint

Section: `models/StringFlags/section.md`.  Model: `models/StringFlags/StringFlags.pm` (in progress; `status.md`).

## Element aliasing

Suite: `suites/aliasing` (28 cases, 26 runnable, 2 undefined in Perl).

## Arrays

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

## Readonly values

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

## Address identity, literal cells, and global destruction

Probes: `probes/corpus/addr_*`, `probes/corpus/consts_*`, `probes/corpus/gd_*`, `probes/research/value-model/` (14),
each cited in `harness/sources.md`.
