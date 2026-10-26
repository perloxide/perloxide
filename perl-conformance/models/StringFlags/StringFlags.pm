package Perl::Conformance::Model::StringFlags;

# Executable transcription of perl 5.44.0's string-flag and taint semantics.
#
# A string value is { b => bytes, u => SVf_UTF8, t => tainted }: the flag is an interpretation claim over the bytes
# (utf8.h), never a property of the content, and taint is a bit on the value.  Every operation runs under a lexical
# context -- none, `use feature "unicode_strings"`, `use bytes`, or `use locale` under a named runtime locale -- which
# attaches to the operation, never to the value; the harness sets $CTX per op.
#
# Routines named after a perl C function transcribe that function (sv_utf8_upgrade_flags_grow, sv_utf8_downgrade_flags,
# sv_utf8_encode, sv_utf8_decode, utf8_length, utf8_hop_back, pp_multiconcat, and so on); the Harness package holds
# what the generator needs that mirrors no C.

use strict;
use warnings;
no warnings 'portable';

our $CTX = 'none';
our @W;
our $MAL;
our @MALB;

# ---------------------------------------------------------------------------------------------------------------------
# The context: which rules an operation runs under.

# IN_BYTES (perl.h): `use bytes` is in effect.
sub IN_BYTES { $CTX eq 'bytes' }

# IN_LC (perl.h): `use locale` is in effect; the runtime locale is the context's.
sub IN_LC { $CTX =~ /^locale_/ }

# The runtime locale's character repertoire: UTF-8, Latin-1, or the ASCII-only C/POSIX locale.  Outside `use locale`
# the harness child runs with no locale selected, which is the C locale.
sub RUNTIME_LOCALE {
    return 'utf8'   if $CTX eq 'locale_utf8';
    return 'latin1' if $CTX eq 'locale_latin1';
    return 'c';
}

# IN_UNI_8_BIT (perl.h): `use feature "unicode_strings"`, which the regex and case code read as "Unicode rules for the
# 0x80-0xFF range of an unflagged string"; a UTF-8 locale under `use locale` has the same effect.
sub IN_UNI_8_BIT { $CTX eq 'feature' || (IN_LC() && RUNTIME_LOCALE() eq 'utf8') }

# DO_UTF8 (sv.h): the string is read as UTF-8 only when it is flagged and `use bytes` is off.
sub DO_UTF8 { my ($v) = @_; $v->{u} && !IN_BYTES() }

# ---------------------------------------------------------------------------------------------------------------------
# utf8.c: reading and writing the encoding.

sub UTF8SKIP {
    my ($b) = @_;
    return $b < 0xC0 ? 1 : $b < 0xE0 ? 2 : $b < 0xF0 ? 3 : $b < 0xF8 ? 4 : $b < 0xFC ? 5 : $b < 0xFE ? 6 : 7;
}

sub uvchr_to_utf8 {
    my ($c) = @_;
    return chr($c) if $c < 0x80;
    my $s = chr($c);
    utf8::encode($s);
    return $s;
}

# The lenient reader (utf8n_to_uvchr with no fatal flags): a malformed sequence counts as one character of UTF8SKIP
# bytes, reads as code point 0, and its bytes travel with it; $MAL records that one was seen.  A sequence cut short by
# the end of the string is still one character here, but utf8_length does not count it.
sub Chars {
    my ($v) = @_;
    return map { ord } split //, $v->{b} unless DO_UTF8($v);
    my @c;
    my $s = $v->{b};
    my $i = 0;
    while ($i < length $s) {
        my $lead = ord substr($s, $i, 1);
        my $n = UTF8SKIP($lead);
        my $chunk = substr($s, $i, $n);
        my $c = $chunk;
        my $ok = ($n == 1 && $lead < 0x80)
            || (length($chunk) == $n && $lead >= 0xC2 && $chunk =~ /^[\xC0-\xFD][\x80-\xBF]+\z/ && utf8::decode($c) && length($c) == 1);
        if ($ok) { push @c, ord($c) }
        else { $MAL = 1; push @c, 0; push @MALB, $chunk }
        $i += $n;
    }
    return @c;
}

