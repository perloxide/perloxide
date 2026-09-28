# Consolidation (2026-09-23): terminology, naming, reconciliation

Terminology: string form / numeric form; value flags (int_form, num_form: 0 none, 1 private, 2 public; is_uv;
stringified; private); Dual.  Models: VF.pm (package VF, was M.pm), FZ.pm, HV.pm, PV.pm.  A snake_case routine in a
model package mirrors the C function of that name (Perl_/S_ prefix removed; macros keep their spelling); everything else
is in <Model>::Harness and CamelCase.  VF.pm is reconciled from two transcriptions (this thread's M.pm and the other
session's MF.pm, equal cell for cell on the 2304-row matrix); the Perl-undefined windows W1/W2/W3 take the
design-defined redispatch when $VF::DESIGN_DEFINED is set, and the matrix reports list them as DIVERGES-defined rows
with Perl's and the design's outputs side by side.  Not done in this pass: the single merged generator with the
Devel::Peek projection (peek_projection_probe.txt shows what the fuller projection distinguishes), depth-4
re-verification of the 13-op core against the renamed model, the random-walk complement.  The counts after renaming are
in reports/.

## Pass 2 (2026-09-23, later)

- vf_core12_depth4.<ver>.txt : 12-op core at depth 4 over the 13 string starts under the package-per-block harness:
  10,416/0 on both Perls (the earlier 21,518 figure was produced by the pre-consolidation harness with a lexical holder
  and unwrapped ops; the two enumerations are not the same state space and the count is not comparable).
- gen_peek.pl, peek_projection.<ver>.txt, peek_states.<ver>.tsv : the fuller observation (Devel::Peek on the original,
  exact slot bits, consumers through a copy, warnings, croaks) over 24 starts x 12 ops to depth 2; the report lists
  every flag-projection class the full projection separates.
- Pending at packaging time: the 56-op depth-3 rerun on 5.38.2 and the PV depth-1 reruns against the renamed models
  (present in reports/ only if they completed); the merged single generator and the seeded random walk; body-type and
  COW_REFCNT modeling in VF.pm.
- A suffixed snake_case name in a model (got_nv, sv_inc_nomg_integer, pp_bit_or_string_other) is a label or arm inside
  the named C function, not a function of its own.

## Pass 3 (2026-09-23, later still)

Harness facts (eval_wrapping_probe, holder_kind_probe): a fresh-package `our $x` is indistinguishable from a fresh `my
$x` under the full projection (54/54); wrapping an op in `eval { }` DOES change state the projection sees — the copy op
(`my $y = $x; $x = $y`) leaves COW_REFCNT 2 bare and 1 inside an eval, because the eval's scope frees `$y` — so the
partition generator runs bare ops, and a package variable that is reused (not fresh) keeps its body type and buffer and
does not take COW on re-assignment.  Counts are stated per (holder, op set, depth, harness) and never compared across
harness generations.  Partition (gen_partition.pl, partition.5.44.0.txt): 24 starts, 12 core ops to depth 2 bare, 3,116
states, every state stepped by the 58-op set with the full observation: 307 flag-projection classes split; class (a) = 4
(all NOK-only integral NVs whose members differ in body type NV/PVNV and stale buffer CUR/LEN; a consumer column differs
now or after `nv`), class (b) = 303, which includes every COW_REFCNT split (1 versus 2: both SvTHINKFIRST,
consumer-invisible).  The (a) column was not pinned and VF.pm was not extended; step 4 is open.  Not confirmed in this
bundle unless present in reports/: the 56-op depth-3 rerun on 5.38.2 and the PV depth-1 reruns.  The merged generator
and the seeded random walk are not built.

## Pass 4

classA_pin.<ver>.txt: the four consumer-separated classes re-probed in isolation are consumer-identical on both Perls;
the partition's separation traced to a Data::Dumper XS quoting difference on an identical fresh state inside the
enumeration process (cause not pinned).  Class (a) is empty for the scalar; no VF.pm change.  Long runs started detached
in this pass (longruns.sh, pid recorded): confirmed reports are present in reports/ only if they completed before
packaging.  Steps 3 and 4 (merged generator, seeded random walk) not built.  Pass 4 confirmed: 56-op depth 3 on 5.38.2
against the renamed VF.pm = 295,858 transitions / 0 mismatches (vf_56op_depth3.5.38.2.txt).  PV.pm rename had turned the
child's utf8::upgrade/downgrade calls into the model's C names (a string-literal rename side effect); fixed in
pv_gen.pl/PV.pm; the PV depth-1 reruns are in reports/ only if they completed before packaging.

## Pass 5

Dumper artifact pinned: case (i) — pp_add's fast path (pp_hot.c) skips SvIV_please_nomg when both operands share public
NOK, and the consumer chain's shared literal 0 had acquired NOK from an earlier non-numeric addend; scalar state
identical; class (a) empty for the scalar; VF.pm gains pp_add_with_partner.  PV rename regression isolated: the `*op =
sub` override glob was not renamed with `sub op` (same class as VF's `*grok`); fixed; reruns launched (reports present
only if completed).  Rename-script rule going forward: never rewrite identifiers inside quoted child source; the two
glob-assignment misses are listed here.  Merged generator and random walk: not built.  PV reruns after the glob fix:
5.44.0 1903/2052, 5.38.2 1900/2052 -- the pre-rename counts, confirmed against the renamed PV.pm.

## Pass 6

copycheck.<ver>.txt (gen_copycheck.pl): copy-state rows and the destructive copy-vs-original cross-check over the 12-op
core lane at depth 2 -- consumer outputs identical on every state (0/3099 on 5.44.0, 0/3084 on 5.38.2); the copy differs
from its source only by IsCOW/COW_REFCNT (both sides) and by not carrying a stale unflagged buffer; every value flag is
carried.  No VF.pm change.  Merged generator and random walk: not reached.

## Pass 7

vf_suite.pl is the value-flags verification driver: five lanes (handler matrix, locale axis, 12-op core depth 4, 58-op
set depth 3, copy check) on both Perls under one entry point; reports/suite/coverage.txt is its coverage table and the
definition of "verified" for this area.  Lane reports are cached in reports/suite/<lane>.<ver>.txt and rerun with
RERUN=1; the lanes' own generators are still the separate files (the shared observation module is not yet factored out
of them: the core and copy lanes carry the full projection, matrix/locale/full3 the flags-plus-slots one).  ver-div is
counted from the lanes' transition tables, which are byte-identical between 5.38.2 and 5.44.0 for every lane.
Random-walk lane: not added.  Harness rules (all three found the hard way): (1) never eval-wrap an op -- the eval scope
frees the copy op's temporary and changes COW_REFCNT; (2) the holder must be fresh -- a reused package variable keeps
body and buffer and takes no COW on re-assignment; (3) the observer's copy holder must be fresh per block too -- a
lexical inside the observer sub is a reused pad slot and its stale body/buffer masquerades as a copy transition, and a
shared literal partner inside the observer drifts.  Partner-typed report (partner_typed.txt): add, subtract, multiply,
`==`, `!=`, `<`, `>`, `<=`, `>=` are partner-typed (flags-AND fast path); `/`, `%`, `**`, `<=>`, sort numeric, unary
minus are not; identical on both Perls.  VF.pm: binop_operand_flags.

