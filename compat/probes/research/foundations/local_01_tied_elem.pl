# local on tied hash element vs tied array element: which methods run, in what order.
use strict; use warnings;
package LogHash;  our @log;
sub TIEHASH  { bless { k => 10 }, shift }
sub FETCH    { push @log, "FETCH($_[1])"; $_[0]{$_[1]} }
sub STORE    { push @log, "STORE($_[1]," . ($_[2] // 'undef') . ")"; $_[0]{$_[1]} = $_[2] }
sub EXISTS   { push @log, "EXISTS($_[1])"; exists $_[0]{$_[1]} }
sub DELETE   { push @log, "DELETE($_[1])"; delete $_[0]{$_[1]} }
package LogArray; our @log;
sub TIEARRAY  { bless [10], shift }
sub FETCH     { push @log, "FETCH($_[1])"; $_[0][$_[1]] }
sub STORE     { push @log, "STORE($_[1]," . ($_[2] // 'undef') . ")"; $_[0][$_[1]] = $_[2] }
sub FETCHSIZE { push @log, "FETCHSIZE"; scalar @{$_[0]} }
sub STORESIZE { push @log, "STORESIZE($_[1])"; $#{$_[0]} = $_[1]-1 }
sub EXISTS    { push @log, "EXISTS($_[1])"; exists $_[0][$_[1]] }
sub DELETE    { push @log, "DELETE($_[1])"; delete $_[0][$_[1]] }
package main;
tie my %h, 'LogHash'; tie my @a, 'LogArray';
{ local $h{k} = 20; push @LogHash::log, '|scope-exit|'; }
print "local \$h{k} = 20: @LogHash::log\n";
{ local $a[0] = 20; push @LogArray::log, '|scope-exit|'; }
print "local \$a[0] = 20: @LogArray::log\n";
@LogHash::log = (); { local $h{k}; push @LogHash::log, '|scope-exit|'; } print "local \$h{k}:      @LogHash::log\n";
@LogArray::log = (); { local $a[0]; push @LogArray::log, '|scope-exit|'; } print "local \$a[0]:      @LogArray::log\n";
@LogHash::log = (); { local $h{absent} = 5; push @LogHash::log, '|scope-exit|'; } print "local \$h{absent}=5: @LogHash::log\n";
