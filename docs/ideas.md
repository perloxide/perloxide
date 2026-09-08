# PerlOxide: Findings and Candidate Designs

This document is not the design.  `design.md` records what is
ruled; this records two other things so that neither is lost to
the sessions that produced it:

1. **Verified findings** — facts about perl 5 established by
   probes against a real interpreter, where the current design
   either has no position or has one the probe contradicts.  Each
   states the fact, the probe that shows it, the design's present
   position, and what a ruling would settle.  A finding moves to
   `design.md` when it is ruled, and is deleted here.
2. **Candidate designs** — mechanisms drawn from a corpus of
   sixty-odd greenfield Perl-in-Rust designs produced by external
   models against the same constraints, kept where they would
   change an observable, a byte count, or a class of bugs and are
   not already in the design.  Each states the argument, the cost,
   and the ruling that decides it.  Candidates that were rejected
   are kept at the end with the reason, so the argument is not
   re-run.

Nothing here licenses implementation.  Every entry is a design
question for the architect, stated with enough precision to be
answered.  Probe results are from perl 5.38.2 unless a version is
named; nothing probed is known to differ in 5.44.

---

## 1. Verified findings awaiting rulings

### 1.1 Numification installs its cache after the warning, not before

**Fact.**  `sv_2iv`/`sv_2nv` compute the number, then emit the
`numeric` warning — which runs `$SIG{__WARN__}`, arbitrary Perl —
and only then install the numeric cache onto whatever the scalar
holds *now*.  If the handler dies, nothing is installed.

```perl
my $x = '12x';
local $SIG{__WARN__} = sub { $x = '99' };
my $n = 0 + $x;
print "$x:$n:", 0 + $x, "\n";       # 99:12:12
# handler stores 'abc' instead:     # abc:12:12, one warning total
# handler dies: the next numification of $x warns again
```

The scalar ends up string `"99"` with an authoritative numeric
face of 12 — a non-dualvar case where the faces disagree, which
the `Dual` payload already expresses as `Dual(12, "99")`.

**Design's position.**  `Scalar::numify_noting_warning` installs
the `Dual` face under the write lock and returns the warning event
for the ops layer to emit afterward: install-then-warn.  On the
paths above that yields `99:12:99`, two warnings for the `abc`
case, and no second warning after a fatal first attempt.

**Ruling.**  A sequencing rule, not a representation change, and
the shape §2.3.9 already prescribes: parse → release → emit (Perl
may run) → if the handler returned normally, acquire → store
`Dual(pre-callback number, current string)` → release.  Whichever
of `Dual`-in-`Value` or a face bit in `rc_state` owns warn-once
(§2.3.8 question 5), it is set only after the handler returns.
The probe above is the acceptance test, in all three forms.

### 1.2 `IV_MAX + 1` is exact, not lossy

**Fact.**  `pp_add` has an unsigned result path: `IV_MAX + 1` is
`9223372036854775808` as a UV, `IV_MAX + 2` is `…809`, and
`IV_MAX++` is the same UV.  Only `UV_MAX++` falls to an NV
(`1.84467440737096e+19`).  The constraint summary the corpus was
given stated the addition case as "verified lossy"; it is not.

**Design's position.**  §2.2.2 says integer promotion is unwritten
and reserves `Unsigned` for values above `i64::MAX`.

**Ruling.**  The promotion ladder for the integer operators —
signed, then unsigned when the exact result is non-negative and
fits, then NV — per operator, since `pp_add`, `pp_subtract`,
`pp_multiply`, and `pp_preinc` each have their own path in
`pp_hot.c`/`pp.c`.  `Unsigned` is the right home; the rule needs
writing before any arithmetic lands.

### 1.3 V-strings are a value kind

**Fact.**  Perl implements v-strings as `PERL_MAGIC_vstring` on a
`PVMG`, and `sv_setsv_flags` copies that magic.  Observably it is a
data type, not magic:

- survives every copy (assignment, into an element, into a hash
  value, `local $_ = $v`, self-assignment) and survives
  numification, a read;
- is cleared by every string write, including no-op writes
  (`.= ""`, `s/^//`, `substr` writing the same byte, `++`,
  `$t = "$t"`);
- carries the **original literal text** (`v1.02.003` retains
  `"v1.02.003"`; `B` and `version` read it), while the content is
  `chr(1).chr(2).chr(3)`.  `sprintf "%vd"` needs none of it — it
  formats any string's ordinals.

**Design's position.**  No mention of v-strings anywhere.

**Ruling.**  A `Value` kind (or `PString` subkind) holding the
literal text, the content derived on read or cached; inline when
the literal fits, heap otherwise; one discriminant from the
§2.3.8 chain.  `ref \$v` is `VSTRING` exactly when the referent's
payload is that kind, and the §2.3.9 store path (any store
replaces the payload) gives clear-on-mutation with no special case.
Bare `1.2.3` with two or more dots is also a v-string literal.

