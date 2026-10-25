# The weak flag belongs to the holder SV, never to the value: every copy of a weak reference -- assignment,
# list assignment, shift and pop of a weak element, a sub's return, a hash value copied out -- is a strong
# reference that keeps the referent alive, while the holder it was copied from stays weak and is cleared at
# death, wherever that holder has moved to.
use strict; use warnings; use Scalar::Util qw(weaken isweak refaddr);
{ package T; sub DESTROY { print "  DESTROY\n" } }
sub w { isweak($_[0]) ? "weak" : "strong" }
print "assignment copy:\n";
{ my $t = bless [], 'T'; my $w = $t; weaken $w; my $c = $w; print "  holder ", w($w), ", copy ", w($c), "\n"; undef $t; print "  after undef \$t: holder defined=", (defined $w ? 1 : 0), ", copy defined=", (defined $c ? 1 : 0), "\n"; undef $c; print "  after undef copy: holder defined=", (defined $w ? 1 : 0), "\n" }
print "list assignment copy:\n";
{ my $t = bless [], 'T'; my $w = $t; weaken $w; my ($c) = ($w); print "  copy ", w($c), "\n"; undef $t; print "  holder defined=", (defined $w ? 1 : 0), "\n"; undef $c }
print "shift of a weak element (the element SV itself leaves the array):\n";
{ my $t = bless [], 'T'; my @a = ($t, 'x'); weaken $a[0]; my $r = \$a[0]; my $addr = refaddr $r;
  my $c = shift @a; print "  held element ", w($$r), " same_sv=", (refaddr($r) == $addr ? 1 : 0), ", shifted copy ", w($c), "\n";
  undef $c; undef $t; print "  after death: held element defined=", (defined $$r ? 1 : 0), " ", w($$r), "\n" }
print "sub return of a weak lexical:\n";
{ my $t = bless [], 'T'; my $w = $t; weaken $w; sub ret { return $_[0] } my $c = ret($w); print "  returned ", w($c), "\n"; undef $t; print "  holder defined=", (defined $w ? 1 : 0), "\n"; undef $c }
print "hash value copied out:\n";
{ my $t = bless [], 'T'; my %h = (k => $t); weaken $h{k}; my $c = $h{k}; my ($v) = values %h; print "  copy ", w($c), ", values copy ", w($v), "\n"; undef $t; print "  element defined=", (defined $h{k} ? 1 : 0), "\n"; undef $c; undef $v }
print "end\n";
