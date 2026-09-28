use strict; use warnings;
package T;
sub TIESCALAR { my $v = 10; bless \$v, shift }
sub FETCH { my $s = shift; print "FETCH($$s) "; $$s }
sub STORE { my ($s, $v) = @_; print "STORE(", defined $v ? $v : "undef", ") "; $$s = $v }
package main;
tie our $x, 'T';
print "enter ";
{ local $x; print "| "; }
print "exit\n";
