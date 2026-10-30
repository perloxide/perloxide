#!/usr/bin/perl
# vf_explore.pl -- exploration beyond the blessed recipes: runs perl and the model deeper than vf_gen.pl does, stores
# no table, and reports only what the blessed tables do not already show.
#
#   PERL_CONFORMANCE_PERL=/path/to/perl TAG=<version> [DEPTH=2] [WALK=500 WALK_DEPTH=10 SEED=n] \
#       perl generators/vf_explore.pl
#
# Three steps, each a gen3_vf.pl run:
#
#   classes  every op on the start states and on every state one op away (depth 1).  Two ops are in one behavior class
#            when they reach the same state from every state both were applied to, and a class whose ops never change
#            the state is inert: information about which ops share a conversion path, for closing model gaps.  The
#            classes do not narrow the search, which already visits each state once and must apply every op to it.
#   search   breadth-first to DEPTH, every op on every state.  Every class is checked again on every state the search
#            reaches: two ops of one class that reach different states split it, and an inert class that changes a
#            state is NOT-INERT; the report says where.  The search's cost is its states times the ops, so depth 2
#            takes minutes and depth 3 hours; walks reach further for less.
#   walks    WALK seeded random walks of WALK_DEPTH ops from each start, over every op (none when WALK is unset).
#
# A mismatch's signature is its op and the key fields on which perl and the model differ (flags, P/N slot, L, B, T, C,
# O).  The report lists every signature the replay of the blessed transitions table at TAG does not have, each with the
# shortest path that shows it, written as a line for generators/pinned.tsv (start, tab, the path's ops); an edge whose
# result differs from the blessed table's for the same (start, state, op) is a CONFLICT -- a key that does not determine
# the next state.  The report is $WORK/explore.<TAG>.txt and the candidate paths $WORK/pinned.<TAG>.tsv.
use strict; use warnings;
use FindBin; use File::Spec; use File::Path qw(make_path);
use lib File::Spec->catdir($FindBin::Bin, '..', '..', '..', 'lib');
use Perl::Conformance::Table;
my $ROOT = $ENV{MODEL_ROOT} || File::Spec->rel2abs("$FindBin::Bin/..");
my $WORK = $ENV{MODEL_WORK} || "$ROOT/work"; make_path($WORK);
my $PERL = $ENV{PERL_CONFORMANCE_PERL} || 'perl';
my $TAG = $ENV{TAG} or die "TAG=<version> is required: the blessed table's version to compare against\n";
my $DEPTH = $ENV{DEPTH} || 2;
my $GEN = "$ROOT/generators";

# Runs gen3_vf.pl under ENV; returns its output and the edges file it wrote.
sub run_gen3 {
    my ($name, $env) = @_;

    # The search settings are this step's alone; STARTS passes through, to narrow every step.
    local @ENV{qw(WALK SEED PATHS OPS DEPTH REPLAY_EDGES)};
    delete @ENV{qw(WALK SEED PATHS OPS DEPTH REPLAY_EDGES)};
    local @ENV{ keys %$env } = values %$env;
    local @ENV{qw(MODEL_ROOT MODEL_WORK PERL_CONFORMANCE_PERL PROJ)} = ($ROOT, $WORK, $PERL, 'full');
    local $ENV{TAG} = "explore_${name}_$TAG";
    my $out = `$^X $GEN/gen3_vf.pl 2>/dev/null`;
    die "gen3_vf.pl ($name) failed (status $?)\n" if $?;
    return ($out, "$WORK/edges.explore_${name}_$TAG.tsv");
}

# { "start\tfrom" => { op => to } } from an edges file.
sub read_edges {
    my ($file) = @_;
    my %by;
    open my $fh, '<:utf8', $file or die "cannot read $file: $!\n";
    while (<$fh>) { chomp; my ($c, $from, $op, $to) = split /\t/, $_, -1; $by{"$c\t$from"}{$op} = $to }
    close $fh;
    return \%by;
}

