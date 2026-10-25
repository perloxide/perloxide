# A tied array under foreach, argument passing and list copies: when FETCHSIZE and FETCH run.
# foreach consults FETCHSIZE before every iteration and advances by index, so structural changes in the body
# give the same visible element sequence as on a plain array; flattening @a into a call or a foreach list
# is one FETCHSIZE and one proxy per element with no FETCH until a read; a list copy and an interpolation
# FETCH everything; and every syntactic $a[i], even two in one expression, is its own proxy with its own
# once-only FETCH.  The tied hash is asked the same questions.
use strict; use warnings; use Scalar::Util qw(refaddr);
{ package TA; require Tie::Array; our @ISA = ('Tie::StdArray');
  sub FETCH     { my ($s, $i) = @_; print "    FETCH[$i]\n"; $s->[$i] }
  sub FETCHSIZE { my $n = scalar @{$_[0]}; print "    FETCHSIZE=$n\n"; $n }
  sub SHIFT     { print "    SHIFT\n"; shift @{$_[0]} }
  sub PUSH      { my $s = shift; print "    PUSH @_\n"; push @$s, @_ }
  sub STORESIZE { print "    STORESIZE $_[1]\n"; $#{$_[0]} = $_[1] - 1 }
  package TH; require Tie::Hash; our @ISA = ('Tie::StdHash');
  sub FETCH    { my ($s, $k) = @_; print "    FETCH{$k}\n"; $s->{$k} }
  sub FIRSTKEY { print "    FIRSTKEY\n"; my $a = keys %{$_[0]}; each %{$_[0]} }
  sub NEXTKEY  { print "    NEXTKEY\n"; each %{$_[0]} } }
sub run { my ($label, $tied, $body) = @_;
  print "$label\n";
  if ($tied) { tie my @a, 'TA'; @a = (10, 20, 30, 40); $body->(\@a) } else { my @a = (10, 20, 30, 40); $body->(\@a) } }
for my $tied (1, 0) {
  my $k = $tied ? "tied" : "plain";
  run "$k: shift during the loop", $tied, sub { my $a = shift; my $n = 0; for my $e (@$a) { print "  iter: e=$e\n"; shift @$a if ++$n == 1 } print "  left: @$a\n" };
  run "$k: push during the loop", $tied, sub { my $a = shift; my $n = 0; for my $e (@$a) { print "  iter: e=$e\n"; push @$a, 50 if ++$n == 1; last if $n > 6 } print "  left: @$a\n" };
  run "$k: truncate during the loop", $tied, sub { my $a = shift; my $n = 0; for my $e (@$a) { print "  iter: e=$e\n"; $#$a = 0 if ++$n == 1 } print "  left: @$a\n" };
}
tie my @a, 'TA'; @a = (10, 20, 30);
sub none  { print "  (reads nothing)\n" }
sub third { my $x = $_[2]; my $y = $_[2]; print "  read \$_[2] twice: $x $y\n" }
sub count { print "  scalar(\@_) = ", scalar(@_), "\n" }
print "f(\@a), reading nothing:\n";      none(@a);
print "f(\@a), reading \$_[2] twice:\n"; third(@a);
print "f(\@a), only counting:\n";        count(@a);
print "f(\$a[0]), reading nothing:\n";   none($a[0]);
print "my \@copy = \@a:\n";              my @copy = @a;
print "interpolation \"\@a\":\n";         my $s = "@a";
print "for (\@a) reading nothing:\n";    for (@a) { }
print "for (\@a) reading \$_ twice:\n";  for (@a) { my $x = $_; my $y = $_ }
print "list (\$a[0], \$a[0]):\n";        my @l = ($a[0], $a[0]);
print "concat \$a[0] . \$a[0]:\n";       my $c = $a[0] . $a[0];
print "\\\$a[0] twice in one statement: ", (refaddr(\$a[0]) == refaddr(\$a[0]) ? "same" : "different"), " proxy\n";
print "f(\$a[0], \$a[0]) reading each twice:\n"; sub two { my $x = $_[0]; my $y = $_[0]; my $z = $_[1] } two($a[0], $a[0]);
tie my %h, 'TH'; %h = (k => 'v');
print "f(\%h), reading nothing:\n";      none(%h);
print "f(\$h{k}), reading nothing:\n";   none($h{k});
print "for (values \%h) reading nothing:\n"; for (values %h) { }
print "for (values \%h) reading \$_ twice:\n"; for (values %h) { my $x = $_; my $y = $_ }
print "my \@copy = \%h:\n";              my @hc = %h;
