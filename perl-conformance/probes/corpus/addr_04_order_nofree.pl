# Address-order dependence with no deliberate frees: ordering fresh references by address.
use strict; use warnings;
use Scalar::Util qw(refaddr);
$| = 1;
my $o1 = { name => 'a' };
my $o2 = { name => 'b' };
my $o3 = { name => 'c' };
my $o4 = { name => 'd' };
my @objs = ($o3, $o1, $o4, $o2);
print "(a) sort by refaddr: ", join(" ", map { $_->{name} } sort { refaddr($a) <=> refaddr($b) } @objs), "\n";
my %registry = map { ("$_" => $_->{name}) } @objs;
print "(b) sort keys of a ref-string registry: ", join(" ", map { $registry{$_} } sort keys %registry), "\n";
print "(c) \$o1 < \$o2 (numified references): ", ($o1 < $o2 ? "yes" : "no"), "\n";