## Pass 8

VF::Observe (models/VF/Observe.pm) is the one observation module: flags+slots key (what the model is checked against),
and under PROJ=full the Devel::Peek body/flags/CUR/LEN/COW_REFCNT plus the consumer chain on a fresh-per-block package
copy.  gen3_vf.pl (core, 58-op, walk lanes) is wired to it; the key is projection-independent, so lane counts did not
move (spot-checked: 159/95 under both projections).  Lanes still carrying their own head: matrix, locale, copy
(functionally the same key; the copy lane already makes a fresh per-block copy).  core4 stays the cached historical lane
(13 starts; its exact start list was not recorded in the report and is not recoverable from the driver -- the transition
table is).  Walk lane: 24 starts x 125 seeded walks x depth 6 over the 58-op set, seed 20260924, full projection, both
Perls; its mismatches are listed with recipes in reports/suite/walk.<ver>.txt.  First run exposed a harness gap: the six
starts added to gen3 for the 24-union had no mstart entries (i0/f0 were modeled as strings); fixed for i0/f0; "0 but
true" (s0but) remains open in the model.  binop_operand_flags renamed: the gate is VF::pp_add_partner_gate (the
flags_and prelude shared by pp_add/pp_subtract/pp_multiply and the comparison ops).

## Pass 9

