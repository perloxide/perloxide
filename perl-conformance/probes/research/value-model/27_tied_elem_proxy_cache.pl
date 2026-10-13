# A held reference to a tied element is a proxy that FETCHes once and then answers from its cache.
#
# `\$a[1]` on a tied array is a proxy SV with tied-element magic.  Its first read FETCHes and sets MGf_GSKIP
# on that magic (Perl_magic_getpack, mg.c 2240); only a set through the same proxy clears the flag (mg_set,
# mg.c 287).  Every later read returns the value the proxy cached, whatever the tie now holds at the index,
# and a write through the proxy STOREs at the index and re-arms the FETCH.  A fresh `$a[1]` is a new proxy.
# `local $a[1]` saves and restores through proxies of its own, so a proxy the program holds is not
# invalidated by the restore: first read before the local, it reports the pre-local value inside the scope;
# first read inside the scope, it keeps reporting the localized value after the scope.
#   1. weaken on a tied element, bare or as `${\$a[0]}`, leaves the tie's own slot strong (the proxy is a
#      temporary and weaken runs no set magic)
#   2. read before a shift, read after: the cached pre-shift value
#   3. not read before the shift: the first read FETCHes the moved array
#   4. read before, written after the shift: STORE at the index, then a re-FETCH
#   5. a copy of the reference is the same proxy, same cache
#   6. local, proxy read before: inside and after, the pre-local value
#   7. local, proxy first read inside: inside and after, the localized value
#   8. local with a shift inside, proxy read before: the cached value, which the restore happens to match
use strict; use warnings;
use Scalar::Util qw(weaken isweak);
{
    package TA; require Tie::Array; our @ISA = ('Tie::StdArray');
    sub STORE { my ($s, $i, $v) = @_; print "    STORE[$i]=", (!defined $v ? 'undef' : ref $v ? 'ref' : $v), "\n"; $s->[$i] = $v }
    sub FETCH { my ($s, $i) = @_; print "    FETCH[$i]\n"; $s->[$i] }
    sub SHIFT { print "    SHIFT\n"; shift @{$_[0]} }
}
$| = 1;
tie my @a, 'TA';
sub reset_a { @a = (); @a = (10, 20, 30) }
sub head   { print "\n$_[0]\n" }

head "1. weaken on a tied element, bare and as \${\\\$a[0]}";
my $t = [];
$a[0] = $t; print "  (the STORE above is the assignment)\n";
{ no warnings; weaken $a[0]; }       print "  after weaken \$a[0]:      tie slot ", (isweak((tied @a)->[0]) ? 'weak' : 'strong'), "\n";
{ no warnings; weaken ${\$a[0]}; }   print "  after weaken \${\\\$a[0]}: tie slot ", (isweak((tied @a)->[0]) ? 'weak' : 'strong'), "\n";

head "2. read before the shift, read after";
reset_a(); { my $r = \$a[1]; my $v = $$r; shift @a; print "  via r: $$r\n" }
head "3. not read before the shift";
reset_a(); { my $r = \$a[1]; shift @a; print "  via r: $$r\n" }
head "4. read before, written after the shift";
reset_a(); { my $r = \$a[1]; my $v = $$r; shift @a; $$r = 99; print "  via r: $$r; array: @a\n" }
head "5. a copy of the reference";
reset_a(); { my $r = \$a[1]; my $r2 = $r; my $v = $$r; shift @a; print "  via r2: $$r2\n" }
head "6. local, proxy read before";
reset_a(); { my $r = \$a[1]; my $v = $$r; { local $a[1] = 99; print "  inside via r: $$r; fresh: $a[1]\n" } print "  after via r: $$r; fresh: $a[1]\n" }
head "7. local, proxy first read inside";
reset_a(); { my $r = \$a[1]; { local $a[1] = 99; print "  inside via r: $$r; fresh: $a[1]\n" } print "  after via r: $$r; fresh: $a[1]\n" }
head "8. local with a shift inside, proxy read before";
reset_a(); { my $r = \$a[1]; my $v = $$r; { local $a[1] = 99; shift @a } print "  after via r: $$r; fresh: $a[1]; array: @a\n" }
