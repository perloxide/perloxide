use strict; use warnings; use lib '/tmp/probe'; use fl; *fl=\&fl::fl;
my ($r1,$r2) = (\"zz", \"zz"); print "two literal sites: ", ($r1 == $r2 ? "shared" : "distinct"), "\n";
sub h { my $numify = shift; for my $v ("10") { my $before = fl(\$v); no warnings; my $x = $v + 0 if $numify; return $before } }
print "aliased literal: call1=", h(0), " call2(numify)=", h(1), " call3=", h(0), "\n";
use constant ZZ => "zz"; use constant TEN => "10";
sub cnt { my @r = ("aa" .. ZZ); scalar @r }
print "range with use-constant end: before=", cnt(); { no warnings; my $x = ZZ + 0; } print " after ZZ+0 elsewhere=", cnt(), " flags(ZZ)=", fl(\ZZ), "\n";
sub site { no warnings; my $r = TEN & $_[0]; join " ", map { sprintf "%02x", ord } split //, $r } print "TEN & 'abc' fresh: [", site("abc"), "]"; { my $x = TEN + 1 } print " after TEN+1 elsewhere: [", site("abc"), "]\n";
sub lit { no warnings; my $r = "10" + 0; my $q = \"10"; fl($q) } print "distinct-site literal not marked by neighbor: ", lit(), "\n";
