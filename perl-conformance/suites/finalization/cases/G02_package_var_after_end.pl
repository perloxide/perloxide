use strict; use warnings; $| = 1;
$SIG{__WARN__} = sub { my $m = $_[0]; $m =~ s/ at \S+ line \d+\.$//m; print "warn: $m" };
package O; sub new { my ($c, $n) = @_; bless { n => $n }, $c }
sub DESTROY { print "D $_[0]{n}\n" }
package main;
# An object held only by a package variable dies in global destruction, phase DESTRUCT, after END.
package Ph; our @ISA = ('O'); sub DESTROY { print "D $_[0]{n} phase ${^GLOBAL_PHASE}\n" }
package main;
our $global = Ph->new('global');
END { print "END phase ${^GLOBAL_PHASE}\n" }
print "main done\n";
