use strict; use warnings; $| = 1;
$SIG{__WARN__} = sub { my $m = $_[0]; $m =~ s/ at \S+ line \d+\.$//m; print "warn: $m" };
package O; sub new { my ($c, $n) = @_; bless { n => $n }, $c }
sub DESTROY { print "D $_[0]{n}\n" }
package main;
# exit unwinds the active frames: their lexicals die in phase RUN, before END, innermost frame first.
package Ph; our @ISA = ('O'); sub DESTROY { print "D $_[0]{n} phase ${^GLOBAL_PHASE}\n" }
package main;
END { print "END phase ${^GLOBAL_PHASE}\n" }
sub inner { my $i = Ph->new('inner'); exit 3 }
sub outer { my $o = Ph->new('outer'); inner(); print "not reached\n" }
outer();