"0 but true": VF.pm already had the branch but placed it after the trailing-garbage test, so the general parse returned
first; moved ahead of the parse as in numeric.c Perl_grok_number_flags (memEQs(pv, len, "0 but true") ->
IS_NUMBER_IN_UV, value 0), s0but depth-2 mismatches 674 -> 20.  Key precision: VF::Observe::slots and gen3's model
projection now print IV/UV slots exactly (the %.17g key had collapsed adjacent integers above 2^53, which produced the
iMax/sUV/s1e19 "deep recipes" -- they were key-collision artifacts, not model gaps); state counts in integer-heavy lanes
move by construction of the key, and the table's counts are from the reruns.  core4 retired and rerun fresh through the
driver: 24 starts, the 13-op core, depth 4, full projection (41,639 transitions; 20 open on 5.44.0, 32 on 5.38.2).  Walk
rerun with seed 20260924: 170 -> 12 open on both Perls.  Remaining open family (core4 and walk): append (`.=`) onto a
buffer that holds private numeric flags after an empty append (`.= ""`) followed by a read that caches them -- Perl
clears the private flags, the model keeps them; observed cause: Perl's empty append leaves the COW share intact
(S_sv_uncow, sv.c, then clears on the next non-pure append) while the model drops cow on any append; not yet fixed.
Lanes wired to VF::Observe: core4, full3, walk, locale, copy.  The matrix lane keeps its own head: its key carries ROK
(reference holders) where the module key carries UTF8, so wiring it changed its key and its counts (290 rows); it was
reverted to keep the counts, and the difference is recorded here.  full3 projection cost: not measured this pass; the
lane stays on flags-plus-slots by prior decision.  Matrix 5.44.0 report in the chain was contaminated by a concurrent
run during the wiring experiment; rerun cleanly (2154/0/114/36) and the table regenerated.

## Pass 10 -- the key widened, and what it exposed

Key change: VF::Observe::flags and VF::Harness::FlagsProjection now emit IOK,NOK,POK,pIOK,pNOK,pPOK,IsUV,ROK,UTF8,IsCOW,
and integer slots print exactly (no %.17g).  Two harness faults fixed on the way: the observation copy (`our $c = $x`)
was taken BEFORE the key and COW-shared the observed scalar (IsCOW appeared on every read-op result); record() now takes
the key first.  The matrix lane is on the module key (its handler-assignment model now sets cow: string literal 1,
number/ref/undef 0).  IsCOW was added to the key because without it the walk's replay recipes collided (a COW and a
non-COW state share a key and the replayed recipe reaches the wrong one -- the "empty-append family" was that collision,
not a pp_multiconcat branch; the append probe (appendprobe.pl) shows private numeric flags survive both empty and
non-empty appends on a non-COW buffer on both Perls).  Under the widened key the model's cow tracking is exposed as an
approximation: nearly every open row is cow-only (Perl IsCOW, model not) -- see the counts below -- and the dominant
source is the harness copy op after an un-COWed buffer, where Perl re-establishes IsCOW and VF.pm's sv_setsv_flags
(rewritten this pass to leave cow unchanged, on a probe that turns out not to generalize) does not.  This is the open
modeling item; the rule to transcribe is sv_setsv_flags's COW branch (sv.c: the CAN_COW_MASK / SvLEN > SvCUR+1
conditions) and the copy-back's same-buffer case.  Counts moved by the key change, as expected: core4 41,639/20 ->
44,382/2,002 (5.44.0); walk 10,107/12 -> 10,407/596; matrix 2154/0 -> 2154/44; locale unchanged 1152/0; copy 3096/3081
with 0 consumer differences.  full3 under the new key was still running at packaging and is NOT in the table (pending,
marked in vf_suite.pl); the caption now says the key changed and which counts moved.  Full-projection cost
(full3_cost.txt): ~100 us/state versus 2-6 us for flags, ~0.5 min extra per Perl over 295,858 transitions -- full3 runs
under the full projection from now on.  ver-div is computed from the per-lane transition tables
(TAG=suite_<lane>_<ver>); the 12-row 5.38/5.44 core4 difference from pass 9 is superseded by this key change and must be
re-derived from the new tables.  "0 but true" rows: closed (they were in the collision family).

