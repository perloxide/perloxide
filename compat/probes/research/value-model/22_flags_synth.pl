use strict; use warnings;
use B ();
use Scalar::Util qw(dualvar);

# The pure function: kind supplies base marks, cache marks OR in on top.
#   flags(kind, i, n, ppok, isuv, utf8, rok) -> SvFLAGS restricted to MASK
my %C = (
    IOK  => B::SVf_IOK(),  NOK  => B::SVf_NOK(),  POK  => B::SVf_POK(),
    pIOK => B::SVp_IOK(),  pNOK => B::SVp_NOK(),  pPOK => B::SVp_POK(),
    ROK  => B::SVf_ROK(),
    UTF8 => eval { B::SVf_UTF8() } // 0x20000000,
    IsUV => eval { B::SVf_IVisUV() } // 0x80000000,
);
my $MASK = 0; $MASK |= $_ for values %C;

sub synth {
    my %a = (kind => 'Str', i => '', n => '', p => '', isuv => 0,
        utf8 => 0, rok => 0, @_);
    if    ($a{kind} eq 'Int')  { $a{i}  ||= 'pub' }
    elsif ($a{kind} eq 'Num')  { $a{n}  ||= 'pub' }
    elsif ($a{kind} eq 'Bool') { $a{i} ||= 'pub'; $a{n} ||= 'pub'; $a{p} ||= 'pub' }
    elsif ($a{kind} eq 'Ref')  { $a{rok} = 1 }
    my $f = 0;
    $f |= $C{pIOK} if $a{i};  $f |= $C{IOK} if $a{i} eq 'pub';
    $f |= $C{pNOK} if $a{n};  $f |= $C{NOK} if $a{n} eq 'pub';
    $f |= $C{pPOK} if $a{p};  $f |= $C{POK} if $a{p} eq 'pub';
    $f |= $C{ROK}  if $a{rok};
    $f |= $C{UTF8} if $a{utf8};
    $f |= $C{IsUV} if $a{isuv};
    return $f;
}

sub actual { B::svref_2object(\$_[0])->FLAGS & $MASK }
sub bits {
    my $f = shift;
    join '|', grep { $f & $C{$_} } qw(IOK NOK POK pIOK pNOK pPOK ROK UTF8 IsUV);
}

my @cases;
{
    no warnings;
    my $a = 'hello';
    push @cases, ['plain_str', $a, { p => 'pub' }];
    my $b = '10'; my $z = $b + 0;
    push @cases, ['plus10', $b, { i => 'pub', p => 'pub' }];
    my $c = '10abc'; $z = $c + 0;
    push @cases, ['dirty', $c, { i => 'priv', n => 'priv', p => 'pub' }];
    my $d = ' 10'; $z = $d + 0;
    push @cases, ['pad', $d, { i => 'pub', p => 'pub' }];
    my $e = '-0'; $z = sprintf '%g', $e; $z = $e + 0;
    push @cases, ['neg0_gfirst', $e, { i => 'pub', n => 'pub', p => 'pub' }];
    my $f = '-0'; $z = $f + 0;
    push @cases, ['neg0_intfirst', $f, { i => 'pub', p => 'pub' }];
    my $g = '1'; $g++;
    push @cases, ['one_inc', $g, { p => 'pub' }];
    my $h = 'Az'; $h++;
    push @cases, ['az_inc', $h, { p => 'pub' }];
    my $i = 42;
    push @cases, ['int', $i, { kind => 'Int' }];
    my $j = 42; my $s = "$j";
    push @cases, ['int_stringified', $j, { kind => 'Int', p => 'priv' }];
    my $k = 3.14;
    push @cases, ['num', $k, { kind => 'Num' }];
    my $l = 3.14; $s = "$l";
    push @cases, ['num_stringified', $l, { kind => 'Num' }];
    my $m = ~0;
    push @cases, ['uv', $m, { kind => 'Int', isuv => 1 }];
    my $n = 9223372036854775807; $n = $n + 1;
    push @cases, ['iv_overflow', $n, { kind => 'Int', isuv => 1 }];
    my $o = '99999999999999999999x'; $z = $o + 0;
    push @cases, ['huge_dirty', $o,
        { i => 'priv', n => 'priv', p => 'pub', isuv => 1 }];
    my $p = [];
    push @cases, ['ref', $p, { kind => 'Ref' }];
    my $q;
    push @cases, ['undef', $q, {}];
    my $r = !!1;
    push @cases, ['bool_true', $r, { kind => 'Bool' }];
    my $r0 = !!0;
    push @cases, ['bool_false', $r0, { kind => 'Bool' }];
    my $t = dualvar(42, 'forty-two');
    push @cases, ['dualvar', $t, { i => 'pub', p => 'pub' }];
    my $u = '0 but true'; $z = $u + 0;
    push @cases, ['zero_but_true', $u, { i => 'pub', p => 'pub' }];
    my $v = "\x{263A}";
    push @cases, ['utf8_str', $v, { p => 'pub', utf8 => 1 }];
    my $w = '12x'; $z = $w | 0;
    push @cases, ['dirty_bor', $w, { i => 'priv', n => 'priv', p => 'pub' }];
    my $x = 'inf'; $z = $x + 0;
    push @cases, ['clean_inf', $x,
        { i => 'priv', n => 'pub', p => 'pub', isuv => 1 }];
    my $y = 3.7; $z = $y | 0;
    push @cases, ['num_ivcache', $y, { kind => 'Num', i => 'priv' }];
}

my $bad = 0;
for my $case (@cases) {
    my ($name, undef, $ann) = @$case;
    my $want = synth(%$ann);
    my $got  = actual($case->[1]);
    my $ok = $want == $got ? 'ok    ' : do { $bad++; 'FAIL  ' };
    printf "%s %-16s synth=%-28s actual=%s\n", $ok, $name, bits($want),
        bits($got);
}
print "mismatches: $bad / ", scalar @cases, "\n";
