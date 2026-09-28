# Consumers on scalars that start as numbers, across the operations that add or remove public POK.
use strict; use warnings; no warnings qw(numeric void once experimental::builtin);
use JSON::PP (); use Data::Dumper (); use Storable (); use Scalar::Util (); use B ();
$Data::Dumper::Terse = 1; $Data::Dumper::Indent = 0;
my $json = JSON::PP->new->canonical->allow_nonref;
my @states = (
  [ 'int 10',                 sub { my $s = 10; $s } ],
  [ 'int 10, "$s"',           sub { my $s = 10; my $j = "$s"; $s } ],
  [ 'int 10, $s .= ""',       sub { my $s = 10; $s .= ""; $s } ],
  [ 'int 10, utf8::upgrade',  sub { my $s = 10; utf8::upgrade($s); $s } ],
  [ 'int 10, "$s", $s+0',     sub { my $s = 10; my $j = "$s"; $j = $s + 0; $s } ],
  [ 'float 1.5',              sub { my $s = 1.5; $s } ],
  [ 'float 1.5, "$s"',        sub { my $s = 1.5; my $j = "$s"; $s } ],
  [ 'float 3.0, $s|0, "$s"',  sub { my $s = 3.0; my $j = $s | 0; $j = "$s"; $s } ],
  [ 'float -0.0',             sub { my $s = -0.0; $s } ],
  [ 'float -0.0, $s|0',       sub { my $s = -0.0; my $j = $s | 0; $s } ],
);
my @consumers = (
  [ 'flags',          sub { my $f = B::svref_2object(\$_[0])->FLAGS; join '', map { $f & $_->[0] ? $_->[1] : $f & $_->[2] ? lc $_->[1] : '' } [B::SVf_IOK,'I',B::SVp_IOK], [B::SVf_NOK,'N',B::SVp_NOK], [B::SVf_POK,'P',B::SVp_POK] } ],
  [ 'JSON::PP',       sub { $json->encode($_[0]) } ],
  [ 'DD XS',          sub { local $Data::Dumper::Useperl = 0; Data::Dumper::Dumper($_[0]) } ],
  [ 'DD Useperl',     sub { local $Data::Dumper::Useperl = 1; Data::Dumper::Dumper($_[0]) } ],
  [ 'Storable',       sub { unpack "H*", Storable::freeze(\$_[0]) } ],
  [ 'created_as_num', sub { builtin::created_as_number($_[0]) ? 1 : 0 } ],
  [ 'isdual',         sub { Scalar::Util::isdual($_[0]) ? 1 : 0 } ],
  [ '~$s',            sub { my $r = ~$_[0]; $r =~ /^\d+$/ ? "num" : "str" } ],
  [ 'sprintf %g',     sub { sprintf "%g", $_[0] } ],
);
printf "%-24s", 'state'; printf " | %-s", $_->[0] for @consumers; print "\n";
for my $st (@states) {
    printf "%-24s", $st->[0];
    for my $c (@consumers) { my $v = $st->[1]->(); printf " | %s", $c->[1]->($v) }
    print "\n";
}
