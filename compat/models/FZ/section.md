# Finalization and temporary lifetime

When an object's last reference disappears, Perl runs its destructor at a point that depends on *which* reference
disappeared and *how*. This section defines the two death paths, the model of the temporaries stack that decides the
second one, the destructor protocol with resurrection and rebless, the killing of weak references, the interleaving of
cleanups during exception unwinding, and the structure of global destruction. The reference implementation is `FZ.pm`, a
transcription of the functions named below. It runs a scenario IR, not Perl: its coverage is exactly the generator's
scenario set in `fz_gen.pl`, and the program-level oracle is the probe corpus that accompanies it, run on Perl 5.38.2
and 5.44.0, whose traces are identical over the suite.

## 1. Two death paths

A referent dies when `SvREFCNT_dec` reaches zero (`Perl_sv_free2` → `Perl_sv_clear`). Which operation performs that
decrement fixes *when* the destructor runs:

- **Inside the operation.** `sv_setsv_flags` copies the new value first and then releases the old referent
  (`SvREFCNT_dec(old_rv)` after the flag update), so a destructor triggered by `$x = 5` sees the new value in `$x`.
  `sv_set_undef` (`undef $x`), `av_clear` (`@a = ()`, elements from the top index down), `hv_delete` in void context
  (`G_DISCARD`), and `SAVEt_CLEARSV` at scope exit all decrement inside the operation. A destructor in `$x .= "s"` is
  *not* inside the op: `sv_force_normal_flags` calls `sv_unref_flags(sv, 0)`, which mortalizes a referent whose count
  would reach zero (`if (SvREFCNT(target) != 1) dec else sv_2mortal`), so the object dies at the next drain. Overwriting
  a *weak* reference takes the same `sv_unref_flags` path.

- **At a drain site.** Every value created as a temporary — a sub's return value, an anonymous constructor, a `delete`
  in non-void context, the mortalized referent above — sits on `PL_tmps_stack` and dies when `Perl_free_tmps` pops it:
  `while (PL_tmps_ix > PL_tmps_floor) SvREFCNT_dec`.  `free_tmps` reads the floor live and pops in LIFO order, so a
  destructor that creates and drops temporaries during the drain is safe and nested.

## 2. The floor model

Four operations define what a drain can reach:

1. `cx_pushblock` (inline.h): saves the floor in `blk_old_tmpsfloor` and raises it to the current top, `PL_tmps_floor =
   PL_tmps_ix`. Everything created before the block is protected from the block's drains.
2. `cx_popblock`: `PL_tmps_floor = cx->blk_old_tmpsfloor`. Whatever the block left above its floor becomes drainable by
   the enclosing code.
3. `Perl_free_tmps`: the drain, at the sites in §3.
4. `leave_adjust_stacks` (pp_hot.c): the non-void leave. Return values that are temporaries with refcount 1 are kept in
   place, others are mortal-copied; the remaining temporaries above the floor are freed here, before `CX_LEAVE_SCOPE`,
   and the floor is stepped above the kept values (`PL_tmps_floor++`) so the caller's own drain does not free them
   prematurely.

Where blocks begin, and whether a body's leading `nextstate` is live, decides the outcome. A one-statement `if` body
compiles to `OP_SCOPE`, not `OP_ENTER`/`OP_LEAVE`, and the peephole nulls its leading `nextstate` (`ex-nextstate` in
`B::Concise`; `Perl_rpeep` in peep.c, the `OP_NEXTSTATE` case that nulls a state op whose scope adds nothing), so the
body performs no drain and the condition's temporary survives it. A multi-statement `if` body is `enter`/`leave`:
`cx_pushblock` raises the floor above the condition temporary, with the same visible effect. A loop body is different:
`while` and a C-style `for` *without* a step expression keep a live `nextstate` under `enterloop` even for one
statement, and since `enterloop` was pushed *before* the condition, the condition temporary is above the floor and dies
at the body's first statement (`d body`); `pp_unstack` drains again at the end of each iteration. A C-style `for` *with*
a step expression is the exception: `Perl_newFOROP` (op.c) appends the step to the body as a further statement and wraps
the pair in `op_scope`, so the body is an `OP_SCOPE` whose leading `nextstate` is nulled exactly as an `if` body's is;
the condition temporary survives the body and dies at `unstack` (`b dc`), on both interpreters, whatever the body's
length.  `do BLOCK while` and a postfix `while` are wrapped in one `enter`/`leave` around the whole loop; `do`-`while`
has no `unstack`, so every condition temporary survives to the statement after the loop; the postfix form has an
`unstack` per iteration.

## 3. Drain sites

`FREETMPS` runs in `pp_nextstate` (every live statement boundary), `pp_unstack` (loop iteration end),
`pp_grepwhile`/`pp_mapwhile`/`pp_anywhile` (per item, after the item's `ENTER`/`LEAVE`), `Perl_die_unwind` (after
unwinding to the catching `eval`, before `$@` is set, so temporaries die before the catcher sees the exception),
`pp_redo`, `pp_goto`, `S_require_file`, and inside `leave_adjust_stacks` for non-void leaves. `pp_leavesub` and
`pp_leave` in void context do not drain: `rpp_popfree_to_NN(oldsp)` discards the values but the temporaries stay above
the caller's floor after `cx_popblock` and die at the caller's next drain — a void-context callee's last-statement
temporary is freed by the *caller's* `nextstate`, after the callee's lexicals were cleared by `CX_LEAVE_SCOPE`. In list
or scalar context the callee's other temporaries die in `leave_adjust_stacks` before `CX_LEAVE_SCOPE`, and the returned
value survives into the caller.

