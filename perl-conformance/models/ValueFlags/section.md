# Value flags on scalar values

A Perl scalar carries, besides its value, a record of which conversions have been performed on it. That record — the
private and public `IOK`/`NOK`/`POK` flags plus `SVf_IVisUV` in `SvFLAGS`, together with the copy-on-write state and
buffer length that decide later transitions — determines the outcome of later operations and is visible to programs
through several core consumers. This section defines that state as the model records it (the *value-flag record*), the
three situations in which a cached number can disagree with its string, the transition function every operation applies,
and what is and is not observable. The reference implementation is `VF.pm`; every rule below names the Perl 5.44.0
function it transcribes, and the transition tables were generated from both Perl 5.38.2 and 5.44.0.

## 1. State space

A scalar value is one of five kinds — `Str`, `Int`, `Float`, `Ref`, `Undef` — and carries these value-flag record
fields:

| field         | values                  | meaning (Perl flag)                                                         |
|---------------|-------------------------|-----------------------------------------------------------------------------|
| `I`           | none / private / public | integer slot filled (`SVp_IOK` / `SVf_IOK`)                                 |
| `N`           | none / private / public | float slot filled (`SVp_NOK` / `SVf_NOK`)                                   |
| `is_uv`       | bit                     | the integer slot holds a UV (`SVf_IVisUV`)                                  |
| `stringified` | bit                     | a non-string has a cached string form (`SVp_POK` without `SVf_POK`)         |
| `private`     | bit                     | a number whose own slot is private-only (see §3)                            |
| `UTF8`        | bit                     | `SVf_UTF8`                                                                  |
| `COW`         | bit                     | the string buffer is shared copy-on-write (`SvIsCOW`, hence `SvTHINKFIRST`) |

The kind fixes which form is authoritative: `Int`/`Float` own the number and any string form is derived; `Str` owns the
bytes and any number is derived. The model does not store a derived number: it records *which derivation has happened*
and recomputes the number by replaying it. This is exact because every derivation in `sv.c` is a pure function of the
bytes, the `UTF8` flag, the value flags, and the locale radix in effect — with the three exceptions in §3, the only
cases in which Perl's cached number can disagree with its string, which the model records as a `Dual` state holding the
number.

The content class of a `Str` is part of the state for transition purposes: integer (`"10"`), unsigned-only integer
(`"18446744073709551615"`), decimal (`"1.5"`), exponent (`"1e19"`), greater-than-UV (`"18446744073709551616"`), inf/nan
(`"Inf"`, `"NaN"`), inf/nan with trailing text (`"Infx"`), empty, and garbage with or without a numeric prefix (`"12x"`,
`"abc"`). These are the classes `grok_number_flags` (numeric.c) distinguishes: `IS_NUMBER_IN_UV`, `IS_NUMBER_NOT_INT`,
`IS_NUMBER_INFINITY`, `IS_NUMBER_NAN`, `IS_NUMBER_NEG`, `IS_NUMBER_GREATER_THAN_UV_MAX`, and 0. An exponent clears
`IS_NUMBER_IN_UV`; a decimal point keeps it with the integer part as the value; trailing text after an inf/nan yields 0.

Reachable `Str` value-flag record states with a fixed content: `P` (none), `IP`, `IPU`, `NP`, `nP`, `iNP`, `iNPU`,
`inP`, `inPU`, `INP`, `INPU` (upper case public, lower case private, `U` = IsUV). Numbers add `stringified` (integers
only: the `NV` string form is never cached, `sv_2pv_flags` under `USE_LOCALE_NUMERIC`) and `private`.

## 3. Value-observable caches and the `Dual` rule

A cached number disagrees with its string in exactly three situations. The model records each as a `Dual` state — a
string form and a number form with the value flags recording their publicity — because the number cannot be recomputed
from the string. `created_as_string` and `created_as_number` read the `Dual` as Perl reads the corresponding flag set.