## Pass 11

Transcribed: Perl_sv_setsv_flags's `sflags & SVp_POK` arm (sv.c) -- swipe / copy-on-write / plain copy -- with the
CoWable predicate (S_SvPV_shared_hkey_or_CoWable: plain source needs (sflags & CAN_COW_MASK)==CAN_COW_FLAGS, (len-cur) <
80, len < 2*cur, cur+1 < len; an IsCOW source shares when !len or the destination is fresh), and the harness copy op
derived from it (VF::Harness::CopyOp: two calls plus the scope exit).  The predicate reads SvLEN, so the model now
carries len with Perl_sv_grow's minlen rule (cur + cur/4 + 16, 8-byte roundup, 16 floor); the allocator usable-size step
is NOT transcribed and is the stated approximation.  S_sv_uncow (SvLEN 0, SvGROW cur+1) at inc/dec/utf8/append.
Stringification's share is modeled as the setsv COW arm on observation (mechanism not cited).  gen3 lanes: ONE eval per
block (rule 1); a croak is the block's terminal record.  core4 open rows barely moved (2,002 -> 2,018 on 5.44.0; 1,605
on 5.38.2): residue_lists.txt partitions them -- 1,613 cow-only with Perl IsCOW and model not, 321 cow-only the other
way, 84 other -- so the len approximation, not the arm structure, is the remaining cause.  Not done this pass: ver-div
triples re-derived with recipes and source; the record rule (a ver-div triple never counted as open on 5.38.2) is not
yet applied by the driver; full3 and walk under this generation were still running at packaging and are in the table
only if their reports completed.  Every pre-pass-10 zero in this README and in the section is a zero under the old key;
the coverage caption says so.

## Pass 12 -- LEN transcribed and put in the key

Profile condition: usemymalloc='n', d_malloc_good_size='undef', d_malloc_size='undef' (both Perls), so
PERL_UNWARANTED_CHUMMINESS_WITH_MALLOC is undefined and SvLEN is the length sv_grow computes.  Transcribed (VF.pm,
cited): Perl_sv_grow (newlen++, minlen = cur + cur/4 + 16, PERL_STRLEN_ROUNDUP quantum 8 on an existing buffer,
expected_size on a first allocation), SvGROW's SvLEN < n gate, expected_size (perl.h), S_sv_uncow (SvLEN 0 then SvGROW
cur+1), sv_2pv_flags sizes (IV len+1; NV 0.0 -> 2; Inf/NaN -> 5; other NV -> 25 = 1+1+NV_DIG+1+1+5+1), pp_multiconcat's
grow (1 + targ_len + appended, sv_grow only if SvLEN < grow), sv_utf8_upgrade_flags_grow's need (SvCUR + expansion +
extra + 1), the literal via SvPV_shrink_to_cur (sv.h: expected_size(SvCUR+2); toke.c not in the source tree here, cited
from the macro), sv_setpvn (len+1).  Not transcribed: sprintf target sizing, pp_repeat, chr (their lanes are the 58-op
set).  LEN is in the key (|L:n on POK holders, both sides), so a wrong size is named at its site: residue_by_site.txt
partitions core4/walk open rows into len-only (by op), cow(+len), other; len_probe_depth3.txt is the 6-start family
probe (815 len-only of 1,708).  The remaining len-only rows show the model one 8-byte quantum low after an un-COW of a
literal-shared buffer (e.g. Perl 32, model 24 for a 2-byte string) -- S_sv_uncow's allocation sequence for a buffer the
SV does not own is the next thing to pin.  The two-way cow-only split has collapsed into len-only rows, as predicted.
full3 and the other deferred items (ver-div verdict rule, ver-div groups with source) were not reached; stale zeros are
covered by the caption and the section.

## Pass 13 -- the un-COW allocation pinned; residue by site

