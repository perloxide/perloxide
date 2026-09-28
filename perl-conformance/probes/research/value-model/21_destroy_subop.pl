use strict; use warnings;
our ($x, $y, %h, $watch);
package O { sub new { bless {}, shift } sub DESTROY { print "D(", $main::watch->(), ") " } }
package main; $| = 1;
$watch = sub { defined $x ? (ref $x ? 'REF' : $x) : 'undef' };
$x = O->new; $x = 5; print "| ";
$watch = sub { !exists $h{k} ? 'gone' : defined $h{k} ? (ref $h{k} ? 'REF' : $h{k}) : 'undef' };
$h{k} = O->new; $h{k} = 7; print "| ";
$watch = sub { defined $y ? (ref $y ? 'REF' : $y) : 'undef' };
$y = O->new; undef $y; print "| ";
$watch = sub { exists $h{d} ? (ref $h{d} ? 'REF' : 'val') : 'gone' };
$h{d} = O->new; delete $h{d}; print "|\n";
