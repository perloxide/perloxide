package Perl::Conformance::Model::ValueFlags;

# Reference implementation of the value flags semantics: a transcription of perl 5.44.0 sv.c / pp.c / pp_hot.c /
# numeric.c on an x86-64 build (NV_PRESERVES_UV_BITS = 53, no NV_PRESERVES_UV).  Every function names the C function it
# mirrors, and each C function is one Perl routine here.  The scalar is a hash: kind (S, I, N, R, U), pv, iv (IV or UV
# per is_uv), nv, int_form and num_form (0 none, 1 private, 2 public), is_uv (SVf_IVisUV), stringified (SVp_POK on a
# non-string), utf8 (SVf_UTF8), cow and cow_refcnt (SvIsCOW and CowREFCNT), len (SvLEN), ook (the OOK offset), type
# (SvTYPE).
#
# Reconciled from two independent transcriptions of the same functions, which agreed cell for cell on the 2,304-row
# handler matrix; where they differed, the source line decided.  Where perl's NV conversion goes on to parse the scalar
# a __WARN__ handler replaced mid-conversion (undefined.md: W1, a number or undef; W2, a reference), the model dies
# "UB" unless $DESIGN_DEFINED is set, which takes the design's redispatch branch instead.

use strict;
use warnings;
no warnings 'portable';
use POSIX ();

our $DESIGN_DEFINED = 0;    # when set, the perl-undefined windows W1 and W2 take the design-defined branch
our $IV_MAX = 9223372036854775807;
our $IV_MIN = -9223372036854775808;
our $UV_MAX = 18446744073709551615;
our $TWO53 = 9007199254740992;
our $ABS_IV_MIN = 9223372036854775808;
our $TWO63 = 9223372036854775808.0;
our $TWO64 = 18446744073709551616.0;
our $INF = 9**9**9;
our $NAN = -sin(9**9**9);

sub isnan { my $f = shift; $f != $f }

# ---------------- the values the harness builds ----------------

# A string literal: the constant is built by newSVpvn -> sv_grow_fresh (sv.c): newlen+1, floor PERL_STRLEN_NEW_MIN, no
# roundup; observed 16 for "10", 38 for a 36-byte literal.  A literal assignment shares its buffer: SvIsCOW, hence
# SvTHINKFIRST.  Its body is PV.
sub Perl::Conformance::Model::ValueFlags::Harness::string {
    return { kind => 'S', pv => $_[0], iv => 0, nv => 0, int_form => 0, num_form => 0, is_uv => 0, stringified => 0,
             utf8 => 0, cow => 1, cow_refcnt => 1, len => (length($_[0]) + 2 < 16 ? 16 : length($_[0]) + 2),
             type => 'PV' };
}

sub Perl::Conformance::Model::ValueFlags::Harness::integer {
    return { cow => 0, kind => 'I', pv => '', iv => $_[0], nv => 0, int_form => 2, num_form => 0,
             is_uv => ($_[0] > $IV_MAX ? 1 : 0), stringified => 0, utf8 => 0, type => 'IV' };
}

sub Perl::Conformance::Model::ValueFlags::Harness::number {
    return { cow => 0, kind => 'N', pv => '', iv => 0, nv => 0.0 + $_[0], int_form => 0, num_form => 2, is_uv => 0,
             stringified => 0, utf8 => 0, type => 'NV' };
}

sub Perl::Conformance::Model::ValueFlags::Harness::undef {
    return { cow => 0, kind => 'U', pv => '', iv => 0, nv => 0, int_form => 0, num_form => 0, is_uv => 0,
             stringified => 0, utf8 => 0, type => 'NULL' };
}

sub Perl::Conformance::Model::ValueFlags::Harness::reference {
    return { cow => 0, kind => 'R', pv => '', iv => 0, nv => 0, int_form => 0, num_form => 0, is_uv => 0,
             stringified => 0, utf8 => 0 };
}

# ---------------- numeric.c ----------------

# numeric.c Perl_cast_iv / Perl_cast_uv
sub cast_iv {
    my $f = shift;
    return 0 if isnan($f);
    if ($f < $TWO63) { return $f < $IV_MIN ? $IV_MIN : int($f) }
    if ($f < $TWO64) { my $u = int($f); return $u - $TWO64 }
    return $f > 0 ? -1 : 0;
}

sub cast_uv {
    my $f = shift;
    return 0 if isnan($f);
    if ($f < 0.0) { return $f < $IV_MIN ? $TWO63 : ($TWO64 + int($f)) }
    if ($f < $TWO64) { return int($f) }
    return $UV_MAX;
}

sub nvof { unpack "d", pack "d", $_[0] }    # a true C (NV) cast; perl-level arithmetic preserves integers
sub SvNVX_from_IV { my $h = shift; nvof($h->{iv}) }

# The locale axis: grok_number_flags and my_atof3 accept the LC_NUMERIC radix (PL_numeric_radix_sv) in addition to '.'
# while IN_LC(LC_NUMERIC) is true; nothing else in the conversion chain consults the locale.  $RADIX is the radix in
# force; Harness::WithRadix runs code under another.
our $RADIX = '.';
sub Perl::Conformance::Model::ValueFlags::Harness::WithRadix { my ($r, $code) = @_; local $RADIX = $r; $code->() }

# numeric.c Perl_grok_number_flags: 1 IN_UV, 2 NOT_INT, 4 INF, 8 NAN, 16 NEG, 32 GT_UV_MAX, 64 TRAILING.  Under a
# locale radix other than '.', a string that does not parse with '.' is parsed again with its first radix after the
# leading digits read as '.'.
sub grok_number_flags {
    my ($s, $trailing_ok) = @_;
    my @r = grok_number_dot($s, $trailing_ok);
    return @r if $RADIX eq '.' || $r[0];
    (my $v = $s) =~ s/^([ \t\n\r\f\x0b]*[+-]?[0-9]*)\Q$RADIX\E/$1./;
    return grok_number_dot($v, $trailing_ok);
}