### 1.4 `pos` is a per-cell pair with three writers

**Fact.**  `pos` is per-location (a copy has none; aliases and
references see it; `local` gives a fresh cell with none), cleared by
any string write including `.=`, retained across reads such as
numification.  It is not an integer but a pair: the position and
perl's `MGf_MINMATCH` flag, "the last `/g` match ending here was
zero-length", which the regex engine consults to refuse a second
empty match at the same position (`"aab" =~ /a*/g` in list context
yields `aa`, `""`, `""` and stops).  Three writers set the pair
differently: a successful `/g` match sets position and flag
(flag on iff the match was empty); `pos($s) = N` sets the position
and clears the flag *unconditionally*, even for the same value
(`pos($s) = pos($s)` re-enables an empty match at that position);
a string write clears both.  `pos` is also an lvalue, and `\G`
reads it.  Perl stores the position as a byte offset with
`MGf_BYTES` and converts to characters on the way out.

**Design's position.**  `pos` is listed under magic (§2.5) with no
mechanism.

**Ruling.**  Where the pair lives on the cell (`FullScalar` today;
the from-scratch candidate's side table or spare word); that `pos`
as a `Place` variant has its own store semantics rather than
"store an integer into the cursor"; bytes or characters as the
stored unit (a `utf8::upgrade` on a string with a live `pos` is the
probe to run before ruling).  And a consequence for §2.3.8
question 2: `pos` needs identity, and `m//g` can target an
unpromoted element (`$a[0] =~ /a/g; pos($a[0])` is 1), so either
`m//g` is a promotion trigger — `while ($a[0] =~ /x/gc)` promoting
what it touches — or an unpromoted slot has room for a cursor.
This is a better motivating example for question 2 than the
numeric-cache one, which §2.3.4's `Dual` face already answers.

### 1.5 `utf8::upgrade` on a number converts it to a string

**Fact.**  Numeric scalars never observably carry the UTF-8 flag:
a fresh IV, an IV after interpolation, and an IV assigned over a
wide string all report `is_utf8` false (assignment of a number runs
`SvOK_off`, which drops `SVf_UTF8`).  `utf8::upgrade($z)` on
`$z = 9` sets the flag, but also flips `created_as_number` to false
and `created_as_string` to true — the scalar is now a string — and
for `$f = 0.1 + 0.2` the NV is *discarded and re-derived*:
`%.17g` afterward prints `0.29999999999999999`, the parse of
`"0.3"`, not `0.30000000000000004`.

**Design's position.**  Consistent (numeric kinds have no flag)
but unstated for the upgrade path.

**Ruling.**  `utf8::upgrade` on a numeric kind is a kind change:
`%.15g` stringification, then `String(…, flag on)` with the
numeric face dropped — not a `Dual` preserving the NV.  The `%.17g`
probe is the proof.

### 1.6 Weak-reference copy rules

**Fact.**  Copying a weakened scalar yields a strong reference;
self-assignment (`$w = $w`) leaves it weak.  Weak references remain
`defined` inside `DESTROY` (already the design's position, §2.4.4,
`sv_clear` running `curse` before killing backrefs).

**Design's position.**  Copy-strengthens is implied by `HeapWeak`
being a distinct kind; self-assignment is unmentioned.

**Ruling.**  One sentence in §2.4.8 beside `copy_for_assignment`:
self-assignment of a weak scalar is the identity, not a strengthen.

### 1.7 Hash keys compare as characters with downgrade normalization

**Fact.**  A byte `"\xe9"` and its `utf8::upgrade`d twin are one
key (perl downgrades a flagged key to Latin-1 when it can before
storing); `"\xc3\xa9"` as bytes and the same bytes decoded are two
keys, because they are different characters.  Raw `(bytes, flag)`
equality is wrong in the first case; raw byte equality is wrong in
the second.

**Design's position.**  §2.2.13 keys by `PString`; the
normalization step is not stated.

**Ruling.**  A sentence beside the interning rule: keys are
normalized by downgrade-when-possible before hashing and
comparison, and `keys` returns the stored (normalized) form.

### 1.8 Slots are rebound, so the slot→cell edge is not monotonic

**Fact.**  Perl rebinds a slot to a *different* cell in at least
four places, none of them promotion or demotion:

- `local $x`: a fresh SV is installed for the scope (`\$x` taken
  before still sees the old value at the old address; `\$x` inside
  yields a new address; the original returns at exit).
- `local $a[0]` / `local $h{k}`: the element slot is rebound to a
  fresh cell and back; an element that did not exist is *deleted*
  on unwind (`local $a[5]` on a two-element array grows it to six
  and restores it to two with `$a[5]` nonexistent).
- `*x = \$y`: glob assignment rebinds the package scalar's slot
  (`$$r` keeps the old value, `refaddr(\$x)` changes).
- `@a = (...)`: whole-array assignment detaches outstanding
  element cells (`$$r` keeps the old value).

**Design's position.**  §2.3.8 rules "a slot that names a cell
names it until the slot dies" and "reads through a slot's cell
pointer hold no claim."  The first is false for the four cases;
the second is sound only if the claim-free window is bounded by
whatever keeps the *slot* alive and unchanged.

**Ruling.**  Qualify monotonicity: no un-promotion, but rebinding
exists; claim-free use of a cell pointer ends when the container
guard, glob guard, or frame ownership that protected the slot
ends; slot rebinding happens under that same guard and the
outgoing cell's destructor runs after release (the §2.3.9
discipline extended to the slot word).  `local`'s save stack keeps
the old cell alive through the scope, so that direction is safe;
the temporary cell dropped at exit is the case the rule protects.
A second, semantic argument for the no-demotion ruling belongs
beside the measured one: perl's pad reuse keeps the *same* SV across
loop iterations when the reference was dropped (`refaddr(\$x)` is
identical in iterations 1, 2, 3), so demote-and-repromote could
hand out a different address where perl repeats one.

