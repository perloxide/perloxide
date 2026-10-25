use strict; use warnings;
# "ok" means the block ran; "dies:" is the message with its location stripped, since the reference pins the message
# and not the line it names.
sub try { my ($label, $code) = @_; my $r = eval { $code->(); "ok" }; unless (defined $r) { ($r = $@) =~ s/ at \S+ line \d+\.\n//; $r = "dies: $r" } printf "%-40s %s\n", $label, $r }
# How readonly-ness propagates, and which operations a readonly scalar refuses.
use constant K => 7;
try "copy of readonly alias",             sub { for (1) { my $c = $_; $c++ } };
try "list-assign copy",                   sub { my ($x) = (1); $x++ };
try "ref to readonly alias, deref write", sub { for (1) { my $r = \$_; $$r++ } };
try "ref to literal, deref write",        sub { my $r = \1; $$r++ };
try "ref to literal, deref copy",         sub { my $r = \1; my $c = $$r; $c++ };
try "SvREADONLY on, assign",              sub { my $x = 1; Internals::SvREADONLY($x, 1); $x = 2 };
try "SvREADONLY on, copy then modify",    sub { my $x = 1; Internals::SvREADONLY($x, 1); my $y = $x; $y++ };
try "SvREADONLY on then off, assign",     sub { my $x = 1; Internals::SvREADONLY($x, 1); Internals::SvREADONLY($x, 0); $x = 2 };
try "SvREADONLY reads literal alias",     sub { for (1) { die "not flagged\n" unless Internals::SvREADONLY($_) } };
try "SvREADONLY reads range element",     sub { for (1..1) { die "flagged\n" if Internals::SvREADONLY($_) } };
try "assignment",                         sub { for (1) { $_ = 2 } };
try "++",                                 sub { for (1) { $_++ } };
try "+=",                                 sub { for (1) { $_ += 1 } };
try ".=",                                 sub { for ('a') { $_ .= 'b' } };
try "s/// matching",                      sub { for ('a') { s/a/b/ } };
try "s/// not matching",                  sub { for ('a') { s/z/b/ } };
try "tr/// matching",                     sub { for ('a') { tr/a/b/ } };
try "tr/// not matching",                 sub { for ('a') { tr/z/b/ } };
try "tr///r",                             sub { for ('a') { my $t = tr/a/b/r } };
try "chop",                               sub { for ('ab') { chop } };
try "chomp with nothing to remove",       sub { for ('ab') { chomp } };
try "undef \$_",                           sub { for (1) { undef $_ } };
try "local \$_",                           sub { for (1) { local $_ = 5 } };
try "rvalue uses",                        sub { for ('12') { my $n = $_ + 0; my $l = length; my $s = "$_" } };
try "bless a ref to it",                  sub { for (1) { bless \$_, 'Foo' } };
try "utf8::upgrade",                      sub { for ('a') { utf8::upgrade($_) } };
try "utf8::downgrade",                    sub { for ("\x{e9}") { utf8::downgrade($_) } };
try "pos() assignment",                   sub { for ('a') { pos($_) = 0 } };
try "study",                              sub { for ('a') { study } };
