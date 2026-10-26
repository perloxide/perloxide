use strict; use warnings; $| = 1;
$SIG{__WARN__} = sub { my $m = $_[0]; $m =~ s/ at \S+ line \d+\.$//m; print "warn: $m" };
package O; sub new { my ($c, $n) = @_; bless { n => $n }, $c }
sub DESTROY { print "D $_[0]{n}\n" }
package main;
# The holder already holds its new value when DESTROY runs: assignment, undef, element assignment, delete.
our ($x, %h, @a);
package Watch; our @ISA = ('O'); sub DESTROY { my $n = $_[0]{n};
  print "D $n sees ", ($n eq 'x' ? (defined $main::x ? $main::x : 'undef') : $n eq 'h' ? (exists $main::h{k} ? "h{k}=$main::h{k}" : 'h{k} gone') : "a[0]=" . ($main::a[0] // 'undef')), "\n" }
package main;
$x = Watch->new('x'); $x = 5;
$x = Watch->new('x'); undef $x;
$h{k} = Watch->new('h'); $h{k} = 7;
$h{k} = Watch->new('h'); delete $h{k};
$a[0] = Watch->new('a'); $a[0] = 9;