1. **A `__WARN__` handler that mutates the scalar mid-conversion.** On the integer path, `S_sv_2iuv_common` (sv.c) calls
   `S_sv_setnv` — writing the NV slot from `Atof` of the *pre-callback* string — before `not_a_number`, and its x86-64
   tail then rereads `SvNVX(sv)`. The effective number is therefore the NV slot as the handler left it: if the handler
   installed an `N` value-flag record on a string it left in place, or made the scalar a `Float` (`sv_setnv` writes the
   slot), that value stands; if it installed only an `I` value-flag record, or made the scalar an `Int` (`sv_setiv`
   leaves the slot), a `Ref`, or `undef`, the pre-callback number stands. Value flags become private (`SvFLAGS &=
   ~(SVf_IOK|SVf_NOK)` for `numtype == 0`) regardless of what the handler installed, and are written onto the scalar
   whatever kind it now has: an `Int` has its value overwritten with `I_V` of the effective NV and becomes `private`; a
   `Ref` keeps its address for every later conversion (`SvROK` dispatches before the value flags in `sv_2iv_flags`,
   `sv_2nv_flags`, `sv_2pv_flags`) while the outer conversion still returns the number. On the float path `sv_2nv_flags`
   warns first and then reads `Atof` of the *current* PV, so no `Dual` is needed; if the handler made the scalar a
   non-string, Perl reads a dropped COW buffer (a crash or `Atof(NULL)`): a window with no defined behavior, recorded in
   `undefined.md` (W1, W2). The uninitialized-value path returns 0 regardless of the callback (`S_sv_2iuv_common`, undef
   branch; `sv_2nv_flags`, undef branch).
2. **A non-C `LC_NUMERIC` radix in a `use locale` scope.** `grok_number_flags` and `my_atof3` accept
   `PL_numeric_radix_sv` as a decimal point in addition to `.` while `IN_LC(LC_NUMERIC)`; nothing else in the conversion
   chain consults the locale, and `sv_2pv_flags` never caches a float's string form. The parse result is cached in the
   slot, so the cache freezes whichever radix parsed first, copies carry it across scope boundaries, and nothing ever
   reparses a cached value; the `Dual` records the number, not the radix. Under de_DE, `"3,5"` and `"3.5"` both parse as
   3.5; `"3,5x"` parses as 3.5 with private value flags (garbage with a numeric prefix); `"1e3,5"` parses as 1000 (the
   radix is not accepted after an exponent).
3. **Negative zero reached integer-first.** `"-0"` converted on the integer path stores IV 0; a later float conversion
   derives NV 0.0 from the IV (`sv_2nv_flags`, `SvIOKp` branch) and `%g` prints `0` forever; converted float-first it
   stores −0.0 and prints `-0` forever. Both end in `INP`; the order is recorded as a `Dual` state in the integer-first
   case.

The `private` state is a fourth consequence of case 1: a number whose only value flags are private stringifies as
uninitialized (`sv_2pv_flags` dispatches on `SvPOKp`, then public `SvIOK`, then public `SvNOK`, else `report_uninit`),
while `defined` is true (`SvOK` includes the private flags) and numeric use returns the number.

## 4. The transition function

Every operation is a composition of the named Perl functions, and the flag-projection lane checks the model against Perl
on each. Where a rule has several forms in Perl, each form is listed with its function.

