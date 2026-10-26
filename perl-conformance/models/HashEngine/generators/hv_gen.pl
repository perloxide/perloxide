#!/usr/bin/perl
# hv_gen.pl -- validates HashEngine.pm below program level (Hash::Util bucket_array / hash_traversal_mask / hash_value) and at
# program level (keys/each/delete/insert/clear/undef/DESTROY traces), on the reference perl given in $ENV{PERL_CONFORMANCE_PERL}.
#
# Every observation is one row (lane, kind, item):
#   hash     key         Hash::Util::hash_value of one key of the 40-key set (the smaller sets are its prefixes)
#   mask     n           hash_traversal_mask after inserting n keys and listing them
#   buckets  n           bucket_array after the same, in full for 5 and 40 keys, as `sha256:` of it for 700 and 5000
#   hashes   n           `sha256:` of the n keys' hash values, for 700 and 5000
#   program  name        a program's stdout (seed0 and seedX_perturb0 only)
# Lanes: seed0 (PERL_HASH_SEED=0), seedX_perturb0 (a nonzero seed, PERL_PERTURB_KEYS=0), seedX_perturb2 (the same seed in
# DETERMINISTIC mode, where the layout depends on every hash operation the process performed before -- its hash values
# are compared, its mask and buckets recorded but excluded from comparison by construction).
#
#   PERL_CONFORMANCE_PERL=/path/to/perl TAG=<version> perl generators/hv_gen.pl   # rows=... ok=... bad=... excluded=...
#   REPLAY=1 TAG=<version> perl generators/hv_gen.pl                              # the model against the table, no perl
#
# When TAG is a version (a perlbrew build name such as 5.44.0 or 5.44.0-threads) the run is merged into the factored
# table reports/table.tsv (axes lane, kind, item; folded over lane; one field, the value, escaped as
# Perl::Conformance::Table::escape writes it: a newline as `\n`, a backslash as `\\`), and REPLAY=1 replays the model
# against the rows that table holds at TAG instead of running perl.
use strict; use warnings; use FindBin;
my $MODEL_ROOT = $ENV{MODEL_ROOT} || "$FindBin::Bin/..";
my $WORK = $ENV{MODEL_WORK} || "$MODEL_ROOT/work"; mkdir $WORK unless -d $WORK;
require "$MODEL_ROOT/HashEngine.pm";
use File::Spec;
use lib File::Spec->catdir($FindBin::Bin, '..', '..', '..', 'lib');
use Perl::Conformance::Table;
use Digest::SHA qw(sha256_hex);
my $PERL = $ENV{PERL_CONFORMANCE_PERL} || 'perl'; my $TAG = $ENV{TAG} || 'x';
my $REPLAY = $ENV{REPLAY} ? 1 : 0;
my $TABLE_PATH = "$MODEL_ROOT/reports/table.tsv";
my $VERSION_RE = qr/^\d+\.\d+\.\d+(?:-[\w-]+)?\z/;
die "REPLAY needs TAG to name a version the table holds, not `$TAG`\n" if $REPLAY && $TAG !~ $VERSION_RE;
my $ft = $REPLAY || ($TAG =~ $VERSION_RE && -e $TABLE_PATH) ? Perl::Conformance::Table->load($TABLE_PATH)
       : Perl::Conformance::Table->new(axes => [qw(lane kind item)], folded => 'lane', fields => ['value']);
die "the factored table holds no version $TAG (it holds @{ $ft->{versions} })\n"
    if $REPLAY && !grep { $_ eq $TAG } @{ $ft->{versions} };
sub encode { Perl::Conformance::Table::escape($_[0]) }
sub decode { Perl::Conformance::Table::unescape($_[0]) }

my @lanes = ( ['seed0', '0', undef], ['seedX_perturb0', 'deadbeef0123456789abcdef', '0'], ['seedX_perturb2', 'deadbeef0123456789abcdef', '2'] );
my @SIZES = (5, 40, 700, 5000);
my $FULL = 40;    # bucket arrays up to this many keys are stored in full, larger ones as a digest
sub keyset { my $n=shift; map { $_ % 7 == 3 ? ("longkey_" . ("x" x 20) . "_$_") : "k$_" } 1..$n }   # one key in seven exceeds SBOX32_MAX_LEN
sub env { my ($seed,$pert)=@_; "env -u PERL_PERTURB_KEYS PERL_HASH_SEED=$seed " . (defined $pert ? "PERL_PERTURB_KEYS=$pert " : "") }
sub bucket_string { join("|", map { ref $_ ? join(",", @$_) : $_ } @{ $_[0] }) }

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

