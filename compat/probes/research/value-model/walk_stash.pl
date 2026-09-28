use strict; use warnings;
use Scalar::Util qw(refaddr reftype);
use B ();
use Time::HiRes qw(time);
use Mojolicious ();
use Mojolicious::Controller ();
use Mojo::UserAgent ();
use Mojo::DOM ();
use Moose ();
use Moose::Meta::Class ();
use DateTime ();

# Iterative walk of everything reachable from the stash roots: globs and
# their SCALAR/ARRAY/HASH/CODE slots, container contents, ref targets, and
# CV pads (a superset of captures: all pad slots of package subs).
my (%seen, $nodes, $edges) = ((), 0, 0);
my @stack = (\%main::);
my $t0 = time;
while (@stack) {
    my $r = pop @stack;
    next unless defined $r && ref $r;
    my $id = refaddr($r);
    next if $seen{$id}++;
    $nodes++;
    my $t = reftype($r) // '';
    if ($t eq 'HASH') {
        my $is_stash = (refaddr($r) == refaddr(\%main::) || grep { /::\z/ } keys %$r);
        for my $k (keys %$r) {
            my $er = \$r->{$k};
            $edges++;
            if (ref(\$r->{$k}) eq 'GLOB' || ref($r->{$k}) eq 'GLOB') {
                my $gr = ref($r->{$k}) eq 'GLOB' ? $r->{$k} : \$r->{$k};
                if ($is_stash && $k =~ /::\z/) {
                    my $sub = eval { *$gr{HASH} };
                    push @stack, $sub if $sub;
                    next;
                }
                for my $slot (qw(SCALAR ARRAY HASH CODE)) {
                    my $sr = eval { *$gr{$slot} };
                    next unless defined $sr;
                    $edges++;
                    push @stack, $sr;
                }
            }
            else { push @stack, $er }
        }
    }
    elsif ($t eq 'ARRAY') {
        for my $i (0 .. $#$r) { $edges++; push @stack, \$r->[$i] }
    }
    elsif ($t eq 'CODE') {
        my $pads = eval {
            my $cv = B::svref_2object($r);
            return [] unless $cv->isa('B::CV');
            my $pl = $cv->PADLIST;
            return [] unless $$pl;
            my @a = $pl->ARRAY;
            return [] unless @a > 1 && $a[1]->isa('B::AV');
            [map { eval { $_->object_2svref } } grep { $$_ } $a[1]->ARRAY];
        } || [];
        for my $p (@$pads) { next unless $p; $edges++; push @stack, $p }
    }
    elsif ($t eq 'SCALAR' || $t eq 'REF') {
        if (ref $$r) { $edges++; push @stack, $$r }
    }
}
my $dt = time - $t0;
printf "nodes=%d edges=%d perl_walk_ms=%.1f\n", $nodes, $edges, $dt * 1000;