**Integer conversion — `sv_2iv_flags` / `sv_2uv_flags` → `S_sv_2iuv_common`.** `SvROK` returns the address before any
value-flag record. With a public or private `I` value-flag record the slot is returned. With an `N` value-flag record,
the IV is derived by the `got_nv` label: `IOKp` on; if `NV < IV_MAX + 0.5` then `I_V(NV)`, public `IOK` only if it
round-trips, lies within ±(2⁵³−1) and `NOK` is public; else `U_V(NV)` with `is_uv`, public `IOK` only if it round-trips,
is below 2⁵³ and `NOK` is public — NaN takes this UV arm (`U_V(NaN)` is 0), so does +Inf (`UV_MAX`). For a string,
`grok_number` classifies: a clean integer sets public `IOK` (a one-character digit string short-circuits the same way);
inf/nan calls `S_sv_setnv` (`SvNOK_only`, which clears `IOK`, `is_uv`, `UTF8` and re-sets `POK`) and then `got_nv`; any
`IS_NUMBER_IN_UV` value fills the IV slot with `IOKp` (a negative beyond `IV_MIN` instead sets public `NOK`, private
`IOK`, NV = −value, IV = `IV_MIN`); anything not a clean integer then runs `S_sv_setnv` (the NV slot from `Atof`), warns
if `numtype == 0`, and fills the integer slot: `IN_UV|NOT_INT` sets public `NOK` only; otherwise if `2⁵³ > U_V(|NV|)`
the small-enough arm sets `IOKp`, public `NOK`, `I_V(NV)`, and public `IOK` if it round-trips (no 2⁵³ test here);
otherwise `S_sv_2iuv_non_preserve`: below `IV_MIN` → `IV_MIN`; above `UV_MAX` → `UV_MAX` with `is_uv`; else `I_V` or
`U_V` with public `IOK` if it round-trips, never for `UV_MAX`. For `numtype == 0` the public `IOK`/`NOK` bits are then
cleared. These are the three different rules for "public `IOK` from an NV": `got_nv` (round-trip, range and public
`NOK`), the small-enough arm (round-trip only), and `non_preserve` (round-trip, excluding `UV_MAX`).

**Float conversion — `sv_2nv_flags`.** `SvROK` first. `NOKp` returns the slot.  `IOKp` derives NV from the IV; public
`NOK` only if `IOK` is public and the value round-trips (UV-aware, excluding `UV_MAX`). For a string: `grok_number`;
warn if `numtype == 0`; NV = `Atof` of the *current* PV; public `NOK` if `2⁵³ > U_V(|NV|)` or the class is not `IN_UV`;
otherwise, for an `IN_UV` string that is not too-negative, both slots become private, the IV slot is filled from the
grok value, and for a non-`NOT_INT` value public `IOK` is set (with public `NOK` only when the IV round-trips, or for
the UV arm when the grok value equals `U_V(NV)` and is not `UV_MAX`). `numtype == 0` clears the public bits.

**Stringification — `sv_2pv_flags`.** `SvPOKp` returns the PV. Public `IOK` (5.38: or `IOKp` without `NOKp`) formats the
integer and sets `stringified`. Public `NOK` formats `%.15g` and caches nothing (the `USE_LOCALE_NUMERIC` branch),
except that the infnan branches call `SvPOKp_on`. Otherwise `SvROK`, else `report_uninit` and `""`.

**Increment — `sv_inc_nomg`.** `SvTHINKFIRST` first drops COW. `NOKp` without `IOKp` converts via `SvIV` first. Public
`IOK`, or `IOKp` without `NOKp`, increments the integer: `UV_MAX` → `Float` 2⁶⁴, `IV_MAX` → UV, else `SvIOK_only`
(clears `NOK`, `stringified`, `UTF8`, `is_uv`). `NOKp` → `SvNOK_only`, NV + 1. Not `POKp`, or an empty string → `Int` 1.
A string matching `/^[a-zA-Z]*[0-9]*\z/` carries as a string (`"9"` → `"10"`, `"Az"` → `"Ba"`, all `POK`). Otherwise
`grok_number` with `PERL_SCAN_TRAILING`: a non-infinite number converts with `SvIV_nomg`, jumps to the integer path if
that produced public `IOK` (`"-0"` → `Int` 1), or adds 1.0 to the NV if the *pre-conversion* flags had `NOKp`; else
`sv_setnv(Atof + 1)` (`"12x"` → `Float` 13, no warning).

**Decrement — `sv_dec_nomg`.** As above without the `NOKp`-to-`IV` pre-step (`3.0--` stays `Float` 2.0 while `3.0++`
becomes `Int` 4) and without the empty-string test (`""--` → `Float` −1.0), and without string carry; the `grok_number`
call has no `PERL_SCAN_TRAILING`.

