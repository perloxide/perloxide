#!/usr/bin/perl
# analyze_reentry.pl FILE.jsonl: summarizes the generated reentry matrix without re-evaluating Perl SVs.
# analyze_reentry.pl --compare A.jsonl B.jsonl: the cases whose records differ between two runs, addresses masked.
#
# Its output is byte for byte what the Python script it replaces printed (PyFormat.pm writes Python's repr and
# json.dumps text), so the committed summaries stay reproducible.
use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use JSON::PP ();
use PyFormat;

binmode STDOUT, ':encoding(UTF-8)';
my $JSON = JSON::PP->new->utf8;

sub load {
    my ($path) = @_;
    open my $fh, '<', $path or die "cannot read $path: $!\n";
    my @rows = map { $JSON->decode($_) } grep { /\S/ } <$fh>;
    close $fh;
    my $meta = shift @rows;
    return ($meta->{metadata}, \@rows);
}

sub key3 { my ($r) = @_; return join("\0", @$r{qw(mode input op)}) }
sub tuple_key { my (@v) = @_; return join("\0", @v) }

sub main {
    my ($path) = @_;
    my ($meta, $rows) = load($path);
    print PyFormat::dumps($meta), "\n";
    print "cases: ", scalar(@$rows), "\n";
    my @failures = grep { exists $_->{harness_error} || exists $_->{child_status} } @$rows;
    print "harness/process failures: ", scalar(@failures), "\n";
    print PyFormat::dumps($_), "\n" for @failures;
    my %baseline = map { (key3($_) => $_) } grep { $_->{action} eq 'none' } @$rows;
    my (%groups, %errors, %gkey, %ekey);
    for my $r (@$rows) {
        next unless exists $r->{ok};
        my $b = $baseline{ key3($r) };
        if (!$r->{ok}) {
            my ($msg) = split / at /, $r->{error}, 2;
            my @k = (@$r{qw(mode action op)}, $msg);
            my $k = tuple_key(@k);
            $ekey{$k} //= PyFormat::tuple(@k);
            push @{ $errors{$k} }, $r->{input};
        }
        elsif (!same($r->{result}, $b->{result})) {
            my @k = @$r{qw(mode action op)};
            my $k = tuple_key(@k);
            $gkey{$k} //= PyFormat::tuple(@k);
            push @{ $groups{$k} }, PyFormat::tuple($r->{input}, $b->{result}, $r->{result});
        }
    }
    print "\nRESULT DIFFERENCES FROM UNMUTATED SAME-OP BASELINE:\n";
    print PyFormat::repr($gkey{$_}), ' ', PyFormat::repr($groups{$_}), "\n" for sort keys %groups;
    print "\nEXCEPTIONS:\n";
    print PyFormat::repr($ekey{$_}), ' ', PyFormat::repr($errors{$_}), "\n" for sort keys %errors;
    print "\nWARN junk12 SUMMARY (all numeric ops):\n";
    for my $r (@$rows) {
        next unless $r->{mode} eq 'warn' && $r->{input} eq 'junk12' && grep { $r->{op} eq $_ } qw(add iv nv);
        my $obs = $r->{observed} || {};
        my %o = map { ($_ => $obs->{$_}) } grep { exists $obs->{$_} } qw(error next text);
        print join(' ', $r->{action}, $r->{op}, 'result=' . PyFormat::str($r->{result}),
            'post=' . PyFormat::str($r->{post}), 'obs=' . PyFormat::str(\%o)), "\n";
    }
    for my $s ([ 'FETCH', 'fetch', 'add' ], [ 'OVERLOAD', 'overload', 'concat' ]) {
        my ($title, $mode, $op) = @$s;
        print "\n$title junk12 SUMMARY ($op):\n";
        for my $r (@$rows) {
            next unless $r->{mode} eq $mode && $r->{input} eq 'junk12' && $r->{op} eq $op;
            print join(' ', map { PyFormat::str($_) } $r->{action}, $r->{result}, $r->{post},
                [ map { $_->{event} } @{ $r->{events} || [] } ], ($r->{observed} || {})->{text}), "\n";
        }
    }
}

# Python's != between two decoded JSON values.
sub same { my ($a, $b) = @_; return PyFormat::dumps($a) eq PyFormat::dumps($b) }

# The record with every address in its observed reference string replaced by `<address>`, in both spellings, and the
# nv_slot fields dropped.
sub normalize {
    my ($r) = @_;
    my $text = ($r->{observed} || {})->{text} // '';
    my @addresses = $text =~ /0x([0-9a-fA-F]+)/g;
    my $s = PyFormat::dumps($r);
    for my $h (@addresses) {
        no warnings q{portable};    # addresses are 64-bit
        my $dec = hex $h;
        $s =~ s/\Q$dec\E/<address>/g;
        $s =~ s/\Q0x$h\E/<address>/g;
    }
    return clean(JSON::PP->new->decode($s));
}

sub clean {
    my ($x) = @_;
    return { map { ($_ => clean($x->{$_})) } grep { $_ ne 'nv_slot' } keys %$x } if ref $x eq 'HASH';
    return [ map { clean($_) } @$x ] if ref $x eq 'ARRAY';
    return $x;
}

if (@ARGV && $ARGV[0] eq '--compare') {
    my ($am, $aa) = load($ARGV[1]);
    my ($bm, $bb) = load($ARGV[2]);
    my @diffs;
    for my $i (0 .. ($#$aa < $#$bb ? $#$aa : $#$bb)) {
        my ($a, $b) = ($aa->[$i], $bb->[$i]);
        die "case order differs at row $i\n"
            unless join("\0", @$a{qw(mode input action op)}) eq join("\0", @$b{qw(mode input action op)});
        my ($na, $nb) = (normalize($a), normalize($b));
        push @diffs, { case => [ @$a{qw(mode input action op)} ], a => $na, b => $nb } unless same($na, $nb);
    }
    my %report = (a => $am, b => $bm, rows_a => scalar(@$aa), rows_b => scalar(@$bb), differences => \@diffs);
    print PyFormat::dumps(\%report, 2), "\n";
}
else {
    main($ARGV[0]);
}