S_sv_uncow (sv.c), exactly: IsCOW off; if CowREFCNT != 0 decrement and copy_over, else the SV is the sole owner and
keeps the buffer with its LEN; copy_over sets SvPVX NULL, SvCUR 0, SvLEN 0, then SvGROW(cur+1): inside Perl_sv_grow
newlen = cur+2, minlen from the now-zero SvCUR = 16, first-allocation arm -> expected_size (round up to 8 above 16): 16
for a 2-byte string, 40 for a 36-byte one.  The model now carries cow_refcnt (literal share 1; each sv_setsv share +1;
CopyOp leaves it where it began).  The literal's own buffer is newSVpvn -> sv_grow_fresh (newlen+1, floor 16, NO
roundup: 38 for a 36-byte literal -- this is why the earlier expected_size guess was wrong); a fresh plain-copy
destination also takes sv_grow_fresh.  sv_2pv_flags sizing applies only to non-POKp holders (SvPOKp returns the PV as
is).  Family probe (6 starts, 7 ops, depth 3): 815 -> 41 open.  core4 under this generation: 50,392 / 677 open on 5.44.0
and 50,130 / 4,811 on 5.38.2 (the difference is the version-divergent COW/LEN behavior of 5.38, not yet subtracted from
open); walk 757 / 934.  residue_by_site.txt partitions them.  Locale lane: its copy op had still called sv_setsv_flags
with one argument and its model key lacked LEN; fixed, rerun: 1152/0 on both Perls under the complete key.  Not reached:
sprintf/pp_repeat/pp_chr sizing, the 88 "other" rows, the stringification-share citation (pp_stringify), full3 under
this generation, the ver-div verdict rule and groups.

## Pass 14 -- the stringification "share" was the observer; 5.44 core to 20; the verdict rule; 5.38's sizing

pp_stringify (pp_hot.c:266) is sv_copypv(TARG, sv) -> sv_setpvn: a plain copy, it shares nothing.  The holder's IsCOW
after `my $t = "$x"` came from the harness: the per-step observation copy (`our $c = $x`) is sv_setsv_flags, whose COW
arm left IsCOW on the holder for the NEXT op.  The per-step observation is now key + Dump only; consumers run once,
destructively, at the block's end on the original (the pass-6 copy check is what licenses this).  StringifyOp removed.
Also from source: sv_utf8_upgrade_flags_grow returns before any un-COW when SvUTF8 is already set.  Family probe (6
starts, 7 ops, depth 3): 815 -> 0.  core4 on 5.44.0: 50,613 transitions / 20 open (from 677); walk 626 (its 58-op set
has the unsized sites: sprintf/pp_repeat/pp_chr and the rest -- residue_by_site.txt lists them by op).  5.38.2 sizing,
from the fetched v5.38.2 sources (raw.githubusercontent.com, Perl/perl5 v5.38.2): Perl_sv_grow has the same newlen++ and
minlen = cur + cur/4 + 16 (PERL_STRLEN_NEW_MIN 16, EXPAND_SHIFT 2 -- both already present in 5.38.2) but does NOT round
a first allocation (comment: "Don't round up on the first allocation"); expected_size (perl.h) is new in 5.44, so first
allocations above 16 differ (NV stringification 26 vs 32, a 36-byte un-COW 38 vs 40).  SvPV_shrink_to_cur in 5.38.2
renews to SvCUR+1 (5.44: expected_size (SvCUR+2)).  S_sv_uncow and pp_multiconcat's grow are the same in both.  The
model follows 5.44; the 5.38 first-allocation rule is the version-divergent group behind the 5.38.2 len-only rows.
Driver: the verdict rule is implemented (open on 5.38.2 = mismatch rows minus version-divergent triples); the
groups-with-source list beyond this paragraph, sprintf/repeat/ chr sizing, and the 20 remaining 5.44.0 core rows are not
done.  full3 under this generation: in the table only if present.

## Pass 15 -- core4 on 5.44.0 at zero

