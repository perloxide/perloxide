use strict; use warnings;
# "ok" means the block ran; "dies:" is the message with its location stripped, since the reference pins the message
# and not the line it names.
sub try { my ($label, $code) = @_; my $r = eval { $code->(); "ok" }; unless (defined $r) { ($r = $@) =~ s/ at \S+ line \d+\.\n//; $r = "dies: $r" } printf "%-40s %s\n", $label, $r }
# Negative subscripts below the array's start are "non-creatable": a different message from readonly, raised by every
# lvalue route and by no rvalue route.
sub set { $_[0] = 1 }
my @a = (1, 2); my %h = (k => 1);
try "\$b[-3] = 1",              sub { my @b = @a; $b[-3] = 1 };
try "\$b[-2] = 1",              sub { my @b = @a; $b[-2] = 1 };
try "\$b[5] = 1 grows",         sub { my @b = @a; $b[5] = 1; die "len ", scalar(@b), "\n" unless @b == 6 };
try "\$b[-3] //= 1",            sub { my @b = @a; $b[-3] //= 1 };
try "\$e[-1] = 1 on empty",     sub { my @e; $e[-1] = 1 };
try "set(\$b[-3])",              sub { my @b = @a; set($b[-3]) };
try "set(\$b[5]) grows",         sub { my @b = @a; set($b[5]); die "len ", scalar(@b), "\n" unless @b == 6 };
try "for (\$b[-3])",             sub { my @b = @a; for ($b[-3]) { $_ = 1 } };
try "for (\$b[5]) grows",        sub { my @b = @a; for ($b[5]) { $_ = 1 } die "len ", scalar(@b), "\n" unless @b == 6 };
try "\\\$b[-3]",                  sub { my @b = @a; my $r = \$b[-3] };
try "\\\$b[5] grows",             sub { my @b = @a; my $r = \$b[5]; die "len ", scalar(@b), "\n" unless @b == 6 };
try "splice(\@b, -3)",           sub { my @b = @a; splice(@b, -3) };
try "\$#b = -2",                 sub { my @b = @a; $#b = -2 };
try "\$#b = -1 empties",         sub { my @b = @a; $#b = -1; die "len ", scalar(@b), "\n" if @b };
try "rvalue \$b[-3]",            sub { my @b = @a; my $v = $b[-3]; die "defined\n" if defined $v };
try "exists \$b[-3]",            sub { my @b = @a; die "exists\n" if exists $b[-3] };
try "delete \$b[-3]",            sub { my @b = @a; delete $b[-3] };
try "set(\$g{nokey}) creates",   sub { my %g = %h; set($g{nokey}); die "no key\n" unless exists $g{nokey} };