# The decoding reader (utf8n_to_uvchr with the replacement flags, as pp_unpack uses it): a malformed sequence consumes
# only its first byte and reads as U+FFFD, and the bytes after it are read on their own.
sub DecodeChars {
    my ($v) = @_;
    return map { ord } split //, $v->{b} unless DO_UTF8($v);
    my @c;
    my $s = $v->{b};
    my $i = 0;
    while ($i < length $s) {
        my $lead = ord substr($s, $i, 1);
        my $n = UTF8SKIP($lead);
        my $chunk = substr($s, $i, $n);
        my $c = $chunk;
        my $ok = ($n == 1 && $lead < 0x80)
            || (length($chunk) == $n && $lead >= 0xC2 && $chunk =~ /^[\xC0-\xFD][\x80-\xBF]+\z/ && utf8::decode($c) && length($c) == 1);
        if ($ok) { push @c, ord($c); $i += $n }
        else { push @c, 0xFFFD; $i += 1 }
    }
    return @c;
}

# Perl_utf8_length: counts by UTF8SKIP; a final sequence that runs past the end of the string stops the count, and
# what is returned then is the number of bytes consumed before it, not the number of characters.
sub utf8_length {
    my ($v) = @_;
    return length $v->{b} unless DO_UTF8($v);
    my ($s, $i, $len) = ($v->{b}, 0, 0);
    while ($i < length $s) {
        my $n = UTF8SKIP(ord substr($s, $i, 1));
        return $i if length($s) - $i < $n;
        $i += $n;
        $len++;
    }
    return $len;
}

# The last character's byte length, as utf8_hop_back finds it: back over continuation bytes, then one more.
sub utf8_hop_back {
    my ($s) = @_;
    my $n = 1;
    $n++ while $n < length $s && (ord substr($s, -$n, 1)) >= 0x80 && (ord substr($s, -$n, 1)) < 0xC0;
    return $n;
}

# Builds a value from code points: encoded when the flag is on, bytes otherwise; a code point above 0xFF forces the
# flag.  A malformed character read by Chars (code point 0 while $MAL is set) is written back as its original bytes.
sub FromCps {
    my ($cps, $u, $t) = @_;
    $u = 1 if grep { $_ > 0xFF } @$cps;
    my @mb = @MALB;
    my $b = $u ? join('', map { $_ == 0 && @mb ? shift(@mb) : uvchr_to_utf8($_) } @$cps) : join('', map { chr } @$cps);
    return { b => $b, u => $u ? 1 : 0, t => $t ? 1 : 0 };
}

# A number result: an unflagged string of digits.
sub Num {
    my ($n, $t) = @_;
    return { b => "$n", u => 0, t => $t ? 1 : 0 };
}

# A byte-string result under `use bytes`: the bytes as they are and the flag off, which is what every operation that
# builds its result from the string's bytes (sv_setpvn and friends) leaves when DO_UTF8 is false.
sub Bytes {
    my ($b, $t) = @_;
    return { b => $b, u => 0, t => $t ? 1 : 0 };
}

# The strict readers (utf8n_to_uvchr_msgs with the fatal flags): a malformed sequence in a string read as UTF-8 croaks.
sub Strict {
    my ($v) = @_;
    return unless DO_UTF8($v);
    local $MAL = 0;
    local @MALB = ();
    Chars($v);
    die "Malformed UTF-8 character (fatal)\n" if $MAL;
}

# ---------------------------------------------------------------------------------------------------------------------
# sv.c: upgrade, downgrade, encode, decode.