The twenty: after `copy`, `my $y` lives to the block's end (one eval per block), so its share stays counted -- CowREFCNT
is one more than before the op, never 0 -- and the next un-COW takes copy_over: SvCUR 0, SvLEN 0, SvGROW(cur+1) ->
sv_grow newlen = cur+2 with minlen 16 from the zeroed SvCUR, first-allocation expected_size -> 24 for a 21-byte string.
The model's CopyOp had returned cow_refcnt to its old value (sole owner -> buffer kept -> 32).  core4 on 5.44.0: 50,613
/ 0 open.  Walk: `$x = "10"` is sv_setsv_flags(holder, literal): an IsCOW source shares only when SvLEN(dsv) < cur+1 (or
cur >= 1250), so a holder owning any buffer takes the plain copy and keeps its LEN; one without a buffer shares
(VF::Harness::assign_string); a holder already sharing an equal literal stays IsCOW (observed; same-buffer line not yet
cited).  sv_pvn_force_flags on undef -> the 16-byte first allocation.  Not sized this pass, listed by op with rows in
residue_by_site.txt: smat (pp_subst), subw (sv_insert_flags), vec (do_vecset), spg/sprintf (sv_vcatpvfn_flags), xl
(pp_repeat), chr (pp_chr), sortn, hkey.  5.38.2: open after the verdict rule is in the table; its one version-divergent
rule (no first-allocation rounding before expected_size; SvPV_shrink_to_cur at SvCUR+1) is the group, not yet listed
with recipes.  full3: still running; not in table.  Harness rule 5: the observer never copies the holder between ops --
any sv_setsv from it is a COW share the next op sees; observe with B/Devel::Peek per step and run consumers once, at the
end, on the original.

## Pass 16 (2026-09-26)

Path-based version divergence: verdiv_paths.pl replays every 5.38.2 open row's path from its START key through both
Perls' transition tables (gen3 now writes starts.<TAG>.txt) and marks the path divergent from the first step whose
observations differ; it prints the agreeing-open count (true model gaps on 5.38.2) and the divergent paths grouped by
first differing op with an example.  It needs tables and start files from the SAME run; those are produced by chain8
(core4 + walk reruns queued behind full3) -- if verdiv_paths.<lane>.txt reports no_start_key or is empty, chain8 had not
finished at packaging.  Lane children are now named child2_<TAG>_<start>.pl (a probe can no longer collide with a
running lane).  Sites from source: sv_insert_flags (sv.c:7075/7083), do_vecset (doop.c SvGROW(offset+len+1)), pp_subst's
copy path (dstr = newSVpvn_flags(orig, s-orig) sized by sv_grow_fresh, sv_catpvn appends, TARG takes dstr's buffer/LEN),
sort's copies (pp_aassign -> sv_setsv_flags COW arm; @s lives to block end).  Family probe (5 starts, 8 ops, depth 2):
161 -> 129 open; remaining shapes: assignment onto a holder whose stale buffer from a zero-NV stringification is absent
in Perl (the sv_2pv zero path; not yet cited), and cascades from it.  Not cited: the same-buffer early return in
sv_setsv_flags; sprintf's target, pp_repeat, pp_chr, hkey (they read the holder only in these ops).  full3 (chain7) and
the core4/walk reruns (chain8) were still running at packaging unless their reports are present in reports/suite.

## Pass 17 (2026-09-26)

Key completed once more: a stale buffer's LEN now enters the key for NON-POK holders too (|B:n), because a numeric or
undef holder with a stale buffer and one without were sharing a key and the replayed recipe reached the wrong one --
that, not the sv_2pv zero path, was the "zero-NV family" (sv_2pv_flags does give 0.0 a buffer: SvGROW_mutable(sv, 2) ->
16 via minlen).  Destination-side rules from sv.c, transcribed: sv_setsv_flags runs SV_CHECK_THINKFIRST_COW_DROP(dsv)
before the source arms (a sharing destination drops its buffer, SvLEN 0, so the incoming string is shared -- this is
also the equal-literal case); sv_setiv/sv_setnv/sv_set_undef drop a COW buffer and keep a private one (the stale buffer
of the B rows); sv_pvn_force_flags un-COWs by copy_over before writing (a forced literal share ends at
expected_size(cur+2)); pp_subst's copy path sizes by sv_catpvn's SvGROW(cur + n + 1) with SvCUR still the old length.
Family probe (5 starts, 9 ops, depth 2): 369 -> 43 open, the remainder under smat (pp_subst) and its cascades.  The
queue (full3 both Perls, then core4/walk with starts files for verdiv_paths.pl) was restarted at the end of this pass
with the final model and had NOT produced reports at packaging: the coverage table in this bundle is the previous
generation's and the 5.38.2 column is still the triple-based verdict.

## Pass 18 (2026-09-26) -- reporting

Queue: the full3 launches of passes 15-17 all exited early (empty reports) -- the launch collided with the kill loops in
the same turn; chain10.sh runs a `perl -c VF.pm` check before any lane (compile-check rule) and logs each lane's rc.
Reordered: core4 + walk first (they feed the path-based column), full3 after; full3 was still running at packaging (~35
min per Perl under the full projection: 24 starts x 58 ops x depth 3 with Dump per state).  core4 under the completed
key (|B:n): 5.44.0 55,343 / 0.  5.38.2: 6,287 mismatch rows, ALL on version-divergent paths, 0 agreeing-open
(verdiv_paths.core4.txt): every group's first differing step is a first allocation one quantum apart (L:23 vs L:24 for a
21-byte un-COW), i.e. the 5.38 rule "no rounding on the first allocation before expected_size (5.44)".  Walk: 5.44.0 360
-> 46 after one model fix the residue forced: pp_undef (pp.c, scalar default arm) FREES the buffer (SvPV_free, SvPV_set
NULL, SvLEN_set 0 after sv_force_normal_flags(SV_COW_DROP_PV)), unlike `$x = undef`; 107 rows.  The 46: 29 cow(+len)
(xr, sorts, asgs, ...) and 17 len-only (smat, subw, vec) -- walk_residue_by_site.txt.  5.38.2 walk: 722 rows, 715 on
version-divergent paths (groups: cat0/subw/chop/utf8/cmps on iMax, same rule, L:21 vs 24 and 38 vs 40), 5 agreeing-open.
Citations collected (not modeled where the holder is only read): sv_vcatpvfn_flags -- need = SvCUR + segment + 1 (+1 per
non-invariant byte), SvGROW(sv, need) per literal segment (sv.c, the fmtstart loop); pp_chr -- SvGROW(TARG,
UVCHR_SKIP(value)+1) for code points above 255, else SvGROW(TARG, 2) (pp.c); pp_repeat -- sv_setsv_nomg(TARG, tmpstr)
then SvGROW(TARG, max) (pp.c, PP_wrapped(pp_repeat) +114/+128); hkey -- hv_common stores the key through
share_hek_flags(key, klen, hash, flags & ~HVhek_FREEKEY) (hv.c:876): the HEK is shared in PL_strtab and the key SV
itself is only read.