# The behavior classes of the ops over the states in BY: ops that agree on every state both were applied to.  Returns
# a list of [ops...], each sorted, the classes in the order of their first op.
sub classes {
    my ($by) = @_;
    my %ops;
    for my $s (values %$by) { $ops{$_} = 1 for keys %$s }
    my @ops = sort keys %ops;
    my (@classes, %placed);
    for my $o (@ops) {
        next if $placed{$o};
        my @c = ($o);
        $placed{$o} = 1;
        for my $p (@ops) {
            next if $placed{$p};
            my $agree = 1;
            for my $s (values %$by) {
                next unless exists $s->{$o} && exists $s->{$p};
                if ($s->{$o} ne $s->{$p}) { $agree = 0; last }
            }
            if ($agree) { push @c, $p; $placed{$p} = 1 }
        }
        push @classes, \@c;
    }
    return @classes;
}

# Whether every op of a class leaves every state as it found it.
sub inert {
    my ($by, $class) = @_;
    for my $k (keys %$by) {
        my ($c, $from) = split /\t/, $k;
        for my $o (@$class) { return 0 if exists $by->{$k}{$o} && $by->{$k}{$o} ne $from }
    }
    return 1;
}

# Mismatch lines of a gen3/gen4 report as [start, from, op, perl, model, recipe ops...].
sub mismatches {
    my ($out) = @_;
    my @m;
    for (split /\n/, $out) {
        my ($c, $from, $op, $perl, $model, $recipe) =
            /^(\S+)\s+(\S+)\s+--(\S+?)\s*--> perl: (\S+)\s+model: (\S+)\s+\[recipe: ([^\]]*)\]/ or next;
        push @m, [ $c, $from, $op, $perl, $model, grep { length } split /,/, $recipe ];
    }
    return @m;
}

