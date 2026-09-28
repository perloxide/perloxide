use strict; use warnings; use B; use Scalar::Util qw(isdual); use Data::Dumper; use JSON::PP; use Storable qw(freeze);
use builtin qw(created_as_number created_as_string); no warnings 'experimental::builtin';
$Data::Dumper::Indent=0; $Data::Dumper::Terse=1;
my @F=(IOK=>B::SVf_IOK,NOK=>B::SVf_NOK,POK=>B::SVf_POK,pIOK=>B::SVp_IOK,pNOK=>B::SVp_NOK,pPOK=>B::SVp_POK,IsUV=>B::SVf_IVisUV);
sub fl { my $f=B::svref_2object($_[0])->FLAGS; join(",", map { $f & $F[$_*2+1] ? $F[$_*2] : () } 0..$#F/2) || "-" }
sub consumers { my $r=shift; my $ddxs = Dumper($$r); local $Data::Dumper::Useperl=1; my $ddpp = Dumper($$r);
  sprintf "isdual=%d DDxs=%s DDpp=%s JSON=%s c_as=%s%s Storable=%s", (isdual($$r)?1:0), $ddxs, $ddpp, encode_json([$$r]),
    (created_as_number($$r)?"N":"-"), (created_as_string($$r)?"S":"-"), unpack("H*", substr(freeze([$$r]), 12)) }
sub row { my ($label, $setup, $op) = @_; my $x = $setup->(); my $before = consumers(\$x); my $fb = fl(\$x); $op->($x); my $after = consumers(\$x);
  printf "%-32s %-24s -> %-28s %s\n", $label, $fb, fl(\$x), ($before eq $after ? "consumers unchanged" : "CHANGED: $after   (was: $before)"); }
print "== Int starts\n";
row('Int 10, stringify "$i"',       sub { 10 },   sub { my $s = "$_[0]" });
row('Int 10, regex match',          sub { 10 },   sub { $_[0] =~ /1/ });
row('Int 10, * 1.5',                sub { 10 },   sub { my $s = $_[0] * 1.5 });
row('Int 10, sqrt',                 sub { 10 },   sub { my $s = sqrt $_[0] });
row('Int 10, == 10.5',              sub { 10 },   sub { my $s = $_[0] == 10.5 });
row('Int 10, / 3',                  sub { 10 },   sub { my $s = $_[0] / 3 });
row('Int 10, | ""',                 sub { 10 },   sub { my $s = $_[0] | "" });
row('Int 10, stringify then *1.5',  sub { 10 },   sub { my $s = "$_[0]"; $s = $_[0] * 1.5 });
row('Int IV_MAX, ++',               sub { 9223372036854775807 }, sub { $_[0]++ });
row('Int 10, ++',                   sub { 10 },   sub { $_[0]++ });
print "== Float starts\n";
row('Float 3.0, stringify',         sub { 3.0 },  sub { my $s = "$_[0]" });
row('Float 3.5, stringify',         sub { 3.5 },  sub { my $s = "$_[0]" });
row('Float 3.0, + 1',               sub { 3.0 },  sub { my $s = $_[0] + 1 });
row('Float 3.0, == 3',              sub { 3.0 },  sub { my $s = $_[0] == 3 });
row('Float 3.0, | 0',               sub { 3.0 },  sub { my $s = $_[0] | 0 });
row('Float 3.5, + 1',               sub { 3.5 },  sub { my $s = $_[0] + 1 });
row('Float 3.5, int()',             sub { 3.5 },  sub { my $s = int $_[0] });
row('Float 3.5, sprintf %d',        sub { 3.5 },  sub { my $s = sprintf "%d", $_[0] });
row('Float 3.0, ++',                sub { 3.0 },  sub { $_[0]++ });
row('Float 3.5, ++',                sub { 3.5 },  sub { $_[0]++ });
row('Float 1e19, | 0',              sub { 1e19 }, sub { my $s = $_[0] | 0 });
row('Float 3.0, +1 then ++',        sub { 3.0 },  sub { my $s = $_[0] + 1; $_[0]++ });
print "== Int/Float results of ++ (fresh vs marked) as DD sees them\n";
{ my $a = 3.0; $a++; my $b = 3.0; my $t = $b + 1; $b++; print "3.0++ fresh: ", Dumper($a), " flags ", fl(\$a), " | 3.0 marked then ++: ", Dumper($b), " flags ", fl(\$b), "\n"; }
