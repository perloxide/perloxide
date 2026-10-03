# oracle-requires: locale radix_comma.UTF-8
# Locale-dependent parse: is a numeric cache made under 'use locale' (comma radix) reused outside it?
use strict; use warnings; no warnings 'numeric';
use POSIX qw(setlocale LC_NUMERIC);
my $got = setlocale(LC_NUMERIC, "radix_comma.UTF-8"); print "setlocale: ", ($got // 'undef'), "\n";
my $s = "" . "1,5";
my $inside;
{ use locale; $inside = $s + 0; }
my $outside_cached = $s + 0;
my $outside_fresh  = ("" . $s) + 0;
my $copy = $s; my $copy_outside = $copy + 0;
print "copy of the scalar, read outside: $copy_outside\n";
print "under use locale: $inside; outside, same scalar: $outside_cached; outside, fresh copy: $outside_fresh\n";
my $t = "" . "1,5";
my $first_outside = $t + 0;
my $then_inside; { use locale; $then_inside = $t + 0; }
my $inside_fresh; { use locale; $inside_fresh = ("" . $t) + 0; }
print "outside first: $first_outside; then under use locale, same scalar: $then_inside; under use locale, fresh copy: $inside_fresh\n";
