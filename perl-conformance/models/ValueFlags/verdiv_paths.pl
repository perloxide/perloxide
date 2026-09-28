#!/usr/bin/perl
use lib ($ENV{VF_ROOT} || '.'); our $ROOT = $ENV{VF_ROOT} || '.';
# verdiv_paths.pl -- path-based version divergence.  For a lane, replay every open row's path (recipe + op) from its START
# key through both perls' transition tables; the first step whose observations differ, and every step after it, is
# version-divergent.  Prints: open rows on 5.38.2 that both perls agree on (true model gaps), rows divergent, and the
# divergent paths grouped by the op of the first differing step with an example.
use strict; use warnings;
my ($lane, $v538, $v544) = @ARGV; $v538 //= '5.38.2'; $v544 //= '5.44.0';
sub load { my $tag=shift; my (%t,%s); open my $f,'<',"$ROOT/transitions.$tag.txt" or die "$tag: $!"; while (<$f>) { chomp; my ($c,$from,$op,$to)=split /\t/,$_,4; $t{"$c\t$from\t$op"}=$to } close $f;
  if (open my $g,'<',"$ROOT/starts.$tag.txt") { while (<$g>) { chomp; my ($c,$k)=split /\t/; $s{$c}=$k } } return (\%t,\%s) }
my ($t38,$s38) = load("suite_${lane}_$v538"); my ($t44,$s44) = load("suite_${lane}_$v544");
open my $r,'<',"$ROOT/suite/$lane.$v538.txt" or die; my ($open,$vd,$nostart)=(0,0,0); my (%group,%example);
while (<$r>) { my ($c,$from,$op,$recipe) = /^(\S+)\s+(\S+)\s+--(\w+)\s*-->.*\[recipe: ([^\]]*)\]/ or next; my @path = ((split /,/, $recipe), $op);
  my ($k38,$k44) = ($s38->{$c}, $s44->{$c}); if (!defined $k38 || !defined $k44) { $nostart++; next }
  my $first; for my $i (0..$#path) { my $n38 = $t38->{"$c\t$k38\t$path[$i]"}; my $n44 = $t44->{"$c\t$k44\t$path[$i]"}; if (!defined $n38 || !defined $n44 || $n38 ne $n44) { $first = $i; last } ($k38,$k44)=($n38,$n44) }
  if (defined $first) { $vd++; my $g = "$path[$first] (step " . ($first+1) . " of " . scalar(@path) . ")"; $group{$path[$first]}++; $example{$path[$first]} //= "$c: " . join(",", @path[0..$first]) . "  5.38 -> " . ($t38->{"$c\t$k38\t$path[$first]"}//'(no edge)') . "  5.44 -> " . ($t44->{"$c\t$k44\t$path[$first]"}//'(no edge)') }
  else { $open++ } }
print "lane=$lane open_agreeing=$open version_divergent_paths=$vd no_start_key=$nostart\n";
print "$group{$_}\t$_\t$example{$_}\n" for sort { $group{$b} <=> $group{$a} } keys %group;
