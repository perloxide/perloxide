use strict; use warnings;
use Scalar::Util qw(isdual dualvar);
my @a = (10, 20);
my $before = isdual($a[0]) ? 1 : 0;
{ open my $null, '>', '/dev/null' or die; print $null "$_\n" for @a; }
my $after = isdual($a[0]) ? 1 : 0;
print "array_elem: before=$before after_print=$after\n";
my $i = 42;
my $i0 = isdual($i) ? 1 : 0; my $s = "$i";
print "int: before=$i0 after_stringify=", (isdual($i) ? 1 : 0), "\n";
my $f = 3.14;
my $f0 = isdual($f) ? 1 : 0; my $t = "$f";
print "num: before=$f0 after_stringify=", (isdual($f) ? 1 : 0), "\n";
my $n = 'inf' + 0; my $u = "$n";
print "inf_nv_stringified=", (isdual($n) ? 1 : 0), "\n";
my $p = '10'; my $z = $p + 0;
print "numified_string=", (isdual($p) ? 1 : 0), " dualvar=", (isdual(dualvar(1, 'x')) ? 1 : 0), "\n";