### 1.9 The magic-localization protocol

**Fact.**  `save_scalar` runs `mg_get(A)`, pushes A's pointer,
installs a fresh undef B, then `mg_localize(A → B)`, which copies
*container* magic (tie, `%ENV`, captures) and not *value* magic
(`pos`, taint).  Exit rebinds and runs `mg_set(A)` unconditionally
with A's then-current payload — a write event even when the value
is unchanged, so no dead-store elimination across a set-magical
cell.  `local $x = RHS` still fires `STORE(undef)` first
(`save_scalar_at(SAVEf_SETMAGIC)`, the #60360 FIXME), and because
the RHS `gvsv` merely pushes A while the LHS localization runs
`STORE(undef)` before `SvSetMagicSV` fetches A, a tied
`local $x = $x` ends up undef.  Tied scalar `$x` holding 10:

| Program | Callbacks |
| --- | --- |
| `{ local $x; }` | `FETCH(10) STORE(undef) STORE(10)` |
| `{ local $x = 10; }` | `FETCH(10) STORE(undef) STORE(10) STORE(10)` |
| `{ local $x = $x; }` | `FETCH(10) STORE(undef) FETCH(undef) STORE(undef) STORE(undef)` |
| `$old=\$x; { local $x; $$old = 99; }` | `… STORE(99) …`, final external value 99 |
| `{ local $x; tied($x) }` | same tie object, new `refaddr(\$x)` |

**Design's position.**  §3.3's per-task overlay stores the
localized state as a `Value`, covers special variables and package
scalars, and has no `localize` hook on magic.

**Ruling.**  `local` as slot rebinding: save the old *cell*, install
a fresh one, `localize` on the magic vtable with the container/value
split, unconditional set-magic on the old cell at exit; element
forms with the present/absent save distinction; `local *glob`.
The table is the acceptance test.  Source: the `scope.c`/`mg.c`
reading in the ChatGPT 5.6 Sol transcript, reproduced here.

### 1.10 Tied elements are proxies, and tied hashes and arrays differ

**Fact.**  On a tied hash, `\$h{k}` twice yields two different
addresses: each access manufactures a magical lvalue proxy (`PVLV`),
so a tied aggregate exposes no stable cell per key.  Consequently
`$$old = 99` inside `local $h{k} = 20` on a tied hash restores 10,
not 99 — the save stack holds a different proxy than `$old`.
Tied hash and tied array elements localize differently:

| | `local $h{k} = 20` (tied hash) | `local $a[0] = 20` (tied array) |
| --- | --- | --- |
| callbacks | `EXISTS FETCH STORE(20) STORE(10)` | `EXISTS FETCH STORE(undef) STORE(20) STORE(10)` |

(`pp_helem` passes `0` instead of `SAVEf_SETMAGIC` when an
assignment follows; `save_aelem` always sets magic.)  Restoring
absence on a tied element works only if the tie class offers
usable `EXISTS`/`DELETE`; otherwise perl falls back to
`FETCH`/`STORE` and leaves an existing-undef entry.

**Design's position.**  `Place` is the evaluator's navigator with
no proxy branch.

**Ruling.**  `Place` gains a second branch — stable slot versus
computed lvalue/proxy (tied element, `substr`, `pos`, other
magical lvalues) — and `local` operates on a `Place`.  The
hash/array asymmetry is preserved as-is.

### 1.11 Arrays have an `each` iterator

**Fact.**  `each @a` advances a per-array cursor shared with
`keys @a`/`values @a`, which reset it.  Perl keeps it in
`arylen_p` magic on the AV.

**Design's position.**  `PerlArray`'s 24-byte header has no field
for it and the doc does not mention it.

**Ruling.**  Four header bytes, or a side table for the rare case.

### 1.12 Document staleness and code nits

- §2.2.8 says the first numification warning *promotes*; §2.3.4 and
  `scalar.rs` install a `Dual` face without promotion.  §2.2.8 is
  the stale stratum.
- §2.3.8 question 2's motivating example (`$x + 0` on a string
  "must become a shared cell merely to cache a numeric face") is
  the case `Dual` already covers; 1.4's `pos` example is the one
  that needs the question.