# ---------- observation: perl, or the table under REPLAY ----------
my %obs;    # "lane\tkind\titem" -> value (decoded)
if ($REPLAY) {
    for my $r ($ft->expand($TAG)) { my ($l, $k, $i, $v) = @$r; $obs{"$l\t$k\t$i"} = decode($v) }
}
else {
    for my $lane (@lanes) { my ($lname,$seed,$pert)=@$lane;
        my %hash;
        for my $n (@SIZES) {
            my @keys = keyset($n);
            my $src = 'use strict; use Hash::Util qw(bucket_array hash_traversal_mask hash_value); my %h; my @k = @ARGV; $h{$_} = 1 for @k; my @kk = keys %h;'
              . 'my $b = bucket_array(\%h); print join("|", map { ref $_ ? join(",", @$_) : $_ } @$b), "\n"; print hash_traversal_mask(\%h), "\n"; print join("\n", map { hash_value($_) } @k), "\n";';
            open my $fh, '>', "$WORK/hv_child.pl" or die; print $fh $src; close $fh;
            my $out = `${\ env($seed,$pert)} $PERL $WORK/hv_child.pl @keys 2>&1`; my ($ba,$mask,@hv) = split /\n/, $out;
            $obs{"$lname\tmask\t$n"} = $mask;
            if ($n <= $FULL) {
                $obs{"$lname\tbuckets\t$n"} = $ba;
                for my $i (0 .. $#keys) {
                    die "hash_value of $keys[$i] differs between key sets in one lane\n" if defined $hash{$keys[$i]} && $hash{$keys[$i]} ne $hv[$i];
                    $hash{$keys[$i]} = $hv[$i];
                }
            }
            else {
                $obs{"$lname\tbuckets\t$n"} = 'sha256:' . sha256_hex($ba);
                $obs{"$lname\thashes\t$n"} = 'sha256:' . sha256_hex(join(",", @hv));
            }
        }
        $obs{"$lname\thash\t$_"} = $hash{$_} for keys %hash;
    }
    for my $lane (@lanes[0,1]) { my ($lname,$seed,$pert)=@$lane;
        for my $pr (@progs) { my ($pname,$code)=@$pr;
            open my $fh, '>', "$WORK/hv_child.pl" or die; print $fh "$pre\n$code\n"; close $fh;
            $obs{"$lname\tprogram\t$pname"} = `${\ env($seed,$pert)} $PERL $WORK/hv_child.pl 2>&1`;
        }
    }
}

