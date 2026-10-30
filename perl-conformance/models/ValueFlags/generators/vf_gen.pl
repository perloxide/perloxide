#!/usr/bin/perl
# vf_gen.pl -- the value-flags driver: runs the enumeration recipes on one Perl, merges what perl did into the model's
# factored tables, and replays the model against them.
#
#   PERL_CONFORMANCE_PERL=/path/to/perl TAG=<version> perl generators/vf_gen.pl
#   REPLAY=1 TAG=<version> TABLE=transitions|matrix|copy perl generators/vf_gen.pl
#   DIFF=<version>,<version> perl generators/vf_gen.pl
#
# Three tables, one per kind of observation (`../../README.md`, Tables and replay):
#
#   reports/transitions.tsv  (start, state, op) -> the state after op, with the recipe that reached the from-state in
#                            the run that observed the edge (the shortest when several runs did); folded over op.  The
#                            union of the transition recipes below: an edge is a fact about perl whichever search found
#                            it.
#   reports/matrix.tsv       (input, repl, then, outer) -> the eight observations of the __WARN__-handler matrix and
#                            the panic perl croaked with when the scalar was freed (`-` for none), or CRASH; a result
#                            read through the undefined window W2 is `?`.  Folded over outer.
#   reports/copy.tsv         (start, state) -> the copy check: the copy's Peek and key, the original's after the copy,
#                            and the consumers' output on each; folded over start.
#
# The transition recipes (each gen3_vf.pl or gen4_vf.pl with the given environment) are the lanes: core2 (the 13-op
# core at depth 2), full1 (all 59 ops at depth 1), walk6 (125 seeded random walks of 6 ops from each start), locale1
# (the radix ops under the harness's comma-radix locale, depth 1) and pinned (the paths in generators/pinned.tsv, each
# the shortest path vf_explore.pl found to a mismatch the other recipes do not show; absent while the file lists
# none).  At depth N every sequence of up to N ops is followed by every op, so depth 1 observes two-op sequences.  The
# handler matrix is gen_vf.pl and the copy check gen_copycheck.pl at depth 2.  Two recipes that observe the same (start, state, op) with different results are a
# CONFLICT: the key does not determine the next state, which is a key audit failure, never a model gap.
#
# A run whose TAG is a version (a perlbrew build name such as 5.44.0 or 5.44.0-threads) merges into the three tables,
# writes reports/vf.<version>.txt (each recipe's summary line, then the model against the merged transitions, the
# matrix and the copy check) and regenerates reports/coverage.txt from every version's report.  REPLAY=1 runs no perl:
# the model is replayed against the rows the named table holds at TAG and the mismatches printed.
use strict; use warnings;
use FindBin; use File::Spec; use File::Path qw(make_path);
use lib File::Spec->catdir($FindBin::Bin, '..', '..', '..', 'lib');
use Perl::Conformance::Table;
my $ROOT = $ENV{MODEL_ROOT} || File::Spec->rel2abs("$FindBin::Bin/..");
my $WORK = $ENV{MODEL_WORK} || "$ROOT/work"; make_path($WORK);
my $PERL = $ENV{PERL_CONFORMANCE_PERL} || 'perl';
my $TAG = $ENV{TAG} || 'x';
my $REPLAY = $ENV{REPLAY} ? 1 : 0;
my $VERSION_RE = qr/^\d+\.\d+\.\d+(?:-[\w-]+)?\z/;
my $GEN = "$ROOT/generators";
my $CORE = 'add,bors,cat0,catx,copy,dec,fbors,inc,iv,nv,rng,str,utf8';
my @RECIPES = (
    [ core2   => 'gen3_vf.pl', { OPS => $CORE, DEPTH => 2, PROJ => 'full' } ],
    [ full1   => 'gen3_vf.pl', { DEPTH => 1, PROJ => 'full' } ],
    [ walk6   => 'gen3_vf.pl', { WALK => 125, DEPTH => 6, SEED => 20260924, PROJ => 'full' } ],
    [ locale1 => 'gen4_vf.pl', { DEPTH => 1 } ],
    (grep { !/^\s*(?:#|\z)/ } do { open my $p, '<', "$GEN/pinned.tsv" or die "cannot read $GEN/pinned.tsv: $!\n"; <$p> })
        ? [ pinned => 'gen3_vf.pl', { PATHS => "$GEN/pinned.tsv", PROJ => 'full' } ] : (),
);
my %LOCALE_START = map { $_ => 1 } qw(c35 d35 c35x e35 c15 f35 abc c0);
my %TABLE = (
    transitions => { axes => [qw(start state op)], folded => 'op', fields => [qw(to via)], separator => '^',
                     layout => 'nested' },
    matrix      => { axes => [qw(input repl then outer)], folded => 'outer',
                     fields => [qw(result str add or nv flags calls defined panic)], separator => '/', layout => 'nested' },
    copy        => { axes => [qw(start state)], folded => 'start', fields => [qw(recipe copy original_after consumers consumers_original)], separator => '^' },
);

# Runs one generator with extra environment; returns its stdout.
sub run_gen {
    my ($script, $env) = @_;
    local @ENV{ keys %$env } = values %$env;
    local $ENV{MODEL_ROOT} = $ROOT;
    local $ENV{MODEL_WORK} = $WORK;
    local $ENV{PERL_CONFORMANCE_PERL} = $PERL;
    my $out = `$^X $GEN/$script 2>/dev/null`;

    # Exit 3 is a generator's stop: results that contradict perl-bugs.md, reported on its output.
    die "$script stopped:\n$out" if ($? >> 8) == 3;
    die "$script failed (status $?)\n" if $? && !$env->{REPLAY_EDGES} && !$env->{REPLAY_MATRIX} && !$env->{REPLAY_COPY};
    return $out;
}

# The number of ops in a recipe written as the generators write it: comma-separated, `-` when empty.
sub recipe_length {
    my ($via) = @_;
    return 0 if $via eq '-';
    my @ops = split /,/, $via;
    return scalar @ops;
}

# A table as declared in %TABLE, with every version already recorded in reports/<name>.tsv; a recorded table written in
# another layout is carried over into the declared one.
sub load_table {
    my ($name) = @_;
    my $path = "$ROOT/reports/$name.tsv";
    my $t = Perl::Conformance::Table->new(%{ $TABLE{$name} });
    return $t unless -e $path;
    my $old = Perl::Conformance::Table->load($path);
    $t->merge($_, $old->cells($_)) for @{ $old->{versions} };
    return $t;
}

# The model against a set of edges ({ "start\tstate\top" => [to, via] }): split by which generator knows the ops on
# the path, replayed through each, the mismatch lines merged.  Returns (edges, mismatches, lines).
sub replay_edges {
    my ($edges, $tag) = @_;
    my (%by);
    for my $k (sort keys %$edges) {
        my ($c, $from, $op) = split /\t/, $k;
        my ($to, $via) = @{ $edges->{$k} };
        my @path = ((split /,/, ($via eq '-' ? '' : $via)), $op);
        my $locale = $LOCALE_START{$c} || grep { /^(?:de|cl|nl)_|^copyf\z/ } @path;
        push @{ $by{ $locale ? 'gen4_vf.pl' : 'gen3_vf.pl' } }, join("\t", $c, $from, $op, $to, $via);
    }
    my ($n, $bad, @lines) = (0, 0);
    for my $script (sort keys %by) {
        my $file = "$WORK/replay_edges.$tag.$script.tsv";
        open my $fh, '>:utf8', $file or die "cannot write $file: $!\n";
        print $fh "$_\n" for @{ $by{$script} };
        close $fh;
        my $out = run_gen($script, { REPLAY_EDGES => $file, TAG => "replay_$tag" });
        my ($head, @rest) = split /\n/, $out;
        my ($t, $m) = $head =~ /transitions=(\d+) model_mismatches=(\d+)/ or die "$script replay printed no summary\n";
        $n += $t; $bad += $m; push @lines, @rest;
    }
    return ($n, $bad, sort @lines);
}

sub replay_matrix {
    my ($rows, $tag) = @_;
    my $file = "$WORK/replay_matrix.$tag.tsv";
    open my $fh, '>:utf8', $file or die "cannot write $file: $!\n";
    print $fh join("\t", $_, @{ $rows->{$_} }), "\n" for sort keys %$rows;
    close $fh;
    return run_gen('gen_vf.pl', { REPLAY_MATRIX => $file, TAG => "replay_$tag", PERL_VERSION => $tag });
}

sub replay_copy {
    my ($rows, $tag) = @_;
    my $file = "$WORK/replay_copy.$tag.tsv";
    open my $fh, '>:utf8', $file or die "cannot write $file: $!\n";
    for my $k (sort keys %$rows) {
        my ($c, $px) = split /\t/, $k;
        print $fh join("\t", map { Perl::Conformance::Table::escape($_) } $c, $px, @{ $rows->{$k} }), "\n";
    }
    close $fh;
    return run_gen('gen_copycheck.pl', { REPLAY_COPY => $file, TAG => "replay_$tag" });
}

# Table records <-> generator observations.  Transitions store `=` for a to-state equal to the from-state; the copy
# table stores `=` for a copy or after-state equal to the original's and for the original's consumers equal to the
# copy's; every field is escaped (Perl::Conformance::Table::escape).
sub copy_record {
    my ($px, $recipe, $pc, $px2, $cc, $co) = @_;
    return join("\t", map { Perl::Conformance::Table::escape($_) }
        $recipe, ($pc eq $px ? '=' : $pc), ($px2 eq $px ? '=' : $px2), $cc, ($co eq $cc ? '=' : $co));
}
sub copy_fields {
    my ($px, $rec) = @_;
    my ($recipe, $pc, $px2, $cc, $co) = map { Perl::Conformance::Table::unescape($_) } split /\t/, $rec, -1;
    return [ $recipe, ($pc eq '=' ? $px : $pc), ($px2 eq '=' ? $px : $px2), $cc, ($co eq '=' ? $cc : $co) ];
}

# DIFF=A,B: how the transitions of two versions differ, by kind.  A row the two share has the same result, or results
# that differ only in LEN (L:n on a string, the /n of B:cur/n on any other holder), or results that differ otherwise.  A
# row only one version has is counted by whether the other has the same (start, state, op) once every LEN in the state
# is blanked, with the same LEN-blind result (a state renamed by its LEN alone) or another; else it has no partner.
# Allocation policy is LEN-only by construction, so these counts show how much of a version difference is policy.
if (my $pair = $ENV{DIFF}) {
    my ($va, $vb) = split /,/, $pair;
    die "DIFF=<version>,<version>\n" unless defined $vb;
    my $t = Perl::Conformance::Table->load("$ROOT/reports/transitions.tsv");
    my ($ca, $cb) = ($t->cells($va), $t->cells($vb));
    my $to = sub {
        my ($k, $rec) = @_;
        my ($x) = map { Perl::Conformance::Table::unescape($_) } split /\t/, $rec, -1;
        return $x eq '=' ? (split /\t/, $k)[1] : $x;
    };
    my $blind = sub { my ($s) = @_; $s =~ s/\|L:\d+/|L:_/g; $s =~ s/\|B:(\d+)\/\d+/|B:$1\/_/g; return $s };
    my %n;
    for my $k (keys %$ca) {
        next unless exists $cb->{$k};
        my ($x, $y) = ($to->($k, $ca->{$k}), $to->($k, $cb->{$k}));
        $n{ $x eq $y ? 'same row, same result' : $blind->($x) eq $blind->($y) ? 'same row, LEN only'
            : 'same row, otherwise' }++;
    }
    my %only;
    for ([ $va, $ca, $cb ], [ $vb, $cb, $ca ]) {
        my ($v, $mine, $theirs) = @$_;
        for my $k (keys %$mine) {
            next if exists $theirs->{$k};
            my ($c, $from, $op) = split /\t/, $k;
            $only{$v}{ join "\t", $c, $blind->($from), $op }{ $blind->($to->($k, $mine->{$k})) }++;
        }
    }
    for my $k (keys %{ $only{$va} }) {
        my $theirs = $only{$vb}{$k};
        my $rows = 0;
        $rows += $_ for values %{ $only{$va}{$k} };
        my $kind = !$theirs ? "only $va, no partner"
            : join(' ', sort keys %{ $only{$va}{$k} }) eq join(' ', sort keys %$theirs) ? 'renamed state, LEN only'
            : 'renamed state, otherwise';
        $n{$kind} += $rows;
    }
    for my $k (keys %{ $only{$vb} }) {
        next if $only{$va}{$k};
        $n{"only $vb, no partner"} += $_ for values %{ $only{$vb}{$k} };
    }
    printf "%-32s %d\n", $_, $n{$_} for sort keys %n;
    exit 0;
}

if ($REPLAY) {
    die "REPLAY needs TAG to name a version, not `$TAG`\n" unless $TAG =~ $VERSION_RE;
    my $name = $ENV{TABLE} || '';
    die "REPLAY needs TABLE=transitions, matrix or copy, not `$name`\n" unless $TABLE{$name};
    my $t = Perl::Conformance::Table->load("$ROOT/reports/$name.tsv");
    die "the $name table holds no version $TAG (it holds @{ $t->{versions} })\n" unless grep { $_ eq $TAG } @{ $t->{versions} };
    my $cells = $t->cells($TAG);
    if ($name eq 'transitions') {
        my %e;
        for my $k (keys %$cells) {
            my ($c, $from, $op) = split /\t/, $k;
            my ($to, $via) = map { Perl::Conformance::Table::unescape($_) } split /\t/, $cells->{$k}, -1;
            $e{$k} = [ $to eq '=' ? $from : $to, $via eq '' ? '-' : $via ];
        }
        my ($n, $bad, @lines) = replay_edges(\%e, $TAG);
        print "replay=$TAG table=transitions transitions=$n model_mismatches=$bad\n"; print "$_\n" for @lines;
        exit($bad ? 1 : 0);
    }
    if ($name eq 'matrix') {
        my %r = map { my $k = $_; (join('/', split /\t/, $k) => [ map { Perl::Conformance::Table::unescape($_) } split /\t/, $cells->{$k}, -1 ]) } keys %$cells;
        print "replay=$TAG table=matrix ", replay_matrix(\%r, $TAG);
        exit 0;
    }
    my %r = map { my ($c, $px) = split /\t/, $_; ($_ => copy_fields($px, $cells->{$_})) } keys %$cells;
    print "replay=$TAG table=copy ", replay_copy(\%r, $TAG);
    exit 0;
}

# ---------------- a live run ----------------
my (@report, %edges, %via, $conflicts);
my @conflict_lines;
for my $r (@RECIPES) {
    my ($lane, $script, $env) = @$r;
    my $out = run_gen($script, { %$env, TAG => "vf_${lane}_$TAG" });
    my ($head) = split /\n/, $out;
    push @report, "$lane: $head";
    open my $in, '<:utf8', "$WORK/edges.vf_${lane}_$TAG.tsv" or die "no edges from $lane\n";
    while (<$in>) {
        chomp;
        my ($c, $from, $op, $to, $via) = split /\t/, $_, -1;
        my $k = "$c\t$from\t$op";
        if (defined $edges{$k} && $edges{$k} ne $to) {
            $conflicts++;
            push @conflict_lines, "CONFLICT $c $from --$op--> $edges{$k} (earlier recipe) / $to ($lane)";
            next;
        }
        $edges{$k} //= $to;

        # Each edge keeps the recipe of a recipe run that observed it -- the shortest, then the first in string order --
        # so the whole path (recipe and op) is one generator's to replay.
        my $have = $via{$k};
        $via{$k} = $via if !defined $have || recipe_length($via) < recipe_length($have)
            || (recipe_length($via) == recipe_length($have) && $via lt $have);
    }
    close $in;
}
my %e = map { ($_ => [ $edges{$_}, $via{$_} ]) } keys %edges;
my ($n, $bad) = replay_edges(\%e, $TAG);
my %states; $states{ join("\t", (split /\t/, $_)[0, 1]) } = 1 for keys %edges;
push @report, "transitions: union of the recipes: transitions=$n states=" . scalar(keys %states) . " model_mismatches=$bad conflicts=" . ($conflicts // 0);

my $mout = run_gen('gen_vf.pl', { TAG => "vf_matrix_$TAG" });
push @report, "matrix: " . (split /\n/, $mout)[0];
my %matrix;
open my $mi, '<:utf8', "$WORK/matrix_final.vf_matrix_$TAG.tsv" or die "no matrix observations\n";
while (<$mi>) { chomp; my ($k, @f) = split /\t/, $_, -1; $matrix{$k} = \@f }
close $mi;

my $cout = run_gen('gen_copycheck.pl', { DEPTH => 2, TAG => "vf_copy_$TAG" });
push @report, "copy: " . (split /\n/, $cout)[0];
my %copy;
open my $ci, '<:utf8', "$WORK/copy.vf_copy_$TAG.tsv" or die "no copy observations\n";
while (<$ci>) {
    chomp;
    my ($c, $px, @rest) = map { Perl::Conformance::Table::unescape($_) } split /\t/, $_, -1;
    $copy{"$c\t$px"} = copy_record($px, @rest);
}
close $ci;

print "perl=$PERL\n"; print "$_\n" for @report, @conflict_lines;
exit 0 unless $TAG =~ $VERSION_RE;

my $tt = load_table('transitions');
$tt->merge($TAG, { map {
    my ($c, $from) = split /\t/, $_;
    my ($to, $via) = @{ $e{$_} };
    ($_ => join("\t", map { Perl::Conformance::Table::escape($_) } ($to eq $from ? '=' : $to), ($via eq '-' ? '' : $via)))
} keys %e });
$tt->write("$ROOT/reports/transitions.tsv");
my $mt = load_table('matrix');
$mt->merge($TAG, { map { (join("\t", split m{/}, $_) => join("\t", map { Perl::Conformance::Table::escape($_) } @{ $matrix{$_} })) } keys %matrix });
$mt->write("$ROOT/reports/matrix.tsv");
my $ct = load_table('copy');
$ct->merge($TAG, \%copy);
$ct->write("$ROOT/reports/copy.tsv");
open my $rp, '>', "$ROOT/reports/vf.$TAG.txt" or die; print $rp "perl=$PERL\n"; print $rp "$_\n" for @report, @conflict_lines; close $rp;

# reports/coverage.txt: one line per recipe and version from every version's report.
my @rows;
for my $f (sort { Perl::Conformance::Table::version_cmp($a =~ s/.*vf\.|\.txt\z//gr, $b =~ s/.*vf\.|\.txt\z//gr) } glob "$ROOT/reports/vf.*.txt") {
    my ($ver) = $f =~ /vf\.(.+)\.txt\z/;
    open my $h, '<', $f or die; my @l = <$h>; close $h;
    for (@l) {
        chomp;
        my ($lane) = /^(\w+): / or next;
        my %v = /(\w+)=(\d+)/g;
        my @c = $lane eq 'matrix' ? ($v{rows}, '-', $v{values_ok} - $v{flag_mismatch_on_value_ok_rows}, $v{values_bad} + $v{flag_mismatch_on_value_ok_rows}, $v{ub_rows})
              : $lane eq 'copy'   ? ($v{states}, $v{states}, $v{states} - $v{consumer_copy_vs_original_differs}, $v{consumer_copy_vs_original_differs}, '-')
              : ($v{transitions}, $v{states}, $v{transitions} - $v{model_mismatches}, $v{model_mismatches}, ($lane eq 'transitions' ? "conflicts $v{conflicts}" : '-'));
        push @rows, sprintf("%-12s %-26s %9s %7s %9s %7s  %s", $lane, $ver, @c);
    }
}
open my $cv, '>', "$ROOT/reports/coverage.txt" or die;
print $cv sprintf("%-12s %-26s %9s %7s %9s %7s  %s\n", qw(lane version observed states match open undefined/conflicts));
print $cv "$_\n" for @rows;
print $cv "\nGenerated by generators/vf_gen.pl from reports/vf.<version>.txt.  `match` and `open` are the model against perl:\n",
    "`open` is a model gap, listed by `perl-conformance replay ValueFlags/transitions` (or /matrix, /copy).  The matrix's\n",
    "undefined rows are the crashes and unreliable reads of the undefined windows W1 and W2 (`../../undefined.md`); the copy\n",
    "check's `open` is a consumer that reads a copy differently from the original.  A conflict is two recipes observing\n",
    "different results for one (start, state, op): a key that does not determine the next state.\n";
close $cv;
print STDERR "merged $TAG into reports/transitions.tsv, matrix.tsv, copy.tsv\n";
