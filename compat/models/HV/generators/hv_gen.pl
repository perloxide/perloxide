#!/usr/bin/perl
# hv_gen.pl -- validates HV.pm below program level (Hash::Util bucket_array / hash_traversal_mask / hash_value) and at
# program level (keys/each/delete/insert/clear/undef/DESTROY traces), on the oracle perl given in $ENV{ORACLE}.
use strict; use warnings; use FindBin; use lib ($ENV{MODEL_ROOT} || "$FindBin::Bin/.."); my $WORK = $ENV{MODEL_WORK} || ($ENV{MODEL_ROOT} || "$FindBin::Bin/..") . "/work"; mkdir $WORK unless -d $WORK; require HV;
my $PERL = $ENV{ORACLE} || 'perl'; my $TAG = $ENV{TAG} || 'x';
my @lanes = ( ['seed0', '0', undef], ['seedX_perturb0', 'deadbeef0123456789abcdef', '0'], ['seedX_perturb2', 'deadbeef0123456789abcdef', '2'] );
sub keyset { my $n=shift; map { $_ % 7 == 3 ? ("longkey_" . ("x" x 20) . "_$_") : "k$_" } 1..$n }   # one key in seven exceeds SBOX32_MAX_LEN
my ($ok,$bad)=(0,0); my @rep;
sub env { my ($seed,$pert)=@_; "env -u PERL_PERTURB_KEYS PERL_HASH_SEED=$seed " . (defined $pert ? "PERL_PERTURB_KEYS=$pert " : "") }
# ---------- level 1: structure ----------
for my $lane (@lanes) { my ($lname,$seed,$pert)=@$lane;
  for my $n (5, 40, 700, 5000) {
    my @keys = keyset($n);
    my $src = 'use strict; use Hash::Util qw(bucket_array hash_traversal_mask hash_value); my %h; my @k = @ARGV; $h{$_} = 1 for @k; my @kk = keys %h;'
      . 'my $b = bucket_array(\%h); print join("|", map { ref $_ ? join(",", @$_) : $_ } @$b), "\n"; print hash_traversal_mask(\%h), "\n"; print join("\n", map { hash_value($_) } @k), "\n";';
    open my $fh, '>', "$WORK/hv_child.pl" or die; print $fh $src; close $fh;
    my $out = `${\ env($seed,$pert)} $PERL $WORK/hv_child.pl @keys 2>&1`; my ($ba,$mask,@hv) = split /\n/, $out;
    my $p = HV::Harness::NewProcess($seed, $pert); my $hv = HV::Harness::NewHV($p); HV::hv_common($hv, $_, 1) for @keys; HV::Harness::Keys($hv);
    my $mba = join("|", map { ref $_ ? join(",", @$_) : $_ } @{ HV::Harness::BucketArray($hv) }); my $mmask = $hv->{aux}{rand};
    my @mhv = map { $p->PERL_HASH_WITH_STATE($_) } @keys; my $hvok = (join(",",@hv) eq join(",",@mhv));
    my $name = "structure.$lname.$n";
    if ($lname eq 'seedX_perturb2') { push @rep, "EXCLUDED $name (DETERMINISTIC perturbation depends on all prior hash activity in the process): hash-values " . ($hvok ? "match" : "differ") . ", buckets " . ($ba eq $mba ? "match" : "differ"); next }
    my @bad; push @bad, "hash_value" unless $hvok; push @bad, "traversal mask perl=$mask model=$mmask" unless $mask == $mmask; push @bad, "bucket_array" unless $ba eq $mba;
    if (@bad) { $bad++; push @rep, "MISMATCH $name: @bad" . ($ba ne $mba && $n <= 40 ? "\n  perl:  $ba\n  model: $mba" : "") } else { $ok++ }
  } }