**Addition and comparison — `pp_add`, `pp_eq`, `do_ncmp`.** `SvIV_please_nomg` (sv.h): convert with `sv_2iv_flags` when
the operand has no `I` flag and has public `NOK` or `POK`; then integer arithmetic if `IOK` is public, else `SvNV_nomg`.
With a partner that itself fails `SvIV_please` (`== 1.5`), only the NV path runs on the operand. `sort { $a <=> $b }`
(`pp_sort`) first calls `sv_2nv_flags` on every element that is not `SvNSIOK` — public `NOK`, or public `IOK` without
`is_uv` — and then `do_ncmp`.

**Bitwise — `pp_bit_or`, `pp_complement`.** Without `feature 'bitwise'`, numeric if either operand is `SvNIOKp`, in
which case `SvUV_nomg` converts and a READONLY operand has the value flags removed again (`SvNIOK_off`); otherwise
string, converting with `SvPV_nomg_const` (`stringified` on a number). With the feature, `|`/`~` always convert
numerically and `|.`/`~.` always stringify.

**Range — `pp_flop`.** `RANGE_IS_NUMERIC` (pp_ctl.c): numeric if either operand is `SvNIOKp`, or defined and not
`SvPOKp`, or looks like a number and does not start with `0` followed by more characters. Numeric operands get
`SvNV_nomg` only when not already public `IOK`, then `SvIV_nomg`; string operands `SvPV_nomg`.

**`int`, `abs`, `sprintf "%d"`, `pack "j"`, `chr`, `unary -`.** `pp_int` and `pp_abs`: `SvIV_nomg`, then `SvNV_nomg`
unless public `IOK`. `%d` (`sv_vcatpvfn_flags`) and `pack "j"` (`S_sv_check_infnan`) and `pp_chr` test `Perl_isinfnansv`
(numeric.c): `NOKp` → `isinfnan(NVX)`; `IOKp` → false; else `grok_infnan` on the PV *without converting* — but the croak
message and the `%d` formatting then read `SvNV`, which is what leaves `NOK` on `"Inf"` and private `NOK` on `"Infx"`.
`pp_chr` then reads `SvNV_nomg` for any defined non-UV operand before `SvUV_nomg`. `pp_negate`: `S_negate_string`
handles a string with no public numeric value-flag record that starts with a letter, `+`, or a non-numeric `-` (no
conversion beyond `SvPV`); public `IOK` negates the integer unless it is a UV above `ABS_IV_MIN`, which drops through to
`-SvNV_nomg`; `SvNIOKp` with public value flags or no `POK` uses `SvNV_nomg`; a `POKp` string converts with
`SvIV_please_nomg` and re-enters the integer arm.

**`pack "w"`.** `SvNV_nomg` first, croak if negative, then `SvUV_nomg` when `IOK` is public or the NV fits a UV.

**`pp_repeat`.** The count uses `IOKp`/`NOKp` slots directly, else `SvIV_nomg`; the repeated string is stringified on a
*copy* in TARG, so `$s x 2` leaves no value-flag record on `$s`.

**Reads that only stringify** — `eq`, `cmp`, default `sort`, hash key, `length` (not on `undef`), `substr` read, `tr///`
count, `s///` with no match, `.` in either position, `%s`, `chomp` with nothing to remove: `SvPV`-family, hence
`stringified` on a number and nothing on a string.

**Reads that value-flag record nothing** — boolean context and `!` (`SvTRUE_common` reads flags), `local`/restore, copy
(`sv_setsv_flags` copies the flag set and shares a `POK` buffer copy-on-write).

