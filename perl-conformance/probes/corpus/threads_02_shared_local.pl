# perl-conformance-requires: threads
# local on threads::shared variables with two threads involved.  Every step is handed off with a
# condition variable, so the interleaving is the one written here and the output is a function of
# the program.  What it shows:
#   - local on a shared element or scalar overwrites the shared cell in place: the other thread
#     sees the localized value for as long as the scope lasts;
#   - the restore writes the saved value twice, through the shared SV the saved proxy points at
#     and at the original index, whichever thread moved the array in between (see
#     local_03_shared_elem_move.pl for the single-thread form and the mechanism);
#   - a reference to a shared element is a proxy by index and reads whatever is there now;
#   - two threads localizing the same element each write back their own saved value when their
#     scope ends, in whatever order the scopes end;
#   - an absent element or key of a shared aggregate is never recorded as absent, because
#     threads::shared::tie has EXISTS but no DELETE method and pp_aelem/pp_helem consult EXISTS
#     only when both exist (SvCANEXISTDELETE); the restore STOREs the saved undef at the index,
#     so the slot or key exists afterward.
use strict; use warnings;
use threads; use threads::shared;

my $step :shared = 0;
sub reach { my ($n) = @_; lock $step; $step = $n; cond_broadcast $step }
sub await { my ($n) = @_; lock $step; cond_wait $step until $step >= $n }
sub fmt   { join ', ', map { defined $_ ? $_ : 'undef' } @_ }
sub show  { my ($who, $label, @v) = @_; printf "%-5s %-42s (%s)\n", $who, $label, fmt(@v) }
sub start { my ($code) = @_; $step = 0; threads->create($code) }

my @a :shared;
my %h :shared;
our $s :shared;

print "A. child localizes an element; main shifts while the local is active\n";
@a = (10, 20, 30);
my $t = start sub {
    {
        local $a[1] = 99; show 'child', 'after local $a[1] = 99', @a; reach 1; await 2;
        show 'child', 'after main shifted', @a;
    }
    show 'child', 'after its scope', @a; reach 3;
};
await 1; show 'main', 'during the child local', @a;
my $r = \$a[1]; shift @a; show 'main', 'after shift', @a; reach 2; await 3;
show 'main', 'after the child scope', @a;
printf "%-5s %-42s %s\n", 'main', '$$r, \$a[1] taken before the shift', $$r;
$t->join;

print "\nB. main localizes; the child shifts during it\n";
@a = (10, 20, 30);
$t = start sub { await 1; shift @a; show 'child', 'shifted during the main local', @a; reach 2 };
{ local $a[1] = 99; reach 1; await 2; show 'main', 'inside, after the child shift', @a; }
show 'main', 'after its scope', @a; $t->join;

print "\nC. both threads localize the same element; the inner (main) scope ends first\n";
@a = (10, 20, 30);
$t = start sub {
    { local $a[1] = 99; reach 1; await 2; show 'child', 'after main local and exit', @a; }
    show 'child', 'after its scope', @a; reach 3;
};
await 1;
{ local $a[1] = 7; show 'main', 'inside its local', @a; }
show 'main', 'after its scope', @a; reach 2; await 3;
show 'main', 'after the child scope', @a; $t->join;

print "\nD. child localizes; main unshifts and pushes\n";
@a = (10, 20, 30);
$t = start sub { { local $a[1] = 99; reach 1; await 2; } show 'child', 'after its scope', @a; reach 3 };
await 1; unshift @a, 0; push @a, 40; show 'main', 'after unshift 0, push 40', @a; reach 2; await 3; $t->join;

print "\nE. child localizes an absent element; main shifts\n";
@a = (10, 20, 30);
$t = start sub {
    { local $a[5] = 50; show 'child', 'after local $a[5] = 50', @a; reach 1; await 2; }
    show 'child', 'after its scope', @a; reach 3;
};
await 1; shift @a; show 'main', 'after shift', @a; reach 2; await 3;
printf "%-5s %-42s %s\n", 'main', 'exists after', join ' ', map { exists $a[$_] ? "$_:yes" : "$_:no" } 0 .. 5;
$t->join;

print "\nF. child localizes a shared scalar\n";
$s = 'S';
$t = start sub { { local $s = 'L'; reach 1; await 2; } show 'child', 'after its scope', $s; reach 3 };
await 1; show 'main', 'during the child local', $s; reach 2; await 3;
show 'main', 'after the child scope', $s; $t->join;

print "\nG. child localizes a present and an absent key of a shared hash; main deletes the present one\n";
%h = (k => 1);
$t = start sub {
    { local $h{k} = 2; local $h{new} = 3; reach 1; await 2; }
    show 'child', 'after its scope: k, new, exists new', $h{k}, $h{new}, (exists $h{new} ? 'yes' : 'no'); reach 3;
};
await 1; show 'main', 'during the child local: k, new', $h{k}, $h{new}; delete $h{k}; reach 2; await 3;
show 'main', 'after the child scope: k, exists new', $h{k}, (exists $h{new} ? 'yes' : 'no'); $t->join;