# ---------- the model against the observations ----------
my ($n,$ok,$bad,$excluded,$absent)=(0,0,0,0,0); my @rep;
sub check {
    my ($key, $exp, $is_excluded) = @_;
    $n++;
    my $got = $obs{$key};
    if (!defined $got) { $absent++; return }
    my $name = join('.', split /\t/, $key);
    if ($is_excluded) { $excluded++; push @rep, "EXCLUDED $name (DETERMINISTIC perturbation depends on all prior hash activity in the process): " . ($got eq $exp ? "matches" : "differs"); return }
    if ($got eq $exp) { $ok++ } else { $bad++; push @rep, "MISMATCH $name\n  perl:  " . encode($got) . "\n  model: " . encode($exp) }
}
for my $lane (@lanes) { my ($lname,$seed,$pert)=@$lane;
    my $xd = $lname eq 'seedX_perturb2';
    my $p0 = Perl::Conformance::Model::HashEngine::Harness::NewProcess($seed, $pert);
    check("$lname\thash\t$_", $p0->PERL_HASH_WITH_STATE($_), 0) for keyset($FULL);
    for my $sz (@SIZES) {
        my @keys = keyset($sz);
        my $p = Perl::Conformance::Model::HashEngine::Harness::NewProcess($seed, $pert); my $hv = Perl::Conformance::Model::HashEngine::Harness::NewHV($p);
        Perl::Conformance::Model::HashEngine::hv_common($hv, $_, 1) for @keys; Perl::Conformance::Model::HashEngine::Harness::Keys($hv);
        my $mba = bucket_string(Perl::Conformance::Model::HashEngine::Harness::BucketArray($hv));
        check("$lname\tmask\t$sz", $hv->{aux}{rand}, $xd);
        check("$lname\tbuckets\t$sz", $sz <= $FULL ? $mba : 'sha256:' . sha256_hex($mba), $xd);
        check("$lname\thashes\t$sz", 'sha256:' . sha256_hex(join(",", map { $p->PERL_HASH_WITH_STATE($_) } @keys)), 0) if $sz > $FULL;
    }
}
for my $lane (@lanes[0,1]) { my ($lname,$seed,$pert)=@$lane;
    check("$lname\tprogram\t$_->[0]", replay($_->[0], $seed, $pert), 0) for @progs;
}
sub replay { my ($pname,$seed,$pert)=@_; my $p = Perl::Conformance::Model::HashEngine::Harness::NewProcess($seed,$pert); my $hv = Perl::Conformance::Model::HashEngine::Harness::NewHV($p); my $out='';
  my $keys = sub { my $n=shift; my @k = map { "k$_" } 1..$n; Perl::Conformance::Model::HashEngine::hv_common($hv,$_,1) for @k; @k };
  my $each = sub { my $w=0; my $e = Perl::Conformance::Model::HashEngine::hv_iternext_flags($hv, \$w); $out .= "W\n" if $w; $e };
  if ($pname eq 'keys20') { $keys->(20); $out .= join(",", Perl::Conformance::Model::HashEngine::Harness::Keys($hv)) . "\n" }
  elsif ($pname eq 'each20') { $keys->(20); while (my $e = $each->()) { $out .= "$e->{k} " } $out .= "\n" }
  elsif ($pname eq 'delcur') { $keys->(20); while (my $e = $each->()) { $out .= "$e->{k} "; Perl::Conformance::Model::HashEngine::hv_delete_common($hv,$e->{k}) } $out .= "| " . Perl::Conformance::Model::HashEngine::Harness::Keys($hv) . "\n" }
  elsif ($pname eq 'delother') { my @k=$keys->(20); my $n=0; while (my $e = $each->()) { $out .= "$e->{k} "; if (!$n++) { Perl::Conformance::Model::HashEngine::hv_delete_common($hv,$_) for grep { $_ ne $e->{k} } @k[0..4] } } $out .= "| " . join(",", sort(Perl::Conformance::Model::HashEngine::Harness::Keys($hv))) . "\n" }
  elsif ($pname eq 'inseach') { $keys->(20); my $n=0; while (my $e = $each->()) { $out .= "$e->{k} "; Perl::Conformance::Model::HashEngine::hv_common($hv,"n$n",1) if $n++ < 3 } $out .= "\n" }
  elsif ($pname eq 'reset') { $keys->(20); my $a=$each->()->{k}; my $b=$each->()->{k}; Perl::Conformance::Model::HashEngine::Harness::Keys($hv); my $c=$each->()->{k}; $out .= "$a $b $c\n" }
  elsif ($pname eq 'clearfill') { my @k=$keys->(40); Perl::Conformance::Model::HashEngine::hv_clear($hv); Perl::Conformance::Model::HashEngine::hv_common($hv,$_,1) for @k; $out .= join(",", Perl::Conformance::Model::HashEngine::Harness::Keys($hv)) . "\n" }
  elsif ($pname eq 'undeffill') { my @k=$keys->(40); Perl::Conformance::Model::HashEngine::hv_undef_flags($hv); Perl::Conformance::Model::HashEngine::hv_common($hv,$_,1) for @k; $out .= join(",", Perl::Conformance::Model::HashEngine::Harness::Keys($hv)) . "\n" }
  elsif ($pname eq 'destroy') { $keys->(20); $out .= join("", map { "D$_ " } Perl::Conformance::Model::HashEngine::hfree_next_entry_all($hv)) . "\n" }
  elsif ($pname eq 'destroy_after_iter') { $keys->(20); Perl::Conformance::Model::HashEngine::Harness::Keys($hv); $each->(); $out .= join("", map { "D$_ " } Perl::Conformance::Model::HashEngine::hfree_next_entry_all($hv)) . "\n" }
  $out }
if ($REPLAY) {
    print "replay=$TAG rows=$n ok=$ok bad=$bad excluded=$excluded absent=$absent\n"; print "$_\n" for @rep;
    exit($bad ? 1 : 0);
}
my $raw = "$WORK/hv_table.$TAG.tsv";
open my $tab, '>', $raw or die "cannot write $raw: $!\n";
print $tab "$_\t", encode($obs{$_}), "\n" for sort keys %obs;
close $tab;
my $digest = do { open my $fh, '<', $raw or die; local $/; sha256_hex(<$fh>) };
print "oracle=$PERL rows=$n ok=$ok bad=$bad excluded=$excluded table-sha256=$digest\n"; print "$_\n" for @rep;
if ($TAG =~ $VERSION_RE) {
    $ft->merge($TAG, { map { $_ => encode($obs{$_}) } keys %obs });
    $ft->write($TABLE_PATH);
    print STDERR "merged $TAG into $TABLE_PATH\n";
}
