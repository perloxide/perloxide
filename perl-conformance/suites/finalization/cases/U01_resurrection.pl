use strict; use warnings; $| = 1;
$SIG{__WARN__} = sub { my $m = $_[0]; $m =~ s/ at \S+ line \d+\.$//m; print "warn: $m" };
package O; sub new { my ($c, $n) = @_; bless { n => $n }, $c }
sub DESTROY { print "D $_[0]{n}\n" }
package main;
# A DESTROY that stores its invocant keeps the object alive; its next death runs DESTROY again.
our $keep; my $count = 0;
package K; our @ISA = ('O'); sub DESTROY { $count++; print "D $_[0]{n} death $count\n"; $main::keep = $_[0] if $count == 1 }
package main;
my $x = K->new('k'); undef $x;
print "keep: ", (defined $keep ? ref $keep : 'undef'), "\n";
undef $keep;
print "released again\n";
