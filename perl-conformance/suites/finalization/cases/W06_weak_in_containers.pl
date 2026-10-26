use strict; use warnings; $| = 1;
$SIG{__WARN__} = sub { my $m = $_[0]; $m =~ s/ at \S+ line \d+\.$//m; print "warn: $m" };
package O; sub new { my ($c, $n) = @_; bless { n => $n }, $c }
sub DESTROY { print "D $_[0]{n}\n" }
package main;
# Weak references stored in containers are cleared in place: the element still exists and reads undef.
use Scalar::Util qw(weaken);
my $s = O->new('o'); my @a = ($s); my %h = (k => $s);
weaken $a[0]; weaken $h{k};
undef $s;
print "a[0] exists ", (exists $a[0] ? 1 : 0), " defined ", (defined $a[0] ? 1 : 0), "\n";
print "h{k} exists ", (exists $h{k} ? 1 : 0), " defined ", (defined $h{k} ? 1 : 0), "\n";
