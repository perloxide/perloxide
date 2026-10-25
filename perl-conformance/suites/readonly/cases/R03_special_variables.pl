use strict; use warnings;
# "ok" means the block ran; "dies:" is the message with its location stripped, since the reference pins the message
# and not the line it names.
sub try { my ($label, $code) = @_; my $r = eval { $code->(); "ok" }; unless (defined $r) { ($r = $@) =~ s/ at \S+ line \d+\.\n//; $r = "dies: $r" } printf "%-40s %s\n", $label, $r }
# Which special variables are readonly.
'abc' =~ /(b)/;
try "\$1 =",                  sub { $1 = 'x' };
try "\$& =",                  sub { $& = 'x' };
try "\$\` =",                  sub { $` = 'x' };
try "\$' =",                  sub { $' = 'x' };
try "\$+ =",                  sub { $+ = 'x' };
try "\$-[0] =",               sub { $-[0] = 5 };
try "\$+[0] =",               sub { $+[0] = 5 };
try "copy of \$1, modify",    sub { my $c = $1; $c .= 'x' };
try "for (\$1)",              sub { for ($1) { $_ = 'x' } };
try "sub arg \$1",            sub { sub setit { $_[0] = 'x' } setit($1) };
try "sub arg \"\$1\"",          sub { setit("$1") };
try "\$0 =",                  sub { local $0 = 'x' };
try "\$0 .=",                 sub { local $0 = $0; $0 .= 'x' };
try "\$\$ =",                  sub { local $$ = 1 };
try "\$] =",                  sub { $] = 1 };
try "\$^V =",                 sub { $^V = 1 };
try "\$^O =",                 sub { local $^O = 'x' };
try "\$^T =",                 sub { local $^T = 1 };
try "\$^W =",                 sub { local $^W = 1 };
try "\$; =",                  sub { local $; = 'x' };
try "\$ENV{X} =",             sub { local $ENV{X} = 1 };
try "\$ARGV[0]++",            sub { local @ARGV = (1); $ARGV[0]++ };
try "for (\@ARGV)",            sub { local @ARGV = (1); $_++ for @ARGV };