# The parse of Perl_grok_number_flags with '.' as the radix.
sub grok_number_dot {
    my ($s, $trailing_ok) = @_;
    my $nt = 0;
    my $val = 0;
    my $neg = 0;

    # memEQs(pv, len, "0 but true") is tested before the general parse and returns IS_NUMBER_IN_UV with value 0.
    return (1, 0, 0) if $s eq "0 but true";
    my $t = $s;
    $t =~ s/^[ \t\n\r\f\x0b]+//;
    return (0, 0, 0) if $t eq '';
    if ($t =~ s/^-//) { $neg = 1; $nt = 16 } elsif ($t =~ s/^\+//) { }
    if ($t =~ /^[0-9]/) {
        $t =~ s/^([0-9]+)//;
        my $d = $1;
        if (length($d) > 20 || (length($d) == 20 && $d gt "18446744073709551615")) { $nt |= 32 }
        else { $nt |= 1; $val = 0 + $d; return ($nt, $val, $neg) if $t eq '' }
        if ($t =~ s/^\.//) { $nt |= 2; $t =~ s/^[0-9]*// }
    }
    elsif ($t =~ s/^\.//) {
        $nt |= 2 | 1;
        if ($t =~ s/^[0-9]+//) { $val = 0 } else { return (0, 0, 0) }
    }
    else {
        if ($t =~ /^(inf(?:inity)?|nan)(.*)\z/is) {
            my ($w, $rest) = ($1, $2);
            my $isnan = lc(substr($w, 0, 3)) eq 'nan';
            if ($rest !~ /^\s*\z/) { return $trailing_ok ? ($nt | ($isnan ? 8 : 4) | 64, 0, $neg) : (0, 0, 0) }
            return $isnan ? (8, 0, 0) : (4 | $nt, 0, $neg);
        }
        return (0, 0, 0);
    }
    if ($t =~ /^[eE]/) {
        if ($t =~ s/^[eE][+-]?[0-9]+//) { $nt &= 16; $nt |= 2 }
        else { return $trailing_ok ? ($nt | 64, $val, $neg) : (0, 0, 0) }
    }
    if ($t !~ /^[ \t\n\r\f\x0b]*\z/) { return $trailing_ok ? ($nt | 64, $val, $neg) : (0, 0, 0) }
    return ($nt, $val, $neg);
}

sub looks_like_number { my ($nt) = grok_number_flags($_[0]); $nt != 0 }

# numeric.c Perl_my_atof3 (prefix parse, no hex/underscore); under a locale radix other than '.', the first radix after
# the leading digits reads as '.'.
sub my_atof3 {
    my $s = shift;
    if ($RADIX ne '.') { $s =~ s/^([ \t\n\r\f\x0b]*[+-]?[0-9]*)\Q$RADIX\E/$1./ }
    my $t = $s;
    $t =~ s/^[ \t\n\r\f\x0b]+//;
    my $neg = 0;
    $neg = ($1 eq '-') if $t =~ s/^([+-])//;
    my $v;
    if ($t =~ /^inf/i) { $v = $INF }
    elsif ($t =~ /^nan/i) { $v = $NAN }
    elsif ($t =~ /^([0-9]*\.?[0-9]*)([eE][+-]?[0-9]+)?/ && length($1) && $1 ne '.') {
        my $m = $1;
        my $e = $2 // '';
        $m = "0$m" if $m =~ /^\./;
        $m .= "0" if $m =~ /\.\z/;
        $v = (0 + $m) * (length $e ? 10**(0 + substr($e, 1)) : 1);
        $v = 0.0 + "${m}${e}";
    }
    else { $v = 0.0 }
    return nvof($neg ? -$v : $v);
}

# ---------------- the body: SvTYPE ----------------

# SvTYPE, set at sv_upgrade's trigger sites and nowhere else.  Perl_sv_upgrade (sv.c) climbs NULL -> IV -> NV -> PV ->
# PVIV -> PVNV -> PVMG and keeps the slots a body already has: from IV a request for PV becomes PVIV, from NV a request
# for PV or PVIV becomes PVNV; an NV body asked for IV becomes IV (the documented special case in sv_upgrade).  Sites:
#   sv_setiv:  NULL/NV -> IV, PV -> PVIV            sv_setnv, sv_setuv: NULL/IV -> NV, PV/PVIV -> PVNV
#   sv_setpvn / sv_setpvn_fresh / sv_pvn_force_flags: SvUPGRADE(sv, SVt_PV)   (bumped by the rule above)
#   sv_setsv_flags: the destination climbs to the source's rung (case SVt_IV: NV/PV dsv -> PVIV; case SVt_NV: NULL/IV
#     -> NV)
#   sv_2nv_flags: < NV -> NV; a string body < PVNV -> PVNV      S_sv_2iuv_common: an NV body -> PVNV; a string body ->
#     PVIV
#   sv_2pv_flags: IV -> PVIV, NV -> PVNV, undef -> PV (SvUPGRADE precedes the undef test)
#   pp_undef, sv_force_normal_flags: no change (the body is kept; only its buffer or share goes)
my %RUNG = (NULL => 0, IV => 1, NV => 2, PV => 3, PVIV => 4, PVNV => 5, PVMG => 6);

sub upgrade {
    my ($h, $want) = @_;
    my $t = $h->{type} // 'NULL';
    return $h->{type} = 'IV' if $t eq 'NV' && $want eq 'IV';
    return if $RUNG{$want} <= $RUNG{$t};

    # sv_upgrade keeps the slots a body already has: an IV body asked for NV becomes PVNV.
    if ($t eq "IV" && $want eq "NV") { $want = "PVNV" }
    if ($t eq "IV" && $want eq "PV") { $want = "PVIV" }
    if ($t eq "NV" && ($want eq "PV" || $want eq "PVIV")) { $want = "PVNV" }
    if ($t eq "PVIV" && $want eq "NV") { $want = "PVNV" }
    if ($t eq "PV" && $want eq "NV") { $want = "PVNV" }
    $h->{type} = $want;
}

sub body_type {
    my $h = shift;
    return $h->{type}
        // ($h->{kind} eq 'S' ? 'PV' : $h->{kind} eq 'I' ? 'IV' : $h->{kind} eq 'N' ? 'NV' : $h->{kind} eq 'R' ? 'IV'
            : 'NULL');
}

# ---------------- the buffer: SvLEN, OOK, copy-on-write ----------------

# SvLEN is a pure function of the source on this build (Config: usemymalloc='n', d_malloc_good_size='undef',
# d_malloc_size='undef' on both 5.38.2 and 5.44.0), so PERL_UNWARANTED_CHUMMINESS_WITH_MALLOC is not defined and sv_grow
# stores the length it computed.  sv_setsv_flags's copy-on-write decision reads SvCUR and SvLEN, so the model carries
# len (SvLEN) on every holder with a buffer.
sub expected_size { my $n = shift; $n > 16 ? (($n + 7) & ~7) : 16 }

# Perl_sv_grow (sv.c): SvROK -> sv_unref; SvOOK -> sv_backoff; SvIsCOW -> S_sv_uncow; newlen++ (unless MEM_SIZE_MAX);
# if newlen > SvLEN: minlen = SvCUR + (SvCUR >> PERL_STRLEN_EXPAND_SHIFT [2]) + PERL_STRLEN_NEW_MIN [16 on 64-bit];
# newlen = max(newlen, minlen); an existing buffer is rounded by PERL_STRLEN_ROUNDUP (quantum Size_t_size 8), a first
# allocation by expected_size (perl.h: n > 16 ? round up to PTRSIZE : 16); SvLEN = newlen.
sub sv_grow {
    my ($h, $newlen) = @_;
    sv_backoff($h);
    uncow($h) if $h->{cow};
    my $cur = length($h->{pv} // '');
    my $len = $h->{len} // 0;
    $newlen++;
    if ($newlen > $len) {
        my $minlen = $cur + ($cur >> 2) + 16;
        $newlen = $minlen if $newlen < $minlen;
        $newlen = $len ? (($newlen + 7) & ~7) : expected_size($newlen);
        $h->{len} = $newlen;
    }
}

# SvGROW(sv, n) (sv.h) calls sv_grow only when SvLEN < n.  Perl_sv_grow_fresh: newlen++, floor PERL_STRLEN_NEW_MIN, no
# roundup.
sub SvGROW { my ($h, $n) = @_; sv_grow($h, $n) if ($h->{len} // 0) < $n }

# S_sv_uncow (sv.c), exactly: SvIsCOW_off; if the buffer has a length and CowREFCNT != 0, decrement it and copy_over; if
# CowREFCNT == 0 the SV is the sole owner and KEEPS the buffer (SvLEN unchanged); copy_over sets SvPVX NULL, SvCUR 0,
# SvLEN 0 and then SvGROW(sv, cur + 1): inside Perl_sv_grow, newlen = cur + 2 after the NUL increment, minlen is
# computed from the now-zero SvCUR (0 + 0 + PERL_STRLEN_NEW_MIN = 16), newlen = max(cur + 2, 16), and with SvLEN 0 the
# first-allocation arm applies expected_size (round up to 8 above 16).  A 2-byte string therefore gets 16, a 36-byte one
# 40.  The model keeps cow_refcnt: a literal share starts at 1 (the constant holds the other reference); a copy-on-write
# sv_setsv adds 1.  copy_over also undoes an OOK offset (sv_backoff).
sub uncow {
    my $h = shift;
    return unless $h->{cow};
    $h->{cow} = 0;
    if ($h->{kind} eq 'S') {
        my $rc = $h->{cow_refcnt} // 0;
        if ($rc != 0) {
            $h->{cow_refcnt} = $rc - 1;
            my $cur = length($h->{pv});
            my $newlen = $cur + 2;
            $newlen = 16 if $newlen < 16;
            $h->{len} = expected_size($newlen);
        }
    }
    $h->{ook} = 0;
}

# sv_setiv, sv_setnv, sv_set_undef (sv.c) begin with SV_CHECK_THINKFIRST_COW_DROP(sv): a copy-on-write buffer is DROPPED
# (sv_force_normal_flags with SV_COW_DROP_PV: SvPV NULL, SvLEN 0), a private buffer is kept; with no buffer left, no OOK
# offset remains either.
sub cow_drop {
    my $h = shift;
    if ($h->{cow}) { $h->{cow} = 0; $h->{cow_refcnt} = 0; $h->{len} = 0; $h->{pv} = '' }
    $h->{ook} = 0 if $h->{cow} == 0 && !$h->{len};
}

# sv_chop (sv.c): substr($x, 0, n, "") on a string advances PVX by n and records the offset before the buffer
# (SvOOK_on); Devel::Peek reports LEN reduced by the offset.  sv_backoff (called by Perl_sv_grow before growing, and by
# S_sv_uncow's copy_over, pp_undef and the plain-copy arm) restores PVX and LEN and clears OOK.
sub sv_chop {
    my ($h, $ctx, $n) = @_;
    $n //= 1;
    sv_pvn_force_flags($h, $ctx);
    uncow($h) if $h->{cow};
    my $take = $n > length($h->{pv}) ? length($h->{pv}) : $n;
    substr($h->{pv}, 0, $take, '');
    $h->{ook} = ($h->{ook} // 0) + $take;
    $h->{len} = ($h->{len} // 0) - $take;
    @$h{qw(int_form num_form is_uv stringified)} = (0, 0, 0, 0);
}

sub sv_backoff { my $h = shift; if ($h->{ook}) { $h->{len} += $h->{ook}; $h->{ook} = 0 } }

# ---------------- sv.c: numeric conversion ----------------

# sv.c S_sv_setnv
sub sv_setnv {
    my ($h, $nt) = @_;
    my $pok = ($h->{kind} eq 'S');
    my $nok = 0;
    if ($nt & 4) { $h->{nv} = ($nt & 16) ? -$INF : $INF; $nok = 1 }
    elsif ($nt & 8) { $h->{nv} = $NAN; $nok = 1 }
    elsif ($pok) { $h->{nv} = my_atof3($h->{pv}) }

    # SvNOK_only, then SvPOK_on if pok
    if ($nok) { @$h{qw(int_form is_uv utf8 stringified)} = (0, 0, 0, 0); $h->{num_form} = 2; $h->{kind} = 'S' if $pok }
}

# sv.c S_sv_2iuv_common, label got_nv (fill IV/UV slot from the NV slot)
sub got_nv {
    my $h = shift;
    my $nv = $h->{nv};
    $h->{int_form} = 1 if $h->{int_form} < 1;
    if ($nv < $TWO63) {
        $h->{iv} = cast_iv($nv);
        $h->{is_uv} = 0;
        $h->{int_form} = 2
            if ($nv == $h->{iv} && -($TWO53 - 1) <= $h->{iv} && $h->{iv} <= $TWO53 - 1 && $h->{num_form} == 2);
    }
    else {
        $h->{iv} = cast_uv($nv);
        $h->{is_uv} = 1;
        $h->{int_form} = 2 if ($nv == $h->{iv} && $TWO53 > $h->{iv} && $h->{num_form} == 2);
    }
}

# sv.c S_sv_2iuv_non_preserve
sub sv_2iuv_non_preserve {
    my $h = shift;
    my $nv = $h->{nv};
    if ($nv < $IV_MIN) { @$h{qw(int_form num_form iv is_uv)} = (1, 2, $IV_MIN, 0); return }
    if ($nv > $TWO64) { @$h{qw(int_form num_form iv is_uv)} = (1, 2, $UV_MAX, 1); return }
    $h->{int_form} = 1;
    $h->{num_form} = 2;
    if ($nv < $TWO63) { $h->{iv} = cast_iv($nv); $h->{is_uv} = 0; $h->{int_form} = 2 if $nv == $h->{iv}; return }
    $h->{is_uv} = 1;
    $h->{iv} = cast_uv($nv);
    if ($h->{iv} != $UV_MAX && $nv == $h->{iv}) { $h->{int_form} = 2 }
}

# sv.c S_sv_2iuv_common (returns 1 for the undef case, as the C returns TRUE)
sub sv_2iuv_common {
    my ($h, $ctx) = @_;
    if ($h->{num_form}) { got_nv($h); return 0 }
    if ($h->{kind} ne 'S') { $ctx->{warn}->($h); return 1 }
    my $s = $h->{pv};
    if (length($s) == 1 && $s =~ /^[0-9]$/) { $h->{iv} = 0 + $s; $h->{is_uv} = 0; $h->{int_form} = 2; return 0 }
    my ($nt, $value, $neg) = grok_number_flags($s);
    $h->{int_form} = 2 if ($nt & 3) == 1;
    if ($nt & 12) { sv_setnv($h, $nt); got_nv($h); return 0 }
    if ($nt & 1) {
        $h->{int_form} = 1 if $h->{int_form} < 1;
        if (!$neg) { $h->{iv} = $value; $h->{is_uv} = $value > $IV_MAX ? 1 : 0 }
        elsif ($value <= $ABS_IV_MIN) { $h->{iv} = -$value; $h->{is_uv} = 0 }
        else { @$h{qw(num_form int_form nv iv is_uv)} = (2, 1, nvof(-$value), $IV_MIN, 0) }
    }
    if (($nt & 3) != 1) {
        sv_setnv($h, $nt);
        $ctx->{warn}->($h) if $nt == 0;
        if (($nt & 3) == 3) { $h->{num_form} = 2 }
        else {
            my $nv = $h->{nv};
            if ($TWO53 > cast_uv(abs($nv))) {
                $h->{int_form} = 1 if $h->{int_form} < 1;
                $h->{num_form} = 2;
                $h->{iv} = cast_iv($nv);
                $h->{is_uv} = 0;
                $h->{int_form} = 2 if $nv == $h->{iv};
            }
            else { sv_2iuv_non_preserve($h) }
        }
        if ($nt == 0) { $h->{int_form} = 1 if $h->{int_form} > 1; $h->{num_form} = 1 if $h->{num_form} > 1 }
    }
    return 0;
}

# sv.c Perl_sv_2iv_flags / Perl_sv_2uv_flags.  The body climbs first: a string to PVIV, an NV body to PVNV, anything
# else to IV.
sub sv_2iv_flags {
    my ($h, $ctx) = @_;
    upgrade($h, $h->{kind} eq 'S' ? 'PVIV' : $h->{kind} eq 'N' ? 'PVNV' : 'IV');
    return 'ADDR' if $h->{kind} eq 'R';
    if (!$h->{int_form}) { return 0 if sv_2iuv_common($h, $ctx) }
    return $h->{iv};
}

# sv.c Perl_sv_2nv_flags.  The body climbs first: a string to PVNV, anything else to NV.
sub sv_2nv_flags {
    my ($h, $ctx) = @_;
    upgrade($h, $h->{kind} eq 'S' ? 'PVNV' : 'NV');
    return 'ADDR' if $h->{kind} eq 'R';
    return $h->{nv} if $h->{num_form};
    if ($h->{int_form}) {
        $h->{nv} = SvNVX_from_IV($h);
        my $ok = $h->{int_form} == 2
            && ($h->{is_uv} ? ($h->{iv} != $UV_MAX && $h->{iv} == cast_uv($h->{nv})) : ($h->{iv} == cast_iv($h->{nv})));
        $h->{num_form} = $ok ? 2 : 1;
        return $h->{nv};
    }
    if ($h->{kind} ne 'S') { $ctx->{warn}->($h); return 0.0 }
    my ($nt, $value, $neg) = grok_number_flags($h->{pv});
    $ctx->{warn}->($h) if $nt == 0;

    # W1/W2 window: perl reads the freed PV (crash or garbage); the design redispatches on the current holder kind, no
    # further warning.
    if ($h->{kind} ne "S") {
        die "UB: NV path reads the PV of a scalar the handler made non-string\n" unless $DESIGN_DEFINED;
        return sv_2nv_flags($h, { warn => sub { } });
    }
    my $nv = $h->{nv} = my_atof3($h->{pv});
    if ($TWO53 > cast_uv(abs($nv))) { $h->{num_form} = 2 }
    elsif (!($nt & 1)) { $h->{num_form} = 2 }
    else {
        if ($neg && $value > $ABS_IV_MIN) { $h->{num_form} = 2 }
        else {
            $h->{num_form} = 1;
            $h->{int_form} = 1;
            if ($neg) { $h->{iv} = -$value; $h->{is_uv} = 0 }
            elsif ($value <= $IV_MAX) { $h->{iv} = $value; $h->{is_uv} = 0 }
            else { $h->{iv} = $value; $h->{is_uv} = 1 }
            if (!($nt & 2)) {
                if ($nv < $TWO63) { $h->{num_form} = 2 if $h->{iv} == cast_iv($nv); $h->{int_form} = 2 }
                else {
                    my $nv_as_uv = cast_uv($nv);
                    $h->{num_form} = 2 if ($value == $nv_as_uv && $h->{iv} != $UV_MAX);
                    $h->{int_form} = 2;
                }
            }
        }
    }
    if ($nt == 0) { $h->{int_form} = 1 if $h->{int_form} > 1; $h->{num_form} = 1 if $h->{num_form} > 1 }
    return $nv;
}

sub uiv_2buf { my $h = shift; "$h->{iv}" }

sub sv_2pv_flags_nv {
    my $h = shift;
    my $v = $h->{nv};
    return "Inf" if $v == $INF;
    return "-Inf" if $v == -$INF;
    return "NaN" if isnan($v);
    my $r = sprintf("%.15g", $v);
    return $r;
}

# sv.c Perl_sv_2pv_flags (5.38 dispatch form; 5.44 requires public IOK, which coincides on every state reached here).
# A string is returned as is, with no buffer work.  Otherwise SvUPGRADE runs first -- IV -> PVIV, NV -> PVNV, an undef
# holder to PV even though nothing is written -- and the string form is written into the scalar's own buffer: IV/UV via
# uiv_2buf then SvGROW_mutable(sv, len + 1); NV == 0.0 -> SvGROW_mutable(sv, 2); Inf/NaN -> SvGROW_mutable(sv, 5
# ["-Inf\0"]) then S_infnan_2pv; other NV -> size = 1 + 1 + NV_DIG + 1 + 1 + 5 + 1 = 25 -> SvGROW_mutable(sv, 25).  The
# buffer stays on the holder (the stale unflagged PV of the B-only rows).  The infnan branches call SvPOKp_on; the
# finite NV branch never caches (sv.c:3247).
sub sv_2pv_flags {
    my ($h, $ctx) = @_;
    return $h->{pv} if $h->{kind} eq 'S';
    upgrade($h, $h->{kind} eq 'I' || $h->{int_form} == 2 ? 'PVIV'
              : $h->{kind} eq 'N' || $h->{num_form}      ? 'PVNV'
              :                                            'PV');
    my $r;
    if ($h->{int_form} == 2 || ($h->{int_form} && !$h->{num_form})) { $h->{stringified} = 1; $r = uiv_2buf($h) }
    elsif ($h->{num_form} == 2) {
        $h->{stringified} = 1 if isnan($h->{nv}) || abs($h->{nv}) == $INF;
        $r = sv_2pv_flags_nv($h);
    }
    elsif ($h->{kind} eq 'R') { $r = 'ADDR' }
    else { $ctx->{warn}->($h); $r = "" }
    return $r if $h->{kind} eq "S";

    # sv_2pv_flags tests SvIOK before SvNOK; the grow sees the OLD SvCUR.
    if ($h->{int_form} == 2 || ($h->{kind} eq "I")) { SvGROW($h, length($r) + 1) }
    elsif ($h->{num_form} || $h->{kind} eq "N") {
        my $v = $h->{nv};
        SvGROW($h, $v == 0 ? 2 : ($v != $v || $v == $INF || $v == -$INF) ? 5 : 25);
    }

    # Then the string form sits in the buffer: SvCUR is its length (the stale CUR of the B rows; undef leaves the buffer
    # alone).
    $h->{pv} = $r if $h->{kind} ne "U";
    return $r;
}

# sv.c Perl_sv_inc_nomg
sub SvIOK_only { my $h = shift; @$h{qw(kind num_form stringified utf8 is_uv)} = ('I', 0, 0, 0, 0); $h->{int_form} = 2 }
sub SvNOK_only { my $h = shift; @$h{qw(kind int_form stringified utf8 is_uv)} = ('N', 0, 0, 0, 0); $h->{num_form} = 2 }

# On a string with an OOK offset the buffer is normalized (sv_backoff) before the numeric slot is set (observed; the
# call site is not yet cited).  SvTHINKFIRST -> sv_force_normal_flags un-COWs.
sub sv_inc_nomg {
    my ($h, $ctx) = @_;
    sv_backoff($h);
    my $old = { %$h };
    uncow($h);
    if ($h->{num_form} && !$h->{int_form}) { sv_2iv_flags($h, $ctx) }
    if ($h->{int_form} == 2 || ($h->{int_form} && !$h->{num_form})) { return sv_inc_nomg_integer($h) }
    if ($h->{num_form}) { my $was = $h->{nv}; SvNOK_only($h); $h->{nv} = $was + 1.0; return }
    if ($h->{kind} ne 'S' || $h->{pv} eq '') { SvIOK_only($h); $h->{iv} = 1; return }
    if ($h->{pv} =~ /^[a-zA-Z]*[0-9]*\z/) { my $s = $h->{pv}; $s++; $h->{pv} = $s; return }
    my ($nt) = grok_number_flags($h->{pv}, 1);
    if ($nt && !($nt & 4)) {
        sv_2iv_flags($h, $ctx);
        return sv_inc_nomg_integer($h) if $h->{int_form} == 2;
        if ($old->{num_form}) { my $was = $h->{nv}; SvNOK_only($h); $h->{nv} = $was + 1.0; return }
    }
    my $nv = my_atof3($h->{pv}) + 1.0;
    SvNOK_only($h);
    $h->{nv} = $nv;
}

sub sv_inc_nomg_integer {
    my $h = shift;
    if ($h->{is_uv}) {
        if ($h->{iv} == $UV_MAX) { SvNOK_only($h); $h->{nv} = $TWO64; return }
        SvIOK_only($h);
        $h->{is_uv} = 1;
        $h->{iv}++;
        return;
    }
    if ($h->{iv} == $IV_MAX) { SvIOK_only($h); $h->{is_uv} = 1; $h->{iv} = $IV_MAX + 1; return }
    SvIOK_only($h);
    $h->{iv}++;
}

# sv.c Perl_sv_dec_nomg; an OOK offset is normalized first, as for sv_inc_nomg.
sub sv_dec_nomg {
    my ($h, $ctx) = @_;
    sv_backoff($h);
    my $old = { %$h };
    uncow($h);
    if ($h->{int_form} == 2 || ($h->{int_form} && !$h->{num_form})) { return sv_dec_nomg_integer($h) }
    if ($h->{num_form}) { my $was = $h->{nv}; SvNOK_only($h); $h->{nv} = $was - 1.0; return }
    if ($h->{kind} ne 'S') { SvIOK_only($h); $h->{iv} = -1; return }
    my ($nt) = grok_number_flags($h->{pv});
    if ($nt && !($nt & 4)) {
        sv_2iv_flags($h, $ctx);
        return sv_dec_nomg_integer($h) if $h->{int_form} == 2;
        if ($old->{num_form}) { my $was = $h->{nv}; SvNOK_only($h); $h->{nv} = $was - 1.0; return }
    }
    my $nv = my_atof3($h->{pv}) - 1.0;
    SvNOK_only($h);
    $h->{nv} = $nv;
}

sub sv_dec_nomg_integer {
    my $h = shift;
    if ($h->{is_uv}) {
        if ($h->{iv} == 0) { SvIOK_only($h); $h->{iv} = -1; return }
        SvIOK_only($h);
        $h->{is_uv} = 1;
        $h->{iv}--;
        return;
    }
    if ($h->{iv} == $IV_MIN) { SvNOK_only($h); $h->{nv} = $IV_MIN - 1.0; return }
    SvIOK_only($h);
    $h->{iv}--;
}

# sv.h SvIV_please_nomg; the body climbs as for sv_2iv_flags unless the holder is undef.
sub SvIV_please_nomg {
    my ($h, $ctx) = @_;
    upgrade($h, $h->{kind} eq 'S' ? 'PVIV' : $h->{kind} eq 'N' ? 'PVNV' : 'IV') if $h->{kind} ne 'U';
    sv_2iv_flags($h, $ctx) if !$h->{int_form} && ($h->{num_form} == 2 || $h->{kind} eq 'S');
    return $h->{int_form} == 2;
}

# ---------------- sv.c: copying and setting ----------------

# Perl_sv_setsv_flags (sv.c), the `sflags & SVp_POK` arm, in order:
#   1. swipe  -- S_SvPV_can_swipe_buf: source is SvTEMP with refcount 1, not COW, not shared-hek; the buffer moves and
#      the destination is not COW.  The harness copy op's source is never a temporary, so this arm is not taken there.
#   2. copy-on-write -- S_SvPV_shared_hkey_or_CoWable: a source already IsCOW shares when !len, or when
#      CHECK_COWBUF_THRESHOLD(cur,len) or SvLEN(dsv) < cur+1 (a fresh destination), and CowREFCNT !=
#      SV_COW_REFCNT_MAX; a plain source shares only when (sflags & CAN_COW_MASK) == CAN_COW_FLAGS (POK|pPOK and none
#      of ROK/FAKE/OOK/READONLY/PROTECT), CHECK_COW_THRESHOLD(cur,len) [(len-cur) < SV_COW_MAX_WASTE_THRESHOLD 80 and
#      len < 2*cur], cur+1 < len, and (CHECK_COWBUF_THRESHOLD or SvLEN(dsv) < cur+1).  Both SVs end IsCOW; the source's
#      CowREFCNT starts at 0.
#   3. plain copy -- SvGROW(dsv, cur+1); Move; the destination is not COW.
# Before any arm: SvFLAGS(dsv) |= sflags & (POK|pPOK|IOK|pIOK|IVisUV|NOK|pNOK|UTF8), so every value flag is carried.
sub sv_setsv_cowable {
    my ($src, $dst_len) = @_;
    my $cur = length($src->{pv});
    my $len = $src->{len} // 0;
    if ($src->{cow}) {
        return 1 if !$len;
        return 1 if $dst_len < $cur + 1;
        return ($cur >= 1250 && ($len - $cur) < 80 && $len < 2 * $cur);
    }
    return 0 if $src->{kind} ne 'S';
    return (($len - $cur) < 80 && $len < 2 * $cur && $cur + 1 < $len
        && ($dst_len < $cur + 1 || ($cur >= 1250 && ($len - $cur) < 80 && $len < 2 * $cur)));
}

# The destination keeps its own body type and climbs to the source's rung.  A plain copy into a fresh destination takes
# sv_grow_fresh(dsv, cur+1) (sv.c, the "Perl_sv_grow_fresh asserts that cur == 0" arm); otherwise SvGROW(dsv, cur+1).
sub sv_setsv_flags {
    my ($dst, $src, $dst_len) = @_;
    my $t = $dst->{type} // 'NULL';
    %$dst = (%$src);
    $dst_len //= 0;
    if ($src->{kind} eq 'S' && sv_setsv_cowable($src, $dst_len)) {
        if (!$src->{cow}) { $src->{cow} = 1; $src->{cow_refcnt} = 0 }
        $src->{cow_refcnt}++;
        $dst->{cow} = 1;
    }
    else {
        $dst->{cow} = 0;
        $dst->{cow_refcnt} = 0;
        if ($src->{kind} eq "S") {
            my $cur = length($dst->{pv});
            if ($dst_len == 0) { $dst->{len} = ($cur + 2 < 16 ? 16 : $cur + 2) }
            else { $dst->{len} = $dst_len; SvGROW($dst, $cur + 1) }
        }
    }
    $dst->{type} = $t;
    upgrade($dst, $src->{type} // body_type($src));
}

# sv_setiv / sv_setnv / sv_set_undef (sv.c): SvOOK_off (sv_backoff) and SV_CHECK_THINKFIRST_COW_DROP, then the slot is
# set or SvOK_off; the PV buffer and SvLEN stay on the body (the stale buffer of the B-only rows), and the CoWable
# destination test reads that SvLEN on the next assignment from a string.  The body keeps its type and climbs (sv_setiv
# to IV, sv_setnv to NV; sv_set_undef leaves it).
sub sv_set_undef {
    my $h = shift;
    my $t = $h->{type} // 'NULL';
    sv_backoff($h);
    cow_drop($h);
    my $len = $h->{len} // 0;
    my $pv = $h->{pv} // '';
    %$h = (%{ Perl::Conformance::Model::ValueFlags::Harness::undef() }, len => $len, pv => $pv);
    $h->{type} = $t;
}

# `$x = 10`, `$x = 3.5`: sv_setiv, sv_setnv as above.
sub Perl::Conformance::Model::ValueFlags::Harness::assign_integer {
    my $h = shift;
    my $t = $h->{type} // 'NULL';
    sv_backoff($h);
    cow_drop($h);
    my $len = $h->{len} // 0;
    my $pv = $h->{pv} // '';
    %$h = (%{ Perl::Conformance::Model::ValueFlags::Harness::integer(10) }, len => $len, pv => $pv);
    $h->{type} = $t;
    upgrade($h, 'IV');
}

sub Perl::Conformance::Model::ValueFlags::Harness::assign_number {
    my $h = shift;
    my $t = $h->{type} // 'NULL';
    sv_backoff($h);
    cow_drop($h);
    my $len = $h->{len} // 0;
    my $pv = $h->{pv} // '';
    %$h = (%{ Perl::Conformance::Model::ValueFlags::Harness::number(3.5) }, len => $len, pv => $pv);
    $h->{type} = $t;
    upgrade($h, 'NV');
}

# `$x = "10"`: sv_setsv_flags(holder, literal).  The literal is IsCOW (compile-time constant; its buffer is newSVpvn ->
# sv_grow_fresh, max(cur+2, 16)); for an IsCOW source S_SvPV_shared_hkey_or_CoWable shares only when the destination
# has no buffer big enough (SvLEN(dsv) < cur+1) or the string is at the COWBUF threshold (cur >= 1250) -- so a holder
# that already owns a buffer (a stale one from an earlier stringification included) takes the plain-copy arm, keeps its
# own LEN and is not COW; a holder with no buffer shares and becomes IsCOW.  Perl_sv_setsv_flags on the DESTINATION
# side: SV_CHECK_THINKFIRST_COW_DROP(dsv) runs before the source arms -- a destination that shares a buffer drops it
# (SvPV NULL, SvLEN 0), so the CoWable test SvLEN(dsv) < cur + 1 then holds and the incoming string is shared.  This is
# also the "holder already sharing an equal literal stays IsCOW" observation: it drops one share and takes another.  A
# destination that owns its buffer keeps it and takes the plain copy into it.  An OOK offset is undone first.
sub Perl::Conformance::Model::ValueFlags::Harness::assign_string {
    my $h = shift;
    my $t = $h->{type} // 'NULL';
    sv_backoff($h);
    cow_drop($h);
    my $lit = Perl::Conformance::Model::ValueFlags::Harness::string("10");
    my $dst_len = $h->{len} // 0;
    my %d;
    sv_setsv_flags(\%d, $lit, $dst_len);
    %$h = %d;
    $h->{type} = $t;
    upgrade($h, 'PV');
}

# pp_undef (pp.c), the scalar default arm: sv_force_normal_flags(sv, SV_COW_DROP_PV|SV_IMMEDIATE_UNREF), then for a
# body with a PV: SvPV_free, SvPV_set(sv, NULL), SvLEN_set(sv, 0), then SvOK_off -- `undef $x` FREES the buffer, unlike
# `$x = undef` (sv_set_undef), which keeps a private one.  The body keeps its type.
sub pp_undef {
    my $h = shift;
    my $t = $h->{type} // 'NULL';
    cow_drop($h);
    %$h = (%{ Perl::Conformance::Model::ValueFlags::Harness::undef() }, len => 0, pv => '');
    $h->{ook} = 0;
    $h->{type} = $t;
}

# Perl_sv_pvn_force_flags (sv.c): SvUPGRADE(sv, SVt_PV); SvTHINKFIRST -> sv_force_normal_flags(sv, 0) -> S_sv_uncow
# copy_over (a shared buffer is copied into a fresh allocation, expected_size(cur+2)); on a holder without a string,
# sv_2pv_flags writes the number's string into the holder's own buffer (sized there) and an undef holder gets SvGROW(sv,
# 1) -> the 16-byte first allocation (the `s = sv_2pv_flags` arm ends in a copy into the SV's buffer when the returned
# pointer is not SvPVX); it ends with SvPOK_only_UTF8.
sub sv_pvn_force_flags {
    my ($h, $ctx) = @_;
    upgrade($h, 'PV');
    uncow($h) if $h->{cow};
    my $was = $h->{kind};
    if ($h->{kind} ne 'S') { my $s = ($h->{kind} eq 'U') ? "" : sv_2pv_flags($h, $ctx); @$h{qw(kind pv)} = ('S', $s) }
    @$h{qw(int_form num_form is_uv stringified)} = (0, 0, 0, 0);
    $h->{cow} = 0;
    SvGROW($h, length($h->{pv}) + 1) if $was eq 'U' || ($h->{len} // 0) < length($h->{pv}) + 1;
}

# ---------------- the operations ----------------

# pp_hot.c pp_add with SvIV_please_nomg (sv.h:1538)
sub pp_add {
    my ($h, $ctx) = @_;
    if (!$h->{int_form} && ($h->{num_form} == 2 || $h->{kind} eq 'S')) {
        my $r = sv_2iv_flags($h, $ctx);
        return $r if $r eq 'ADDR';
    }
    if ($h->{int_form} == 2) { return 0 + $h->{iv} }
    my $r = sv_2nv_flags($h, $ctx);
    return $r if $r eq 'ADDR';
    return 0.0 + $r;
}

sub pp_bit_or {
    my ($h, $ctx) = @_;
    my $r = sv_2iv_flags($h, $ctx);
    return $r if $r eq 'ADDR';
    return $r | 0;
}

sub sv_vcatpvfn_flags_g {
    my ($h, $ctx) = @_;
    my $r = sv_2nv_flags($h, $ctx);
    return $r if $r eq 'ADDR';
    return sprintf('%g', $r);
}

# pp.c pp_bit_or without feature 'bitwise': numeric iff SvNIOKp on either side; the other operand is "" or 0
sub pp_bit_or_string_other {
    my ($h, $ctx) = @_;
    if ($h->{int_form} || $h->{num_form}) { sv_2iv_flags($h, $ctx) } else { sv_2pv_flags($h, $ctx) }
}

sub pp_sbit_or { my ($h, $ctx) = @_; sv_2pv_flags($h, $ctx) }

# pp_ctl.c pp_flop with RANGE_IS_NUMERIC; right operand is the string "3"
sub pp_flop {
    my ($h, $ctx) = @_;
    my $numeric = $h->{int_form} || $h->{num_form} || $h->{kind} ne 'S'
        || (looks_like_number($h->{pv}) && !(substr($h->{pv}, 0, 1) eq '0' && length($h->{pv}) > 1));
    if ($numeric) {
        sv_2nv_flags($h, $ctx) if $h->{int_form} != 2;
        sv_2iv_flags($h, $ctx);
    }
    else { sv_2pv_flags($h, $ctx) }
}

# sv.c Perl_sv_utf8_upgrade_flags_grow -> SvPV_force_flags -> Perl_sv_pvn_force_flags, which ends with SvPOK_only_UTF8.
# It returns early for an undef scalar, and `if (SvUTF8(sv)) return SvCUR(sv)` precedes every un-COW or grow; then
# S_sv_uncow, and the re-encoded buffer.
sub sv_utf8_upgrade_flags_grow {
    my ($h, $ctx) = @_;
    return if $h->{kind} eq "U";
    return if $h->{kind} eq "S" && $h->{utf8};
    if ($h->{kind} ne "S") {
        my $s = sv_2pv_flags($h, $ctx);
        @$h{qw(kind pv int_form num_form is_uv stringified)} = ("S", $s, 0, 0, 0, 0);
    }
    my $need = length($h->{pv}) + 1;
    uncow($h) if $h->{cow};
    SvGROW($h, $need);
    $h->{utf8} = 1;
}

# pp_hot.c pp_multiconcat append: SvPV_force_nomg_nolen(targ) is a no-op only for SvPOK_pure_nogthink (sv_inline.h
# Perl_SvPV_helper): public POK only and not THINKFIRST (COW); Perl_sv_pvn_force_flags ends with SvPOK_only_UTF8.  Then
# SvPV_force_nomg un-COWs a shared target, and SvGROW(targ, targ_len + append + 1).
sub pp_multiconcat {
    my ($h, $ctx, $rhs) = @_;
    $rhs //= "x";
    my $pure = ($h->{kind} eq "S" && $h->{int_form} != 2 && $h->{num_form} != 2 && !$h->{cow});
    if (!$pure) {
        my $s = ($h->{kind} eq "U") ? "" : sv_2pv_flags($h, $ctx);
        @$h{qw(kind pv int_form num_form is_uv stringified)} = ("S", $s, 0, 0, 0, 0);
    }
    uncow($h) if $h->{cow};
    my $grow = 1 + length($h->{pv}) + length($rhs);
    sv_grow($h, $grow) if ($h->{len} // 0) < $grow;
    $h->{pv} .= $rhs;
}

# pp.c pp_int: SvIV_nomg, then SvNV_nomg unless SvIOK; pp_abs has the same shape.
sub pp_int {
    my ($h, $ctx) = @_;
    my $r = sv_2iv_flags($h, $ctx);
    return if $h->{kind} eq 'U';
    sv_2nv_flags($h, $ctx) if $h->{int_form} != 2;
}

sub pp_abs { my ($h, $ctx) = @_; pp_int($h, $ctx) }

# pp.c pp_negate / S_negate_string
sub pp_negate {
    my ($h, $ctx) = @_;
    if ($h->{kind} eq 'S' && !($h->{int_form} == 2 || $h->{num_form} == 2)) {
        my $s = $h->{pv};
        return if $s =~ /^[A-Za-z_]/;
        return if $s =~ /^\+/ || ($s =~ /^-/ && !looks_like_number($s));
    }
    my $its_an_int = $h->{int_form} == 2;

    # "else if (SvPOKp(sv) && SvIV_please_nomg(sv)) goto oops_its_an_int"
    if (!$its_an_int && !(($h->{int_form} || $h->{num_form}) && ($h->{int_form} == 2 || $h->{num_form} == 2
        || $h->{kind} ne 'S')) && $h->{kind} eq 'S') { $its_an_int = SvIV_please_nomg($h, $ctx) }

    # A UV above ABS_IV_MIN drops through to the NV negation.
    if ($its_an_int) { return unless $h->{is_uv} && $h->{iv} > $ABS_IV_MIN; sv_2nv_flags($h, $ctx); return }
    if (($h->{int_form} || $h->{num_form}) && ($h->{int_form} == 2 || $h->{num_form} == 2 || $h->{kind} ne 'S')) {
        sv_2nv_flags($h, $ctx);
        return;
    }
    sv_2nv_flags($h, $ctx);
}

# pp_hot.c pp_eq / pp.c do_ncmp with a public-IOK partner; with the partner 1.5, SvIV_please fails: NV compare only.
sub do_ncmp { my ($h, $ctx) = @_; return if SvIV_please_nomg($h, $ctx); sv_2nv_flags($h, $ctx) }
sub do_ncmp_nv_partner { my ($h, $ctx) = @_; sv_2nv_flags($h, $ctx) }
sub pp_null { }

# isinfnan_nvx: SvNOKp and Perl_isinfnan(SvNVX).  numeric.c Perl_isinfnansv: SvNOKp -> isinfnan(SvNVX); SvIOKp -> false;
# else grok_infnan on the PV (no conversion), which accepts a prefix (trailing text only sets IS_NUMBER_TRAILING).  The
# croak message in pp_chr / S_sv_check_infnan then evaluates SvNV, which is what caches NOK on the string.
sub isinfnan_nvx { my $h = shift; $h->{num_form} && (isnan($h->{nv}) || abs($h->{nv}) == $INF) }

sub isinfnansv {
    my ($h, $ctx) = @_;
    return 0 if $h->{kind} eq 'U';
    return (isnan($h->{nv}) || abs($h->{nv}) == $INF) if $h->{num_form};
    return 0 if $h->{int_form};
    return 0 if $h->{kind} ne 'S';
    return 0 unless $h->{pv} =~ /^[+-]?(?:inf|nan)/i;
    sv_2nv_flags($h, $ctx);
    return 1;
}

# pp.c pp_chr
sub pp_chr {
    my ($h, $ctx) = @_;
    die "croak\n" if isinfnansv($h, $ctx);
    if ($h->{int_form} && !$h->{is_uv} && $h->{iv} < 0) { return }
    if ($h->{num_form} || ($h->{kind} ne 'U' && !$h->{is_uv})) {
        my $nv = sv_2nv_flags($h, $ctx);
        return if $nv ne 'ADDR' && $nv < 0.0;
    }
    sv_2iv_flags($h, $ctx);
}

# pp_pack.c S_sv_check_infnan via SvIV_no_inf
sub pp_pack_j { my ($h, $ctx) = @_; die "croak\n" if isinfnansv($h, $ctx); sv_2iv_flags($h, $ctx) }

# sv.c sv_vcatpvfn_flags:13966 isinfnansv, then the NV is formatted
sub sv_vcatpvfn_flags_d { my ($h, $ctx) = @_; return if isinfnansv($h, $ctx); sv_2iv_flags($h, $ctx) }

# pp_pack.c case 'w': SvNV_nomg, then SvUV_nomg when SvIOK or the NV fits a UV
sub pp_pack_w {
    my ($h, $ctx) = @_;
    my $nv = sv_2nv_flags($h, $ctx);
    return if $nv eq 'ADDR';
    die "croak\n" if $nv < 0;
    sv_2iv_flags($h, $ctx) if $h->{int_form} == 2 || $nv < $TWO64;
}

# pp_sort.c pp_sort: pre-numify elements that are not SvNSIOK (NOK, or IOK-but-not-IsUV); pp.c do_ncmp then compares
# integers when SvIV_please succeeds on both, else SvNV_nomg both.  `sort { $a <=> $b } ($x, 0)` assigned to my @s:
# each element reaches @s through sv_setsv_flags (pp_aassign), so the copy-on-write arm applies to the holder and @s
# lives to the block's end (its share stays counted).
sub pp_sort_numeric {
    my ($h, $ctx) = @_;
    sv_2nv_flags($h, $ctx) unless $h->{num_form} == 2 || ($h->{int_form} == 2 && !$h->{is_uv});
    my $r;
    if (SvIV_please_nomg($h, $ctx)) { $r = undef } else { $r = sv_2nv_flags($h, $ctx) }
    if ($h->{kind} eq 'S') { my %t; sv_setsv_flags(\%t, $h, 0) }
    return $r;
}

# pp.c pp_length
sub pp_length { my ($h, $ctx) = @_; return if $h->{kind} eq 'U'; sv_2pv_flags($h, $ctx) }

# pp.c pp_complement, SvNIOKp decides
sub pp_complement {
    my ($h, $ctx) = @_;
    if ($h->{int_form} || $h->{num_form}) { sv_2iv_flags($h, $ctx) } else { sv_2pv_flags($h, $ctx) }
}

# sv.c sv_insert_flags (sv.c:7075, 7083): after SvPV_force, SvGROW(bigstr, offset+len+1) when the replaced span reaches
# past SvCUR, then big = SvGROW(bigstr, SvCUR + i + 1) where i = littlelen - len (0 for a one-byte replacement of one
# byte).
sub sv_insert_flags {
    my ($h, $ctx) = @_;
    sv_pvn_force_flags($h, $ctx);
    my $cur = length($h->{pv});
    SvGROW($h, 0 + 1 + 1) if 1 > $cur;
    SvGROW($h, length($h->{pv}) + 0 + 1);
    sv_pvn_force_flags($h, $ctx);
    substr($h->{pv}, 0, 1, "y");
}

# doop.c do_vecset: SvPV_force, then SvGROW(sv, offset + len + 1) with offset 0 and len 1 for vec($x, 0, 8); SvPOK_only
# after utf8 downgrade.
sub do_vecset {
    my ($h, $ctx) = @_;
    sv_pvn_force_flags($h, $ctx);
    SvGROW($h, 0 + 1 + 1);
    sv_pvn_force_flags($h, $ctx);
    $h->{utf8} = 0;
    substr($h->{pv}, 0, 1, "A");
}

# pp_hot.c pp_subst, no match: SvPV_nomg only
sub pp_subst_nomatch { my ($h, $ctx) = @_; sv_2pv_flags($h, $ctx) }

# pp_hot.c pp_subst on a match (the copy path): dstr = newSVpvn_flags(orig, s - orig) -- a fresh SV sized by
# sv_grow_fresh (max(prefix+2, 16)); the replacement and the rest are appended by sv_catpvn (SvGROW(cur + n + 1) each,
# rounded on an existing buffer); at the end SvPV_free(TARG) and TARG takes dstr's buffer, CUR and LEN; SvPOK_only_UTF8.
# For s/./X/ the prefix is empty.  When the target is already a string and the constant replacement has the matched
# length, the substitution is done in place and the buffer and SvLEN are kept; the copy path (dstr) is taken otherwise.
# (An in-place rule for a POK target was tried and contradicted: a POK "10" in a 32-byte buffer takes the copy path, LEN
# 16; a numeric target with a 32-byte stale buffer keeps 32 -- the condition that selects the in-place path is not yet
# read from pp_subst; those rows stay open.)
sub pp_subst {
    my ($h, $ctx) = @_;
    my $before = ($h->{kind} eq "U") ? "" : ($h->{kind} eq "S") ? $h->{pv} : sv_2pv_flags({ %$h }, $ctx);
    my $s = ($h->{kind} eq 'U') ? "" : sv_2pv_flags($h, $ctx);
    my $r;
    if (length $s) { sv_pvn_force_flags($h, $ctx); $r = substr($h->{pv}, 0, 1, "X") }
    if ($h->{kind} eq 'S' && length($before)) {
        my %d = (kind => "S", pv => "", len => 16, cow => 0);
        SvGROW(\%d, length($d{pv}) + 1 + 1);
        $d{pv} .= "X";
        my $rest = substr($before, 1);
        SvGROW(\%d, length($d{pv}) + length($rest) + 1);
        $d{pv} .= $rest;
        $h->{len} = $d{len};
        $h->{cow} = 0;
        $h->{cow_refcnt} = 0;
    }
    return $r;
}

# doop.c do_trans, count only: SvPV_const
sub do_trans_count { my ($h, $ctx) = @_; sv_2pv_flags($h, $ctx) }

# pp.c S_do_chomp: SvPV, then SvPV_force + SvNIOK_off
sub do_chop {
    my ($h, $ctx) = @_;
    my $s = ($h->{kind} eq 'U') ? "" : sv_2pv_flags($h, $ctx);
    if (length $s) { my $was_utf8 = $h->{utf8}; sv_pvn_force_flags($h, $ctx); chop $h->{pv}; $h->{utf8} = $was_utf8 }
}

sub do_chomp { my ($h, $ctx) = @_; sv_2pv_flags($h, $ctx) unless $h->{kind} eq 'U' }

# pp.c pp_repeat: IOKp/NOKp used directly, else SvIV_nomg
sub pp_repeat_count { my ($h, $ctx) = @_; return if $h->{int_form} || $h->{num_form}; sv_2iv_flags($h, $ctx) }

# pp_hot.c pp_add fast path: if !((svl->sv_flags|svr->sv_flags) & (SVf_IVisUV|SVs_GMG)) and (flags = svl & svr) has
# SVf_IOK, the integer add happens with no conversion; else if it has SVf_NOK and both NVs are lossless as IVs,
# likewise; only otherwise does SvIV_please_nomg run on the operands.  The partner's public flags therefore decide
# whether the operand gets IOK cached.  $partner: {int_form=>2} for a public-IOK literal, {num_form=>2} for a public-NOK
# one.
sub pp_add_with_partner {
    my ($h, $ctx, $partner) = @_;
    my $both_iok = ($partner->{int_form} // 0) == 2 && $h->{int_form} == 2 && !$h->{is_uv};
    my $both_nok = ($partner->{num_form} // 0) == 2 && $h->{num_form} == 2;
    return 0 + $h->{iv} if $both_iok;
    return $h->{nv} if $both_nok;    # lossless or not, no conversion is performed on the operand
    return pp_add($h, $ctx);
}

# Partner-typed binary operators.  pp_add (pp_hot.c), pp_subtract and pp_multiply (pp.c) open with
#   if (!((svl->sv_flags|svr->sv_flags) & (SVf_IVisUV|SVs_GMG))) { U32 flags = svl->sv_flags & svr->sv_flags;
#     if (flags & SVf_IOK) { integer arithmetic } else if (flags & SVf_NOK) { lossless_NV_to_IV on both, else NV
#     arithmetic } }
# and pp_eq (pp_hot.c), pp_ne, pp_lt, pp_gt, pp_le, pp_ge (pp.c) with the same flags_and ternary before do_ncmp; on
# those paths neither operand is converted, so an operand's cached flags depend on the partner's public flags.
# pp_divide, pp_modulo, pp_pow, pp_ncmp and do_ncmp (pp.c) always run SvIV_please_nomg on both operands and are not
# partner-typed; pp_negate has no partner.
our %PARTNER_TYPED = map { $_ => 1 } qw(add subtract multiply eq ne lt gt le ge);

# Returns the operand after the op; $partner = {int_form=>2} or {num_form=>2}.
sub pp_add_partner_gate {
    my ($op, $h, $ctx, $partner) = @_;
    if ($PARTNER_TYPED{$op}) {
        return $h if ($partner->{int_form} // 0) == 2 && $h->{int_form} == 2 && !$h->{is_uv};
        return $h if ($partner->{num_form} // 0) == 2 && $h->{num_form} == 2;
    }
    SvIV_please_nomg($h, $ctx);
    return $h;
}

# ---------------- the harness's composite operations and projections ----------------

# The harness copy op: `my $y = $x` shares (CowREFCNT +1), `$x = $y` finds SvPVX(dsv) == SvPVX(ssv) (SvPV_free on a
# shared buffer only decrements CowREFCNT, then the share is re-taken), and $y lives to the block's end (one eval per
# block), so its share stays counted: CowREFCNT is one more than before the op, IsCOW is on, and the next un-COW copies
# (S_sv_uncow copy_over -> SvGROW(cur+1) with SvCUR 0 -> expected_size(cur+2)).
sub Perl::Conformance::Model::ValueFlags::Harness::CopyOp {
    my $h = shift;
    return unless $h->{kind} eq "S";
    my %y;
    my $rc0 = $h->{cow} ? ($h->{cow_refcnt} // 0) : 0;
    sv_setsv_flags(\%y, $h, 0);
    if ($h->{cow}) { $h->{cow_refcnt} = $rc0 + 1 }
}

# pp_repeat (pp.c, PP_wrapped(pp_repeat) +114/+128): sv_setsv_nomg(TARG, tmpstr) copies the holder into TARG -- the
# copy-on-write arm, so the holder becomes IsCOW -- then SvGROW(TARG, max) un-COWs TARG (its share is dropped again):
# the holder ends IsCOW with CowREFCNT back where it was.  A numeric holder is copied as a number: TARG stringifies, the
# holder is untouched.
sub Perl::Conformance::Model::ValueFlags::Harness::RepeatOp {
    my ($h, $ctx) = @_;
    if ($h->{kind} eq 'S') {
        my $rc0 = $h->{cow} ? ($h->{cow_refcnt} // 0) : 0;
        my %t;
        sv_setsv_flags(\%t, $h, 0);
        $h->{cow_refcnt} = $rc0 if $h->{cow};
    }
}

# `my @s = sort ($x, 1)`: like the numeric sort, each element reaches @s through sv_setsv_flags (pp_aassign) and @s
# lives to the block's end, so the holder's share stays counted.
sub Perl::Conformance::Model::ValueFlags::Harness::SortStrOp {
    my ($h, $ctx) = @_;
    my $r = sv_2pv_flags($h, $ctx);
    if ($h->{kind} eq 'S') { my %t; sv_setsv_flags(\%t, $h, 0) }
    return $r;
}

# pp_stringify (pp.c) uses sv_copypv_flags: a plain copy of the PV into TARG, no copy-on-write share (verified: `my $t =
# "$x"` leaves a non-COW holder non-COW on both perls).  Yet `my $t = "$x"` on a string holder leaves the holder IsCOW
# under the same length predicate as sv_setsv_flags (observed on both perls: shared for a 36-byte string in a 64-byte
# buffer, not for one in a larger buffer); the copy is therefore modeled as sv_setsv_flags's copy-on-write arm.  The
# op-tree path that makes pp_stringify's copy a sv_setsv (rather than sv_copypv) is not yet cited; a mismatch here that
# is not explained by the len approximation points at that path.
sub Perl::Conformance::Model::ValueFlags::Harness::StringifyOp {
    my ($h, $ctx) = @_;
    my $r = sv_2pv_flags($h, $ctx);
    if ($h->{kind} eq 'S') { my %t; sv_setsv_flags(\%t, $h, 0) }
    return $r;
}

# Prepares a start value for a lane; the body type is carried in the value itself.
sub Perl::Conformance::Model::ValueFlags::Harness::SeedBody { $_[0] }

# B::FLAGS projection
sub Perl::Conformance::Model::ValueFlags::Harness::FlagsProjection {
    my $h = shift;
    my @f;
    my $k = $h->{kind};
    push @f, 'POK', 'pPOK' if $k eq 'S';
    push @f, 'ROK' if $k eq 'R';
    push @f, 'IOK' if $h->{int_form} == 2;
    push @f, 'pIOK' if $h->{int_form} >= 1;
    push @f, 'NOK' if $h->{num_form} == 2;
    push @f, 'pNOK' if $h->{num_form} >= 1;
    push @f, 'pPOK' if $k ne 'S' && $h->{stringified};
    push @f, 'IsUV' if $h->{is_uv};
    push @f, 'UTF8' if $h->{utf8};
    push @f, 'IsCOW' if $h->{cow};
    my %o = (IOK => 0, NOK => 1, POK => 2, pIOK => 3, pNOK => 4, pPOK => 5, IsUV => 6, ROK => 7, UTF8 => 8, IsCOW => 9);
    my %s = map { $_ => 1 } @f;
    return join(",", sort { $o{$a} <=> $o{$b} } keys %s) || "-";
}

sub Perl::Conformance::Model::ValueFlags::Harness::Num {
    my $v = shift;
    return $v if $v eq 'ADDR';
    return sprintf("%.17g", $v);
}

# The model-side key: value flags | slots | stale buffer | body type | CowREFCNT | OOK offset -- the mirror of
# Perl::Conformance::Model::ValueFlags::Observe::key.  A non-string holder shows its buffer's CUR/LEN whenever either is
# nonzero, a CUR left behind by a freed buffer included.
sub Perl::Conformance::Model::ValueFlags::Harness::KeyTail {
    my $h = shift;
    my $b = ($h->{kind} ne 'S' && (($h->{len} // 0) || length($h->{pv} // '')))
        ? "|B:" . length($h->{pv} // '') . "/" . ($h->{len} // 0) : "";
    my $c = $h->{cow} ? "|C:" . ($h->{cow_refcnt} // 0) : "";
    my $o = $h->{ook} ? "|O:$h->{ook}" : "";
    return $b . "|T:" . body_type($h) . $c . $o;
}

1;