- The from-scratch candidate in §2.3.8 makes "the face-valid bit in
  `rc_state` is the warn-once bit"; §2.3.4 makes the `Dual` face
  the warn-once carrier.  The observable is copy behavior (one
  warning across original and copy), which a cell bit cannot
  reproduce and a `Value` face does.  Which owns warn-once must be
  ruled before the candidate's 40-byte cell is evaluated further.
- `scalar.rs` has two `unreachable!` calls (`upgrade_to_full`,
  `numify_noting_warning`) under a no-panic rule; both can return
  through the match.
- Readonly lives in `FullScalar` in code and in `rc_state` in
  §2.4.3; §2.3.2's ledger should say so where `set_readonly`
  promotes to `Full`.
- §13.11's linearizability unit ("one primitive op") should
  explicitly exclude ops that ran user code: between a callback and
  the store that follows it, another task may write the cell, and
  the callback's result lands over the newer value.  Harmless for
  tied cells (the payload is not authoritative) and visible for
  get-magic write-through and set-magic that mirrors state
  elsewhere.  Accepted, and should be stated.
- Opus 4.8's question, ruled explicitly: drop-point or
  statement-boundary `DESTROY` equivalence, with the page-bitmap
  drain point named.

---

## 2. Array shapes

Agreed direction; the rulings still open are listed at the end.

**Motivation.**  Perl stores every element as an SV: 32 bytes for
an integer (an 8-byte `AvARRAY` pointer plus a bodyless 24-byte
`SVt_IV` head), more for a float, and a mortal temporary per
element during list assignment.  Measured on 5.38.2, one process
per row, peak RSS growth across the build:

| Workload | n | build | scan/pass | peak | B/elt |
| --- | --- | --- | --- | --- | --- |
| `unpack "C*"` byte array | 4,000,000 | 178 ms | 94 ms | 218 MB | 57 |
| `(1..N)` integer array | 4,000,000 | 143 ms | 95 ms | 215 MB | 56 |
| `map { $_/7 }` float array | 4,000,000 | 818 ms | 117 ms | 461 MB | 121 |
| 1M `{ i => $_ }` hashrefs | 1,000,000 | 234 ms | 62 ms | 261 MB | 274 |

The `Option<Value>` slot is already 16 bytes, half of perl's
steady state.  The shapes below take a byte array to 1 byte per
element (32×), a 32-bit integer array to 4 (8×), a float array to
8 (7×), and an array of references to 8 at the array level (4×);
the reads of a numeric array become a sequential stream that fits
in cache where perl's scattered heads do not.  The transient during
`@a = unpack …` depends on the ops layer's list path (16 bytes per
element if `Value`s are folded, less with a shape hint); the
steady-state ratio is the one that matters for anything that keeps
the array.

**One shape per array.**  No pages, no segmentation, no
interleaved groups (rejected below).  The shape is a header enum;
every structural op indexes one geometry through the existing
front-gap `start`.  Shapes are chosen by *representability*: a
value either fits the shape or the array widens along a fixed
ladder, so the policy is mechanical and cannot misfire.

**Flat shapes.**  A payload block at the allocation base, one
element per aligned word of the shape's width, holding exactly one
`Value` kind:

- integers at widths 1, 2, 4, 8 — signed by default; unsigned only
  once a value exceeds the signed range with no negative ever
  stored (`i8 → i16 → i32 → i64`, `u*` alongside); `u64` for the
  `Unsigned` kind, which is at least 2^63 and fits nothing else;
- `f64`; no `f32` (rejected below);
- any one-word pointer kind — `HashRef`, `ArrayRef`, `CodeRef`,
  `ScalarRef`, the cell handles (`@_` and a `foreach`-promoted
  array become a handle page), each a shape of its own.

**Kind purity.**  An `i64` page holds only integer-kind values, an
`f64` page only float-kind, whatever the numeric value: `3.0` and
`3` print alike but differ under `++`, `~`, overflow, and every
introspection path.  A mixed integer/float array is tagged.

**Undef, holes, and booleans without reserved values.**  A flat
page carries an optional *bit block* trailing the payload block:
one bit per physical slot, indexed like the payload through
`start`.  Bit clear: the word is a plain value over the shape's
full range.  Bit set: the word holds one of four codes — hole,
undef, `PL_sv_yes`, `PL_sv_no`.  A header flag, "specials
present", gates both the read-path test and the block's
existence:

- clear: every read is a plain load; the tail of the allocation is
  spare element capacity;
- set: reads test the bit; the last `ceil(capacity / 8)` bytes are
  the block, and usable element capacity is reduced by that much
  (one in nine at `u8`, one in sixty-five at 8-byte widths).

