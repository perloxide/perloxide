use strict; use warnings; $| = 1;
$SIG{__WARN__} = sub { my $m = $_[0]; $m =~ s/ at \S+ line \d+\.$//m; print "warn: $m" };
package O; sub new { my ($c, $n) = @_; bless { n => $n }, $c }
sub DESTROY { print "D $_[0]{n}\n" }
package main;
# An object kept alive only by a reference to itself is reaped in global destruction.
package Ph; our @ISA = ('O'); sub DESTROY { print "D $_[0]{n} phase ${^GLOBAL_PHASE}\n" }
package main;
{ my $o = Ph->new('cycle'); $o->{self} = $o; }
print "scope left\n";
