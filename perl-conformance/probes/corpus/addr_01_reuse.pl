# SV head reuse: when does a newly allocated container, scalar, or object get a freed one's address?
use strict; use warnings;
use Scalar::Util qw(refaddr);
$| = 1;
sub same { $_[0] == $_[1] ? "REUSED" : "fresh" }
sub fresh_scalar { my $x = shift; \$x }
my %r;
# 1. free then allocate the same kind, via undef
for my $kind (['scalar', sub { fresh_scalar(1) }], ['array', sub { [] }], ['hash', sub { {} }], ['object', sub { bless {}, 'Obj' }], ['closure', sub { my $v = 1; sub { $v } }]) {
    my $x = $kind->[1]->(); my $a = refaddr $x; undef $x;
    my $y = $kind->[1]->();
    printf "%-44s %s\n", "undef, then new $kind->[0]", same($a, refaddr $y);
}
# 2. cross-kind: free a hash, allocate an array (heads share one free list; bodies do not)
{ my $h = {}; my $a = refaddr $h; undef $h; my $ar = []; printf "%-44s %s\n", "free hash, allocate array", same($a, refaddr $ar); }
{ my $o = bless [], 'Obj'; my $a = refaddr $o; undef $o; my $s = fresh_scalar(2); printf "%-44s %s\n", "free blessed array, allocate scalar", same($a, refaddr $s); }
# 3. scope exit
my $scoped; { my $h = {}; $scoped = refaddr $h; } { my $h2 = {}; printf "%-44s %s\n", "scope exit, then new hash", same($scoped, refaddr $h2); }
# 4. delete from a hash (the deleted value is a mortal freed at statement end)
{ my %h; $h{k} = {}; my $a = refaddr $h{k}; delete $h{k}; $h{k2} = {}; printf "%-44s %s\n", "delete \$h{k}, then \$h{k2} = {}", same($a, refaddr $h{k2}); }
{ my %h; $h{k} = {}; my $a = refaddr $h{k}; my $n = {}; delete $h{k}; my $m = {}; printf "%-44s %s\n", "delete in void, next statement allocates", same($a, refaddr $m); }
# 5. LIFO order across two frees
{ my ($p, $q) = ({}, {}); my ($ap, $aq) = (refaddr $p, refaddr $q); undef $p; undef $q;
  my ($s, $t) = ({}, {});
  # a {} allocates two heads (the hash and the reference); which freed heads come back, and in which order?
  printf "%-44s first new=%s second new=%s\n", "free P then Q, allocate two hashes", (refaddr $s == $aq ? 'Q' : refaddr $s == $ap ? 'P' : 'other'), (refaddr $t == $aq ? 'Q' : refaddr $t == $ap ? 'P' : 'other'); }
# 6. intervening allocations between free and reuse
{ my $h = {}; my $a = refaddr $h; undef $h; my $str = join "", "a", "b"; my @list = (1, 2, 3); my $h2 = {};
  printf "%-44s %s\n", "free, join + 3-element list, new hash", same($a, refaddr $h2); }