## Pass 19 (2026-09-28)

Driver computes match = transitions - open - ver-div and the 5.38.2 columns itself (verdiv_paths.pl; no hand edits).
Walk sites from source: pp_repeat copies the holder into TARG (sv_setsv_nomg -> COW arm, holder IsCOW) and un-COWs TARG
at SvGROW(TARG, max) (CowREFCNT back); a numeric holder is copied as a number and untouched.  `sort ($x, 1)`: copies
through pp_aassign as for the numeric sort.  pp_subst: an in-place rule was tried and contradicted (a POK "10" in a
32-byte buffer takes the copy path -> 16; a numeric target with a 32-byte stale buffer keeps 32); withdrawn, rows
listed.  Walk-site family probe (iMax, s0but, f3; 8 ops; depth 2): 25 -> 11 open (walk_sites_probe_pass19.txt),
remaining under smat and its cascades.  The walk lane itself was not rerun this pass; its rows in the table are from
pass 18 (360 -> 46 then).  full3: every background run has died at a turn boundary (this environment does not keep
processes alive between turns), and under the completed key the depth-3 58-op lane is far larger than its flags-only
predecessor (11,988 states): after 9 minutes only the 6th of 24 starts was in progress under BOTH projections, so a run
needs well over an hour per Perl and cannot complete within a pass.  It is out of the table by that reason; the options
are a depth-2 lane under the completed key (fits in a pass) or a runner outside this environment.  Section text added:
the key sentence, `undef $x` versus `$x = undef` with lines, the LEN-determinism condition, and the verification
pointer.

## Pass 20 (2026-09-28) -- the key audited against sv.h; the harness made relocatable

