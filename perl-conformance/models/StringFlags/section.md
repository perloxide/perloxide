# The UTF-8 flag and taint

A string value carries its bytes, one bit that says how to read them (`SVf_UTF8`), and one bit that says whether the
value came from outside the program (`SVs_TAINT`).  Neither bit is a property of the content class from the value flags
section: a `Str` that is numeric, a `Dual`, and a plain string all carry them the same way.  This section defines the
flag as an interpretation claim, the operations that change it, the operations whose *rules* depend on it and on the
lexical context they run under, the I/O boundary, hash keys by reference to the hash section, and taint as per-value
state with a statement-scoped accumulator.  The reference implementation is `StringFlags.pm`; its harness `pv_gen.pl`
enumerates seven string families × seven lexical contexts × tainted/untainted × sixty-one operations at depth 1 (6,272
rows) and, at depth 2, every producer operation under one context handed to every reader operation under another
(121,800 rows), comparing bytes, flag, `length`, the `ord` of every character, `tainted`, and any croak, on the
supported 5.44.0 builds (and on the unsupported 5.38.2 as a difference detector, `../../unsupported-perls.md`).

The contexts: no pragma; `use feature "unicode_strings"`; `use bytes`; and `use locale` under four runtime locales --
the harness's compiled `ctype_utf8` (a UTF-8 locale), `ctype_latin1` (an ISO-8859-1 locale), `posix` (the glibc POSIX
source compiled under the ASCII charmap), and the C library's built-in `C`.  A pragma attaches to the operation, never
to the value: a string crosses from one context to another carrying nothing but its bytes, its flag and its taint, which
is what makes the depth-2 grid the whole cross-context space.

## 1. The flag as an interpretation claim

With the flag off, each byte is one character whose code point is the byte value; with the flag on, the bytes are read
as UTF-8 by `utf8n_to_uvchr` (utf8.c), and `length`, `substr`, `index`, `reverse`, `chop`, `ord`, `split //`, and
`tr///` all operate on the decoded characters.  `DO_UTF8` (sv.h) is the test every one of them makes: the flag is on
*and* `use bytes` is off, so under `use bytes` a flagged string is its bytes to all of them (`tr///` excepted:
`do_trans` reads the flag directly).

The claim need not be true: `Encode::_utf8_on` or a `:utf8` layer can flag malformed bytes.  The lenient readers accept
them by `UTF8SKIP` of the lead byte: a malformed sequence counts as one character, `ord` reads 0, and the bytes travel
with the character unchanged through `substr`, `reverse` and concatenation.  `Perl_utf8_length` counts the same way,
except that a final sequence cut short by the end of the string stops the count, and what it returns then is the number
of bytes consumed before that sequence, not a character count (`length` of the flagged `"\xC3"` is 0; of
`"\xA9\xC3\xB5\xC2"` 3).  `pp_unpack` reads through `utf8n_to_uvchr` instead, which consumes one byte of a malformed
sequence, reads it as U+FFFD, and goes on with the byte after it (`"\xC3\x28"` unpacks `"U*"` as 65533, 40).  The strict
readers die with "Malformed UTF-8 character (fatal)": `pp_lc`/`pp_uc`/`pp_lcfirst`/`pp_ucfirst`/`pp_fc`, `do_trans`,
`pack "a*"`/`"A*"`, `unpack "C0U*"`, and the regex engine where the match needs the character decoded (§4).

`substr` (`pp_substr`) returns a flagged string only when the source is read as UTF-8 and its character count differs
from its byte count: the first character of the flagged `"abc"` is an unflagged `"a"`, the first character of
`"a\x{100}"` a flagged one.

Two strings are `eq` when they have the same UTF-8 bytes after the unflagged side is upgraded (`sv_eq_flags`), which is
code-point equality for well-formed strings: `"\xB5\xE9"` unflagged equals its upgraded form, and the same bytes read
under different flags are different strings.  Under `use bytes` the bytes are compared as they are and the flag plays no
part, so the flagged `"\xB5\xE9"` equals its own UTF-8 encoding there.  `cmp` is the same comparison outside `use
locale`; under `use locale` see §5.