The first store of a special with the flag clear zeroes the tail,
sets the flag, and writes the bit and code if `len` still fits
below the reduced capacity — no reallocation, no element movement;
otherwise it reallocates with the block reserved.  Growth with the
flag set reserves the block; whole-array assignment decides from
the fold; the flag clears on whole-array assignment and `@a = ()`
and not on individual overwrites (a stale set flag costs only the
bit test).  The lazy block is strictly dominant over reserving it:
the reallocation it triggers on the first special is one a reserved
block would have taken earlier, at the same element count, on
every array — including the majority that never store an undef.
The block is also a SIMD-friendly structure: sixty-four elements
per byte, so "any holes?" is an OR and `grep defined` a popcount.
Sentinel values were the alternative and are rejected below.

**The tagged shape.**  For mixtures: a payload block of 8-byte
words and a contiguous tag block of one byte per slot trailing it,
both indexed through `start`.  Tags trail because the payload then
starts aligned at the base and the bytes after it need no padding;
growth is a wash either way, since neither block can grow in place
and a fresh allocation lays the tag block out at its new size
before the elements are copied.  The tag byte is a compressed
`Value` discriminant: kind (about 17–19 without inline strings,
about 23 with them: undef, hole, the two booleans, `Int`,
`Unsigned`, `Float`, `Dual`, `Typed`, the flattened reference
arms, the two handle arms), plus taint.  No readonly bit: readonly
is a location property, so it applies only to a promoted element
and lives in the cell reached through the handle.  No UTF-8 bit
except as the class axis of inline-string kinds, if admitted:
numeric kinds never carry the flag (finding 1.5), and every pointer
kind carries its own behind the pointer.  Six bits used of eight;
leave the rest unassigned.  **Tagged pages hold no heap strings.**
A `Heap8`/`Heap16` envelope carries length, capacity, class, and
count authoritatively so its allocation header is two bytes; a thin
pointer would move those bytes into the header, byte for byte, plus
a dereference to answer `length` — the saving is illusory for
strings and real only for kinds that are already one pointer.  A
string that needs a heap tier widens the array to the 16-byte
`Value` shape, which keeps one heap-string layout.

**The ladder.**  `i8 → i16 → i32 → i64` / `u64` / `f64` / pointer
kind → tagged → 16-byte `Value`.  Widening on a non-conforming
store is an O(n) rewrite under the container write lock, paid once;
flat-to-tagged is a tag-block allocation with no element movement.
Narrowing only on whole-array assignment, where the source list is
in hand and the body is being rebuilt: a min/max fold during the
copy yields `(min, max, kinds-seen)`, which decides everything —
narrowest width, unsigned or not, `u64` forced by any `Unsigned`,
tagged forced by any mixture, `Value` forced by any heap string —
at two compares per element on values already in registers.  A
third integer kind for "fits both signed and unsigned" would not
help: width is a property of the value, and the fold that finds it
subsumes the sign check.

**Concurrency.**  A flat store is one aligned word — the §2.3.9
quadrant with nothing owned and nothing torn, no sequence needed.
A tagged store is two writes (tag, payload) and takes the §2.3.9
protocol the 16-byte envelope already uses.

**Invisibility.**  Callers above `Slot` never see the shape:
`load` materializes a `Value` from tag or page kind plus word;
`alias` promotes and stores the handle under the `Cell` tag (or in
a handle page), so `for (@a)` on a numeric array does not change
its shape; `store` checks conformance and widens on failure.  This
is the same invisibility the packed tiers have inside `PString`.

**Cost.**  One more branch on every array access (the shape), a
second and third `ArraySlot` representation to keep correct through
`splice`/`shift`/holes/`$#a`, and a benchmark obligation before the
shape branch is accepted on the hot path.

**Open rulings.**

1. Whether the tagged word admits inline strings.  With the
   envelope's own trick — a full-word form with implied length 8
   and a shorter form with a length nibble, each doubled by the
   UTF-8 class — it costs four kinds and nothing in the tag budget,
   and buys 8-byte strings inline; it costs one more inline
   encoding to keep correct.
2. The gate: a one-word cell handle (§2.3.8 question 1), since
   neither the tagged word nor a handle page can hold a two-word
   `ScalarRef`.
3. Whether widening preserves capacity slack or resizes, and what
   an empty array starts as (flat at the narrowest width, the first
   `push` deciding, is the natural answer).
4. Whether pointer-kind flat pages distinguish references to
   `Const` cells from `Mut` ones as two shapes or fall to tagged.

**Deferred, not rejected.**  A fused `@a = unpack "C*", $s` /
`$s = pack "C*", @a` whose `u8` page shares the string's COW buffer
(a refcount bump instead of a copy; detach on the first structural
op from either side).  The flat page already captures essentially
all of the 32×; sharing removes a sub-millisecond memcpy and halves
one idiom's transient.  It adds a borrowed payload state to every
structural op, so it waits for a measured workload.

