# Perl reentry probes and corrected design conclusions

Executed on Perl 5.38.2 and a locally built Perl 5.44.0, both x86-64 with 64-bit IV/UV and double NV.  This report
distinguishes measurements, source explanations, and proposed concurrency semantics.  It does not claim coverage of all
possible handlers, Perl configurations, magic types, or operator lowerings.

The unqualified claim about replacing a scalar with `'99'` and then doing `+ 0` was wrong.  That probe gives `99:12:12`.
A narrower claim is true: forcing an NV conversion of the replacement changes the shared NV slot, and the resumed outer
conversion observes it.  The physical pin counter is not required when an epoch guard spans the complete access.  A
task-local element overlay is coherent with the rules below.

## 1. Generator, coverage, and results

`reentry_matrix.pl` runs each case in a separate child with a three-second alarm.  The matrix has 18 inputs, 19 handler
actions, five operations, and four effect locations: 6,840 cases per interpreter, 13,680 total.

Inputs: `'0 but true'`, `' 12'`, `'12x'`, `'1e5'`, `'0x10'`, `'inf'`, `'nan'`, numeric IV_MAX and UV_MAX, `'-0'`, `''`,
`undef`, textual IV_MAX and UV_MAX, numeric 0, 12, 12.5, and `'12.5x'`.

Actions: no mutation; replace with string `'99'`, string `'99y'`, integer 99, or NV 99.5; numify the original with `+ 0`
or an NV operation; replace with `'99'` then force ordinary, IV, or NV conversion; replace with `'99.5'` then force
ordinary or NV conversion; bless the scalar cell; replace its value with a blessed reference; replace with a weak
reference whose target remains owned; temporarily `local`ize the scalar; tie/retie it to a scalar returning `'77'`;
untie it; or die.

Operations: ordinary `0 + $x`; `0 + $x` under `use integer`; `sprintf '%.17g', $x` to request NV conversion; `$x .
$tail`; and `"$x"`.

Effect locations:

* `warn`: an ordinary scalar, mutated in `__WARN__`.
* `fetch`: a tied FETCH captures its return value, mutates the source scalar, then returns the captured value.
* `overload`: overloaded `""`, with fallback enabled, does the same.
* `warn_tied`: a tied FETCH returns normally, and a later warning handler mutates the tied scalar.  This adds genuine
  untie-during-warning cases and exercises the magical NV path.

Valid numbers do not trigger a warning handler merely because one was installed.  FETCH and overload actions execute on
all the supplied inputs.  Nested handler mutation is guarded; nested conversions still execute and are logged.

The raw state inspector uses `B` flags and raw IVX/UVX/NVX access, rather than IV/NV accessors that would themselves
convert or FETCH.  Raw NV storage is also logged before validity flags are installed; its existence does not make it an
authoritative face.  Primary events and post-operation state are captured before a separate, explicitly labeled
observation phase stringifies and numifies the scalar again.  No observation-phase event is counted as an original
operation event.

Per interpreter:

| Outcome                                                                             | Count |
|-------------------------------------------------------------------------------------|------:|
| Returned normally                                                                   | 6,618 |
| Threw from the deliberately dying handler                                           |   214 |
| Terminated with SIGSEGV                                                             |     8 |
| Normally returned a result different from the same input/operation with no mutation |    88 |

The 88 changed returns are 72 ordinary-warning cases and 16 tied-warning cases.  `matrix_findings.json` lists every
changed return, thrown exception, and signal by its complete case key.  There are no differences between the two
versions in the compared results, exceptions, signals, warning text, event ordering, or subsequent text/numeric
observations after reference-address normalization.  Some `B` storage types and flags differ; they remain in the raw
records.

### Complete grouping of changed numeric results

Let S be the four initially invalid numeric strings `'12x'`, `'0x10'`, `''`, and `'12.5x'`.  Let N be their original
ordinary/NV numeric results: 12, 0, 0, and 12.5; I is the original integer result: 12, 0, 0, and 12.

For an ordinary scalar and warning handler:

| Handler action, for every input in S                  | Ordinary addition | Integer addition | Direct NV conversion           |
|-------------------------------------------------------|-------------------|------------------|--------------------------------|
| Replace with `'99'`                                   | N                 | I                | 99                             |
| Replace with `'99y'`                                  | N                 | I                | 99                             |
| Replace with `'99'`, then ordinary or IV conversion   | N                 | I                | 99                             |
| Replace with `'99'`, then NV conversion               | 99                | 99               | 99                             |
| Replace with numeric 99                               | N                 | I                | SIGSEGV                        |
| Replace with numeric 99.5                             | 99.5              | 99               | SIGSEGV                        |
| Replace with `'99.5'`, then ordinary or NV conversion | 99.5              | 99               | 99.5                           |
| Replace with blessed reference or live weak reference | Reference address | I                | Observed 0; unsafe source path |
| Other returning actions in this matrix                | N                 | I                | N                              |

The reference-address results are not precision claims about arbitrary addresses.  The direct-NV reference cases enter
code that still treats the scalar union as a string pointer.  Their observed zero is not a stable semantic rule to
implement.

For a tied scalar whose warning handler mutates it, exactly two action families change primary results: replacing with
numeric 99.5, or replacing with `'99.5'` then doing ordinary addition.  For each input in S these give 99.5 under
ordinary addition and 99 under integer addition.  All other returning actions, including every direct-NV case, match
their unmutated primary result.  The magical NV path captures the earlier PV pointer before warning, which explains the
difference from the ordinary path.  This particular generator retains the original string through other ownership; it
does not prove arbitrary pointer lifetimes safe.

Additional failures of the simple “compute, warn, install onto the current payload” model are about state rather than
the immediate result:

* `undef` returns numeric zero after the warning but does not install a zero numeric face.  A handler replacement
  remains available to the next read.  With no replacement, subsequent conversions warn again.  The scalar's storage
  type can still be upgraded.
* After integer-path warning reentry replaces the source with a plain numeric value, the resumed conversion can clear
  public numeric-validity flags while leaving private numeric flags.  Stringification then warns about an uninitialized
  value and returns `''`, although a subsequent numeric read returns 12 or 99.5 in the corresponding `'12x'` cases.  A
  representation containing only “string present / number present” cannot reproduce this.
* Installing a tie during a warning does not restart the current conversion with the new FETCH.  The current result
  follows its existing continuation; later reads FETCH 77.
* Replacing with a reference preserves the reference flag, but the outer arithmetic opcode and a direct integer
  conversion can subsequently take different routes.  Ordinary addition returns the new referent's address; integer
  addition returns I.
* A dying warning handler aborts continuation.  On the integer path, the prewarning raw NV write has already occurred,
  even though no successful conversion flags have been installed.  This is not an atomic rollback.

The deliberately dying warning handler throws for S and `undef` in numeric operations, and for `undef` in string
operations: 17 cases per warning mode.  The dying FETCH/overload handler throws for all 18 inputs and all five
operations: 90 cases per mode.

### FETCH and overload mutation

Every returning handler in the generated FETCH and overload modes produces the same primary result as the corresponding
unmutated case.  That is 1,620 returning cases in each mode, per interpreter.  They have substantially different state
continuations:

* FETCH's captured return is copied onto the original destination SV after the method returns, including when the method
  untied or retied the scalar.  A plain assignment to that scalar during its own FETCH does not invoke STORE in these
  probes; get-magic has temporarily disabled the magic flags.  A new tie remains effective for later reads.  The
  operation does not redispatch FETCH just because the tie changed.
* Overloaded stringification uses the method's return for the ongoing expression without replacing the original scalar's
  payload with that return.  The minimal example yields `OLD:tail` while the operand afterward contains `NEW`.
* A `local` executed inside FETCH has its own magic interactions.  In the generated case, it leaves the tie object's
  later fetched value as 99 even though the current FETCH returns its captured original string.  The event log includes
  the localization STORE calls.  This is another reason to preserve effects, not just the operation's final numeric
  result.

These statements are bounded by the exact generator.  A method that computes a different return value, returns another
magical object, recursively changes a magic chain, or changes overload definitions is not covered by the absence of
primary-result differences here.

### Minimal interpreter crash

Both versions terminate with SIGSEGV on `minimal_nv_reentry.pl`:

```perl
use strict;
use warnings;
my $x = '12x';
local $SIG{__WARN__} = sub { $x = 99 };
my $r = sprintf '%.17g', $x;
print "$r\n";
```

