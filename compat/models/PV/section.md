# The UTF-8 flag and taint

A string value carries its bytes, one bit that says how to read them (`SVf_UTF8`), and one bit that says whether the
value came from outside the program (`SVs_TAINT`). Neither bit is a property of the content class from the value flags
section: a `Str` that is numeric, a `Dual`, and a plain string all carry them the same way. This section defines the
flag as an interpretation claim, the operations that change it, the operations whose *rules* depend on it, the I/O
boundary, hash keys by reference to the hash section, and taint as per-value state with a statement-scoped accumulator.
The reference implementation is `PV.pm`; its harness `pv_gen.pl` enumerates six string families × three lexical contexts
× tainted/untainted × fifty-seven operations (2,052 rows per interpreter) and compares bytes, flag, `length`, the `ord`
of every character, `tainted`, and any croak, on Perl 5.38.2 and 5.44.0.

## 1. The flag as an interpretation claim

With the flag off, each byte is one character whose code point is the byte value; with the flag on, the bytes are read
as UTF-8 by `utf8n_to_uvchr` (utf8.c), and `length`, `substr`, `index`, `reverse`, `chop`, `ord`, `split //`, and
`tr///` all operate on the decoded characters. The claim need not be true: `Encode::_utf8_on` or a `:utf8` layer can
flag malformed bytes. The lenient readers — `Perl_utf8_length` (which advances by `UTF8SKIP` of the lead byte),
`substr`, `reverse`, `ord` — accept them: a malformed sequence counts as one character, `ord` reads 0, and the bytes
travel with the character unchanged. The strict readers — `pp_lc`/`pp_uc`/`pp_lcfirst`/`pp_ucfirst`/`pp_fc`, `do_trans`,
`pp_unpack` in character mode — die with "Malformed UTF-8 character (fatal)". Two strings are `eq` when their code point
sequences are equal, whatever their flags: `"\xB5\xE9"` unflagged equals its upgraded form; the same bytes read under
different flags are different strings.

## 2. Upgrade, downgrade, encode, decode

