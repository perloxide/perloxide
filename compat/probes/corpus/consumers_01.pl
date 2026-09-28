# oracle-variant: default
# oracle-variant: use_b USE_B=1
# Core consumers whose output depends on numeric flag state. For each value, compare a plain string
# against the same string after a numification that leaves the string unchanged.
use strict; use warnings; no warnings qw(numeric void once uninitialized);
BEGIN { $ENV{PERL_JSON_PP_USE_B} = $ENV{USE_B} // 0 }
use JSON::PP (); use Data::Dumper (); use Storable (); use Scalar::Util (); use CPAN::Meta::YAML (); use Math::BigInt ();
$Data::Dumper::Terse = 1; $Data::Dumper::Indent = 0;
my $json = JSON::PP->new->canonical->allow_nonref;
sub plain  { my $c = "" . $_[0]; $c }
sub marked { my $c = "" . $_[0]; my $n = $c + 0; $c }
our $ZZ = "zz";   # copied per call: a literal "zz" would itself acquire numeric flags (see consts_01_literal_mark.pl)
my %consumer = (
  '01 JSON::PP encode'            => sub { $json->encode($_[0]) },
  '02 Data::Dumper (XS)'          => sub { local $Data::Dumper::Useperl = 0; Data::Dumper::Dumper($_[0]) },
  '03 Data::Dumper (Useperl)'     => sub { local $Data::Dumper::Useperl = 1; Data::Dumper::Dumper($_[0]) },
  '04 Data::Dumper (XS, Useqq)'   => sub { local $Data::Dumper::Useqq = 1; Data::Dumper::Dumper($_[0]) },
  '05 Storable freeze (hex)'      => sub { unpack "H*", Storable::freeze(\$_[0]) },
  '06 Storable round trip->JSON'  => sub { $json->encode(${ Storable::thaw(Storable::freeze(\$_[0])) }) },
  '07 CPAN::Meta::YAML'           => sub { my $y = CPAN::Meta::YAML->new({ v => $_[0] })->write_string; $y =~ s/\n/\\n/g; $y },
  '08 looks_like_number'          => sub { Scalar::Util::looks_like_number($_[0]) ? 1 : 0 },
  '09 Scalar::Util::isdual'       => sub { Scalar::Util::isdual($_[0]) ? 1 : 0 },
  '10 pack "w"'                   => sub { my $r = eval { unpack "H*", pack "w", $_[0] }; defined $r ? $r : "die" },
  '11 pack "j"'                   => sub { unpack "H*", pack "j", $_[0] },
  '12 printf "%s"'                => sub { sprintf "%s", $_[0] },
  '13 sprintf "%g"'               => sub { sprintf "%g", $_[0] },
  '14 ~$s'                        => sub { unpack "H*", "" . ~$_[0] },
  '15 $s & "1"'                   => sub { unpack "H*", "" . ($_[0] & "1") },
  '16 $s | "" (use v5.28 bitwise)'=> sub { use feature 'bitwise'; no warnings 'experimental::bitwise'; unpack "H*", "" . ($_[0] | "") },
  '17 sort default ($s, "9")'     => sub { join ",", sort $_[0], "9" },
  '18 $s++'                       => sub { my $c = $_[0]; $c++; $c },
  '19 $s .. $zz (list)'            => sub { my $l = $_[0]; my $zz = $main::ZZ; my @r = ($l .. $zz); scalar(@r) > 6 ? scalar(@r) . " elems" : join ",", @r },
  '20 $s ~~ "10.0"'               => sub { no warnings; (eval q{ $_[0] ~~ "10.0" }) ? 1 : 0 },
  '21 builtin::created_as_number' => sub { no warnings 'experimental::builtin'; builtin::created_as_number($_[0]) ? 1 : 0 },
  '22 Math::BigInt->new'          => sub { Math::BigInt->new($_[0])->bstr },
  '23 $h{$s} key / "$s"'          => sub { my %h = ($_[0] => 1); join ",", keys %h },
);
my @values = ("10", "1.50", "-0", "Az", "a", "09", "18446744073709551615", "123456789012345678901234567890");
for my $name (sort keys %consumer) {
    for my $v (@values) {
        my ($p, $m) = map { my $x = $_; my $r = eval { $consumer{$name}->($x) }; defined $r ? $r : "die" } plain($v), marked($v);
        next if $p eq $m && !$ENV{ALL};
        printf "%-32s %-34s plain=%-28s marked=%s\n", $name, qq{"$v"}, $p, $m;
    }
}
print "(rows omitted where plain and marked agree; ALL=1 shows everything)\n";
