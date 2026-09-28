use strict; use warnings;
use Math::BigInt;

# Executable spec of the two-slot FatBody reentrancy rules, transcribed from
# perl 5.44.0 sv.c for the x86-64 configuration: NV is a double and
# NV_PRESERVES_UV is NOT defined, so the #else branches of S_sv_2iuv_common
# and Perl_sv_2nv_flags are the ones modeled here.
my $UV_MAX   = Math::BigInt->new('18446744073709551615');
my $TWO64    = Math::BigInt->new(2)->bpow(64);
my $P53      = 9007199254740992;
my $IV_MAX   = 9223372036854775807;
my $INF      = 9**9**9;
my $NAN      = -sin(9**9**9);

sub new_state { return { pv => $_[0], ppok => 1, pok => 1, rok => 0,
    iv => 0, nv => 0, isuv => 0, piok => 0, iok => 0, pnok => 0, nok => 0 } }

# grok_number without PERL_SCAN_TRAILING: any trailing garbage makes the
# whole string invalid, except inf/nan which report trailing separately.
sub grok0 {
    my ($s) = @_;
    return ('invalid') unless defined $s && length $s;
    my $t = $s; $t =~ s/^\s+//;
    if ($t =~ /^([+-]?)inf(?:inity)?(.*)$/si) {
        my $tr = $2; $tr =~ s/\s+$//;
        return ('invalid') if length $tr;
        return ('inf', $1 eq '-' ? -1 : 1, 0);
    }
    if ($t =~ /^([+-]?)nan(.*)$/si) {
        my $tr = $2; $tr =~ s/\s+$//;
        return ('invalid') if length $tr;
        return ('nan', 1, 0);
    }
    if ($t =~ /^([+-]?)(\d+)\s*$/) {
        my ($sg, $d) = ($1, $2);
        (my $c = $d) =~ s/^0+(?=\d)//;
        my $in_uv = length($c) < 20 || (length($c) == 20 && $c le "$UV_MAX");
        return ('int', $sg eq '-' ? -1 : 1, 0, $c, $in_uv);
    }
    if ($t =~ /^([+-]?)(?:(\d+)\.(\d*)|\.(\d+))([eE][+-]?\d+)?\s*$/
        || $t =~ /^([+-]?)(\d+)()([eE][+-]?\d+)\s*$/) {
        return ('float', $1 eq '-' ? -1 : 1, 0);
    }
    return ('invalid');
}

