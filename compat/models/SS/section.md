# `local` and the save stack

Validation: every rule below is transcribed into `SS.pm` and replayed by `generators/ss_gen.pl` over 400 cells.  The
first block is 312 cells — {plain, tied, magical (`$/`, `$0`), glob-aliased} × {package scalar, element present, element
absent, whole glob} × {bare, assignment, self-assignment} × {no mutation, pre-`local`-ref mutation, container clear,
delete} × {normal exit, die in body, die in a restoration `STORE`, die in the displaced value's `DESTROY`} × nesting
depth 1–2 — observing the callback trace, first-appearance-normalized addresses at three points, final values, `exists`,
and `$@` at the catch and at the following statement boundary.  The second block is 88 structural cells on a plain array
— {element present, element absent} × {bare, assignment} × {no change, `shift`, `shift` twice, `unshift`, `pop`, `push`,
`splice` removing, `splice` inserting, `$#a = -1`, `$#a = 0`, clear-and-refill} × {normal exit, die in body} — observing
per-index (identity, `exists`, value) over indices 0–6 after the scope, the final `$#a`, and references captured inside
the scope to the SV `local` installed and to the SV a removing operation returned.  perl 5.38.2 and 5.44.0 produce
byte-identical observation lines on all 400 cells, and `SS.pm` matches both on all 400.  Zero mismatches, zero crashes.
Address triples on tied-container elements are masked in both columns: a held reference always yields a distinct mirror
address, and the cross-statement equalities perl exhibits are reuse of a freed mirror's memory — an allocator artifact,
excluded under the freed-memory rule. Source citations are perl 5.44.0.

## 1. `local` is slot rebinding, never value mutation

A scalar `local` does not save a value; it rebinds a slot. `pp_gvsv` under `OPpLVAL_INTRO` calls `Perl_save_scalar`,
which records the glob and the old SV, then `S_save_scalar_at` installs a brand-new `SVt_NULL` in `GvSV(gv)`. Inside the
scope the site names a different SV at a different address; on exit the original SV — same address, same identity — is
put back. Consequences the matrix pins down: a reference taken before the `local` still names the old cell, a write
through it during the scope is a write to the saved SV, and that write is what the site shows after restore (the tied
variant additionally re-`STORE`s it; §5). The fresh SV starts life undef regardless of the old value.

## 2. The save record is `(site, old cell | absent)`, and element sites are re-fetched by key

`Perl_save_scalar` pushes `SAVEt_SV` holding the GV and a new reference to the old SV — the site is the glob, not a raw
pointer.  `Perl_save_aelem_flags` pushes `SAVEt_AELEM` holding the array, the index, and the old SV;
`Perl_save_helem_flags` pushes `SAVEt_HELEM` holding the hash, a copy of the key (`newSVsv`), and the old SV. On unwind,
`Perl_leave_scope` re-fetches the slot through the container: `av_fetch(av, idx, 1)` for `SAVEt_AELEM`,
`hv_fetch_ent(hv, key, 1, 0)` for `SAVEt_HELEM`. The lvalue re-fetch vivifies: `local $c[1] = 99; @c = ()` ends with the
unwind re-creating slot 1 and installing the saved SV there, so the element is resurrected at its index after a
container clear or an in-scope `delete`. The index is all the record knows, so a structural change inside the scope is
not compensated: after `unshift @c, 7` the saved SV is installed at index 1 over the element that migrated there (the
former `$c[0]`), which is freed, while the SV `local` installed sits at index 2 and stays; after `shift @c` it is
installed over the element that moved down into index 1, and the installed SV is now `$c[0]` (or, taken by reference
from the `shift`, lives on outside the array).  Nothing reclaims the installed SV at scope exit; it is an ordinary
element wherever it ended up. The record for an element that did not exist stores no old cell at all: `pp_aelem` and
`pp_helem` decide preeminence up front (through `EXISTS` when the container is tied and `SvCANEXISTDELETE`) and push
`SAVEADELETE`/`SAVEHDELETE` instead (§6).

## 3. The fresh cell's magic: `mg_localize` splits container from value

`S_save_scalar_at` gives the fresh SV the old SV's *container* magic and none of its *value* magic: `Perl_mg_localize`
walks the old SV's magic chain, skips every `PERL_MAGIC_TYPE_IS_VALUE_MAGIC` type, and copies the rest onto the fresh SV
(through the vtable's `svt_local` when the magic has `MGf_LOCAL`, else `sv_magicext`). A localized tied scalar is
therefore still tied — to the same tie object — while its cached payload is fresh.  The magical flags of the old SV are
OR-ed onto the new one. For `$/`-class variables the same copy applies; note that `Perl_magic_get`'s case for `$/` is an
empty `break` (mg.c:1237): reads return the SV's cached payload, and only `Perl_magic_set` maintains the
interpreter-global side, which is why `local $/ = $/` preserves the value while `local $/` alone switches the global to
undef.

## 4. The entry `mg_set`, and where it is suppressed

When `SAVEf_SETMAGIC` is passed, `mg_localize` finishes with `SvSETMAGIC` on the fresh SV under `PL_localizing = 1` —
this is the entry `STORE(undef)` a tied site observes. `Perl_save_scalar` always passes it: a tied package scalar traces
`FETCH(10)` (the `mg_get` of the old SV that `Perl_save_scalar` performs first, under `PL_localizing = 1`), then
`STORE(undef)`. `pp_aelem`'s localizing arm calls `save_aelem`, which is `Perl_save_aelem_flags` with `SAVEf_SETMAGIC`
unconditionally — a tied array element always gets the entry `STORE(idx, undef)`, in every mode.  `pp_helem` passes
`(PL_op->op_flags & OPf_SPECIAL) ? 0 : SAVEf_SETMAGIC`: the assignment form — `local $h{k} = 20` and equally the
self-assignment `local $h{k} = $h{k}` — carries `OPf_SPECIAL` and skips the entry `STORE`, while bare `local $h{k}`
performs it. This is the one hash/array asymmetry at entry, and it interacts with evaluation order: an rvalue element
fetch is eager, so the right side of `local $a[1] = $a[1]` is `FETCH`ed before the entry `STORE(undef)` clobbers the tie
and the element ends at its old value, whereas the right side of `local $x = $x` on a tied scalar is the old SV itself,
whose get-magic runs only inside the assignment — after the entry `STORE(undef)` — so the scalar ends undef. Both
element localizations `SvGETMAGIC` the old element first (`Perl_save_aelem_flags`, `Perl_save_helem_flags`), and when
the container is tied they `sv_2mortal` the fresh SV, because the tie's store never holds it and the mortals stack is
what bounds its life.

## 5. The exit `mg_set`: gated on `SvSMAGICAL`, carrying the then-current value

`Perl_leave_scope`'s shared `restore_sv` tail rebinds the slot to the saved SV, drops the displaced one, and then — only
if the restored SV is `SvSMAGICAL` — runs `mg_set` on it under `PL_localizing = 2`. The value stored is whatever the
saved SV holds *at restore time*: a write through a pre-`local` reference during the scope changes what the exit `STORE`
transmits. A plain restored SV gets no call at all. On a tied hash or array element the re-fetched slot holds a fresh
mortal mirror; the saved old mirror replaces it, and the exit `mg_set` on that old mirror is the `STORE(key, old_value)`
that writes the element back through the tie.  `SAVEt_AELEM` and `SAVEt_HELEM` take one extra reference on the fetched
mirror when the container is tied before jumping to `restore_sv`, keeping the mortal bookkeeping balanced.

## 6. Delete-on-unwind

Localizing an element that does not exist pushes `SAVEADELETE` (`Perl_save_adelete`) or `SAVEHDELETE`
(`Perl_save_hdelete`, which copies the key bytes with `savepvn` and pushes `SAVEt_DELETE`). The unwind executes
`av_delete`/`hv_delete` with `G_DISCARD`; on a tied container that is the tie's `DELETE`. Both cases rewrite their own
save-stack frame into `SAVEt_FREESV` (and `SAVEt_FREEPV` for the copied key) *before* calling the delete, so a die
inside a tied `DELETE` still releases the container and key in the continuing unwind. On a plain array, deleting the top
element shrinks the array past any contiguous holes below it, so the array shrinks only if the deleted element was
trailing. Deleting past the fill is a no-op (`Perl_av_delete` returns at `key > AvFILLp`). The vivification that the
entry's lvalue fetch performed is thereby undone: the element does not exist after the scope, even though it existed
(undef) inside it.  Both are by the original index: if a `shift` moved the vivified element below that index it survives
there, and if a `push` or `unshift` moved other elements above it the deletion leaves a hole between them.

## 7. The unwind contract

`Perl_leave_scope` pops each record before executing it; a record that pushes new records (the FREESV cleanups of
`restore_sv`, the frame rewrites of `SAVEt_DELETE`/`SAVEt_ADELETE`) extends the same loop, and the new records run next.
Cleanups are pushed *before* fallible magic: `restore_sv` pushes `SAVEt_FREESV` for the restored value and for the
container/glob before calling `mg_set`, so the references are released whether the `STORE` returns or dies. There is no
rollback: a die inside a restoration `STORE` leaves every already-executed restore in place, and the remaining records
still run — the exception unwinds to the enclosing eval through `LEAVE_SCOPE` of that eval's saved index, which pops
them — so the exception is observed at the catch *after* the rest of the scope has been restored. A die inside an
implicitly invoked `DESTROY` never propagates at all: `S_curse` calls the destructor with
`G_DISCARD|G_EVAL|G_KEEPERR|G_VOID` (sv.c:7783), downgrading the exception to an "(in cleanup)" warning, whether the
destructor runs inside the unwind, at a container clear, or at a statement-boundary `FREETMPS`. A displaced object's
`DESTROY` runs when its last reference drops, and the tie's own store participates in that accounting: `local $x = $obj`
on a tied scalar traces the object's `DESTROY` *after* the exit `STORE(old)`, because the tie held the reference the
entry `STORE` gave it until the restore overwrote the slot.

## 8. Pad clears are save actions, interleaved LIFO with restores

`my` at run time pushes `SAVEt_CLEARSV` (`Perl_save_clearsv`, the pad offset packed into the tight-form record), so a
lexical declared after a `local` is cleared *before* that `local` is restored — its referent's `DESTROY` precedes the
restoration `STORE` in the same unwind. The clear itself has two arms: a pad SV whose reference count is 1 and which is
not itself a blessed object is cleared in place (dropping its referent, which is where a `my $pad = $obj` lexical's
object dies); otherwise the pad slot is abandoned to a fresh SV and the old one merely loses the pad's reference.

## 9. Whole-glob localization

`local *x` goes through `Perl_save_gp`: the record holds the GV and the current GP; with `empty` true a new GP (fresh
scalar slot, so `$x` is a fresh undef inside) is installed, otherwise the old GP gains a reference and `GvINTRO_on`
marks the GV. `local *x = \$y` follows with `S_glob_assign_ref` semantics on the new GP: the scalar slot drops its fresh
SV and takes a new reference to the referent, so `$x` aliases `$y` inside the scope. `local *x = *x` assigns the saved
GP back into the GV (glob-to-glob assignment is GP sharing), so the site keeps its original identity inside the scope.
The unwind's `SAVEt_GP` case runs `gp_free` on the current GP — releasing the fresh scalar slot — and reinstates the
saved one. Aliasing established before the scope (`*x = \$w`) is orthogonal: `local $x` on the aliased GV saves and
replaces the shared SV in `*x`'s slot only, and `$w` — a different GV whose slot still holds the old SV — continues to
name it throughout.
