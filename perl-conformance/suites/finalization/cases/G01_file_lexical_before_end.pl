use strict; use warnings; $| = 1;
$SIG{__WARN__} = sub { my $m = $_[0]; $m =~ s/ at \S+ line \d+\.$//m; print "warn: $m" };
package O; sub new { my ($c, $n) = @_; bless { n => $n }, $c }
sub DESTROY { print "D $_[0]{n}\n" }
package main;
# A file-scope lexical dies when the main program's scope is left, in phase RUN, before END.
package Ph; our @ISA = ('O'); sub DESTROY { print "D $_[0]{n} phase ${^GLOBAL_PHASE}\n" }
package main;
my $lex = Ph->new('lexical');
END { print "END phase ${^GLOBAL_PHASE}\n" }
print "main done\n";
