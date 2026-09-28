# local installs a fresh SV; references taken before local keep the old cell.
use strict; use warnings; no warnings 'once';
our $g = 'old'; my $r = \$g; my $addr_before = 0 + $r;
{ local $g = 'new'; printf "inside: \$g=%s  \$\$r=%s  same cell=%s\n", $g, $$r, (0+\$g == $addr_before ? 'yes':'no'); $$r = 'via-ref'; }
printf "after:  \$g=%s  same cell as before=%s\n", $g, (0+\$g == $addr_before ? 'yes':'no');
my %h = (k => 'old'); my $hr = \$h{k};
{ local $h{k} = 'new'; printf "helem inside: \$h{k}=%s \$\$hr=%s\n", $h{k}, $$hr; }
printf "helem after: \$h{k}=%s same cell=%s\n", $h{k}, (\$h{k} == $hr ? 'yes' : 'no');
my @a = ('old'); my $ar = \$a[0];
{ local $a[0] = 'new'; printf "aelem inside: \$a[0]=%s \$\$ar=%s\n", $a[0], $$ar; }
printf "aelem after: \$a[0]=%s same cell=%s\n", $a[0], (\$a[0] == $ar ? 'yes' : 'no');
# absent element: local restores absence
my %z; { local $z{gone} = 1; } print "local on absent key restores absence: ", (exists $z{gone} ? 'NO' : 'yes'), "\n";
