# Predict gd_01_order.pl's DESTRUCT-phase order from its HOLDER table using the sv_clean_objs model:
# pass 1 visits ROK SVs arena by arena (newest arena first; arenas are 4080-byte chunks, assumed newer at
# higher addresses), ascending within an arena, and drops one reference per strong holder; an object whose
# count reaches zero is destroyed at once and frees the holders it owns. Pass 2 handles glob-slot objects,
# pass 4 curses the rest. Usage: gd_predict.pl PERL PATH/TO/gd_01_order.pl [ENV=VAL ...]
use strict; use warnings; no warnings "portable";
my ($perl, $probe, @env) = @ARGV;
die "usage: gd_predict.pl PERL PATH/TO/gd_01_order.pl [ENV=VAL ...]\n" unless defined $probe && -f $probe;
my $out = do { local %ENV = (%ENV, map { split /=/, $_, 2 } @env); `$perl $probe 2>&1` };
my (@holders, @observed);
for (split /\n/, $out) {
    push @holders, { name => $1, addr => hex $2, target => $3, owner => $4 } if /^HOLDER (.+?)\s+0x([0-9a-f]+) -> (\S+) owner=(\S+)/;
    push @observed, $1 if /^DESTROY (\S+) phase=DESTRUCT/;
}
my @sorted = sort { $a->{addr} <=> $b->{addr} } @holders;
my (@arenas, $start);
for my $h (@sorted) {
    if (!@arenas || $h->{addr} - $start >= 4080) { push @arenas, []; $start = $h->{addr} }
    push @{ $arenas[-1] }, $h;
}
my %rc; $rc{ $_->{target} }++ for grep { $_->{owner} ne 'weak' } @holders;
my (%dead, %freed, @predicted);
my $drop; $drop = sub {
    my $obj = shift;
    return if $dead{$obj} || --$rc{$obj} > 0;
    $dead{$obj} = 1; push @predicted, $obj;
    for my $h (grep { $_->{owner} eq $obj && !$freed{ $_->{name} } } @holders) { $freed{ $h->{name} } = 1; $drop->($h->{target}) }
};
for my $h (map { @$_ } reverse @arenas) {
    next if $freed{ $h->{name} } || $h->{owner} eq 'weak';
    $freed{ $h->{name} } = 1; $drop->($h->{target});
}
push @predicted, 'GS', 'L';
my $obs = join ' ', @observed; my $pred = join ' ', @predicted;
printf "%-34s arenas=%d\n  observed:  %s\n  predicted: %s\n  %s\n", "@env", scalar(@arenas), $obs, $pred, ($obs eq $pred ? "MATCH" : "MISMATCH");
print "  stderr/other: $_\n" for grep { !/^(HOLDER|DESTROY)/ } split /\n/, $out;