sub atof {
    my ($s) = @_;
    return 0 unless defined $s;
    return $1 eq '-' ? -$INF : $INF if $s =~ /^\s*([+-]?)inf/i;
    return $NAN if $s =~ /^\s*[+-]?nan/i;
    return 0 + $1
        if $s =~ /^\s*([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)/;
    return 0;
}

sub is_nan { my $n = shift; return $n != $n }

# Perl_cast_uv on this platform: NaN casts to 0, > UV_MAX clamps.
sub cast_uv {
    my ($nv) = @_;
    return Math::BigInt->new(0) if is_nan($nv);
    return $UV_MAX->copy if $nv == $INF || $nv >= 2**64;
    return Math::BigInt->new(sprintf '%.0f', $nv) if $nv >= 0;
    return Math::BigInt->new(0);
}

sub warn_now {
    my ($st, $ctx) = @_;
    $ctx->{w}++;
    return if $ctx->{fired}++;
    my ($r, $p) = ($ctx->{repl}, $ctx->{post});

    # sv_setpv keeps slot contents, clears numeric flags, sets POK.
    if ($r eq 'S') {
        @$st{qw(pv ppok pok rok piok iok pnok nok isuv)} =
            ('99', 1, 1, 0, 0, 0, 0, 0, 0);
    }
    elsif ($r eq 'N') {

        # sv_setiv-equivalent: IV slot + public IOK; PV freed; NV kept.
        @$st{qw(pv ppok pok rok piok iok pnok nok isuv iv)} =
            (undef, 0, 0, 0, 1, 1, 0, 0, 0, 99);
    }
    else {
        @$st{qw(pv ppok pok rok piok iok pnok nok isuv)} =
            (undef, 0, 0, 1, 0, 0, 0, 0, 0);
    }
    if    ($p eq 'I') { my $z = model_add($st, $ctx) }
    elsif ($p eq 'V') { my $z = model_nv($st, $ctx) }
    elsif ($p eq 'D') { die "boom\n" }
}

# The shared got_nv fill: IOKp on, then IV or UV slot from the NV slot.
sub fill_from_nv {
    my ($st) = @_;
    $st->{piok} = 1;
    my $nv = $st->{nv};
    if (!is_nan($nv) && $nv < $IV_MAX + 0.5) {
        $st->{iv} = int($nv);
        $st->{iok} = 1 if $st->{iv} == $nv && $st->{nok};
    }
    else {
        $st->{isuv} = 1;
        $st->{uv} = cast_uv($nv);
        $st->{iok} = 1 if !is_nan($nv) && $nv != $INF
            && "$st->{uv}" + 0 == $nv && $st->{nok};
    }
}

sub non_preserve {
    my ($st) = @_;
    my $nv = $st->{nv};
    $st->{piok} = 1;
    $st->{nok} = $st->{pnok} = 1;
    if (!is_nan($nv) && $nv > 2**64 - 1) {
        $st->{isuv} = 1; $st->{uv} = $UV_MAX->copy;
        return;
    }
    if (!is_nan($nv) && $nv < $IV_MAX + 1) {
        $st->{iv} = int($nv);
        return;
    }
    $st->{isuv} = 1; $st->{uv} = cast_uv($nv);
}

# sv_2iv / sv_2uv.
# Perl_cast_uv of fabs(nv), as the fill-selection test applies it: NaN casts
# to 0 (so NaN takes the small fill), infinities saturate to UV_MAX.
sub cast_uv_abs {
    my $nv = abs($_[0]);
    return 0 if is_nan($nv);
    return 2**64 if $nv >= 2**64;
    return int($nv);
}

sub model_iv {
    my ($st, $ctx) = @_;
    return 'ADDR' if $st->{rok};
    if ($st->{piok}) { return $st->{isuv} ? $st->{uv} : $st->{iv} }
    if ($st->{pnok}) { fill_from_nv($st); return $st->{isuv} ? $st->{uv} : $st->{iv} }
    if ($st->{ppok}) {
        my ($kind, $sign, $trail, $digits, $in_uv) = grok0($st->{pv});
        if ($kind eq 'int' && $in_uv) {
            if ($sign > 0 && "$digits" + 0 > $IV_MAX) {
                $st->{isuv} = 1; $st->{uv} = Math::BigInt->new($digits);
            }
            else { $st->{iv} = $sign * $digits }
            $st->{piok} = $st->{iok} = 1;
            return $st->{isuv} ? $st->{uv} : $st->{iv};
        }
        if ($kind eq 'float' || ($kind eq 'int' && !$in_uv)) {
            $st->{piok} = 1 if $kind eq 'float';
            $st->{nv} = atof($st->{pv});
            if ($kind eq 'float') {
                $st->{iv} = int($st->{nv});
                $st->{nok} = $st->{pnok} = 1;
            }
            else { non_preserve($st) }
            return $st->{isuv} ? $st->{uv} : $st->{iv};
        }
        if ($kind eq 'inf' || $kind eq 'nan') {
            warn_now($st, $ctx) if $trail;

            # S_sv_setnv on infnan: NOK_only nukes other flags; POK restored
            # if the (possibly handler-replaced) state still had it.
            my $pok_was = $st->{pok};
            @$st{qw(piok iok isuv)} = (0, 0, 0);
            $st->{nv} = $kind eq 'inf' ? $sign * $INF : $NAN;
            $st->{nok} = $st->{pnok} = 1;
            $st->{pok} = $st->{ppok} = $pok_was ? 1 : 0;
            fill_from_nv($st);
            return $st->{isuv} ? $st->{uv} : $st->{iv};
        }

        # Invalid: the reentrancy window. NV slot from the pre-handler
        # string; handler; refill from the NV slot as the handler left it;
        # strip public numeric flags at the end.
        $st->{nv} = atof($st->{pv});
        warn_now($st, $ctx);
        if ($P53 > cast_uv_abs($st->{nv})) {
            $st->{piok} = 1; $st->{nok} = $st->{pnok} = 1;
            $st->{iv} = is_nan($st->{nv}) ? 0 : int($st->{nv});
            $st->{iok} = 1 if $st->{iv} == $st->{nv};
        }
        else { non_preserve($st) }
        $st->{iok} = 0; $st->{nok} = 0;
        return $st->{isuv} ? $st->{uv} : $st->{iv};
    }
    $ctx->{w}++; return 0;
}

# sv_2nv. Dispatch order per Perl_sv_2nv_flags: NOKp, then THINKFIRST/ROK,
# then IOKp shortcut, then the POKp parse.
sub model_nv {
    my ($st, $ctx) = @_;
    return 'ADDR' if $st->{rok};
    return $st->{nv} if $st->{pnok};
    if ($st->{piok}) {
        $st->{nv} = $st->{isuv} ? "$st->{uv}" + 0 : $st->{iv};
        $st->{pnok} = 1; $st->{nok} = 1 if $st->{iok};
        return $st->{nv};
    }
    if ($st->{ppok}) {
        my ($kind, $sign, $trail, $digits, $in_uv) = grok0($st->{pv});
        warn_now($st, $ctx) if $kind eq 'invalid';
        if (!$st->{ppok}) {

            # Perl is undefined here: a segfault when the handler left a
            # numeric holder, a read through the freed PV when it left a
            # ref. Design-defined: numify the current holder by its actual
            # kind, with no further warning; the row is marked divergent.
            $ctx->{div} = 1;
            return model_nv($st, $ctx);
        }
        $st->{nv} = atof($st->{pv});
        $st->{nok} = $st->{pnok} = 1;

        # sv_2nv ends with the same public-flag turn-off as
        # S_sv_2iuv_common when grok recognized nothing (sv.c, the
        # NV_PRESERVES_UV #else tail of Perl_sv_2nv_flags).
        if ($kind eq 'invalid') { $st->{iok} = 0; $st->{nok} = 0 }
        return $st->{nv};
    }
    $ctx->{w}++; return 0;
}

# pp_add with a zero left operand: IV please, public IOK decides the path.
sub model_add {
    my ($st, $ctx) = @_;
    return 'ADDR' if $st->{rok};
    if (!$st->{piok} && ($st->{nok} || $st->{pok})) {
        my $a = model_iv($st, $ctx);
        return 'ADDR' if $a eq 'ADDR';
    }
    if ($st->{iok}) { return $st->{isuv} ? big_str($st->{uv}) : $st->{iv} }
    my $n = model_nv($st, $ctx);
    return $n;
}

sub big_str { my $v = shift; return ref $v ? $v->bstr : "$v" }

sub model_bor {
    my ($st, $ctx) = @_;
    my $a = model_iv($st, $ctx);
    return 'ADDR' if $a eq 'ADDR';
    return $st->{uv}->bstr if $st->{isuv};
    return $a >= 0 ? "$a" : ($TWO64 + $a)->bstr;
}

sub model_str {
    my ($st, $ctx) = @_;
    return $st->{pv} if $st->{pok};
    if ($st->{iok}) { return $st->{isuv} ? $st->{uv}->bstr : "$st->{iv}" }
    if ($st->{nok}) { my $t = 0 + $st->{nv}; return "$t" }
    return 'REF' if $st->{rok};
    $ctx->{w}++;
    return '';
}

sub fmt_num { my $v = shift; return $v if $v =~ /[A-Z]/; my $t = 0 + $v; return "$t" }

my @inputs = ('12x', '12.5x', ' 12x', '-12x', '+12x', 'abc', '', '.', '12e',
    '.5x', '0x10', '1e5x', '99999999999999999999x', 'infx', 'nanx', '12 ',
    '-0x', 'e5');
for my $in (@inputs) {
    for my $r (qw(S N R)) {
        for my $p (qw(0 I V D)) {
            for my $op (qw(plus bor g cat)) {
                my $st = new_state($in);
                my $ctx = { fired => 0, w => 0, repl => $r, post => $p };
                my $n = eval {
                    $op eq 'plus' ? fmt_num(big_str(model_add($st, $ctx)))
                  : $op eq 'bor'  ? big_str(model_bor($st, $ctx))
                  : $op eq 'g'    ? do { my $v = model_nv($st, $ctx);
                                         $v =~ /[A-Z]/ ? $v : sprintf('%g', $v) }
                  :                 model_str($st, $ctx) . '';
                };
                my $died = ($@ && $@ eq "boom\n") ? 1 : ($@ ? 2 : 0);
                my $re = eval { fmt_num(big_str(model_add($st, $ctx))) };
                $re = 'u' unless defined $re && !$@;
                $n = 'u' unless defined $n;
                my $pv = $st->{rok} ? 'REF'
                    : defined $st->{pv} && $st->{pok} ? $st->{pv}
                    : model_str($st, $ctx);
                $pv = 'u' unless defined $pv;
                $n = 'ADDR', $re = 'ADDR' if 0;
                print join("\t", "$in|$r|$p|$op", $pv, $n, $died, $re,
                    $ctx->{w}, $ctx->{div} ? 'DIV' : ''), "\n";
            }
        }
    }
}