`sv_utf8_upgrade_flags_grow` re-encodes each byte as a UTF-8 character and sets the flag; on a flagged string it does
nothing; on a number it first forces a string through `sv_pvn_force_flags`, whose final `SvPOK_only_UTF8` drops the
numeric face (the value-flags section's rule). `sv_utf8_downgrade_flags` clears the flag after replacing each character
by its byte; a character above 0xFF — or a malformed sequence — makes it die with "Wide character in subroutine entry",
or return false under `FAIL_OK` (`utf8::downgrade($s, 1)`) leaving the string unchanged. `utf8::encode` upgrades and
then clears the flag, so the bytes become the UTF-8 encoding; `utf8::decode` (`sv_utf8_decode`) first downgrades — so a
flagged Latin-1 string comes back as its bytes — and then sets the flag only if the bytes are valid UTF-8 containing at
least one high byte.

## 3. Concatenation

`pp_multiconcat` and `S_do_concat` read the flags of all operands: if any is flagged the result is flagged and every
unflagged operand is upgraded for the copy, so `"\x{100}" . "\xB5"` is two characters and the last is U+00B5; if none is
flagged the result is bytes. `.=` applies the same rule to the target in place — appending a flagged string to an
unflagged target, including an empty one, upgrades the target — and a target that is also an operand is copied first.
`join` and `x` follow concatenation; `sprintf "%s"` copies the argument's flag; `sprintf "%c"`, `chr`, and `pack "U"`
produce a byte for a code point at most 0xFF and a flagged string above it (`pack "U"` always flags).

## 4. The Unicode bug

Whether a character in 0x80–0xFF has a case mapping or belongs to `\w`/`\s` depends on the string's flag unless
something else decides:

| string          | no feature                                             | `use feature 'unicode_strings'`                                                   | `use locale`, UTF-8 locale                              |
|-----------------|--------------------------------------------------------|-----------------------------------------------------------------------------------|---------------------------------------------------------|
| flagged         | Unicode rules                                          | Unicode rules                                                                     | Unicode rules                                           |
| unflagged bytes | ASCII only: `uc("\xB5")` is `"\xB5"`, `"\xB5" !~ /\w/` | Latin-1 rules: `uc("\xB5")` is U+039C and the result is flagged; `"\xB5" =~ /\w/` | case functions use Unicode rules; `/\w/` does not match |

Regex modifiers override the table: `/u` applies Unicode rules to bytes, `/a` restricts `\w`/`\s`/`\d` to ASCII, `/l`
applies the locale, which under a UTF-8 locale treats an unflagged byte as non-word. A pattern containing a code point
above 0xFF is compiled under Unicode rules, so `/\x{39C}/i` matches `"\xB5"` flagged or not, with or without the feature
(the fold of U+00B5 and U+039C is U+03BC); `/a` does not disable that fold. `fc` maps U+00B5 to U+03BC and U+00DF to
`ss`; `uc` maps U+00DF to `SS` and U+00FF to U+0178.

`unpack`: `"U*"` reads the characters as they are; `"C*"` in character mode gives full code points without wrapping;
`"U0C*"` gives the bytes of the UTF-8 encoding; `"C0U*"` re-reads the characters as octets — malformed octets read as
U+FFFD on 5.44.0 and as 0 on 5.38.2, and on a flagged string any non-ASCII character makes it fatal while a character
above 0xFF reads as 0. `pack "a*"` and `"A*"` copy the string with its flag.

## 5. I/O layers

`:raw` writes the bytes; a flagged string with a character above 0xFF warns "Wide character" and its UTF-8 bytes go out.
`:utf8` writes the UTF-8 encoding of the characters (an unflagged high byte becomes two bytes) and reads bytes with the
flag set and no validation; `:encoding(UTF-8)` does the same with validation, so malformed input reads as U+FFFD with a
warning. Not enumerated by the harness.

## 6. Hash keys and captures

A flagged key whose characters all fit Latin-1 is stored downgraded with `HVhek_WASUTF8` and returned by `keys` upgraded
again; a key that does not fit stays flagged; an unflagged key stays bytes (hash section §1). So `"\xB5"` and its
upgrade are one key and `"\xB5"` and its UTF-8 encoding `"\xC2\xB5"` are two. A regex capture inherits the flag of the
string matched against.

## 7. Taint

Taint is a bit on the value (`SVs_TAINT`), copied with the value — `my $c = $t` is tainted — and propagated by every
operation that builds a string or number from a tainted operand: concatenation, `substr`, `reverse`, case mapping,
`sprintf` (including `"%d"`), `join`, `x`, `tr`, `length`, `index`, `unpack`, `split`'s fields. `PL_tainted` is a
per-statement accumulator: reading a tainted value sets it, `pp_nextstate` clears it (`TAINT_NOT`), and the checked
operations (`TAINT_PROPER`: `system`, `exec`, `open` for writing, `unlink`, `eval STRING`, …) die under `-T` when it is
set. Results that carry no taint: the booleans of comparisons and pattern matches, `ord` and hence `chr(ord(…))`, hash
keys, and regex captures — the launder mechanism.

## 8. Verification

2,052 rows per interpreter. On 5.44.0 the harness reports 1,903 matching, 149 open; on 5.38.2, 1,900 matching, 152 open.
The open rows are, first, the `unpack` family on the malformed and flagged Latin-1 strings, where the 5.38/5.44
difference above (0 versus U+FFFD) and the fatal-versus-replacement boundary are partly transcribed; second, the `tr`
count on a malformed string; third, a taint row: `ord` of a tainted string is tainted in Perl while `chr(ord $t)` is
not, so taint is dropped at `chr`, not at `ord`, and the model has it the other way. The tables in the bundle
(`table.<ver>.tsv`) are the oracle records for every row; the 51 rows on which the two interpreters differ are listed in
`version-differences.diff`, and the model follows 5.44.0 where they differ. Depth 2 (chains of two string-valued
operations) is implemented in the generator but was not run in this pass.
