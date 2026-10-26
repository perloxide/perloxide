use strict; use warnings; $| = 1;
$SIG{__WARN__} = sub { my $m = $_[0]; $m =~ s/ at \S+ line \d+\.$//m; print "warn: $m" };
package O; sub new { my ($c, $n) = @_; bless { n => $n }, $c }
sub DESTROY { print "D $_[0]{n}\n" }
package main;
# An uncaught die prints its message, then unwinds: lexicals die in phase RUN, before END.  The exit status is $! when
# that is nonzero, else 255; $! is zeroed first so the status is 255.
package Ph; our @ISA = ('O'); sub DESTROY { print "D $_[0]{n} phase ${^GLOBAL_PHASE}\n" }
package main;
END { print "END phase ${^GLOBAL_PHASE}\n" }
open STDERR, '>&', \*STDOUT or die;
sub f { my $x = Ph->new('frame'); $! = 0; die "uncaught\n" }
f();
