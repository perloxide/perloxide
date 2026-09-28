use strict; use warnings; use Scalar::Util qw(refaddr weaken);
{ my @a=(1,2,3,4); my @o; for (@a) { my $s = shift @a; push @o, "s=$s _=$_ [@a]" } print "A1 shift in loop:      ", join(" | ", @o), "\n"; }
{ my @a=(1,2,3); my @r; for (@a) { push @r, \$_ } ${$r[0]} = 9; print "A2 \\\$_ in loop:        @a ", (refaddr(\$a[0]) == refaddr($r[0]) ? "ref==\\\$a[0]" : "diff"), "\n"; }
{ my @a=(1,2,3); my @s; for my $x (@a) { push @s, sub { $x } } $a[0]=99; print "A3 closure over alias: ", join(",", map { $_->() } @s), "\n"; }
{ sub mk { my $r = \$_[0]; sub { $$r } } my $x = 5; my $c = mk($x); $x = 6; print "A4 \\\$_[0] outlives:    ", $c->(); { my $y = 1; $c = mk($y); } print " ", $c->(), "\n"; }
{ sub gg { $_[0] = "g"; "done" } sub ff { goto &gg } my $v = "v"; ff($v); print "A5 goto &sub:          $v\n"; }
{ my $x = 1; sub hh { $_[0] = 2; die "boom\n" } eval { hh($x) }; print "A6 die through alias:  $x ", ($@ =~ s/\n//r), "\n"; }
{ my @a=(1,2); my @o; for (@a) { push @a, $_+10 if $_ < 3; push @o, $_ } print "A7 push in loop:       @o | @a\n"; }
{ my @a=(1,2,3,4); my @o; for (@a) { splice(@a,1,1) if $_==1; push @o,$_ } print "A8 splice mid:         @o | @a\n"; }
{ my @a=(1,2,3); my @o; for (@a) { splice(@a,0,1) if $_==1; push @o,$_ } print "A9 splice aliased:     @o | @a\n"; }
{ my @a=(1,2); my @o; for (@a) { local $_ = "L"; push @o, $_ } print "A10 local \$_:          @o | @a\n"; }
{ my @a=(1,2); my @o; for (@a) { { local $_ = "L"; shift @a; } push @o, $_ } print "A10b local+shift:      @o | @a\n"; }
{ my @a=(1,2,3); sub two { $_[0] .= "x"; $_[1] .= "y" } two($a[0],$a[0]); print "A11 two aliases:       @a\n"; }
{ our @g=(1,2,3); sub three { my $z = shift @g; $_[0] .= "!"; $_[1] .= "?"; "$z [@g] $_[0] $_[1]" } print "A12 shift+2 aliases:   ", three($g[0],$g[0]), " | @g\n"; }
{ my @a=(1,2,3); my @o; for my $x (@a) { for my $y (@a) { shift @a if $y==2 } push @o, $x } print "A13 nested aliases:    @o | @a\n"; }
{ my %h=(k=>1); sub hk { $_[0] = 5 } hk($h{nokey}); hk($h{k}); sub hk2 { 1 } hk2($h{other}); print "A14 defelem:           ", join(",", map {"$_=$h{$_}"} sort keys %h), " other:", (exists $h{other} ? "created":"absent"), "\n"; }
{ my @a=(1,2,3); my @o; for (@a) { pop @a if $_==3; push @o, $_ } print "A15 pop aliased:       @o | @a\n"; }
{ my @a=(1,2,3); my @o; for (@a) { @a = () if $_==2; push @o, $_ } print "A16 clear in loop:     @o | @a\n"; }
{ my @a=(3,1,2); my @o; for (@a) { @a = sort @a if $_==3; push @o, $_ } print "A17 sort-assign:       @o | @a\n"; }
{ my @a=(1,2,3); my @o; for (@a) { $#a = 0 if $_==1; push @o, $_ } print "A18 truncate:          @o | @a\n"; }
{ my $done; my @a=(1,2,3); my @o; for (@a) { unshift @a, 0 if $_==1 && !$done++; push @o, $_ } print "A19 unshift:           @o | @a\n"; }
{ sub keep { \@_ } my $x=1; my $r = keep($x, 2); $x = 2; print "A20 \\\@_ escapes:       $$r[0] ", (refaddr(\$$r[0]) == refaddr(\$x) ? "==\\\$x" : "diff"), "\n"; }
{ my @a=(1,2,3); my @o; for (@a) { weaken(my $w = \$_) if $_ == 2; push @o, $_ } print "A21 weaken(\\\$_):       @o | @a\n"; }
{ my @a=(1,2,3); sub inner { $_[0]++ } for (@a) { inner($_) } print "A22 alias passed on:   @a\n"; }
{ my @a=(1,2,3); my @o; for (@a) { @a = (7,8,9) if $_==1; push @o, $_ } print "A23 reassign in loop:  @o | @a\n"; }
{ my @a=(5,6); my @o; my @b = map { $_ * 2 } @a; for (@a) { $_++ } print "A24 map alias/for mod: @a\n"; }
{ my %h=(a=>1,b=>2); $_ *= 10 for values %h; print "A25 values alias:      ", join(",", map {"$_=$h{$_}"} sort keys %h), "\n"; }
{ my %h=(a=>1,b=>2); my @o; for (values %h) { delete $h{a}; push @o, $_ } print "A26 delete under alias:", join(",", sort @o), " | ", join(",", sort keys %h), "\n"; }
