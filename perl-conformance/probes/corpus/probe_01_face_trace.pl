# Demonstrates the fd 3 flag channel: one scalar's flags after each statement of a face transition.
use strict; use warnings; no warnings 'numeric';
my $s = "" . "10";
__PROBE__($s, 'plain string');
my $n = $s + 0;
__PROBE__($s, 'after $s + 0');
my $t = $s;
__PROBE__($t, 'copy');
$s .= "";
__PROBE__($s, 'after $s .= ""');
my $i = 10;
my $str = "$i";
__PROBE__($i, 'integer after "$i"');
utf8::upgrade($i);
__PROBE__($i, 'integer after utf8::upgrade');
print "done\n";