The ordinary NV path reads the current PV pointer after the warning without rechecking that the callback preserved a
string.  The source strongly indicates the numeric assignment's cleared PV pointer as the cause; no debugger/backtrace
was obtained.  The isolated five-line reproduction establishes that the crash does not require the matrix's `B`
inspection.

I would record these as reference-interpreter bugs, not reproduce invalid native memory accesses in Rust.  Exact
compatibility cannot make undefined memory interpretation a portable value rule.

## 2. Correction to the numify-the-replacement claim

This exact original form gives `99:12:12` on both interpreters:

```perl
my $x = '12x';
local $SIG{__WARN__} = sub { $x = '99'; my $z = $x + 0 };
my $n = 0 + $x;
print "$x:$n:", 0 + $x, "\n";
```

Replacing the handler's `$x + 0` with `sprintf '%.17g', $x` gives `99:99:99`.  Replacing `'99'` with `'99.5'` while
retaining `$x + 0` gives `99.5:99.5:99.5`.  These are separate observations, not a defense of the incorrect unqualified
claim.

In [Perl 5.44.0 sv_2iv_flags](https://github.com/Perl/perl5/blob/v5.44.0/sv.c#L2400-L2490), the string conversion
delegates to `S_sv_2iuv_common`.  Its [warning
continuation](https://github.com/Perl/perl5/blob/v5.44.0/sv.c#L2307-L2375) first calls `S_sv_setnv`, then warns, then
uses the scalar's current NVX to construct the integer face.  The prewarning `numtype` remains a local variable and
governs the final validity flags.

The raw slot is 12 before the warning.  Installing string `'99'` and forcing its integer conversion does not replace
that raw NV slot, so the resumed conversion reads 12.  Forcing an NV conversion writes 99 there, so the resumed
conversion reads 99.  Replacing with a numeric NV 99.5 also writes it.  The correct model is a continuation with a
retained classification and a later read of shared scalar state, not a saved immutable numeric result.

The [ordinary and magical sv_2nv_flags paths](https://github.com/Perl/perl5/blob/v5.44.0/sv.c#L2580-L2700) differ from
this integer path and from one another.  An implementation must preserve those distinctions where they are observable.

## 3. A coherent task-local element overlay

This is a proposed shared-task extension.  Perl supplies the sequential identity and localization behavior, but not an
oracle for two tasks sharing arbitrary ordinary cells in this manner.

For hashes, define an overlay stack keyed by `(TaskId, ContainerId, canonical_key)`.  Its entries are `Present(Cell)` or
`Absent`; absence of any entry means consult the shared base hash.  `Absent` is a tombstone that masks the base.  All
accesses through aliases to that container use its identity, not the spelling of a variable.

Entering `local $h{k}` retains the hidden binding as required for its lifetime, pushes a fresh undefined cell, and makes
it present in the local task's effective hash.  Assignment then writes that cell.  Scope exit pops the overlay,
releasing its membership ownership; escaped references can keep its cell alive.  Nested localization naturally stacks.
Underlying cell contents are not copied back from a stale snapshot.

Suppose task A localizes `h{k}`, while task B has no overlay for that key:

| Operation                                | Task A                                                | Task B                                           |
|------------------------------------------|-------------------------------------------------------|--------------------------------------------------|
| Read / write `h{k}`                      | Resolve A's top entry                                 | Resolve shared base entry                        |
| `exists h{k}`                            | Test effective presence, independently of definedness | Test base presence                               |
| `keys` / `values` / hash size            | Enumerate/count the merged effective membership       | Enumerate/count B's effective membership         |
| Delete localized `k`                     | Replace top entry by tombstone; detach its cell       | No change to B's binding                         |
| Recreate `k` after local deletion        | Allocate a new cell in the overlay                    | Still no change to B's binding                   |
| B deletes or replaces base `k`           | Hidden by A's override until it is popped             | Immediately visible in B's view                  |
| A exits the local scope                  | Reveal the current lower view                         | No stale base value is restored over B's changes |
| Reference captured before localization   | Still points directly to the original cell            | Same cell if B possesses that reference          |
| Reference captured inside localization   | Points directly to A's local cell                     | If explicitly passed to B, B sees that same cell |
| Container reference passed between tasks | Lookup uses the executing task's effective view       | Lookup uses B's effective view                   |

A write/delete at a key without a local override uses the shared base.  Thus this is dynamic binding isolation, not
isolation of every write performed within a `local` scope.

`each` requires an explicit decision.  A coherent extension keeps its cursor per `(TaskId, ContainerId)`, shared by
aliases within that task.  `keys` resets that task's cursor.  A simple concurrent-iteration policy can snapshot visible
keys on the first `each`, skip keys absent when reached, and defer newly inserted keys until the next traversal.  This
is a proposed concurrency policy, not a claim that snapshot iteration reproduces every sequential Perl mutation case.
Strict sequential iteration would retain the reference hash engine's iterator rules; task-specific views can still each
carry that engine's cursor state.  Iteration is an additional specification, not a contradiction.

Aliases such as a scalar reference, an argument alias, or a foreach element alias bind the cell selected when the alias
is formed.  They do not repeatedly resolve `(container,key)` after every localization.  Container aliases continue to
resolve keys through the view.  Confusing these two kinds of alias would indeed break the model.

Arrays need the same treatment for holes and visible length, plus a specified routing policy for structural operations
and negative-index resolution.  One fully coherent, if less space-efficient, extension is to create a task-local
structural array view on the first element localization: copy the slot map and length, share the unlocalized element
cells, and give the localized index a fresh cell.  Structural edits thereafter affect that view; ordinary writes through
shared element cells remain shared.  Nested local scopes save/restore structural views; cross-task scalar references
still name selected cells.  This makes structural isolation stronger than the sparse hash overlay, so it must be an
explicit language decision.  A sparse implementation would need an equivalent precise rule for length, shift/splice,
holes, and whole-array replacement; I have not demonstrated that a particular sparse policy preserves every sequential
array-localization edge case.

The direct Perl probes establish the underlying distinctions: pre-local and localized hash-element references name
different cells; deleting/recreating the localized key does not retarget an escaped reference; scope exit restores the
original cell including modifications through its old alias; localizing an absent key makes it exist with undefined
value until scope exit; whole-array assignment detaches old element cells.

For tied containers or tied scalar elements, an overlay cannot silently virtualize the tie object's arbitrary external
state.  FETCH/STORE run with their specified effects; sharing that object shares those effects unless the object itself
implements task-aware state.  The ordinary-cell overlay is coherent without claiming to isolate arbitrary callbacks.

## 4. Continuation rules for five operations

In all five, a callback is a suspension point for the semantic operation.  Release ordinary data locks before invoking
Perl code.  Resume at the recorded stage; do not repeat an effect because a version changed.  Storage lifetime, language
ownership, and synchronization are distinct obligations.

### String numification

Before an integer-path numeric warning, retain the destination cell identity and original numeric classification; write
the parsed NV into its raw numeric slot.  After the warning, reread the current numeric slot, derive IV/UV, and apply
validity flags using the retained classification.  Do not reacquire a variable's current binding as a substitute for the
retained destination.  If the warning dies, later stages do not execute.  For ordinary direct NV conversion, warning
precedes parsing the current PV; for the magical branch a prewarning PV pointer is retained.  Undefined conversion
returns zero without making the scalar numerically defined.

Order: `sv_2iv_flags` / `S_sv_2iuv_common`, and `sv_2nv_flags`, cited above.  The arithmetic opcode can inspect flags
again after conversion, so an entire addition is not interchangeable with one call to an integer conversion function.

### Tied FETCH on read

Before the method call, retain the target SV and the selected tie receiver and method-call lifetime; get-magic
temporarily disables magic flags.  Call FETCH once.  After it returns, copy its return into that original SV.  Account
for magic removal or replacement rather than assuming the old chain is intact.  The calling operation then continues
from the resulting scalar state.  Do not fetch again merely because the callback changed the tie.  A dying FETCH skips
the return-copy stage.

Order: [mg_get](https://github.com/Perl/perl5/blob/v5.44.0/mg.c#L167-L245), [magic_methcall and S_magic_methpack /
magic_getpack](https://github.com/Perl/perl5/blob/v5.44.0/mg.c#L2140-L2247).  The latter explicitly calls the method and
then `sv_setsv` on the original destination.  The replace/untie/retie probes all produce the original returned numeric
value 12.

### Overloaded stringification in concatenation

Before stringification, retain the operand identities and the overload receiver for the call; establish the
target/operand aliasing branch.  Invoke the selected overload once.  Retain its returned string bytes, length, and
encoding state long enough to consume them.  The returned string supplies the current operand even if its original
scalar was replaced.  `sv_2pv_flags` also copies the return's UTF-8 flag back to the original scalar: the Unicode-return
probe leaves replacement text `NEW` with that flag on.  Then perform the remaining operand conversion and append,
followed by target set-magic.  Do not unconditionally install the overload return's bytes in the source cell, or resolve
overload dispatch again on the replacement.

Later operand state is reread only at the stage where that opcode/lowering converts it.  In the tested fresh-target
form, left stringification changing the right scalar from `before` to `after` yields `LEFTafter`.  In the source's
special branch where the target is the right operand, `S_do_concat` saves the right string before left conversion.  This
is why one universal left-then-right rule is insufficient; the actual alias/lowering path matters.

Order: [sv_2pv_flags](https://github.com/Perl/perl5/blob/v5.44.0/sv.c#L2992-L3100), [S_do_concat /
pp_concat](https://github.com/Perl/perl5/blob/v5.44.0/pp_hot.c#L545-L619), and [pp_multiconcat's slow
path](https://github.com/Perl/perl5/blob/v5.44.0/pp_hot.c#L1230-L1435).  These rules describe fallback stringification,
not separately overloaded concatenation.

### Rvalue nested autovivification

Walk dereference stages in evaluation order.  Retain the current parent/container and resolved intermediate cell.
Get-magic may fill it.  If undefined, allocate and install the required reference, perform set-magic, then get-magic
again.  After those callbacks, follow the reference supplied by the second get-magic, not unconditionally the freshly
allocated object.  Retain already performed mutations if a later key evaluation or STORE dies.  Final non-lvalue lookup
need not create the final element.

The tied probe gives `FETCH(undef) -> STORE(HASH) -> FETCH(HASH)`.  When STORE substitutes `{b => 'replacement'}`, the
read returns `replacement`.  A separate probe has the next key expression die; the earlier parent remains autovivified.
An ordinary `$h{a}{b}` read creates `a`, but not the final key `b`.

Order: [pp_multideref](https://github.com/Perl/perl5/blob/v5.44.0/pp_hot.c#L4475-L4840) and
[vivify_ref](https://github.com/Perl/perl5/blob/v5.44.0/pp_hot.c#L6792-L6832).

### local on a tied scalar

Entry first performs old-cell get-magic.  After it returns, the save stack retains the binding anchor and the
then-current old SV.  Install a fresh undefined SV, localize the appropriate magic, and run set-magic for undefined.  An
explicit assignment adds its STORE afterward.

At unwind, restore the saved old SV as the binding, release the localized SV (potentially executing destruction), then
inspect the old SV's current set-magic state and invoke it.  The restore uses the saved cell's current contents; it does
not restore an immutable value snapshot.  The save stack also arranges cleanup if restoration magic dies.

Observed ordinary entry/exit: `FETCH(old) -> STORE(undef) -> BODY -> STORE(old)`.  With assignment: an additional
`STORE(new)` before BODY.  A pre-local alias modifying the old cell causes restoration to STORE that modified value.
`local $t = $t` is a sharper example in these probes: the later RHS FETCH sees the localized external undefined state
and restoration ultimately stores undefined.

Order: [save_scalar / S_save_scalar_at](https://github.com/Perl/perl5/blob/v5.44.0/scope.c#L321-L367),
[mg_localize](https://github.com/Perl/perl5/blob/v5.44.0/mg.c#L484-L530), and [leave_scope's SAVEt_SV
case](https://github.com/Perl/perl5/blob/v5.44.0/scope.c#L1234-L1264).

## 5. Physical pin count, epochs, and the one-word handle

I cannot give a case that defeats properly scoped epoch protection and therefore requires a separate physical pin
counter.  Its inclusion as a mandatory per-cell field was unjustified.

A sufficient reclamation protocol enters the epoch before loading a published cell pointer; validates/acquires whatever
language ownership the operation needs while the membership is protected; keeps protection across every raw use,
including callbacks if raw pointers remain live; retires unlinked storage; and reclaims it only after all relevant
pre-retirement readers have left.  [Crossbeam's epoch
documentation](https://docs.rs/crossbeam-epoch/latest/crossbeam_epoch/) describes the guard/pinning and delayed
reclamation mechanism.  An epoch guard itself need not be a field in each cell.

The tempting broken case is: read an element pointer under a container guard, drop that guard, call a callback that
deletes the element, then use the pointer.  That breaks because protection ended too soon.  A frame epoch guard spanning
the callback, or another valid lifetime mechanism, fixes it.  It does not establish the necessity of a per-cell pin
counter.

Two separate obligations remain.  First, epochs delay freeing storage; they do not make a logically dead Perl object
live, synchronize mutation, or preserve an independently freed string buffer.  Retain/retire payload allocations
separately and obtain language ownership where Perl's evaluation requires it.  Second, Perl-visible finalization and
semantic reference releases must occur at their specified points, not only when an epoch collector eventually frees
memory.  The retired allocation must not postpone user-visible DESTROY merely because physical reclamation is delayed.

A long-lived or suspended guard may retain substantial unrelated retired storage.  A selective hazard or per-object pin
could be useful to reduce that retention.  That is a workload/performance tradeoff, not a semantic proof that every cell
needs the field.  No benchmark here establishes a winner.

For the earlier 48-byte header, deleting the four-byte pin field alone need not reduce the allocation: with the
remaining three 32-bit fields before an eight-byte revision, four bytes of alignment padding take its place.  That is
layout arithmetic, not a measured Rust layout.  A proposed repacking must be checked with `size_of`, allocator size
classes, and actual workload measurements before being called an improvement.

A cell handle can be a single ordinary pointer, e.g. `#[repr(transparent)] struct CellHandle(NonNull<Cell>);`.  The cell
allocation supplies identity; lifetime protection is supplied by ownership/guards.  There is no second heap allocation
for a Binding object.  If Binding also carries an inline 16-byte scalar, however, the whole Binding is not thereby one
word: its outer discriminator and inline representation must be accounted for.  A single-word handle claim and a
single-word inline-or-cell binding claim are different claims.

The blanket seqlock rejection was also too broad.  All-atomic payload words can use a correctly fenced
sequence-validation protocol with serialized writers.  Non-atomic speculative reads would be a Rust data race, and
arbitrary acquire/release placement is not automatically a correct seqlock.  Pointer ownership adds reclamation and safe
ownership-acquisition requirements; a mutex is a practical solution, not the only theoretically sound solution.  Perl
callbacks must remain outside a retried speculative region.

Finally, the supporting regression probes reconfirmed IV_MAX + 1 as the exact unsigned value 9223372036854775808, false
truth for `dualvar(7, '0')`, a strong copy of a weak reference, detached old array-element cells after whole-array
assignment, and v-string metadata surviving assignment but cleared by an empty append.  I agree that v-string provenance
belongs with copied value metadata despite Perl implementing it as a magic record.  Those probes do not prove a
universal “all magic never copies” rule.

## Reproduction

The archive contains the generator, summarizer, exhaustive catalog builder, continuation probes, minimal crash probe,
this report, and all raw result files.  Run with core dumps disabled because eight generated cases deliberately reach
interpreter crashes:

```sh
ulimit -c 0
perl reentry_matrix.pl > all-cases.jsonl
perl continuation_probes.pl > continuations.jsonl
python3 analyze_reentry.py all-cases.jsonl
```

Optional generator arguments select mode, input, action, and operation, in that order.  For example:

```sh
perl reentry_matrix.pl warn junk12 replace99_numify_nv add
perl reentry_matrix.pl warn_tied junk12 untie nv
```

The historical raw files split the first three modes into `reentry-VERSION.jsonl` and the fourth into
`reentry-tied-warning-VERSION.jsonl`.  The current no-argument generator emits all four.  Each file begins with
interpreter/build metadata.  `catalog_results.py` consumes those four saved versioned files and produces
`matrix_findings.json`; it compares complete case keys rather than assuming an arbitrary output ordering.
