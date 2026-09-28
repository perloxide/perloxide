use strict; use warnings;
use Scalar::Util qw(refaddr);

# Full reentrancy matrix: 18 inputs x {replacement x post-action} x outer op.
# Each cell runs in a forked child so segfaulting cells are recorded, not fatal.
my @inputs = ('12x', '12.5x', ' 12x', '-12x', '+12x', 'abc', '', '.', '12e',
    '.5x', '0x10', '1e5x', '99999999999999999999x', 'infx', 'nanx', '12 ',
    '-0x', 'e5');
my @repl = qw(S N R);
my @post = qw(0 I V D);
my @ops  = qw(plus bor g cat);

sub norm {
    my ($v, $x) = @_;
    return 'u' unless defined $v;
    return 'REF' if ref $v;
    if (ref $x) {
        my $a = refaddr($x);
        for my $c ("$a", sprintf('%g', $a), sprintf('%u', $a)) {
            return 'ADDR' if "$v" eq $c;
        }
        return 'REF' if "$v" =~ /^ARRAY\(0x/;
    }
    return "$v";
}

for my $in (@inputs) {
    for my $r (@repl) {
        for my $p (@post) {
            for my $op (@ops) {
                my $pid = open my $fh, '-|';
                die "fork: $!" unless defined $pid;
                if (!$pid) {
                    my $x = $in;
                    my ($fired, $w) = (0, 0);
                    local $SIG{__WARN__} = sub {
                        $w++;
                        return if $fired++;
                        if    ($r eq 'S') { $x = '99' }
                        elsif ($r eq 'N') { $x = 99 }
                        else              { $x = [] }
                        if    ($p eq 'I') { my $z = $x + 0 }
                        elsif ($p eq 'V') { my $z = sprintf '%.17g', $x }
                        elsif ($p eq 'D') { die "boom\n" }
                    };
                    my $n = eval {
                        $op eq 'plus' ? 0 + $x
                      : $op eq 'bor'  ? $x | 0
                      : $op eq 'g'    ? sprintf('%g', $x)
                      :                 $x . '';
                    };
                    my $died = $@ ? 1 : 0;
                    my $re = eval { 0 + $x };
                    print join("\t", norm($x, $x), norm($n, $x), $died,
                        norm($re, $x), $w);
                    exit 0;
                }
                my $out = do { local $/; <$fh> };
                close $fh;
                my $sig = $? & 127;
                $out = "\t\t\t\t" unless defined $out && length $out;
                print join("\t", "$in|$r|$p|$op", $out, "sig=$sig"), "\n";
            }
        }
    }
}