**Content writes.** `substr` 4-arg (`sv_insert_flags`) and lvalue `vec` (`do_vecset`) force with `SvPV_force_flags` and
then `SvPOK_only(_UTF8)`: all value flags cleared, `vec` also downgrading `UTF8`. `s///` with a match ends with
`SvPOK_only_UTF8` (pp_hot.c). `chop` reads with `SvPV`, then on a non-empty string forces and clears with `SvNIOK_off`.
`utf8::upgrade` (`sv_utf8_upgrade_flags_grow`) returns at once for `undef`, skips the force for `SvPOK_nog` (value flags
kept, `UTF8` set), and otherwise goes through `sv_pvn_force_flags`, which ends with `SvPOK_only_UTF8`: a number becomes
a plain string. Assignment from a literal (`sv_setsv_flags`) installs the literal's kind with a COW-shared buffer for
strings; `undef $x` clears everything (`SvOK_off`).

**Append — the COW-dependent clear.** `$x .= ...` is `pp_multiconcat`'s append path: `SvPV_force_nomg_nolen(targ)`, and
`Perl_SvPV_helper` (sv_inline.h) skips the force only for `SvPOK_pure_nogthink` — public `POK` with no public
`IOK`/`NOK` and not `SvTHINKFIRST`. A string whose buffer is still COW-shared with its literal (or with a copy) is
THINKFIRST, so its *private* value flags are cleared by the force's `SvPOK_only_UTF8`; the same string after one append,
`utf8::upgrade` (`S_sv_uncow`), or `++`/`--` (`sv_force_normal_flags`) keeps them. Public value flags are cleared in
every case. The length of the appended string is irrelevant; `.= ""` behaves like `.= "x"`.

## 5. Constants

A compiled constant is a mutable flag cell: a literal reached through an alias or reference site (`f("10")`, `for
("10")`, `\"10"`) is one READONLY SV per op tree, so value flags left on it persist across executions of the same code,
and a constant sub's value is one SV shared by every site that inlines it. Compile-time folding over such a constant
(`ZZ + 0`) leaves value flags on it before runtime, which is why a range `$lo .. ZZ` can be numeric on its first
execution. Under ithreads, thread creation clones the parent's constants with their flags. The nine partner-typed
operators (§4) read a literal partner's public flags, so a literal's drift changes what its partner caches.

## 6. What is observable

Everything a program can observe through stdout depends on the value flags as follows: `isdual` (`SvPOK||SvPOKp` and
`SvNIOK||SvNIOKp`), Data::Dumper's XS `Dumper` (unquotes on public `IOK` with a matching PV), JSON::PP (`"" & $v` then
`0+$v eq $v`), `created_as_number` / `created_as_string` (public `NIOK` without `POK`; public `POK` and not bool),
Storable, `++`/`--` string-versus-numeric, bitwise string-versus- numeric, range string-versus-numeric, smartmatch, the
`private` uninitialized stringification, and the `-0` order dependence.

`B`-only: the private cache flags themselves, as seen through `B::svref_2object->FLAGS` or `Devel::Peek`, reach no
stdout consumer except through the cases above; of every flag a stringified integer or an integer-used float can
acquire, only `pPOK` on the integer (via `isdual`) and public `IOK` on an integral float (via `Dumper`) are
stdout-visible. Perl behaviors that read freed memory — the float-path `__WARN__` handler that changes the scalar's
kind, `` aliases to a shifted element, `values` aliases across `delete` — have no oracle and are recorded in
`undefined.md`.

## 7. Verification

`gen.pl` runs the handler-mutation matrix (18 inputs × 8 replacements × 4 then-actions × 4 outer ops);
`gen2.pl`/`gen3.pl` enumerate (start value, operation sequence) to depth 3 over 18 starts and 56 operations, recording
every observed (state, op) → state through `B::FLAGS` and a side-effect-free slot read, and replay each recipe through
`VF.pm`; `gen4.pl` adds the locale axis with de_DE and C radices in and out of `use locale` scope. Both Perls produce
byte-identical raw tables and `VF.pm` reproduces all of them.

## 9. What the fuller projection separates

