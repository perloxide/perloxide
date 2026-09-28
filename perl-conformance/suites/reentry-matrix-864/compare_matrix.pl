use strict; use warnings;
my ($mf, $df) = @ARGV;
open my $m, '<', $mf or die $!; open my $d, '<', $df or die $!;
my (%model, %drv);
while (<$m>) { chomp; my ($k, @f) = split /\t/, $_, -1; $model{$k} = \@f }
while (<$d>) { chomp; my ($k, @f) = split /\t/, $_, -1; $drv{$k} = \@f }
my (%b, @mis, @wdiff);
for my $k (sort keys %drv) {
    my $dv = $drv{$k}; my $mv = $model{$k};
    (my $sig = $dv->[5]) =~ s/sig=//;
    if ($sig) {
        if ($mv && ($mv->[5] // '') eq 'DIV') {
            $b{'DIVERGES-defined-perl-segv'}++;
            push @mis, "DIVERGES(segv) $k defined=[" . join(',', @$mv[0..4]) . "]";
        }
        else { $b{'SEGV-unpredicted'}++ }
        next;
    }
    if (!$mv) { $b{missing}++; next }
    if (($mv->[5] // '') eq 'DIV') {
        $b{'DIVERGES-defined-perl-ubread'}++;
        push @mis, "DIVERGES(ubread) $k defined=[" . join(',', @$mv[0..4])
            . "] observed=[" . join(',', @$dv[0..4]) . "]";
        next;
    }
    my $ok = 1;
    $ok = 0 if grep { ($dv->[$_] // '') ne ($mv->[$_] // '') } 0 .. 3;
    if ($ok) {
        if (($dv->[4] // '') ne ($mv->[4] // '')) { push @wdiff, "$k w:drv=$dv->[4] model=$mv->[4]"; $b{'match-except-w'}++ }
        else { $b{match}++ }
    }
    else { $b{mismatch}++; push @mis, "$k\n  drv=[" . join(',', @$dv[0..4]) . "]\n  mod=[" . join(',', @$mv[0..4]) . "]" }
}
print "$_: $b{$_}\n" for sort keys %b;
print "--- mismatches ---\n", join("\n", @mis), "\n" if @mis;
print "--- w-only diffs: ", scalar @wdiff, " (first 6) ---\n", join("\n", @wdiff[0..($#wdiff>5?5:$#wdiff)]), "\n" if @wdiff;
