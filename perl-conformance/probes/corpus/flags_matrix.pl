# Flag transition matrix: (start state, operation) -> B::SV::FLAGS projection.
# Code: I/N/P = public+private IOK/NOK/POK; i/n/p = private only; U = IVisUV; 8 = UTF8;
# trailing /n /s /- = builtin::created_as_number / created_as_string / neither;
# '!' marks a stale cache: numeric value read from the scalar differs from a fresh parse of its string.
use strict; use warnings; no warnings qw(numeric uninitialized void experimental::builtin once);
use B (); use Scalar::Util ();
my $F = \&B::svref_2object;
sub proj {
    my $f = $F->($_[0])->FLAGS;  # $_[0] is a reference to the scalar
    my $c = '';
    for ([B::SVf_IOK, B::SVp_IOK, 'I'], [B::SVf_NOK, B::SVp_NOK, 'N'], [B::SVf_POK, B::SVp_POK, 'P']) {
        my ($pub, $priv, $ch) = @$_;
        die "public without private" if ($f & $pub) && !($f & $priv);
        $c .= ($f & $pub) ? $ch : ($f & $priv) ? lc $ch : '';
    }
    $c .= 'U' if $f & B::SVf_IVisUV;
    $c .= '8' if $f & B::SVf_UTF8;
    $c = '0' if $c eq '';
    my $ca = builtin::created_as_number(${$_[0]}) ? 'n' : builtin::created_as_string(${$_[0]}) ? 's' : '-';
    return "$c/$ca";
}
our %T = (s10 => "10", s15 => "1.5", s10abc => "10abc", sabc => "abc", suvmax => "18446744073709551615", s1e3 => "1e3", sAz => "Az", sneg0 => "-0");
my @starts = (
  [ '"10"',          'my $s = $T{s10};' ],
  [ '"1.5"',         'my $s = $T{s15};' ],
  [ '"10abc"',       'my $s = $T{s10abc};' ],
  [ '"abc"',         'my $s = $T{sabc};' ],
  [ '"Az"',          'my $s = $T{sAz};' ],
  [ '"1e3"',         'my $s = $T{s1e3};' ],
  [ '"-0"',          'my $s = $T{sneg0};' ],
  [ 'UV_MAX str',    'my $s = $T{suvmax};' ],
  [ 'int, "$i"',     'my $s = 10; my $junk = "$s";' ],
  [ 'float, $f|0',   'my $s = 1.5; my $junk = $s | 0;' ],
  [ '3.0, $f|0',     'my $s = 3.0; my $junk = $s | 0;' ],
);
my @ops = (
  [ '(start)',              '' ],
  [ '$s == 1',              'my $r = $s == 1;' ],
  [ '$s <=> 1',             'my $r = $s <=> 1;' ],
  [ '$s + 0',               'my $r = $s + 0;' ],
  [ '$s * 1',               'my $r = $s * 1;' ],
  [ '-$s',                  'my $r = -$s;' ],
  [ 'abs $s',               'my $r = abs $s;' ],
  [ 'int $s',               'my $r = int $s;' ],
  [ '$s | 0',               'my $r = $s | 0;' ],
  [ '~$s',                  'my $r = ~$s;' ],
  [ 'if ($s)',              'if ($s) { }' ],
  [ '!$s',                  'my $r = !$s;' ],
  [ '$a[$s]',               'my @a; my $r = $a[$s];' ],
  [ '$h{$s}',               'my %h; my $r = $h{$s};' ],
  [ 'chr $s',               'my $r = chr $s;' ],
  [ '"x" x $s',             'my $r = "x" x $s;' ],
  [ 'sprintf "%d"',         'my $r = sprintf "%d", $s;' ],
  [ 'sprintf "%s"',         'my $r = sprintf "%s", $s;' ],
  [ 'sprintf "%g"',         'my $r = sprintf "%g", $s;' ],
  [ 'length $s',            'my $r = length $s;' ],
  [ '"$s"',                 'my $r = "$s";' ],
  [ '$s eq "10"',           'my $r = $s eq "10";' ],
  [ '$s =~ /0/',            'my $r = $s =~ /0/;' ],
  [ 'looks_like_number',    'my $r = Scalar::Util::looks_like_number($s);' ],
  [ 'sort {$a<=>$b}',       'my @r = sort { $a <=> $b } $s, 1;' ],
  [ '$s++',                 '$s++;' ],
  [ '--$s',                 '--$s;' ],
  [ '$s .= ""',             '$s .= "";' ],
  [ '$s .= "0"',            '$s .= "0";' ],
  [ 's/(.)/$1/',            '$s =~ s/(.)/$1/;' ],
  [ 'tr/1/2/',              '$s =~ tr/1/2/;' ],
  [ 'substr lvalue',        'substr($s, 0, 1) = substr($s, 0, 1);' ],
  [ 'substr 4-arg',         'substr($s, 0, 1, substr($s, 0, 1));' ],
  [ 'vec lvalue',           'vec($s, 0, 8) = vec($s, 0, 8);' ],
  [ 'chop',                 'chop $s;' ],
  [ '$s = "20"',            '$s = "20";' ],
  [ '$s = $s',              '$s = $s;' ],
  [ 'copy (report $t)',     'my $t = $s; return main::proj(\$t);' ],
  [ 'utf8::upgrade',        'utf8::upgrade($s);' ],
  [ 'utf8::encode',         'utf8::encode($s);' ],
  [ 'pos($s) = 0',          'pos($s) = 0;' ],
  [ 'undef $s',             'undef $s;' ],
);
my $stale_check = q{
    my $num  = do { no warnings; sprintf "%.17g", 0 + $s };
    my $copy = do { no warnings; my $c = defined $s ? "".$s : undef; defined $c ? sprintf("%.17g", 0 + $c) : 'u' };
};
# One padded row per op; the last cell is not padded, so no line ends in whitespace.
sub row { my ($head, @cells) = @_; my $line = join " ", sprintf("%-18s", $head), map { sprintf "%-12s", $_ } @cells; $line =~ s/ +$//; print "$line\n" }
row('op \\ start', map { $_->[0] } @starts);
for my $op (@ops) {
    my @cells;
    for my $st (@starts) {
        my $code = "sub { $st->[1] $op->[1] my \$p = main::proj(\\\$s); $stale_check return \$p . (defined \$s && \$num ne \$copy ? '!' : ''); }";
        my $sub = eval $code or die "$@\n$code";
        my $res = eval { $sub->() }; unless (defined $res) { $res = "die"; warn "ERR [$st->[0]] [$op->[0]]: $@" if $ENV{DEBUG} }
        push @cells, $res;
    }
    row($op->[0], @cells);
}
