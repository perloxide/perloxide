#!/usr/bin/perl
# catalog_results.pl: builds the exhaustive outcome catalog, matrix_findings.json, from the saved isolated runs in the
# current directory -- reentry-VERSION.jsonl and reentry-tied-warning-VERSION.jsonl for 5.38.2 and 5.44.0 -- and prints
# each version's counts and the number of cross-version differences in the compared observable fields.
#
# Its output is byte for byte what the Python script it replaces wrote (PyFormat.pm writes Python's json.dumps text).
use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use JSON::PP ();
use PyFormat;

binmode STDOUT, ':encoding(UTF-8)';
my $JSON = JSON::PP->new->utf8;
my @VERSIONS = ('5.38.2', '5.44.0');

sub read_version {
    my ($version) = @_;
    my @rows;
    for my $prefix ('reentry-', 'reentry-tied-warning-') {
        my $path = "$prefix$version.jsonl";
        open my $fh, '<', $path or die "cannot read $path: $!\n";
        my @data = map { $JSON->decode($_) } grep { /\S/ } <$fh>;
        close $fh;
        push @rows, @data[1 .. $#data];
    }
    return \@rows;
}

sub key { my ($row) = @_; return [ @$row{qw(mode input action op)} ] }
sub key_str { my ($row) = @_; return join("\0", @$row{qw(mode input action op)}) }

# The fields compared across versions.  This deliberately excludes B representation details, which the raw files
# preserve; no assertion is made that the internal SV layouts are identical.
sub observable {
    my ($row) = @_;
    my %out = map { ($_ => $row->{$_}) } qw(ok result error child_status stderr);
    my $obs = $row->{observed} || {};
    $out{observed} = { map { ($_ => $obs->{$_}) } qw(text next error) };
    $out{events} = [];
    for my $e (@{ $row->{events} || [] }) {
        push @{ $out{events} }, { map { ($_ => $e->{$_}) } grep { exists $e->{$_} } qw(event message) };
    }
    my $s = PyFormat::dumps(\%out);
    for my $h (($obs->{text} // '') =~ /0x([0-9a-fA-F]+)/g) {
        no warnings 'portable';    # addresses are 64-bit
        my $dec = hex $h;
        $s =~ s/\Q$dec\E/<address>/g;
        $s =~ s/\Q0x$h\E/<address>/g;
    }
    return JSON::PP->new->decode($s);
}

my %all = map { ($_ => read_version($_)) } @VERSIONS;
my %result = (versions => {});
for my $version (@VERSIONS) {
    my $rows = $all{$version};
    my %baseline = map { (join("\0", @$_{qw(mode input op)}) => $_) } grep { $_->{action} eq 'none' } @$rows;
    my (@changed, @exceptions, @signals);
    for my $r (@$rows) {
        if (exists $r->{child_status}) { push @signals, { case => key($r), wait_status => $r->{child_status} } }
        elsif (!$r->{ok})             { push @exceptions, { case => key($r), error => $r->{error} } }
        else {
            my $b = $baseline{ join("\0", @$r{qw(mode input op)}) };
            push @changed, { case => key($r), baseline => $b->{result}, result => $r->{result} }
                if PyFormat::dumps($r->{result}) ne PyFormat::dumps($b->{result});
        }
    }
    my $successful = 0;
    $successful += ($_->{ok} ? 1 : 0) for @$rows;
    $result{versions}{$version} = {
        cases => scalar(@$rows), successful => $successful,
        changed_return_count => scalar(@changed), changed_returns => \@changed,
        exception_count => scalar(@exceptions), exceptions => \@exceptions,
        signal_count => scalar(@signals), signals => \@signals,
    };
}
my %a = map { (key_str($_) => $_) } @{ $all{'5.38.2'} };
my %b = map { (key_str($_) => $_) } @{ $all{'5.44.0'} };
die "the two versions' case keys differ\n" unless join("\n", sort keys %a) eq join("\n", sort keys %b);
my @diffs;
for my $r (@{ $all{'5.38.2'} }) {
    my $k = key_str($r);
    my ($oa, $ob) = (observable($a{$k}), observable($b{$k}));
    push @diffs, { case => key($r), '5.38.2' => $oa, '5.44.0' => $ob } if PyFormat::dumps($oa) ne PyFormat::dumps($ob);
}
$result{cross_version_observable_differences} = \@diffs;
open my $out, '>:encoding(UTF-8)', 'matrix_findings.json' or die "cannot write matrix_findings.json: $!\n";
print $out PyFormat::dumps(\%result, 2), "\n";
close $out;

# The Python script printed this summary without sort_keys, in the order it built the dicts.
my @COUNTS = qw(cases successful changed_return_count exception_count signal_count);
my %counts = (__order__ => [@VERSIONS]);
for my $v (@VERSIONS) {
    my $d = $result{versions}{$v};
    $counts{$v} = { __order__ => [@COUNTS], map { ($_ => $d->{$_}) } @COUNTS };
}
print PyFormat::dumps(\%counts, 2), "\n";
print "Cross-version differences in compared observable fields: ", scalar(@diffs), "\n";
