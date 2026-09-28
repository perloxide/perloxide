use strict; use warnings; use lib '/tmp/probe'; use fl; use JSON::PP; use Data::Dumper; use Scalar::Util qw(isdual);
$Data::Dumper::Indent=0; $Data::Dumper::Terse=1; $Data::Dumper::Useqq=0;
{ my $s="10"; print "JSON/DD '10': ", encode_json([$s]), " ", Dumper($s); my $t=$s+0; print "  after +0: ", encode_json([$s]), " ", Dumper($s), "\n"; }
{ my $s="10"; my $t=$s*1.5; print "JSON/DD '10' after *1.5 (NP): ", encode_json([$s]), " ", Dumper($s), "\n"; }
{ no warnings; my $s="abc"; my $t=$s+0; print "JSON/DD 'abc' after +0 (inP): ", encode_json([$s]), " ", Dumper($s), "\n"; }
{ my $n=3.0; print "DD 3.0: ", Dumper($n); my $u=$n+1; print "  after +1: ", Dumper($n), "\n"; }
{ my $i=10; print "DD 10: ", Dumper($i); my $v="$i"; print "  after \"\$i\": ", Dumper($i), "\n"; }
{ no warnings; my $s="Az"; $s++; print "Az++ plain: $s\n"; my $t="Az"; my $x=$t+0; $t++; print "Az++ marked: $t\n"; my $u="1"; $u++; print "'1'++: $u\n"; my $z="zz"; $z++; print "zz++: $z\n"; }
{ no warnings; my $a="a"; print "range plain: ", join(",", $a.."e"), "\n"; my $x=$a+0; print "range marked: ", join(",", $a.."e"), "\n"; }
{ no warnings; for my $y (5, "abc") { my $r = "10" & $y; print "'10' & \$y: [", join(" ", map { sprintf "%02x", ord } split //, $r), "]\n" } }
{ no warnings; for my $y ("abc", 5) { my $r = "12" & $y; print "'12' & \$y (string first): [", join(" ", map { sprintf "%02x", ord } split //, $r), "]\n" } }
{ no warnings; for my $y ("abc", 5) { my $r = ~"AB"; print "~'AB' len=", length($r), "\n"; my $u = "AB" | $y } }