# The fields of a key, by name: `flags` for the value flags, `slot` for the slot (`P:...`, `N:...` or `-`), then each
# tagged field after it (L, B, T, C, O).
sub fields {
    my ($key) = @_;
    my ($flags, $slot, @rest) = split /\|/, $key;
    my %f = (flags => $flags, slot => $slot // '');
    for (@rest) { my ($t) = /^(\w+):/ or next; $f{$t} = $_ }
    return %f;
}

sub signature {
    my ($op, $perl, $model) = @_;
    my %p = fields($perl);
    my %m = fields($model);
    my %k = map { $_ => 1 } keys %p, keys %m;
    return "$op\t" . join(',', sort grep { ($p{$_} // '') ne ($m{$_} // '') } keys %k);
}

my @report;
my %sig;    # signature -> [start, path ops...] (the shortest seen)
my $note = sub {
    for my $m (@_) {
        my ($c, $from, $op, $perl, $model, @recipe) = @$m;
        my $s = signature($op, $perl, $model);
        my $path = [ $c, @recipe, $op ];
        $sig{$s} = $path if !$sig{$s} || @$path < @{ $sig{$s} }
            || (@$path == @{ $sig{$s} } && join(',', @$path) lt join(',', @{ $sig{$s} }));
    }
};

# The blessed signatures: the model replayed against the table at TAG.
my $blessed_out = do {
    local @ENV{qw(REPLAY TAG TABLE MODEL_ROOT MODEL_WORK)} = (1, $TAG, 'transitions', $ROOT, $WORK);
    `$^X $GEN/vf_gen.pl 2>/dev/null`;
};
die "the blessed transitions table has no version $TAG\n" unless $blessed_out =~ /^replay=\Q$TAG\E /;
my %blessed = map { (signature(@$_[2, 3, 4]) => 1) } mismatches($blessed_out);
my $table = Perl::Conformance::Table->load("$ROOT/reports/transitions.tsv");
my $cells = $table->cells($TAG);

# Step 1: the classes.
my ($cout, $cfile) = run_gen3('classes', { DEPTH => 1 });
$note->(mismatches($cout));
my $cby = read_edges($cfile);
my @classes = classes($cby);
my @inert = grep { inert($cby, $_) } @classes;
push @report, sprintf("classes: %d ops in %d classes, %d inert (%s)", scalar(map { @$_ } @classes), scalar @classes,
    scalar @inert, join(' ', map { "{@$_}" } @inert));
push @report, "  class {" . join(',', @$_) . "}" for grep { @$_ > 1 } @classes;

# Step 2: the search, and the classes checked on every state it reached.
my ($sout, $sfile) = run_gen3('search', { DEPTH => $DEPTH });
$note->(mismatches($sout));
push @report, "search: " . (split /\n/, $sout)[0];
my $sby = read_edges($sfile);
for my $class (grep { @$_ > 1 } @classes) {
    for my $k (sort keys %$sby) {
        my %to;
        push @{ $to{ $sby->{$k}{$_} } }, $_ for grep { exists $sby->{$k}{$_} } @$class;
        next unless keys %to > 1;
        my ($c, $from) = split /\t/, $k;
        push @report, "SPLIT  {" . join(',', @$class) . "} at $c $from: "
            . join('; ', map { join(',', @{ $to{$_} }) . " -> $_" } sort keys %to);
        last;
    }
}

# An inert class was left out of the inner steps; one that changes a state the search reached was not inert after all.
for my $class (@inert) {
    my ($k) = grep { my $k = $_; my $from = (split /\t/, $k)[1];
        grep { exists $sby->{$k}{$_} && $sby->{$k}{$_} ne $from } @$class } sort keys %$sby;
    next unless defined $k;
    my ($c, $from) = split /\t/, $k;
    push @report, "NOT-INERT  {" . join(',', @$class) . "} changes $c $from";
}

# Step 3: the walks.
my @edge_files = ($cfile, $sfile);
if (my $walk = $ENV{WALK}) {
    my ($wout, $wfile) = run_gen3('walks', { WALK => $walk, DEPTH => $ENV{WALK_DEPTH} || 10,
        SEED => $ENV{SEED} // 20261028 });
    $note->(mismatches($wout));
    push @report, "walks: " . (split /\n/, $wout)[0];
    push @edge_files, $wfile;
}

# Conflicts with the blessed table.
my $conflicts = 0;
for my $f (@edge_files) {
    my $by = read_edges($f);
    for my $k (sort keys %$by) {
        for my $op (sort keys %{ $by->{$k} }) {
            my $rec = $cells->{"$k\t$op"} or next;
            my ($to) = map { Perl::Conformance::Table::unescape($_) } split /\t/, $rec, -1;
            my ($c, $from) = split /\t/, $k;
            $to = $from if $to eq '=';
            next if $to eq $by->{$k}{$op};
            $conflicts++;
            push @report, "CONFLICT  $c $from --$op--> explored: $by->{$k}{$op} blessed: $to";
        }
    }
}

my @new = sort grep { !$blessed{$_} } keys %sig;
unshift @report, sprintf("explore=%s perl=%s depth=%d signatures=%d blessed=%d new=%d conflicts=%d", $TAG, $PERL,
    $DEPTH, scalar keys %sig, scalar keys %blessed, scalar @new, $conflicts);
push @report, "NEW  " . join("\t", split /\t/, $_) . "  [path: " . join(',', @{ $sig{$_} }[1 .. $#{ $sig{$_} }])
    . " from $sig{$_}[0]]" for @new;
open my $rp, '>', "$WORK/explore.$TAG.txt" or die "cannot write $WORK/explore.$TAG.txt: $!\n";
print $rp "$_\n" for @report;
close $rp;
my %seen;
open my $pp, '>', "$WORK/pinned.$TAG.tsv" or die "cannot write $WORK/pinned.$TAG.tsv: $!\n";
for my $s (@new) {
    my ($c, @ops) = @{ $sig{$s} };
    my $line = "$c\t" . join(',', @ops);
    print $pp "$line\n" unless $seen{$line}++;
}
close $pp;
print "$_\n" for @report;
exit($conflicts ? 1 : 0);
