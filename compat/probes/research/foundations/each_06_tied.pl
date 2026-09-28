# each/keys/delete/scalar on a tied hash: log every method call.
use strict; use warnings;
package LogHash;
our @log;
sub TIEHASH  { my %s; bless { d => { map { $_ => uc } qw(a b c) } }, shift }
sub FETCH    { push @log, "FETCH($_[1])"; $_[0]{d}{$_[1]} }
sub STORE    { push @log, "STORE($_[1]," . ($_[2] // 'undef') . ")"; $_[0]{d}{$_[1]} = $_[2] }
sub EXISTS   { push @log, "EXISTS($_[1])"; exists $_[0]{d}{$_[1]} }
sub DELETE   { push @log, "DELETE($_[1])"; delete $_[0]{d}{$_[1]} }
sub CLEAR    { push @log, "CLEAR"; %{$_[0]{d}} = () }
sub FIRSTKEY { push @log, "FIRSTKEY"; my @k = sort keys %{$_[0]{d}}; $_[0]{it} = [@k]; shift @{$_[0]{it}} }
sub NEXTKEY  { push @log, "NEXTKEY($_[1])"; shift @{$_[0]{it}} }
sub SCALAR   { push @log, "SCALAR"; scalar %{$_[0]{d}} }
package main;
tie my %t, 'LogHash';
sub run { my ($name, $code) = @_; @LogHash::log = (); $code->(); print "$name: @LogHash::log\n" }
run('each (scalar ctx)',      sub { my $k = each %t });
run('each (list ctx)',        sub { my ($k, $v) = each %t });
run('keys (void)',            sub { keys %t; });
run('keys (scalar)',          sub { my $n = keys %t });
run('scalar(%t)',             sub { my $n = scalar %t });
run('if (%t)',                sub { if (%t) {} });
run('delete during each',     sub { while (my $k = each %t) { delete $t{$k} if $k eq 'b' } });
run('%t = ()',                sub { %t = () });
run('%t = (x=>1)',            sub { %t = (x => 1) });
run('each after list-assign', sub { my @r; while (my ($k,$v) = each %t) { push @r, $k } });