Key (VF::Observe::key, mirrored by VF::Harness::KeyTail): value flags | slot | P:bytes|L:len or B:cur/len | T:SvTYPE |
C:CowREFCNT | O:OOK offset.  Added this pass: SvTYPE (the low byte of sv_flags; sv_upgrade's ladder and its trigger
sites are transcribed as sticky slot-use bits in VF::body_type), OOK + offset (new op chopl = substr($x,0,1,""); sv_chop
/ sv_backoff transcribed; sv_grow, S_sv_uncow copy_over, pp_undef, the setters and sv_inc/sv_dec normalize first),
CowREFCNT (model cow_refcnt; SV_COW_REFCNT_MAX saturation is a rule, not enumerated), stale CUR/LEN on non-POK holders.
KEY EXCLUSIONS (each with its reason): sv_refcnt -- enters only through S_SvPV_can_swipe_buf (SvREFCNT(ssv)==1 &&
SvTEMP), which reads the SOURCE of a copy; a named holder is never TEMP (only sv_2mortal sets it): an op-definition
input.  SVs_TEMP/PADTMP/PADSTALE, SVs_OBJECT, GMG/SMG/RMG, AMAGIC, FAKE, BREAK, magic, stash -- never on a fresh package
holder by lane design (no blessing, magic, globs, global destruction): ASSERTED -- VF::Observe::peek dies if Dump ever
shows one or a MAGIC line.  xpvlv fields -- LVs are the TARGs of substr/vec/pos, never the holder.  Buffer bytes past
CUR -- every writer NUL-terminates at CUR and readers clamp (do_vecget returns 0 past srclen).  sv_u pointer identity --
implicit in single- holder lanes; a multi-holder lane must key buffer identity because of sv_setsv_flags's SvPVX(dsv) ==
SvPVX(ssv) early return.  OP-DEFINITION INPUTS (a class, not key fields): the op tree's constants (partner-typed
arithmetic: pp_add_partner_gate) and an op's TARG, which keeps its buffer across executions (pp_repeat's SvGROW(TARG,
max) sizes differently the second time -- the likely xr residue); each copy-producing op declares its source's flags and
refcount.  Verdicts: body-only (Perl and model differ only in T:) is reported beside open.  Depth-2 under the audited
key, 5.44.0, 13-op core + chopl family probe: 2,379 transitions, 2 body-only, 84 other (key_audit_probe.txt); core2 lane
(13-op core, 24 starts, depth 2, full projection): 11,914 transitions / 167 open, ALL body-only -- SvTYPE never decided
a value flag, LEN or COW difference at depth 2, and those 167 are the type model's own rows (sv_upgrade sites still to
read exactly).  The remaining depth-2 lanes (core2 5.38.2, full2, walk2 both Perls) were still running at packaging and
are not in the table; they run with `vf_suite.pl` (suite) and `vf_suite.pl lane` on the hardware that keeps processes
alive.  Harness (harness/): VF_ROOT and PERLS from the environment (no /tmp/gen), startup checks for the allocator
profile and the locale, TAG-named children, per-start runs merged by merge_starts.pl (tables and start files are keyed
by start) targets suite / lane (xargs -P JOBS across the 24 starts) / verdiv, dependencies.md, core modules only.

## Pass 21 (2026-09-28) -- delivered as models/VF

Startup path rewritten: each check prints what it checked and found and exits nonzero (allocator profile per Perl,
locale); success prints the verified profile.  Lane depths from DEPTH / DEPTH_CORE / DEPTH_FULL / DEPTH_WALK; lane names
carry the depth; a zero or empty report is never cached.  Depth-1 suite on both Perls under the audited key:
reports/coverage.txt (core1 2,715 / 41 open both Perls; full1 25,719 / 835 (5.44.0) and 503 (5.38.2); walk1 1,250 / 11
and 4; locale 504 / 30; copy 3,096 / 3,081 with 0 consumer differences; matrix 2,304 / 44).  SvTYPE is now a field set
at sv_upgrade's trigger sites (VF::upgrade; sites and lines in VF.pm) and nowhere else; the slot-use bits are gone.  NOT
closed: core2 on 5.44.0 shows 2,030 body-only rows (11,914 transitions) -- e.g. a PVIV holder read with sprintf "%.17g"
(sv_2nv_flags: SvTYPE < SVt_PVNV -> PVNV) stays PVIV in the model although the wrapper requests that climb; the first
thing to read is the binding of the `nv`/`iv`/`dec` ops in generators/gen3_vf.pl to the wrapped VF routines and the
order of the wrappers at the end of VF.pm.  Layout: VF.pm and VF/Observe.pm (models), generators/, vf_suite.pl,
merge_starts.pl, verdiv_paths.pl, dependencies.md, reports/ (coverage.txt and the lane reports behind it), section.md.
The Harness routines live in VF.pm under package VF::Harness (a separate VF/Harness.pm split is straightforward and not
yet done).