The verification lanes above observe each state through `B::FLAGS` plus a value fingerprint. A projection built from
`Devel::Peek::Dump` on the original scalar (body type, `REFCNT`, `CUR`/`LEN`, `IsCOW` and `COW_REFCNT`, the magic
chain), with the exact IV/NV slot bits read through `B::IV`/`B::NV` and `pack`, splits classes that the flag projection
collapses.  Over the 24-start, 12-op core to depth 2 on 5.44.0 (2,339 states), 255 flag-projection classes split: 165 by
body type (`PVIV` versus `PVNV` under identical flags — an integer that was stringified and then incremented stays
`PVIV` while reading `IOK,pIOK` like a fresh `IV`; `utf8::upgrade(10)` lands in `PVNV`), 150 by `LEN` and 84 by `CUR` (a
`PVNV` reached through a numeric path has no buffer where the same flags reached through a string path keep one), and 4
by `COW_REFCNT` (a literal's buffer shared once versus twice, which is the `SvTHINKFIRST` input to the append rule).
Body type is monotone (`sv_upgrade`) and is what `sv_pvn_force_flags`, `sv_2iuv_common` and `sv_2nv_flags` upgrade to;
`COW_REFCNT` is the buffer's share count and is what the model's `cow` bit approximates. Neither is yet modeled in
`VF.pm` beyond the `cow` bit; the state tables carry both for every reachable state.

The split classes were then stepped forward by every operation with the full observation (24 starts, 12-op core to depth
2, 3,116 states, 58 step operations, 5.44.0): 4 of 307 split classes are consumer-visible — all of them an integral
NOK-only value whose members differ in body type (`NV` versus `PVNV`) and in a stale, unflagged PV buffer — and 303 are
`B`-only, including every `COW_REFCNT` split: a buffer shared once or twice is `SvTHINKFIRST` either way, so the `cow`
bit is the right granularity for the append rule.  The consumer column that separates the four is recorded in the
partition report and is not yet transcribed.

**Class (a) resolved.** Each of the four consumer-separated classes was re-probed in isolation on both interpreters
(`classA_pin.*`): every member pair — `NV` versus `PVNV`, with or without a stale unflagged buffer of any `CUR`/`LEN` —
produces identical stringification, `+0`, `%.17g`, `isdual`, `created_as_*`, Data::Dumper XS and PP, JSON::PP,
`Storable::freeze`, `pack "j"`, truth and warnings, now and after the numeric read. The one differing record inside the
enumeration was Data::Dumper XS quoting `'3'` for a state whose identical twin printed `3`; it is a consumer-chain
effect within the enumeration process, not a property of the scalar, and its process-level cause is not pinned. So the
rule is: no reader consults a stale `PV` when `SvPOKp` is off — `sv_2pv_flags` dispatches on `SvPOKp`, then public
`IOK`, then public `NOK`, and never on the buffer — and body type changes no consumer-visible transition at this depth.
Body type, `CUR`/`LEN` and `COW_REFCNT` are therefore all `B`/`Devel::Peek`-only under this profile and are recorded,
not modeled; `cow` stays a bit.

**The Dumper artifact, pinned (case i).** In the enumeration's consumer chain, `0 + $c` runs through one shared `+` op
whose literal `0` is the same constant SV on every call. When that op has once added a non-numeric string, its generic
path evaluated `SvNV_nomg` on the literal and left public `NOK` on it. From then on a copy that is public-`NOK` meets
`pp_add`'s fast path (pp_hot.c, `pp_add`: neither operand `SVf_IVisUV`/`SVs_GMG`, `flags = svl->sv_flags &
svr->sv_flags`, `SVf_IOK` → integer add, else `SVf_NOK` with `lossless_NV_to_IV` on both → integer add), which converts
nothing, so the copy reaches `Data::Dumper` without public `IOK` and `DD_is_integer` (Dumper.xs: `SvIOK` plus the PV
round-trip) quotes `'3'`; in isolation the literal is fresh, the generic path runs `SvIV_please_nomg`, and Dumper prints
`3`. The scalar's state was identical in both runs — class (a) is empty for the scalar — but the rule is a transcription
fact: whether `pp_add` caches `IOK` on an operand depends on the *partner's* public flags, so the `add` transition is
partner-typed (`0` IOK versus `0.0` NOK), and `VF.pm`'s `pp_add_with_partner` carries it.

**The copy, observed and cross-checked.** Every consumer reading in the verification lanes is taken through a copy, so
the copy itself was made a row: for each state of the 12-op core lane (bare ops, fresh holder, depth 2; 3,099 states on
5.44.0, 3,084 on 5.38.2) the original is dumped, then `our $c = $x` into a fresh holder, then the copy and the original
are dumped again, the consumer chain is run on the copy, and finally — destructively, last — on the original. Findings:
`sv_setsv_flags` carries every value flag unchanged — public and private `IOK`/`NOK`/`POK`, `IsUV`, `UTF8` — and the
only state differences between copy and source are `IsCOW` appearing on both when a `POK` source's buffer becomes shared
(`COW_REFCNT` rising on the source) and the copy's lack of a stale buffer when the source is numeric with an unflagged
`PV` (`CUR`/`LEN` absent on the copy, the buffer having been left behind by `SvPOK_off`); the copy's body type never
differs from what its flags require. The consumer chain run on the original agrees with the chain run on the copy on
every state on both interpreters (0 of 3,099; 0 of 3,084). The copy method therefore stands with evidence, and the
model's `sv_setsv_flags` — copy the value flags, set `cow` — is the whole carry rule under this profile; the
stale-buffer and body-type differences are `B`-only.

**Partner-typed operators.** The `pp_add` finding generalizes. `pp_add` (pp_hot.c), `pp_subtract` and `pp_multiply`
(pp.c) open with the same fast path — no `SVf_IVisUV`/`SVs_GMG` on either operand, then `flags = svl->sv_flags &
svr->sv_flags`: `SVf_IOK` → integer arithmetic, else `SVf_NOK` → `lossless_NV_to_IV` on both or NV arithmetic — and
`pp_eq` (pp_hot.c), `pp_ne`, `pp_lt`, `pp_gt`, `pp_le`, `pp_ge` (pp.c) have the same `flags_and` ternary ahead of
`do_ncmp`; on those paths neither operand is converted. `pp_divide`, `pp_modulo`, `pp_pow`, `pp_ncmp` and `do_ncmp` (so
`sort { $a <=> $b }`) always run `SvIV_please_nomg` on both operands; `pp_negate` has no partner. Enumerated with a
fresh op tree per cell — 15 operators × three partner states (literal fresh; string-touched, public `NOK` left by a
prior non-numeric operand; float-touched) × six operands — on both interpreters: exactly the nine flags-AND operators
are partner-typed, and identically so on 5.38.2 and 5.44.0. The visible effect is on an integral public-`NOK` operand:
against a fresh integer literal it gains public `IOK`; against a touched literal it gains nothing. `VF.pm` carries
`%PARTNER_TYPED` and `pp_add_partner_gate`.

**§Verification.** The definition of "verified" for this area is the coverage table produced by `vf_suite.pl`
(reports/suite/coverage.txt): per interpreter and lane — holder freshness, op set, depth, projection, transitions,
states — with the four verdicts `match`, `open`, `version-divergent`, `diverges-defined`. At this bundle: handler matrix
2,154 match / 150 diverges-defined (114 crash rows, 36 freed-buffer rows), locale 1,152, 12-op core depth 4 10,416,
58-op set depth 3 295,858, copy check 3,099 and 3,084 — all with 0 open and 0 version-divergent on both interpreters.
The random-walk lane is not yet part of the table.

**`"0 but true"`.** Recognized by `Perl_grok_number_flags` (numeric.c): the exact ten-byte string is tested with
`memEQs` before the general parse and returns `IS_NUMBER_IN_UV` with value 0, so it numifies to 0 with no warning and
installs public `IOK`. It is not a warning exemption in `not_a_number`; the exemption is that the parse never reaches
it. The model's branch had been placed after the trailing-garbage return and never fired; moved, the walk lane's 157 `"0
but true"` rows close.

**Key change and COW.** The projection key now carries `ROK`, `UTF8` and `IsCOW` and prints integer slots exactly.
`IsCOW` entered the key because a hidden COW bit made two states share one key and let a replayed recipe reach the wrong
one — the "empty-append family" was that collision, and the direct probe shows private numeric flags survive an append
on a non-COW buffer on both interpreters. With the bit visible, the model's `cow` tracking stands exposed as an
approximation: the open rows under the widened key are almost all cow-only, dominated by the copy op re-establishing
`IsCOW` on an un-COWed buffer, which is `sv_setsv_flags`'s COW branch (sv.c, the `CAN_COW_MASK` and `SvLEN > SvCUR + 1`
conditions) and is not yet transcribed. Counts under the widened key are in the coverage table; the earlier zeros were
zeros under a key that could not see this bit.