sub sv_utf8_upgrade_flags_grow {
    my ($v) = @_;
    return $v if $v->{u};
    return { b => join('', map { uvchr_to_utf8(ord $_) } split //, $v->{b}), u => 1, t => $v->{t} };
}

# Returns (value, ok).  The flag is tested directly, not through DO_UTF8: `use bytes` does not change what downgrade
# does.  A character above 0xFF, or a malformed sequence, cannot be downgraded: croak, or with fail_ok leave the
# string as it is and report failure.
sub sv_utf8_downgrade_flags {
    my ($v, $fail_ok) = @_;
    return ($v, 1) unless $v->{u};
    local $MAL = 0;
    local @MALB = ();
    local $CTX = 'none';
    my @c = Chars($v);
    if ($MAL || grep { $_ > 0xFF } @c) {
        die "Wide character in subroutine entry\n" unless $fail_ok;
        return ($v, 0);
    }
    return ({ b => join('', map { chr } @c), u => 0, t => $v->{t} }, 1);
}

# sv_utf8_encode: upgrade, then SvUTF8_off.
sub sv_utf8_encode {
    my ($v) = @_;
    my $u = sv_utf8_upgrade_flags_grow($v);
    return { b => $u->{b}, u => 0, t => $v->{t} };
}

# sv_utf8_decode: sv_utf8_downgrade(sv, TRUE) first; then the flag goes on only if the bytes are well-formed UTF-8
# with a byte above 0x7F.  A string that cannot be downgraded is left as it is.
sub sv_utf8_decode {
    my ($v) = @_;
    my ($d, $ok) = sv_utf8_downgrade_flags($v, 1);
    return $v unless $ok;
    my $c = $d->{b};
    return { b => $d->{b}, u => ($d->{b} =~ /[\x80-\xFF]/ && utf8::decode($c) ? 1 : 0), t => $v->{t} };
}

# ---------------------------------------------------------------------------------------------------------------------
# The rules for the 0x80-0xFF range: pp_uc/pp_lc/pp_ucfirst/pp_lcfirst/pp_fc and the regex charsets.

# Which rules the case functions apply to a character in 0x80-0xFF: 'unicode', 'latin1' (the C library's tables for
# the runtime Latin-1 locale), or 'none' (the C locale's tables, or the Unicode bug: no properties at all).
sub CaseRules {
    my ($v) = @_;
    return 'none'    if IN_BYTES();
    return 'unicode' if DO_UTF8($v) && !IN_LC();
    if (IN_LC()) {
        my $loc = RUNTIME_LOCALE();
        return 'unicode' if $loc eq 'utf8';
        return 'latin1'  if $loc eq 'latin1';
        return 'none';
    }
    return 'unicode' if IN_UNI_8_BIT();
    return 'none';
}

# Unicode case mappings for the 0x80-0xFF range that leave it or are multi-character; every other Latin-1 letter maps
# within Latin-1 by +/- 0x20.
my %UC = (0xB5 => [0x39C], 0xDF => [0x53, 0x53], 0xFF => [0x178]);
my %TC = (0xDF => [0x53, 0x73]);
my %FC = (0xB5 => [0x3BC], 0xDF => [0x73, 0x73]);

sub MapChar {
    my ($c, $kind, $rules, $first) = @_;
    if ($c < 0x80) {
        my $ch = chr $c;
        return (ord(($kind eq 'uc' || $kind eq 'tc') ? uc $ch : lc $ch));
    }
    if ($c > 0xFF) {
        return map { ord } split //, ($kind eq 'uc' ? uc chr $c : $kind eq 'tc' ? ucfirst chr $c : $kind eq 'lc' ? lc chr $c : CORE::fc chr $c);
    }
    return ($c) if $rules eq 'none';
    if ($rules eq 'latin1') {
        # toupper/tolower of the Latin-1 locale: a mapping that leaves the repertoire (micro sign, sharp s, y diaeresis)
        # is the identity.
        return ($c - 0x20) if ($kind eq 'uc' || $kind eq 'tc') && $c >= 0xE0 && $c <= 0xFE && $c != 0xF7;
        return ($c + 0x20) if ($kind eq 'lc' || $kind eq 'fc') && $c >= 0xC0 && $c <= 0xDE && $c != 0xD7;
        return ($c);
    }
    if ($kind eq 'uc') { return $UC{$c} ? @{ $UC{$c} } : ($c >= 0xE0 && $c <= 0xFE && $c != 0xF7) ? ($c - 0x20) : ($c) }
    if ($kind eq 'tc') { return $TC{$c} ? @{ $TC{$c} } : $UC{$c} ? @{ $UC{$c} } : ($c >= 0xE0 && $c <= 0xFE && $c != 0xF7) ? ($c - 0x20) : ($c) }
    if ($kind eq 'lc') { return ($c >= 0xC0 && $c <= 0xDE && $c != 0xD7) ? ($c + 0x20) : ($c) }
    return $FC{$c} ? @{ $FC{$c} } : ($c >= 0xC0 && $c <= 0xDE && $c != 0xD7) ? ($c + 0x20) : ($c);
}

# pp_uc and family: a strict read, the mapping under the context's rules, and a result that keeps the flag unless the
# mapping leaves Latin-1.  Under `use bytes` the string is its bytes, only ASCII maps, and the result is unflagged.
sub CaseMap {
    my ($v, $kind, $firstonly) = @_;
    Strict($v);
    my $rules = CaseRules($v);
    my @c = Chars($v);
    my @out;
    for my $i (0 .. $#c) {
        if ($firstonly && $i > 0) { push @out, $c[$i]; next }
        push @out, MapChar($c[$i], ($firstonly && $kind eq 'uc') ? 'tc' : $kind, $rules, $i == 0);
    }
    return Bytes(join('', map { chr } @out), $v->{t}) if IN_BYTES();
    return FromCps(\@out, $v->{u}, $v->{t});
}

# The charset a pattern is compiled under (regcomp.c): an explicit modifier wins; otherwise `use locale` gives /l,
# `unicode_strings` gives /u, and /d is the default -- except that a /d pattern containing a code point above 0xFF
# is compiled under Unicode rules.
sub Charset {
    my ($mod, $wide_pattern) = @_;
    return $mod if length $mod;
    return 'l' if IN_LC();
    return 'u' if $CTX eq 'feature';
    return 'u' if $wide_pattern;
    return 'd';
}

# Which properties a character above 0x7F has under a charset, for a target read as UTF-8 or not: 'unicode'; 'ascii'
# (/a and /aa: none at all, whatever the code point); 'latin1' (the C library's classes for 0x80-0xFF under the Latin-1
# locale); or 'none' (the C locale under /l, and the Unicode bug under /d) -- under which a code point above 0xFF still
# has its Unicode properties.
sub HighRules {
    my ($charset, $target_utf8) = @_;
    return 'unicode' if $charset eq 'u';
    return 'ascii'   if $charset eq 'a' || $charset eq 'aa';
    if ($charset eq 'l') {
        my $loc = RUNTIME_LOCALE();
        return 'unicode' if $loc eq 'utf8';
        return 'latin1'  if $loc eq 'latin1';
        return 'none';
    }
    return $target_utf8 ? 'unicode' : 'none';
}

# \w, \s, \d on one character.
sub ClassMatch {
    my ($cls, $c, $rules) = @_;
    if ($c < 0x80) {
        return chr($c) =~ /\w/a ? 1 : 0 if $cls eq 'w';
        return chr($c) =~ /\s/a ? 1 : 0 if $cls eq 's';
        return chr($c) =~ /\d/a ? 1 : 0;
    }
    return 0 if $rules eq 'ascii';
    return 0 if $rules eq 'none' && $c <= 0xFF;
    if ($rules eq 'latin1' && $c <= 0xFF) {
        # The Latin-1 locale's isalnum: every Latin-1 letter, the micro sign and the ordinal indicators included.
        return ($c == 0xAA || $c == 0xB5 || $c == 0xBA || ($c >= 0xC0 && $c != 0xD7 && $c != 0xF7)) ? 1 : 0 if $cls eq 'w';
        return ($c == 0xA0) ? 0 : 0 if $cls eq 's';
        return 0;
    }
    return chr($c) =~ /\w/u ? 1 : 0 if $cls eq 'w';
    return chr($c) =~ /\s/u ? 1 : 0 if $cls eq 's';
    return chr($c) =~ /\d/u ? 1 : 0;
}

# Whether the regex engine reads the target strictly, so that a malformed flagged target croaks: always for a
# case-insensitive match, whose folding decodes every character; for a character class under Unicode rules (/u, or /d
# on a UTF-8 target); never under /a or /aa, whose classes are decided bytewise; and under /l only for \w in a locale
# with classes above 0x7F, \d and \s being decided without decoding.
sub RegexStrict {
    my ($v, $charset, $cls) = @_;
    return unless DO_UTF8($v);
    return Strict($v) if $cls eq 'i';
    return if $charset eq 'a' || $charset eq 'aa';
    if ($charset eq 'l') {
        return unless $cls eq 'w' && HighRules($charset, 1) ne 'none';
    }
    Strict($v);
}

# A character class match over the target.
sub MatchClass {
    my ($v, $cls, $mod) = @_;
    my $charset = Charset($mod, 0);
    RegexStrict($v, $charset, $cls);
    my $rules = HighRules($charset, DO_UTF8($v));
    my $m = 0;
    for my $c (Chars($v)) { $m = 1 if ClassMatch($cls, $c, $rules) }
    return Num($m, 0);
}

# /\x{39C}/i: the pattern holds a code point above 0xFF.  Capital mu itself always matches, and small mu, above 0xFF,
# folds to it under every charset; the micro sign folds to it only where the 0x80-0xFF range has Unicode rules -- /u,
# /a and /aa (both sides being non-ASCII, the fold is allowed), /d on a UTF-8 target, /l in a UTF-8 locale.
sub MatchMu {
    my ($v, $mod) = @_;
    my $charset = Charset($mod, 1);
    RegexStrict($v, $charset, 'i');
    my $rules = HighRules($charset, DO_UTF8($v));
    my $fold_micro = $rules eq 'unicode' || $rules eq 'ascii';
    my $m = (grep { $_ == 0x39C || $_ == 0x3BC || ($_ == 0xB5 && $fold_micro) } Chars($v)) ? 1 : 0;
    return Num($m, 0);
}

# /ss/i: matches where the target holds "ss" (any case) or, under a full Unicode fold, the sharp s, whose fold is "ss".
# /a allows that multi-character fold; /aa forbids a fold between an ASCII and a non-ASCII character; the sharp s of an
# unflagged string has no fold under the Unicode bug or a non-UTF-8 locale.
sub MatchSs {
    my ($v, $mod) = @_;
    my $charset = Charset($mod, 0);
    RegexStrict($v, $charset, 'i');
    my $rules = HighRules($charset, DO_UTF8($v));
    my @c = Chars($v);
    my $m = 0;
    for my $i (0 .. $#c) {
        $m = 1 if $i < $#c && ($c[$i] == 0x73 || $c[$i] == 0x53) && ($c[$i + 1] == 0x73 || $c[$i + 1] == 0x53);
        $m = 1 if $c[$i] == 0xDF && $charset ne 'aa' && ($rules eq 'unicode' || $charset eq 'a');
    }
    return Num($m, 0);
}

# The collation key the harness's compiled locales give a byte string (glibc strxfrm under the POSIX collating
# sequence): a byte in the sequence weighs itself plus two, a byte above 0x7F -- undefined in that sequence -- weighs
# three, below every defined character; equal keys fall back to the bytes.
sub CollationKey {
    my ($b) = @_;
    return join('', map { my $c = ord $_; chr($c < 0x80 ? $c + 2 : 3) } split //, $b);
}

# ---------------------------------------------------------------------------------------------------------------------
# Concatenation: pp_multiconcat, sv_catsv.

# Appending to a value.  With DO_UTF8 on either side the result is UTF-8 and the other side is upgraded for the copy;
# under `use bytes` the bytes are joined and the result is unflagged.  A constant segment of a multiconcat that is UTF-8
# and cannot be downgraded has no byte form, and under `use bytes` pp_multiconcat's fast path appends nothing for it; a
# magical operand -- a tainted string carries taint magic -- takes the sv_catsv path, which appends the constant's UTF-8
# bytes.
sub Append {
    my ($v, $add, $is_constant) = @_;
    my $t = $v->{t} || $add->{t};
    if (IN_BYTES()) {
        return Bytes($v->{b}, $t) if $is_constant && $add->{u} && $add->{b} =~ /[\xC4-\xFD]/ && !$v->{t};
        return Bytes($v->{b} . $add->{b}, $t);
    }
    my $u = $v->{u} || $add->{u};
    my @c = (Chars($v), Chars({ %$add, u => $add->{u} }));
    return FromCps(\@c, $u, $t);
}

# ---------------------------------------------------------------------------------------------------------------------
# The operations, by the generator's names.

my %FAMILY = (
    A => { b => "abc",              u => 0 },
    B => { b => "\xB5\xE9",         u => 0 },
    L => { b => "\xC2\xB5\xC3\xA9", u => 1 },
    H => { b => "a\xC4\x80",        u => 1 },
    M => { b => "\xC3\x28",         u => 1 },
    E => { b => "",                 u => 0 },
    S => { b => "\xDF",             u => 0 },
);

my $MU    = { b => "\xB5",     u => 0, t => 0 };
my $MU_U  = { b => "\xC2\xB5", u => 1, t => 0 };
my $WIDE  = { b => "\xC4\x80", u => 1, t => 0 };
my $COMMA = { b => ",",        u => 0, t => 0 };

# The generator's entry point.
sub Perl::Conformance::Model::StringFlags::Harness::Run { Run(@_) }

# Run(FAMILY, TAINT, [[op, context], ...]) -> the observation record "bytes-hex, flag, length, ords, tainted, warnings,
# croak" as the generator's child prints it.
sub Run {
    my ($fam, $taint, $steps) = @_;
    local $CTX = 'none';
    local @W = ();
    local $MAL = 0;
    local @MALB = ();
    my $v = { %{ $FAMILY{$fam} }, t => $taint ? 1 : 0 };
    my $err = '';
    my $ok = eval {
        for my $step (@$steps) {
            my ($op, $ctx) = @$step;
            $CTX = $ctx;
            $MAL = 0;
            @MALB = ();
            $v = Op($op, $v);
        }
        1;
    };
    if (!$ok) {
        $err = $@;
        $err =~ s/\n\z//;
        $v = { b => 'undef', u => 0, t => 0 };
    }

    # The child observes the result outside any pragma.
    local $CTX = 'none';
    local $MAL = 0;
    local @MALB = ();
    my $len = utf8_length($v);
    my @o = Chars($v);
    return join("\t", unpack('H*', $v->{b}), $v->{u}, $len, join(',', @o), $v->{t}, '', $err);
}

sub Op {
    my ($op, $v) = @_;
    my $t = $v->{t};
    if ($op eq 'up')     { return sv_utf8_upgrade_flags_grow($v) }
    if ($op eq 'down')   { my ($r) = sv_utf8_downgrade_flags($v, 0); return $r }
    if ($op eq 'downok') { my ($r) = sv_utf8_downgrade_flags($v, 1); return Append($r, { b => '', u => 0, t => 0 }, 1) }
    if ($op eq 'enc')    { return sv_utf8_encode($v) }
    if ($op eq 'dec')    { return sv_utf8_decode($v) }
    if ($op eq 'len' || $op eq 'arith' || $op eq 'spd') { return Num(utf8_length($v), $t) }
    if ($op eq 'rev') {
        # pp_reverse in scalar context.  A plain source is copied character by character in reverse (by UTF8SKIP, a
        # malformed sequence travelling whole) into a fresh target, which under `use bytes` is bytes.  A magical source
        # -- a tainted string carries taint magic -- is copied with sv_setsv, flag included, and reversed in place: if
        # DO_UTF8, each well-formed character's bytes are reversed first, stopping at the first malformed one, and then
        # the whole buffer is reversed; so a flagged string under `use bytes` keeps its flag over reversed bytes.
        if ($t) {
            my $s = $v->{b};
            if (DO_UTF8($v)) {
                my $i = 0;
                while ($i < length $s) {
                    my $lead = ord substr($s, $i, 1);
                    if ($lead < 0x80) { $i++; next }
                    my $n = UTF8SKIP($lead);
                    my $chunk = substr($s, $i, $n);
                    my $c = $chunk;
                    last unless length($chunk) == $n && $lead >= 0xC2 && $chunk =~ /^[\xC0-\xFD][\x80-\xBF]+\z/ && utf8::decode($c) && length($c) == 1;
                    substr($s, $i, $n) = scalar reverse $chunk;
                    $i += $n;
                }
            }
            return { b => scalar reverse($s), u => $v->{u}, t => $t };
        }
        return Bytes(scalar reverse($v->{b}), $t) if IN_BYTES();
        my @c = reverse Chars($v);
        return FromCps(\@c, $v->{u}, $t);
    }
    if ($op eq 'chop') {
        # S_do_chomp: one character off the end, found by utf8_hop_back on a UTF-8 string, one byte otherwise; an empty
        # string is left as it is, flag included.
        return { %$v } unless length $v->{b};
        return Bytes(substr($v->{b}, 0, -1), $t) if IN_BYTES() || !$v->{u};
        return { b => substr($v->{b}, 0, length($v->{b}) - utf8_hop_back($v->{b})), u => 1, t => $t };
    }
    if ($op eq 'chomp') { return $v }
    if ($op eq 'lc')  { return CaseMap($v, 'lc', 0) }
    if ($op eq 'uc')  { return CaseMap($v, 'uc', 0) }
    if ($op eq 'lcf') { return CaseMap($v, 'lc', 1) }
    if ($op eq 'ucf') { return CaseMap($v, 'uc', 1) }
    if ($op eq 'fc')  { return CaseMap($v, 'fc', 0) }
    if ($op eq 'ord') {
        # pp_ord: the first character under DO_UTF8, else the first byte; the number is tainted with the string.
        my @c = Chars($v);
        return Num($c[0] // 0, $t);
    }
    if ($op eq 'chr' || $op eq 'spc') {
        # chr(ord $s) and sprintf "%c": a character below 0x100 is an unflagged byte.  pp_chr taints nothing;
        # sprintf's result is tainted with its argument.
        my @c = Chars($v);
        return FromCps([ $c[0] // 0 ], 0, $op eq 'spc' ? $t : 0);
    }
    if ($op eq 'sub1') {
        # pp_substr: the result is flagged only when the source is read as UTF-8 and its character count differs from
        # its byte count -- a flagged string of ASCII alone yields an unflagged substring.
        return Bytes(substr($v->{b}, 0, 1), $t) if IN_BYTES();
        my @c = Chars($v);
        my $u = ($v->{u} && @c != length $v->{b}) ? 1 : 0;
        return @c ? FromCps([ $c[0] ], $u, $t) : { b => '', u => $u, t => $t };
    }
    if ($op eq 'idx') {
        # index($s, "\xB5"): the needle is upgraded to the haystack's form; under `use bytes` both are bytes.
        my @c = Chars($v);
        for my $i (0 .. $#c) { return Num($i, $t) if $c[$i] == 0xB5 }
        return Num(-1, $t);
    }
    if ($op eq 'sps')  { return IN_BYTES() ? Bytes($v->{b}, $t) : { %$v } }
    if ($op eq 'copy') { return { %$v } }
    if ($op eq 'rep')  { return IN_BYTES() ? Bytes($v->{b} x 2, $t) : { b => $v->{b} x 2, u => $v->{u}, t => $t } }
    if ($op eq 'joinb') { return Append(Append($v, $COMMA, 0), $MU, 0) }
    if ($op eq 'joinu') { return Append(Append($v, $COMMA, 0), $WIDE, 0) }
    if ($op eq 'split') {
        # split //: one field per character under DO_UTF8, per byte otherwise; an empty string has no fields and the
        # empty result carries no taint.
        my @c = Chars($v);
        return Num(join('|', @c), @c ? $t : 0);
    }
    if ($op eq 'tr' || $op eq 'trcnt') {
        # do_trans: reads the string by its own flag, `use bytes` notwithstanding, and strictly.
        local $CTX = $CTX eq 'bytes' ? 'none' : $CTX;
        Strict($v);
        my @c = Chars($v);
        return Num(scalar(grep { $_ == 0xB5 } @c), $t) if $op eq 'trcnt';
        @c = map { $_ == 0xB5 ? 0x58 : $_ } @c;
        return FromCps(\@c, $v->{u}, $t);
    }
    if ($op eq 'unpU' || $op eq 'unpC') {
        # pp_unpack "U*" and "C*" on a string read as UTF-8 give its code points through the decoding reader; on
        # bytes, the bytes.
        return Num(join(',', DecodeChars($v)), $t);
    }
    if ($op eq 'unpU0C') {
        # "U0C*": the bytes of the string's UTF-8 form -- the encoding of each byte when the string is read as bytes.
        my $raw = IN_BYTES() ? { b => $v->{b}, u => 0, t => $t } : $v;
        my $u = sv_utf8_upgrade_flags_grow($raw);
        return Num(join(',', map { ord } split //, $u->{b}), $t);
    }
    if ($op eq 'unpC0U') {
        # "C0U*": the characters re-read as octets and decoded as UTF-8.  A string read as bytes decodes its bytes
        # through the decoding reader; a string read as UTF-8 hands its code points over as octets, so a character in
        # 0x80-0xFF is a stray continuation byte and croaks, a wider one reads as 0, and a malformed one yields nothing.
        if (!DO_UTF8($v)) {
            local $CTX = 'none';
            return Num(join(',', DecodeChars({ b => $v->{b}, u => 1, t => 0 })), $t);
        }
        my @c = Chars($v);
        return Num('', $t) if $MAL;
        die "Malformed UTF-8 character (fatal)\n" if grep { $_ >= 0x80 && $_ <= 0xFF } @c;
        return Num(join(',', map { $_ > 0xFF ? 0 : $_ } @c), $t);
    }
    if ($op eq 'packU') {
        # pack "U", ord($s): the first character's code point, 0 for a malformed one, written fresh.
        my @c = Chars($v);
        local @MALB = ();
        return FromCps([ $c[0] // 0 ], 1, $t);
    }
    if ($op eq 'packa' || $op eq 'packA') {
        # pack "a*"/"A*": the string's bytes and flag, read strictly; bytes under `use bytes`.
        return Bytes($v->{b}, $t) if IN_BYTES();
        Strict($v);
        return { %$v };
    }
    if ($op =~ /^re(w|s|d)(aa|a|u|l|d)?\z/) { return MatchClass($v, $1, $2 // '') }
    if ($op =~ /^rei(u|a)?\z/)              { return MatchMu($v, $1 // '') }
    if ($op =~ /^reiss(u|a|aa|l)?\z/)       { return MatchSs($v, $1 // '') }
    if ($op eq 'cap') {
        # A capture is the matched bytes with the target's flag as read, and is never tainted.
        return Bytes($v->{b}, 0) if IN_BYTES();
        return { b => $v->{b}, u => $v->{u}, t => 0 };
    }
    if ($op eq 'hkey') {
        # hv_common stores a downgradable UTF-8 key downgraded with HVhek_WASUTF8 and hands it back upgraded, so the
        # key read back is the key stored, in its own form; keys are never tainted.
        return { b => $v->{b}, u => $v->{u}, t => 0 };
    }
    if ($op eq 'hkey2') {
        # The string and its other form: one key when the string is bytes (its upgrade normalizes to the same key) or
        # is UTF-8 over ASCII alone (its encoding is the same bytes), two when it is UTF-8 with a byte above 0x7F (its
        # encoding is a different byte string).
        return Num($v->{u} && $v->{b} =~ /[\x80-\xFF]/ ? 2 : 1, 0);
    }
    if ($op eq 'catb' || $op eq 'apb') { return Append($v, $MU, 1) }
    if ($op eq 'catu' || $op eq 'apu') { return Append($v, $WIDE, 1) }
    if ($op eq 'catl' || $op eq 'apl') { return Append($v, $MU_U, 0) }
    if ($op eq 'eqb' || $op eq 'eql' || $op eq 'cmpb') {
        # sv_eq_flags and sv_cmp_flags upgrade the unflagged side and compare the bytes (not decoded code points, which
        # differs only for a malformed string); under `use bytes` the bytes are compared as they are, the flag playing
        # no part.  Under `use locale` sv_cmp_locale compares collation keys instead, except in the
        # built-in C locale, which perl exempts from collation; a compiled POSIX locale is not exempt.
        my $other = $op eq 'eql' ? { b => "\xC2\xB5\xC3\xA9", u => 1, t => 0 } : { b => "\xB5\xE9", u => 0, t => 0 };
        my ($a, $b) = ($v, $other);
        if (IN_BYTES()) {
            my $eq = ($a->{b} eq $b->{b}) ? 1 : 0;
            return Num($eq, 0) if $op ne 'cmpb';
            return Num(($a->{b} cmp $b->{b}), $t);
        }
        if ($a->{u} != $b->{u}) { ($a, $b) = map { sv_utf8_upgrade_flags_grow($_) } $a, $b }
        return Num(($a->{b} eq $b->{b}) ? 1 : 0, 0) if $op ne 'cmpb';
        if (IN_LC() && $CTX ne 'locale_c') {
            # sv_cmp_locale_flags: memcmp of the keys over the shorter length, and the raw strings as the tie-breaker.
            my ($ka, $kb) = (CollationKey($a->{b}), CollationKey($b->{b}));
            my $n = length($ka) < length($kb) ? length($ka) : length($kb);
            return Num((substr($ka, 0, $n) cmp substr($kb, 0, $n)) || ($a->{b} cmp $b->{b}), $t);
        }
        return Num(($a->{b} cmp $b->{b}), $t);
    }
    die "op $op";
}

1;
