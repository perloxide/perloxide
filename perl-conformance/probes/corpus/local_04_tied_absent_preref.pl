# A proxy held before `local` on a tied element, written through inside the scope.  Present key or index:
# the STORE goes to the tie and the unwind restores the saved value over it.  Absent hash key: the STORE
# through the proxy reaches the tie, but the unwind still DELETEs, because local decided on the key's
# absence when it ran; the held proxy reads undef afterward.  Array index past the end: the same question.
use strict; use warnings;
{ package TA; require Tie::Array; our @ISA = ('Tie::StdArray');
  sub STORE     { my ($s, $i, $v) = @_; print "    STORE[$i]=", (defined $v ? $v : 'undef'), "\n"; $s->[$i] = $v }
  sub FETCH     { my ($s, $i) = @_; print "    FETCH[$i]\n"; $s->[$i] }
  sub DELETE    { my ($s, $i) = @_; print "    DELETE[$i]\n"; delete $s->[$i] }
  sub STORESIZE { print "    STORESIZE $_[1]\n"; $#{$_[0]} = $_[1] - 1 }
  package TH; require Tie::Hash; our @ISA = ('Tie::StdHash');
  sub STORE  { my ($s, $k, $v) = @_; print "    STORE{$k}=", (defined $v ? $v : 'undef'), "\n"; $s->{$k} = $v }
  sub FETCH  { my ($s, $k) = @_; print "    FETCH{$k}\n"; $s->{$k} }
  sub DELETE { my ($s, $k) = @_; print "    DELETE{$k}\n"; delete $s->{$k} } }
sub d { defined $_[0] ? $_[0] : 'undef' }
tie my @a, 'TA'; @a = (10, 20, 30);
print "array, present index: hold \\\$a[1], local \$a[1] = 99, store 7 through the proxy inside\n";
{ my $r = \$a[1];
  { local $a[1] = 99; print "  inside before: fresh \$a[1] = $a[1]\n"; $$r = 7; print "  inside after: fresh \$a[1] = $a[1]; via r = $$r\n" }
  print "  after the scope: fresh \$a[1] = $a[1]; via r = $$r\n" }
print "array, absent index: hold \\\$a[5], local \$a[5] = 99, store 7 through the proxy inside\n";
{ my $r = \$a[5];
  { local $a[5] = 99; $$r = 7; print "  inside: fresh \$a[5] = ", d($a[5]), "\n" }
  print "  after the scope: size = ", scalar(@a), ", exists = ", (exists $a[5] ? 1 : 0), ", via r = ", d($$r), "\n" }
tie my %h, 'TH'; %h = (k => 'v');
print "hash, present key: hold \\\$h{k}, local \$h{k} = 'L', store 'X' through the proxy inside\n";
{ my $r = \$h{k};
  { local $h{k} = 'L'; $$r = 'X'; print "  inside after: fresh \$h{k} = $h{k}; via r = $$r\n" }
  print "  after the scope: fresh \$h{k} = $h{k}; via r = $$r\n" }
print "hash, absent key: hold \\\$h{new}, local \$h{new} = 'L', store 'X' through the proxy inside\n";
{ my $r = \$h{new};
  { local $h{new} = 'L'; $$r = 'X'; print "  inside: fresh \$h{new} = ", d($h{new}), "\n" }
  print "  after the scope: exists = ", (exists $h{new} ? 1 : 0), ", via r = ", d($$r), "\n" }
