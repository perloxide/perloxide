package Probe;

# Flag projector for probed programs. The harness loads this module (with -I and -MProbe) only for
# programs that mention __PROBE__. __PROBE__($scalar, $label) writes one line to file descriptor 3:
#
#   PROBE line=N label=LABEL flags=CODE created_as=n|s|-
#
# CODE uses uppercase I, N, P for a public flag (which always implies the private one), lowercase
# i, n, p for a private-only flag, then U for IVisUV, 8 for UTF8, R for ROK, and "RO" for READONLY.
# When descriptor 3 is not open, __PROBE__ does nothing, so probed programs also run outside the
# harness. Passing the scalar through @_ aliases it and does not change its flags.

use strict;
use warnings;
use B ();

my $channel;
if (open my $fh, '>>&=', 3) {
    $fh->autoflush(1);
    $channel = $fh;
}

sub projection {
    my ($ref) = @_;
    my $flags = B::svref_2object($ref)->FLAGS;
    my $code = '';
    for my $spec ([B::SVf_IOK, B::SVp_IOK, 'I'], [B::SVf_NOK, B::SVp_NOK, 'N'], [B::SVf_POK, B::SVp_POK, 'P']) {
        my ($public, $private, $letter) = @$spec;
        $code .= ($flags & $public) ? $letter : ($flags & $private) ? lc $letter : '';
    }
    $code .= 'U'  if $flags & B::SVf_IVisUV;
    $code .= '8'  if $flags & B::SVf_UTF8;
    $code .= 'R'  if $flags & B::SVf_ROK;
    $code .= 'RO' if $flags & B::SVf_READONLY;
    $code = '0' if $code eq '';
    no warnings 'experimental::builtin';
    my $created = builtin::created_as_number($$ref) ? 'n' : builtin::created_as_string($$ref) ? 's' : '-';
    return ($code, $created);
}

sub main::__PROBE__ {
    return unless $channel;
    my ($code, $created) = projection(\$_[0]);
    my (undef, undef, $line) = caller;
    my $label = defined $_[1] ? $_[1] : '';
    print {$channel} "PROBE line=$line label=$label flags=$code created_as=$created\n";
    return;
}

1;
