use strict; use warnings;
# "ok" means the block ran; "dies:" is the message with its location stripped, since the reference pins the message
# and not the line it names.
sub try { my ($label, $code) = @_; my $r = eval { $code->(); "ok" }; unless (defined $r) { ($r = $@) =~ s/ at \S+ line \d+\.\n//; $r = "dies: $r" } printf "%-40s %s\n", $label, $r }
# Which members of a foreach list are the readonly constant SV itself, and which are writable temporaries.
use constant K => 7; use constant L => (1, 2);
sub plain { 1 } sub constsub () { 1 }
my %h = (a => 1);
try "for (1)",                       sub { for (1) { $_++ } };
try "for ('a')",                     sub { for ('a') { $_ .= 'x' } };
try "for qw(a)",                     sub { for (qw(a)) { $_ .= 'x' } };
try "for (undef)",                   sub { for (undef) { $_ = 1 } };
try "for (1==1)",                    sub { for (1==1) { $_ = 0 } };
try "for (!1)",                      sub { for (!1) { $_ = 1 } };
try "for (__PACKAGE__)",             sub { for (__PACKAGE__) { $_ .= 'x' } };
try "for (K)",                       sub { for (K) { $_++ } };
try "for (K())",                     sub { for (K()) { $_++ } };
try "for (&K)",                      sub { for (&K) { $_++ } };
try "for (L) list constant",         sub { for (L) { $_++ } };
try "for (constsub()) inlinable",    sub { for (constsub()) { $_++ } };
try "for (plain())",                 sub { for (plain()) { $_++ } };
try "for ((1) x 2)",                 sub { for ((1) x 2) { $_++ } };
try "for (1..2)",                    sub { for (1..2) { $_++ } };
try "for ('a'..'b')",                sub { for ('a'..'b') { $_ .= 'x' } };
try "for (1 + 1) folded",            sub { for (1 + 1) { $_++ } };
try "for ('a' . 'b') folded",        sub { for ('a' . 'b') { $_ .= 'x' } };
try "for (\"\$h{a}\") interpolated",   sub { for ("$h{a}") { $_ .= 'x' } };
try "for (keys %h)",                 sub { for (keys %h) { $_ .= 'x' } };
try "for (values %h)",               sub { for (values %h) { $_++ } };
try "sub args: f(1); \$_[0]++",       sub { sub m1 { $_[0]++ } m1(1) };
try "sub args: f(\$v); \$_[0]++",      sub { sub m2 { $_[0]++ } my $v = 1; m2($v); die "v=$v\n" unless $v == 2 };
try "sort { } (3, 1)",               sub { $_++ for sort { $a <=> $b } (3, 1) };
try "grep { 1 } (1)",                sub { $_++ for grep { 1 } (1) };
try "reverse (1)",                   sub { $_++ for reverse (1) };
try "map { \$_++ } (1)",              sub { my @r = map { $_++ } (1) };
try "map { \$_ } (1) returns copies", sub { $_++ for map { $_ } (1) };
try "sort over map copies",          sub { $_++ for sort { $a <=> $b } map $_, 3, 1, 2 };
try "grep over map copies",          sub { $_++ for grep { 1 } map $_, 3, 1, 2 };
try "reverse over map copies",       sub { $_++ for reverse map $_, 3, 1, 2 };
# A writable member that is a copy: the write never reaches the next execution.
sub cs () { 10 }
for my $i (1..3) { for (cs()) { $_++ } }
print "inlinable constant after three writes: ", cs(), "\n";
sub folded { for (1 + 1) { $_++; return $_ } }
print "folded constant across calls: ", join(",", map { folded() } 1..3), "\n";
