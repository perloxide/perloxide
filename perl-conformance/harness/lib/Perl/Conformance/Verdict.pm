package Oracle::Verdict;

# Classifies one test from its recorded runs. A record is a hash of stdout, stderr, fd3, and exit.
#
# Required runs: stock seed0 x2, noreuse seed0, descending seed0, stock random x2, noreuse random,
# descending random.
#
# Verdicts, checked in this order:
#   lane-A-eligible       exact-normalized records identical across both stock seed0 runs, noreuse
#                         seed0, and descending seed0.
#   lane-B-only           not lane-A-eligible, but canonical records (sorted lines, addresses erased)
#                         identical across the four seed0 runs and, separately, across the four random
#                         runs. The output's content is stable; only its line order depends on the
#                         allocator, the hash seed, or address values.
#   perl-nondeterministic stock perl disagrees with itself canonically, in seed0 or in random mode.
#   allocator-sensitive   stock perl agrees with itself, but a patched allocator changes the content.

use strict;
use warnings;
use Oracle::Normalize;

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
    my @seed0  = @{$runs}{qw(stock.seed0.1 stock.seed0.2 noreuse.seed0.1 descending.seed0.1)};
    my @random = @{$runs}{qw(stock.random.1 stock.random.2 noreuse.random.1 descending.random.1)};
    my %detail = (
        stock_seed0_self_exact  => _all_equal(map { exact_key($_) } @seed0[0, 1]) ? 1 : 0,
        seed0_builds_exact      => _all_equal(map { exact_key($_) } @seed0) ? 1 : 0,
        seed0_builds_canonical  => _all_equal(map { canonical_key($_) } @seed0) ? 1 : 0,
        random_builds_canonical => _all_equal(map { canonical_key($_) } @random) ? 1 : 0,
        noreuse_differs         => exact_key($seed0[0]) ne exact_key($seed0[2]) ? 1 : 0,
        descending_differs      => exact_key($seed0[0]) ne exact_key($seed0[3]) ? 1 : 0,
    );

    # A lane-A test is also usable in random mode when all four random runs agree exactly.
    $detail{also_lane_b} = _all_equal(map { exact_key($_) } @random) ? 1 : 0;
    return ('lane-A-eligible', \%detail) if $detail{seed0_builds_exact};
    return ('lane-B-only', \%detail) if $detail{seed0_builds_canonical} && $detail{random_builds_canonical};
    my $stock_self_canonical = canonical_key($seed0[0]) eq canonical_key($seed0[1])
        && canonical_key($random[0]) eq canonical_key($random[1]);
    return ('perl-nondeterministic', \%detail) unless $stock_self_canonical;
    return ('allocator-sensitive', \%detail);
}

1;
