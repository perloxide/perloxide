# Ordinary code whose output depends on SV head reuse, without printing any address.
use strict; use warnings;
use Scalar::Util qw(refaddr);
$| = 1;
# (a) a "seen" set keyed by stringified references, over fresh per-iteration hashes
{ my %seen; my @out;
  for my $i (1 .. 4) { my $node = { id => $i }; push @out, $seen{$node}++ ? "dup" : "new" }
  print "(a) seen-set over fresh hashes: @out\n"; }
{ my @msg; for (1 .. 2) { my $h = {}; my $s = "$h"; push @msg, $s }
  print "(d) stringified fresh hashes across iterations identical: ", ($msg[0] eq $msg[1] ? "yes" : "no"), "\n"; }
# (e) ordering objects by address
{ my @keep; my @tmp = map { {} } 1 .. 6; undef $tmp[$_] for 1, 3, 5; push @keep, { name => $_ } for qw(a b c);
  my @all = grep { defined } (@tmp, @keep); $keep[$_]{name} //= '' for 0 .. 2; my $i = 0; $_->{name} //= "t" . $i++ for @all;
  print "(e) names sorted by refaddr: @{[ map { $_->{name} } sort { refaddr($a) <=> refaddr($b) } @all ]}\n"; }
# (f) hash keyed by stringified references: key order depends on address bits
{ my %h; $h{ {} } = 1 for 1 .. 1; my @objs = map { [] } 1 .. 8; $h{"$_"} = 1 for @objs;
  my %idx; @idx{ map { "$_" } @objs } = 0 .. 7; print "(f) key order of ref-keyed hash: @{[ map { $idx{$_} // 'x' } keys %h ]}\n"; }