Consequences the harness checks: `foo(Bar->new)` destroys after `foo` returns (the argument temporary is protected by
`pp_entersub`'s block) and before the next statement; `{ my $a = O->new; my $b = O->new; my $c = O->new }` destroys `b a
c` because the block's last statement leaves `c`'s constructor temporary alive across `SAVEt_CLEARSV`, and `c b a` with
a trailing `1;` whose `nextstate` drained it; `local $::G = O->new; my $b = O->new` restores `G` before `b` dies for the
same reason; `eval { my $h = O->new; die }` destroys `h` during `LEAVE_SCOPE` in `die_unwind` before `$@` is set.

## 4. The destructor protocol — `S_curse`

`Perl_sv_clear` calls `curse(sv, 1)` for any `SvOBJECT` before touching the body.  `S_curse` resolves `DESTROY` through
the MRO cache (or `AUTOLOAD`), builds a READONLY temporary reference `tmpref = newRV(sv)` (raising the count from 0 to
1), and calls the destructor with `G_DISCARD|G_EVAL|G_KEEPERR|G_VOID`: an exception inside `DESTROY` becomes a `(in
cleanup) …` warning and leaves `$@` untouched, so an exception already propagating survives a dying destructor met
during unwinding.  Afterwards, if nothing copied `tmpref` itself, the count is decremented; if the destructor reblessed
the object the loop runs the new class's destructor in the same epoch; and if the count is still positive — because
`DESTROY` stored `$_[0]` somewhere — `curse` returns false and `sv_clear` stops: the object lives, and its next death
runs `DESTROY` again. Under `PL_in_clean_objs` the same condition is fatal: `DESTROY created new reference to dead
object`. References created and dropped inside a destructor never reach zero-with-resurrection and start no epoch.

## 5. Killing weak references — semantic execution

After a successful curse, and before the body is freed, `Perl_hv_kill_backrefs` / `Perl_sv_kill_backrefs` walk the
backref list in weaken order and, for each referrer, clear the pointer (`SvRV_set(referrer, 0)`, `SvROK_off`,
`SvWEAKREF_off`) and call `SvSETMAGIC(referrer)`. The set-magic is real execution: a magical referrer runs its `STORE`,
and a `STORE` that dies propagates out of the operation that killed the object (`undef $x`), leaving later referrers
uncleared.  Inside `DESTROY` every weak reference is still defined; after `sv_clear` they are not. Global destruction's
first pass clears weak references without set-magic and, depending on arena order, may do so before the referent's own
destructor runs.

## 6. Unwinding

`Perl_die_unwind` pops contexts down to the catching `eval`, running `CX_LEAVE_SCOPE` for each — the save stack in LIFO
order, so `SAVEt_CLEARSV` entries for lexicals declared after a `local` run before that `local`'s restore — then
`cx_popblock` (restoring the floor), then `FREETMPS`, then assigns `$@`. A destructor that dies during this unwinding is
trapped by `S_curse`'s `G_EVAL|G_KEEPERR` and the outer exception survives.

## 7. Global destruction — `Perl_sv_clean_objs`

After the main program's own scope is left (file-scope lexicals die in LIFO order here, before `END` blocks) and after
`END`, `perl_destruct` runs four arena visits with `PL_in_clean_objs` set: `do_clean_objs` over every `SVf_ROK` scalar
(strong references decremented, weak references cleared without set-magic), the same for objects held in globs and in
glob IO slots, then `do_curse` over every remaining `SVs_OBJECT` with `curse(sv, 0)`, which runs `DESTROY` regardless of
the count and makes resurrection fatal. The order *within* each pass is the order of the SV arenas — a property of
allocation history, not of the program — and is out of scope: the harness compares those rows as sets.

## 8. Verification

`fz_gen.pl` generates 114 scenarios: five destructor variants (plain, `$_[0]` copied into a global, weak copy, rebless
into a second class, dies) × the death triggers (scope exit with and without a trailing statement, `undef`, assignment,
`.=`, `delete`, `@a = ()`, `die` inside `eval`, global destruction) × the constructs (plain statement, `if` with one-
and two-statement bodies, `while`, postfix `while`, `do`-`while`, C-style `for` with and without a step and with a
two-statement body, call argument, void/list/scalar returns, `grep` block, `local`, `eval`), plus two tied weak holders
whose `STORE` records the call and, in one variant, dies on the first `undef`, and global-destruction rows. Each
construction is a distinct SV in the model, so a destructor that stores `$_[0]` into a global re-enters `curse` on the
object it displaces while the outer `curse` is open (the `grep` row shows three `DESTROY` calls before the next
statement and a fourth, fatal, in global destruction). After `curse` succeeds the object is un-objected (`SvOBJECT_off`
in `sv_clear`) before its backrefs are killed, so an exception from a referrer's `STORE` leaves an unfreed but
no-longer-blessed scalar that global destruction does not curse again. Result: **114 of 114 match on both
interpreters**, whose traces are identical to each other; the two global-destruction rows are compared as sets.
