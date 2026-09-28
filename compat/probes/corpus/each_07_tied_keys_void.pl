use strict; use warnings;
package LogHash; our @log;
sub TIEHASH { bless { d => { a=>1, b=>2, c=>3 } }, shift }
sub FETCH { push @log, "FETCH($_[1])"; $_[0]{d}{$_[1]} }
sub FIRSTKEY { push @log, "FIRSTKEY"; my @k = sort keys %{$_[0]{d}}; $_[0]{it} = \@k; shift @k }
sub NEXTKEY { push @log, "NEXTKEY($_[1])"; shift @{$_[0]{it}} }
package main;
tie my %t, 'LogHash';
my $k1 = each %t; my $k2 = each %t;
keys %t;
my $k3 = each %t;
print "each,each,keys(void),each: @LogHash::log  -> k3=$k3\n";
