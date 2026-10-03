package Oracle::Verdict;

# Classifies one test from its recorded runs. A record is a hash of stdout, stderr, fd3, and exit.
#
# Required runs, in two groups plus a pair:
#   seed0 group   stock seed0 x2, noreuse seed0, descending seed0
#   seed ladder   stock seed1, stock seed2, stock seed3, noreuse seed1, descending seed1
#   random pair   stock random x2
# Every seedN run pins PERL_HASH_SEED, so each is reproducible; the ladder exercises three further
# hash orders and the allocator variants under one of them. The random pair is the only sampled
# input and serves one rule only: stock perl disagreeing with itself.
#
# Verdicts, checked in this order:
#   lane-A-eligible       exact-normalized records identical across the seed0 group.
#   lane-B-only           not lane-A-eligible, but canonical records (sorted lines, addresses erased)
#                         identical across the seed0 group and, separately, across the ladder. The
#                         output's content is stable; only its line order depends on the allocator,
#                         the hash seed, or address values.
#   perl-nondeterministic stock perl disagrees with itself canonically, in seed0 or in random mode.
#   allocator-sensitive   stock perl agrees with itself, but a patched allocator changes the content.
#
# also_lane_b, on a lane-A test: exact-normalized records identical across the seed0 group and the
# ladder together, so the output does not depend on hash order under four distinct orders either.

use strict;
use warnings;
use Oracle::Normalize;

our @SEED0_GROUP  = qw(stock.seed0.1 stock.seed0.2 noreuse.seed0.1 descending.seed0.1);
our @SEED_LADDER  = qw(stock.seed1.1 stock.seed2.1 stock.seed3.1 noreuse.seed1.1 descending.seed1.1);
our @RANDOM_PAIR  = qw(stock.random.1 stock.random.2);
our @REQUIRED     = (@SEED0_GROUP, @SEED_LADDER, @RANDOM_PAIR);

sub exact_key {
    my ($r) = @_;
    return join "\0", Oracle::Normalize::exact($r->{stdout}, $r->{stderr}, $r->{fd3}), $r->{exit};
}

sub canonical_key {
    my ($r) = @_;
    return join "\0", Oracle::Normalize::canonical($r->{stdout}, $r->{stderr}, $r->{fd3}), $r->{exit};
}

sub _all_equal {
    my (@keys) = @_;
    return !grep { $_ ne $keys[0] } @keys;
}

# classify(\%runs) where %runs maps run names to records. Returns (verdict, \%details).
sub classify {
    my ($runs) = @_;
    my @seed0  = @{$runs}{@SEED0_GROUP};
    my @ladder = @{$runs}{@SEED_LADDER};
    my @random = @{$runs}{@RANDOM_PAIR};
    my %detail = (
        stock_seed0_self_exact  => _all_equal(map { exact_key($_) } @seed0[0, 1]) ? 1 : 0,
        seed0_builds_exact      => _all_equal(map { exact_key($_) } @seed0) ? 1 : 0,
        seed0_builds_canonical  => _all_equal(map { canonical_key($_) } @seed0) ? 1 : 0,
        ladder_builds_canonical => _all_equal(map { canonical_key($_) } @ladder) ? 1 : 0,
        noreuse_differs         => exact_key($seed0[0]) ne exact_key($seed0[2]) ? 1 : 0,
        descending_differs      => exact_key($seed0[0]) ne exact_key($seed0[3]) ? 1 : 0,
    );
    $detail{also_lane_b} = _all_equal(map { exact_key($_) } @seed0, @ladder) ? 1 : 0;
    return ('lane-A-eligible', \%detail) if $detail{seed0_builds_exact};
    return ('lane-B-only', \%detail) if $detail{seed0_builds_canonical} && $detail{ladder_builds_canonical};
    my $stock_self_canonical = canonical_key($seed0[0]) eq canonical_key($seed0[1])
        && canonical_key($random[0]) eq canonical_key($random[1]);
    return ('perl-nondeterministic', \%detail) unless $stock_self_canonical;
    return ('allocator-sensitive', \%detail);
}

1;