---

## 3. Shaped hashes (records)

Recorded, not ruled.  Prerequisite landed: the §2.2.9 literal
twins.

**The trigger.**  A hash whose keys have all been literal-form
`PString`s (§2.2.9 twins inline, `Static` heap forms beyond) is a
record.  This is a property of the contents, not a guess about
usage, so it cannot misfire; the only effect of a wrong guess is
one conversion.  Literal-ness in the *value* rather than in the op
serves standalone crate users, who have no op tree: a key built
from `&'static str` through `from_static` triggers shaping exactly
as a program literal does.  An explicit hint on the API can be
layered on top for callers with a fixed schema and dynamic keys.

**The registry.**  Global, shared across tasks, append-only: shapes
are immortal transition nodes, each holding a key list and a small
child map keyed by the next literal key.  Reads are lock-free (a
shape pointer and an immutable key list); transitions are rare and
may lock.  Shapes are keyed by *sorted key set*, not insertion
sequence: adding `age` to `{name}` transitions to `{age, name}` and
inserts the slot at its sorted position (a memmove of a few hundred
bytes at most, once per transition).  Records built incrementally
in varying order — `$r{age} = $age if defined $age` — then share
one shape per distinct populated field set, which for real records
is a small number.  Memory is bounded by distinct literal-key sets
in the program; program text that manufactures new literals at
runtime (`eval STRING` in a loop) grows the registry accordingly,
which is that program's problem.  No key-count cap: a 250-entry
literal lookup table is a fine record; only a sanity limit on
chain depth, stated as a deopt.

**The packed body.**  Shape pointer, the existing container header
(refcount, stash, flags, `each` cursor), and a values block of
`Option<Value>` — 16 bytes each with the niche giving *absent* for
free — later eligible for the array shapes when a record's fields
are homogeneous.  The key is not stored per hash.  `{ i => $_ }`
costs a header plus 16 bytes against ~40 per entry in the table
engine and ~200 in perl.

**What stays packed.**  `delete $h{k}` sets the slot absent (the
key is literal; re-adding is a store into the same slot).  `exists`
reads the slot.  Rvalue lookups with *computed* keys (`$h{$k}`)
find the key by content — a linear compare of 16-byte words below a
small threshold, a per-shape lazily built index above it, shared by
every hash of the shape — and do not convert.  `\$h{k}` promotes
the slot in place, as an array element does.  `keys`/`values`/
`each` iterate the shape's key order with an index cursor.
`%h = ()` resets to the root shape.  `bless` touches only the
header.  Restricted hashes (`Hash::Util::lock_keys`) map onto
shapes almost exactly.

**The conversion.**  One-way, O(n), on the first *store* through a
non-literal key or on exceeding the depth limit: build the table
from the shape's keys and the slots; a converted hash never
re-shapes (hysteresis, so no thrashing).  `tie` replaces the engine
outright.

**Observable.**  All hashes of one shape iterate in one order —
the sorted key set — where perl randomizes per hash.  Order is
unspecified under perl's documented guarantees, which are the
contract; no further policy statement is needed, but code will
notice.