**State versus output.** `IsCOW` is in the key because COW is consumer-invisible at the state where it is observed but
decides a later transition (whether an append forces), so it is state even though it is not output: the key must capture
everything that decides a future observable, not everything observable now. **The copy rule** is `Perl_sv_setsv_flags`'s
string arm, transcribed in `VF.pm` with its three arms and the length predicate; the harness copy op is derived from it.
Every zero stated before the key carried `IsCOW` was a zero under a key that could not see it; the current counts are in
the coverage table.

**`LEN`.** On this build (`usemymalloc='n'`, `d_malloc_good_size` and `d_malloc_size` undefined) `SvLEN` is a pure
function of the source, and `VF.pm` transcribes it: `Perl_sv_grow` with `PERL_STRLEN_NEW_MIN`, the 25% expansion, the
8-byte roundup and `expected_size`, plus the size expression at every buffer-creating site the core lanes reach. `LEN`
is in the key, so a COW decision that goes wrong is reported at the site that produced the wrong length rather than as a
later cow-only row.

**The key.** The projection key carries every field that decides a future observable, for every holder kind: the public
and private value flags, `IsUV`, `UTF8`, `ROK`, `IsCOW`, the exact integer and NV slots, the string bytes, and `SvLEN` —
on a `POK` holder as the buffer's length, on any other holder as the length of the stale buffer it still owns. COW and
`LEN` are consumer-invisible at the state where they are observed but decide later transitions (whether an append
forces, whether an assignment shares), so they are state even though they are not output. Every "model gap" the walk has
found was, first, a field missing from this key.