# ---------- level 2: programs ----------
my $pre = 'use strict; no warnings "once"; $SIG{__WARN__} = sub { print "W\n" if $_[0] =~ /each\(\) on hash after insertion/ }; package O; sub new { bless {id=>$_[1]}, $_[0] } sub DESTROY { print "D$_[0]{id} " } package main; my %h;';
my @progs = (
  [keys20 => 'my @k = map { "k$_" } 1..20; $h{$_}=1 for @k; print join(",", keys %h), "\n";'],
  [each20 => 'my @k = map { "k$_" } 1..20; $h{$_}=1 for @k; while (my ($k) = each %h) { print "$k " } print "\n";'],
  [delcur => 'my @k = map { "k$_" } 1..20; $h{$_}=1 for @k; while (my ($k) = each %h) { print "$k "; delete $h{$k} } print "| ", scalar(keys %h), "\n";'],
  [delother => 'my @k = map { "k$_" } 1..20; $h{$_}=1 for @k; my $n=0; while (my ($k) = each %h) { print "$k "; if (!$n++) { delete $h{$_} for grep { $_ ne $k } @k[0..4] } } print "| ", join(",", sort keys %h), "\n";'],
  [inseach => 'my @k = map { "k$_" } 1..20; $h{$_}=1 for @k; my $n=0; while (my ($k) = each %h) { print "$k "; $h{"n$n"}=1 if $n++ < 3 } print "\n";'],
  [reset => 'my @k = map { "k$_" } 1..20; $h{$_}=1 for @k; my ($a) = each %h; my ($b) = each %h; my @x = keys %h; my ($c) = each %h; print "$a $b $c\n";'],
  [clearfill => 'my @k = map { "k$_" } 1..40; $h{$_}=1 for @k; %h = (); $h{$_}=1 for @k; print join(",", keys %h), "\n";'],
  [undeffill => 'my @k = map { "k$_" } 1..40; $h{$_}=1 for @k; undef %h; $h{$_}=1 for @k; print join(",", keys %h), "\n";'],
  [destroy => '{ my %g; $g{"k$_"} = O->new("k$_") for 1..20; } print "\n";'],
  [destroy_after_iter => '{ my %g; $g{"k$_"} = O->new("k$_") for 1..20; my @x = keys %g; my ($a) = each %g; } print "\n";'],
);
for my $lane (@lanes[0,1]) { my ($lname,$seed,$pert)=@$lane;
  for my $pr (@progs) { my ($pname,$code)=@$pr;
    open my $fh, '>', "$WORK/hv_child.pl" or die; print $fh "$pre\n$code\n"; close $fh;
    my $got = `${\ env($seed,$pert)} $PERL $WORK/hv_child.pl 2>&1`;
    my $exp = replay($pname, $seed, $pert); my $name = "program.$lname.$pname";
    if ($got eq $exp) { $ok++ } else { $bad++; push @rep, "MISMATCH $name\n  perl:  $got  model: $exp" }
  } }
sub replay { my ($pname,$seed,$pert)=@_; my $p = HV::Harness::NewProcess($seed,$pert); my $hv = HV::Harness::NewHV($p); my $out='';
  my $keys = sub { my $n=shift; my @k = map { "k$_" } 1..$n; HV::hv_common($hv,$_,1) for @k; @k };
  my $each = sub { my $w=0; my $e = HV::hv_iternext_flags($hv, \$w); $out .= "W\n" if $w; $e };
  if ($pname eq 'keys20') { $keys->(20); $out .= join(",", HV::Harness::Keys($hv)) . "\n" }
  elsif ($pname eq 'each20') { $keys->(20); while (my $e = $each->()) { $out .= "$e->{k} " } $out .= "\n" }
  elsif ($pname eq 'delcur') { $keys->(20); while (my $e = $each->()) { $out .= "$e->{k} "; HV::hv_delete_common($hv,$e->{k}) } $out .= "| " . HV::Harness::Keys($hv) . "\n" }
  elsif ($pname eq 'delother') { my @k=$keys->(20); my $n=0; while (my $e = $each->()) { $out .= "$e->{k} "; if (!$n++) { HV::hv_delete_common($hv,$_) for grep { $_ ne $e->{k} } @k[0..4] } } $out .= "| " . join(",", sort(HV::Harness::Keys($hv))) . "\n" }
  elsif ($pname eq 'inseach') { $keys->(20); my $n=0; while (my $e = $each->()) { $out .= "$e->{k} "; HV::hv_common($hv,"n$n",1) if $n++ < 3 } $out .= "\n" }
  elsif ($pname eq 'reset') { $keys->(20); my $a=$each->()->{k}; my $b=$each->()->{k}; HV::Harness::Keys($hv); my $c=$each->()->{k}; $out .= "$a $b $c\n" }
  elsif ($pname eq 'clearfill') { my @k=$keys->(40); HV::hv_clear($hv); HV::hv_common($hv,$_,1) for @k; $out .= join(",", HV::Harness::Keys($hv)) . "\n" }
  elsif ($pname eq 'undeffill') { my @k=$keys->(40); HV::hv_undef_flags($hv); HV::hv_common($hv,$_,1) for @k; $out .= join(",", HV::Harness::Keys($hv)) . "\n" }
  elsif ($pname eq 'destroy') { $keys->(20); $out .= join("", map { "D$_ " } HV::hfree_next_entry_all($hv)) . "\n" }
  elsif ($pname eq 'destroy_after_iter') { $keys->(20); HV::Harness::Keys($hv); $each->(); $out .= join("", map { "D$_ " } HV::hfree_next_entry_all($hv)) . "\n" }
  $out }
print "oracle=$PERL ok=$ok bad=$bad\n"; print "$_\n" for @rep;