`reverse` in scalar context has two paths (`pp_reverse`).  A plain source is copied character by character in reverse
into the target, which under `use bytes` means byte by byte into an unflagged target.  A magical source -- a tainted
string carries taint magic -- is copied by `sv_setsv`, flag included, and reversed in place: with `DO_UTF8` each
well-formed character's bytes are reversed first, stopping at the first malformed one, and then the whole buffer is
reversed; so the tainted malformed `"\xC3\x28"` comes back as `"\x28\xC3"` where the untainted one is unchanged, and a
tainted flagged string under `use bytes` keeps its flag over reversed bytes.

## 2. Upgrade, downgrade, encode, decode

`sv_utf8_upgrade_flags_grow` re-encodes each byte as a UTF-8 character and sets the flag; on a flagged string it does
nothing; on a number it first forces a string through `sv_pvn_force_flags`, whose final `SvPOK_only_UTF8` drops the
numeric face (the value-flags section's rule).  `sv_utf8_downgrade_flags` clears the flag after replacing each character
by its byte; a character above 0xFF -- or a malformed sequence -- makes it die with "Wide character in subroutine
entry", or return false under `FAIL_OK` (`utf8::downgrade($s, 1)`) leaving the string unchanged.  Neither consults `use
bytes`.  `utf8::encode` upgrades and then clears the flag, so the bytes become the UTF-8 encoding; `utf8::decode`
(`sv_utf8_decode`) first downgrades -- so a flagged Latin-1 string comes back as its bytes -- and then sets the flag
only if the bytes are valid UTF-8 containing at least one high byte.

## 3. Concatenation

`pp_multiconcat` and `S_do_concat` read the flags of all operands: if any is flagged the result is flagged and every
unflagged operand is upgraded for the copy, so `"\x{100}" . "\xB5"` is two characters and the last is U+00B5; if none is
flagged the result is bytes.  `.=` applies the same rule to the target in place -- appending a flagged string to an
unflagged target, including an empty one, upgrades the target -- and a target that is also an operand is copied first.
`join` and `x` follow concatenation; `sprintf "%s"` copies the argument's flag; `sprintf "%c"`, `chr`, and `pack "U"`
produce a byte for a code point at most 0xFF and a flagged string above it (`pack "U"` always flags).

Under `use bytes` concatenation joins bytes and the result is unflagged, `.= ""` included -- which is what strips the
flag from a `utf8::downgrade($s, 1)` result that the harness appends nothing to.  A constant segment of a multiconcat
that is UTF-8 and cannot be downgraded has no byte form, and `pp_multiconcat`'s fast path appends nothing for it under
`use bytes`: `$s . "\x{100}"` is `$s`.  A magical operand -- a tainted string carries taint magic -- takes the
`sv_catsv` path, which appends the constant's UTF-8 bytes.  `join` is not a multiconcat and appends the bytes either
way.

## 4. The Unicode bug, the charsets, and the runtime locale

Perl's native encoding for an unflagged string has always been Latin-1 on ASCII platforms -- which is why upgrading maps
the byte 0xE9 to U+00E9 -- but under the default regex charset and in the case functions the 0x80-0xFF range of an
unflagged string has no properties at all unless something decides otherwise: before Unicode support those properties
came from the C library under `use locale`, and the no-pragma behavior is the C locale's answer frozen in place.  That
is the Unicode bug, and `use feature "unicode_strings"` is its fix.  What decides, for a character in 0x80-0xFF:

| context                         | unflagged string                                   | flagged string                                    |
|---------------------------------|----------------------------------------------------|---------------------------------------------------|
| no pragma                       | no properties: `uc("\xB5")` is `"\xB5"`, not `\w`  | Unicode rules                                     |
| `use feature "unicode_strings"` | Unicode rules: `uc("\xB5")` is U+039C, flagged     | Unicode rules                                     |
| `use bytes`                     | bytes, ASCII rules only, result unflagged          | bytes, ASCII rules only, result unflagged         |
| `use locale`, UTF-8 locale      | Unicode rules                                      | Unicode rules                                     |
| `use locale`, Latin-1 locale    | the C library's tables: `uc("\xE9")` is `"\xC9"`,  | the same tables for 0x80-0xFF, Unicode above 0xFF |
|                                 | `"\xB5"` is `\w`, `uc("\xB5")` is `"\xB5"`         |                                                   |
| `use locale`, C or POSIX locale | no properties                                      | no properties in 0x80-0xFF, Unicode above 0xFF    |

A character above 0xFF has its Unicode properties everywhere but under `use bytes`, where there are no characters.  A
mapping that leaves Latin-1 flags the result (`uc("\xB5")` under Unicode rules); `uc` maps U+00DF to `SS`, `ucfirst` to
`Ss`, `fc` to `ss` and U+00B5 to U+03BC, and U+00FF to U+0178.

The regex engine's charset (regcomp.c) is the explicit modifier if there is one; otherwise `use locale` gives `/l`, the
feature gives `/u`, and `/d` is the default -- except that a `/d` pattern containing a code point above 0xFF is compiled
under Unicode rules.  Under `/d` the table's first two rows apply by flag; under `/u` Unicode rules apply whatever the
flag; under `/a` and `/aa` the classes `\w`, `\s`, `\d` and the POSIX classes are ASCII-only for every code point, while
case-insensitive matching still folds under Unicode rules -- `/a` lets the unflagged `"\xDF"` match `/ss/i` where `/d`
does not -- and `/aa` additionally forbids a fold between an ASCII and a non-ASCII character, so `"\xDF" !~ /ss/iaa`.
Under `/l` the *runtime* locale decides, whether or not `use locale` is in effect: a UTF-8 locale gives Unicode rules,
the Latin-1 locale the C library's classes (`"\xB5" =~ /\w/l` and `"\xE9" =~ /\w/l`, flagged or not), and the C or POSIX
locale none for 0x80-0xFF; above 0xFF Unicode rules apply under `/l` too.  A pattern holding U+039C compiled under `/l`
in a non-UTF-8 locale matches U+039C and U+03BC but folds nothing in 0x80-0xFF to them.  An explicit `/d` under the
feature is still `/d`: `"\xB5" !~ /\w/d` where `"\xB5" =~ /\w/` under `unicode_strings`.

Whether the engine reads a flagged target strictly, so that a malformed one croaks, follows from what the match needs
decoded: always for a case-insensitive match; for a character class under Unicode rules (`/u`, or `/d` on a flagged
target); never under `/a` or `/aa`, whose classes are decided bytewise; and under `/l` only for `\w` in a locale with
classes above 0x7F, `\d` and `\s` being decided without decoding.

`unpack`: `"U*"` and `"C*"` read the characters as they are (`"C*"` gives full code points without wrapping) through
`utf8n_to_uvchr`, a malformed sequence reading as U+FFFD; `"U0C*"` gives the bytes of the UTF-8 encoding, which under
`use bytes` is the encoding of each byte; `"C0U*"` re-reads the characters as octets and decodes them -- on a string
read as bytes the bytes decode, malformed ones as U+FFFD (0 on 5.38.2), while on a flagged string a character in
0x80-0xFF is a stray continuation byte and fatal, a character above 0xFF reads as 0, and a malformed string yields
nothing.  `pack "a*"` and `"A*"` copy the string with its flag, strictly.

## 5. `cmp` under `use locale`

`sv_cmp_locale_flags` compares collation keys (`sv_collxfrm_flags`, the C library's `strxfrm`): `memcmp` over the
shorter key, then the raw strings as the tie-breaker, so two strings whose keys agree still order by their bytes.  The
harness's compiled locales all carry the POSIX collating sequence, under which a byte in the sequence weighs itself plus
two and a byte above 0x7F, undefined in it, weighs three -- below every defined character, so `"abc" cmp "\xB5\xE9"` is
1 there where it is -1 with no locale.  Perl exempts the built-in `C` locale from collation entirely
(`PL_collation_standard`), and a compiled POSIX locale is *not* exempt: the two differ on `cmp` while agreeing on every
other operation in the grid.

## 6. I/O layers

`:raw` writes the bytes; a flagged string with a character above 0xFF warns "Wide character" and its UTF-8 bytes go out.
`:utf8` writes the UTF-8 encoding of the characters (an unflagged high byte becomes two bytes) and reads bytes with the
flag set and no validation; `:encoding(UTF-8)` does the same with validation, so malformed input reads as U+FFFD with a
warning.  Not enumerated by the harness.

## 7. Hash keys and captures

A flagged key whose characters all fit Latin-1 is stored downgraded with `HVhek_WASUTF8` and returned by `keys` upgraded
again; a key that does not fit stays flagged; an unflagged key stays bytes (hash section §1).  So `"\xB5"` and its
upgrade are one key, `"\xB5"` and its UTF-8 encoding `"\xC2\xB5"` are two, and a flagged key of ASCII alone is the same
key as its unflagged self.  `use bytes` changes none of this.  A regex capture inherits the flag of the string matched
against as it was read, so under `use bytes` a capture of a flagged string is unflagged bytes.

## 8. Taint

Taint is a bit on the value (`SVs_TAINT`), copied with the value -- `my $c = $t` is tainted -- and propagated by every
operation that builds a string or number from a tainted operand: concatenation, `substr`, `reverse`, case mapping,
`ord`, `sprintf` (`"%s"`, `"%c"` and `"%d"` alike), `join`, `x`, `tr` and its count, `length`, `index`, `unpack`,
`pack`, `split`'s fields, the three-way `cmp`, upgrade, downgrade, encode and decode.  It is a property of the operation
and of nothing else: the flag, the context and the locale never change what is tainted, which is why the harness
enumerates it at depth 1 only.  `PL_tainted` is a per-statement accumulator: reading a tainted value sets it,
`pp_nextstate` clears it (`TAINT_NOT`), and the checked operations (`TAINT_PROPER`: `system`, `exec`, `open` for
writing, `unlink`, `eval STRING`, ...) die under `-T` when it is set.  Results that carry no taint: hash keys, regex
captures, `chr` (so `chr(ord $t)` is clean though `ord($t)` is tainted -- the launder is at `chr`), and the empty list
`split` returns for an empty string.

## 9. Verification

Depth 1: 6,272 rows, 6,272 matching on 5.44.0 (stock, both allocator variants and the threaded build); the 5.38.2 rows
differ from the 5.44.0 rows on 131 of them -- `unpack "C0U*"` on malformed octets (0 against U+FFFD), `tr///` on a
malformed string, and the strictness of a few readers -- and the model follows 5.44.0.  Depth 2: 121,800 rows, 121,800
matching, on the same builds.  The reference record of every depth-1 row at every version is the factored table
`reports/table.tsv`: one line per distinct result with the set of contexts and the set of versions it holds for
(`lib/Perl/Conformance/Table.pm`), from which `perl-conformance table StringFlags expand`, `lookup` and `diff` give the
full product at a version, a row's record, and the rows two versions disagree on; two thirds of the grid is one line
with `*` for every context and every version.  The depth-2 run is recorded by its row count and the SHA-256 of its table
in `reports/pv2.5.44.0.txt`, the table being one `DEPTH=2` run away.  The warning column is recorded but not compared,
and the I/O boundary (§6) is described from source rather than enumerated.