**`undef $x` versus `$x = undef`.** `pp_undef` (pp.c, the scalar default arm) runs `sv_force_normal_flags(sv,
SV_COW_DROP_PV|SV_IMMEDIATE_UNREF)` and then, for a body with a PV, `SvPV_free`, `SvPV_set(sv, NULL)`, `SvLEN_set(sv,
0)` before `SvOK_off`: the buffer is freed. `sv_set_undef` (`$x = undef`), like `sv_setiv` and `sv_setnv`, begins with
`SV_CHECK_THINKFIRST_COW_DROP` — a shared buffer is dropped, a private one is kept — and the kept buffer's `LEN` is what
a later `sv_setsv_flags` reads on the destination side.

**`LEN` determinism.** On this build — `usemymalloc='n'`, `d_malloc_good_size='undef'`, `d_malloc_size='undef'` on both
5.38.2 and 5.44.0 — `PERL_UNWARANTED_CHUMMINESS_WITH_MALLOC` is undefined and `SvLEN` is exactly what `Perl_sv_grow`
computes; the model's `LEN` arithmetic holds under that condition and no other.

**Verification.** The definition of "verified" for this area is the coverage table produced by `vf_suite.pl`
(reports/suite/coverage.txt): per interpreter and lane — holder freshness, op set, depth, projection, transitions,
states — with `match`, `open`, `version-divergent` (path-based: from the first step whose oracle observations differ,
computed by `verdiv_paths.pl`), and `diverges-defined`; the model follows 5.44.0, and every 5.38.2 divergence found so
far is one rule, the unrounded first allocation before `expected_size` and `SvPV_shrink_to_cur` at `SvCUR + 1`.