**Subsets.**  Instances that genuinely lack a field are distinct
shapes and cost nothing extra in storage.  What they cost is
polymorphism at access sites, which is the ops layer's problem and
has two standard answers: polymorphic inline caches (a site
remembers a few `(shape, slot)` pairs and degrades to the shape
index beyond that), or a declared field list giving every instance
the superset layout with absent slots.  Perl now has the declared
form natively — `use feature 'class'` with `field` (5.38+) — so
class-based objects get the declared shape and `bless {}` objects
the inferred one.  Inferring a superset ("this `{name}` is probably
a `Person` missing `age`") is the one thing ruled out: it is the
guess that can misfire, and everything else in the scheme is
mechanical.

**Where the CPU half lives.**  Shape-keyed inline caches on
`$obj->{field}` — the shape pointer check replacing a hash lookup —
need the ops layer and are the reason this waits.

---

## 4. Value-layer candidates

### 4.1 A tier bit so the task-local majority pays no atomics

Every promoted read takes a `parking_lot` read lock and every
`HeapArc` clone is an atomic RMW, even in a program that never
spawns.  A `SHARED` bit in `rc_state` with the invariant "a shared
object never points at a local one", maintained by a one-way
traversal when a reference is published into shared reachability
(assignment into a shared container, capture by a spawned closure,
`:shared`), lets local-tier count operations be plain load/add/store
and local-tier reads skip the lock.  Biased counts are exact, so
`DESTROY` timing is unaffected (deferred counting would not be;
the two are often conflated).  Local means *task*-local: a Tokio
task may resume on another worker, and the scheduler's handoff
supplies the happens-before, so the invariant is written in task
terms.  Cost: the `share()` traversal, a `!Send` token discipline
for local-tier operations, and bits in `rc_state` — which is why
it is best decided before the slab `HeapArc` fixes the node
layout.  Sources: Fable 5.1's tier bit, Grok 4.6's `share()`
walk, Opus 5's "sharing is acquired, not declared".

### 4.2 Make the cardinal invariant mechanical

§13.11.1 is prose.  Two cheap enforcements: any function that can
run Perl takes `&mut ExecContext` and cannot accept a lock guard
(guards are `!Send` and have no path into that API); and a
debug-build counter asserting internal lock depth is zero at every
Perl dispatch point.  Deadlock-freedom then rests on a small
auditable kernel rather than on every op author's discipline.
Sources: GPT-5.5's `!Send` guards, Kimi K3's lock-depth assert.

### 4.3 Effect classification for magic; no retry after Perl has run

Classify magic as pure-native / native-no-Perl /
arbitrary-callback so `$!`, `pos`, taint, and `%ENV` never enter
the callback path.  Replace §13.11.2's "try-lock, release, retry"
with the rule that retry is legal only for side-effect-free
preparation; §2.3.9's "run the callback → build → acquire →
store → release" already satisfies this since nothing inside the
section can fail.  Whether the arbitrary class then goes through
one reentrant effect gate (serializing every tie/overload/
`DESTROY` process-wide, deadlock-free by construction) or stays
per-cell with revalidation (the design's current shape) is the
ruling not yet on the ledger; the classification improves either.
Also:
`mg_get` writes the fetched value through the cell's normal store
path — it is not "the result" — so stacked magic and later reads
see it.  Sources: Sol, Terra.

### 4.4 Access intents and deferred elements, ruled before the ops layer

The `get`/`ensure_element` split is settled; the intent enum
(`FETCH_RVALUE`, `FETCH_LVALUE`, `VIVIFY_INTERMEDIATE`, `EXISTS`,
`DELETE`, `LOCALIZE`) decides that `exists $r->{A}{B}{k}` vivifies
intermediates and not the leaf.  Perl's defelem belongs with it:
`sub { 1 }->($h{x})` must not create the key while
`sub { $_[0] = 1 }->($h{x})` must (verified) — a slot kind or an
lvalue variant naming `(container, key)` without materializing.
Sources: GPT-5.4 High's `Place`, GPT-5.5's `LValue`, Fable 5.1's
`Deferred`.

### 4.5 Operations as resumable transitions

For anything that yields an effect (warning, magic, overload,
semantic release): a step under the guard, release, the effect,
resume through an op-specific continuation that follows perl's own
rules about what is re-read and what is retained — explicitly
neither "retry the whole op" nor "abandon on version change".
Finding 1.1 is the demonstration.  Source: ChatGPT 6 Astra.

### 4.6 Smaller items

- Per-thread locale objects (`strtod_l`-style) so `use locale`
  radix behavior in numification is task-safe (Kimi K3).
- An explicit compatibility-profile section: Perl version, IV/NV
  widths, Unicode database version, hash-order stance,
  `Devel::Peek` non-goals (Terra, Sol, Astra).
- Mortal/`FREETMPS` timing as an equivalence surface, with
  `sv_unref_flags` mortalizing the referent in `$a = $a->[1]` as
  the first probe (GLM 5.3 High, Fable 5.1).

---

## 5. Testing and measurement

- **A reentry generator for the differential fuzzer**: boundary
  strings and numbers crossed with a `__WARN__`/tie/overload
  callback that replaces, numifies, blesses, weakens, unties, or
  deletes the scalar being processed.  The existing probes are
  happy-path; this is the class that found finding 1.1.  (Astra.)
- **The `local`/tie sequence tables** in findings 1.9 and 1.10 as
  verbatim acceptance tests.
- **A perl-compatible hash engine** — `hv.c`'s hash function and
  `PERL_HASH_SEED` handling — behind the existing engine enum, not
  as the default, so whole programs can be differential-tested
  against stock perl with the seed pinned.  Order is legitimately
  unspecified; the testability is what the SwissTable engine
  forfeits.  (GLM 5.3 Flash.)
- **A deterministic scheduler** with injected yield points for the
  shared-tier protocols, beside the Loom model planned for
  `rc_state`.  (GPT-5.6 Luna.)
- **The perl baseline harness** for the array shapes, one process
  per workload (freed arenas make later runs in one process read
  low):

```perl
use strict; use warnings; use Time::HiRes qw(time);
sub rss { my $r = `ps -o rss= $$`; $r =~ s/\s+//g; $r * 1024 }
my ($which, $N) = @ARGV;
my %w = (
  bytes  => [ sub { my $s = "x" x $N; my @a = unpack "C*", $s; \@a },
              sub { my $s = 0; $s += $_ for @{$_[0]}; $s } ],
  ints   => [ sub { my @a = (1..$N); \@a },
              sub { my $s = 0; $s += $_ for @{$_[0]}; $s } ],
  floats => [ sub { my @a = map { $_/7 } 1..$N; \@a },
              sub { my $s = 0; $s += $_ for @{$_[0]}; $s } ],
  refs   => [ sub { my @a = map { {i => $_} } 1..$N; \@a },
              sub { my $s = 0; $s += $_->{i} for @{$_[0]}; $s } ],
);
my ($build, $scan) = @{$w{$which}};
my ($r0, $t0) = (rss(), time); my $a = $build->();
my ($t1, $r1) = (time, rss());
my $s; $s = $scan->($a) for 1..3; my $t2 = time;
printf "%-6s n=%d build %.0f ms scan %.0f ms/pass peak %.1f MB %.1f B/elt\n",
  $which, $N, ($t1-$t0)*1000, ($t2-$t1)*1000/3, ($r1-$r0)/2**20,
  ($r1-$r0)/$N;
```

---

## 6. Rejected, with reasons

- **Pages / segmented arrays** (Sol, Astra): per-segment locks and
  per-page shapes buy concurrent writes to distinct inline
  elements of one shared array and density under region-clustered
  heterogeneity — both rare — at the price of a directory, a
  second indirection on every access, and structural ops that
  coordinate across boundaries.  Mixed arrays in real programs are
  mixed uniformly (record-shaped rows), where pages do not help
  either.  The whole-array shape's failure mode is bounded: the
  widest shape is today's 16-byte slot.
- **Interleaved tag groups** (eight tags then eight words): a
  72-byte group is not line-aligned, so the tag and its payload
  still straddle lines often; sequential scans stream both blocks
  in parallel with no penalty; and the separate block gives
  sixty-four tags per line for vectorized checks, tag-only
  widening, contiguous copies, and `start + i` addressing
  everywhere.
- **Reserved sentinel values** for undef/holes/booleans in flat
  pages: any placement collides with some idiomatic extreme (`255`,
  `~0`, `IV_MIN`, `INT_MAX`); a placement keeping `MAX`/`MIN`
  storable and reserving the next four still makes `u8` pages
  useless for uniform binary data (`unpack "C*"` on a file hits a
  reserved byte with near certainty).  The lazy bit block costs
  nothing until a special appears and has no placement question.
- **Bit pages for booleans**: arrays of real `PL_sv_yes`/`PL_sv_no`
  are rare (`map { $_ > 3 }`; `grep` returns elements), flag arrays
  hold the integer 1 and go to `i8`, a bit page would need two bits
  per element (true/false/undef/hole) for a 4× gain over `i8` on
  small arrays, and the language routes bit vectors to `vec`.
  The general test: a shape earns its place by making *existing
  idiomatic Perl* cheaper, not by rewarding a style nobody writes.
- **`f32` pages**: lossy narrowing is an observable rounding and
  therefore not Perl; lossless narrowing (store only values that
  round-trip) has a hit rate near zero on real data, since a
  decimal that is not `f64`-exact is essentially never `f32`-exact.
  `pack "f*"` is the idiomatic route.
- **`i128`/`u128` pages**: no native Perl value is 128-bit; `bigint`
  objects are references with Perl-level behavior.
- **Transparent bigint on overflow**: `IV_MAX + 1 → UV → NV` is
  observable arithmetic that output formats and tests depend on
  whether or not anyone wants it, and bigint also changes
  non-overflow arithmetic (`7 / 2` is `3` under `use bigint`), so a
  transparent promotion would be a third arithmetic.  A native fast
  path *behind* `use bigint`/`bignum`, preserving the object-ness
  and dispatch surface, is the compatible form and is not a
  value-layer concern.
- **A `Natural` integer kind** (fits signed and unsigned): the
  array shape decision needs width, which only the values give,
  and the min/max fold that finds width subsumes the sign check;
  the kind would cost a sign test on every integer result, two
  discriminants, and a departure from perl's own `IV`/`IsUV`
  split.  Any `Unsigned` present already forces `u64`.
- **Literal twins on the packed string tiers**: digit runs,
  datetimes, and UUIDs are data; no literal key reaches them.
- **Carrying literal-ness on the op instead of the value**: precise
  for the interpreter (perl's own constant-key `HEK` path) and free
  in the tag budget, but invisible to standalone crate users, who
  have no op tree.  The value-level form serves both; an op-level
  hint can still be layered on.
- **A string front offset (`sv_chop`/OOK)**: §2.2.15's views give
  `substr($s, 0, n, '')` and `s/^\s+//` an O(1) form at a new
  offset over the same backing, and handle either end.  The one
  asymmetry — perl's OOK'd string appends in place while a view
  must extract before appending — is recoverable at the policy
  layer when the view is the sole holder.
- **A cycle collector**: `DESTROY` on a cycle runs at global
  destruction, observably; a collector would run it earlier.
  (Already the design's position; recorded because roughly eight
  corpus designs added one.)
- **A hash-order policy statement** beyond perl's documented
  guarantees: those are the contract.
