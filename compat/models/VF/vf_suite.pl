#!/usr/bin/perl
use lib ($ENV{VF_ROOT} || '.'); our $ROOT = $ENV{VF_ROOT} || '.';
# vf_suite.pl -- the value-flags verification driver.  Runs the existing lanes under one entry point on both interpreters and
# prints the coverage table that defines "verified" for this area.  Lanes: handler matrix (gen_vf.pl), locale axis (gen4_vf.pl),
# 12-op core depth 4 and 58-op set depth 3 (gen3_vf.pl), copy check (gen_copycheck.pl).  Each lane's report is cached in
# reports/<lane>.<ver>.txt; RERUN=1 forces a rerun.  Verdicts per lane: match, open (recipe + source line in the lane report),
# version-divergent (the two perls' oracle observations differ; the model follows 5.44), diverges-defined (W1-W3 windows).
use strict; use warnings;
my @PERLS = $ENV{PERLS} ? split(/[ ,]+/, $ENV{PERLS}) : ('perl');
# Startup checks.  Each failure prints what was checked and what was found and exits nonzero; success prints the verified profile.
sub startup_check {
  for my $p (@PERLS) { my $out = `$p -V:usemymalloc -V:d_malloc_good_size -V:d_malloc_size 2>&1`; my %c = $out =~ /^(\w+)='([^']*)'/mg;
    my @want = (usemymalloc=>'n', d_malloc_good_size=>'undef', d_malloc_size=>'undef'); my @bad;
    while (my ($k,$v) = splice @want, 0, 2) { push @bad, "$k=" . ($c{$k} // '<missing>') . " (wanted '$v')" if ($c{$k} // '') ne $v }
    if (@bad) { print STDERR "vf_suite: $p: allocator profile check FAILED: @bad -- the LEN rules hold only for usemymalloc=n, d_malloc_good_size=undef, d_malloc_size=undef\n"; exit 2 }
    my $ver = `$p -e 'print \$]'`; print STDERR "vf_suite: $p ($ver): allocator profile verified (usemymalloc=n d_malloc_good_size=undef d_malloc_size=undef)\n" }
  my @loc = `locale -a 2>/dev/null`; chomp @loc; unless (grep { /^de_DE\.(UTF-8|utf8)$/i } @loc) { print STDERR "vf_suite: locale check FAILED: de_DE.UTF-8 not in `locale -a` (" . scalar(@loc) . " locales listed) -- the locale lane needs it\n"; exit 3 }
  print STDERR "vf_suite: locale de_DE.UTF-8 present\n" }
startup_check();
my $R = $ENV{REPORTS} || "$ROOT/suite"; mkdir $R;

# Lanes.  Depths come from the environment (DEPTH_CORE, DEPTH_FULL, DEPTH_WALK; default 2/2/6) so `make suite DEPTH=1`
# is the quick verification and the deep runs are the same lanes with larger depths; lane names carry the depth.
my $DC = $ENV{DEPTH_CORE} // $ENV{DEPTH} // 2; my $DF = $ENV{DEPTH_FULL} // $ENV{DEPTH} // 2; my $DW = $ENV{DEPTH_WALK} // $ENV{DEPTH} // 6;
my $CORE = 'add,bors,cat0,catx,copy,dec,fbors,inc,iv,nv,rng,str,utf8';
my @LANES = (
  [matrix    => 'perl generators/gen_vf.pl',                                                'fresh', 'handler matrix (2304 rows)', 0,   'full'],
  [locale    => 'perl generators/gen4_vf.pl',                                               'fresh', 'locale axis',                1,   'flags+slots'],
  ["core$DC" => "OPS=$CORE DEPTH=$DC PROJ=full perl generators/gen3_vf.pl",                 'fresh', '13-op core, 24 starts',      $DC, 'full'],
  ["full$DF" => "DEPTH=$DF PROJ=full perl generators/gen3_vf.pl",                           'fresh', '58-op set, 24 starts',       $DF, 'full'],
  ["walk$DW" => "WALK=125 DEPTH=$DW SEED=20260924 PROJ=full perl generators/gen3_vf.pl",    'fresh', '58-op set, 3000 seeded walks', $DW, 'full'],
  [copy      => 'DEPTH=2 perl generators/gen_copycheck.pl',                                 'fresh', '12-op core + copy',          2,   'full'],
);
my %T;
for my $p (@PERLS) { my $ver = `$p -e 'print \$]'`; $ver = sprintf("%d.%d.%d", $ver, ($ver*1000)%1000, ($ver*1000000)%1000);
  for my $l (@LANES) { my ($name,$cmd,$holder,$ops,$depth,$proj)=@$l; my $f="$R/$name.$ver.txt";
    system("cd $ROOT && ORACLE=$p TAG=suite_${name}_$ver $cmd > $f 2>/dev/null") if $ENV{RERUN} || !-s $f || !`grep -c "oracle=.*[1-9]\\|rows=[1-9]" $f`;   # an empty or zero-transition report is rerun, never cached
    my $s = `cat $f`; my %v = (match=>0, open=>0, vdiv=>0, defined=>0); my ($tr,$st)=('-','-');
    if ($s =~ /transitions=(\d+) model_mismatches=(\d+) states=(\d+)/) { ($tr,$st)=($1,$3); $v{open}=$2; $v{match}=$1-$2; }
    if (0) { ($tr,$st)=($1,$3); $v{open}=$2; $v{match}=$1-$2 }
    elsif ($s =~ /rows=(\d+) values_ok=(\d+) values_bad=(\d+) flag_mismatch_on_value_ok_rows=(\d+) crash=(\d+) ub_rows=(\d+)/) { $tr=$1; $v{match}=$2-$4; $v{open}=$3+$4; $v{defined}=$5+$6 }
    elsif ($s =~ /states=(\d+) copy_differs=\d+.*?consumer_copy_vs_original_differs=(\d+)/) { ($tr,$st)=($1,$1); $v{open}=$2; $v{match}=$1-$2 }
    $T{$name}{$ver} = {holder=>$holder, ops=>$ops, depth=>$depth, proj=>$proj, tr=>$tr, st=>$st, %v, file=>$f} } }
# version-divergent: a (start, from, op) triple whose oracle observation differs between the two perls, from the lanes' transition tables
for my $name (keys %T) { my @v = sort keys %{$T{$name}}; next unless @v==2; my @tab = map { "$ROOT/transitions.suite_${name}_$_.txt" } @v; next unless -s $tab[0] && -s $tab[1];
  my %a; for my $i (0,1) { open my $t,'<',$tab[$i] or next; while (<$t>) { chomp; my ($k,$to) = /^(.*)\t([^\t]*)$/ or next; $a{$k}[$i] = $to } close $t }
  my $d = grep { defined $a{$_}[0] && defined $a{$_}[1] && $a{$_}[0] ne $a{$_}[1] } keys %a; $T{$name}{$_}{vdiv} = $d for @v }
# Verdict rule: a (start, from, op) triple whose oracle observations differ between the two perls is version-divergent and is
# never counted as open on 5.38.2 (the model follows 5.44.0); the open count on 5.38.2 is its mismatch rows minus those triples.
for my $name (keys %T) { my @v = sort keys %{$T{$name}}; next unless @v==2; my @tab = map { "$ROOT/transitions.suite_${name}_$_.txt" } @v; next unless -s $tab[0] && -s $tab[1];
  my %a; for my $i (0,1) { open my $t,'<',$tab[$i] or next; while (<$t>) { chomp; my ($k,$to) = /^(.*)\t([^\t]*)$/ or next; $a{$k}[$i] = $to } close $t }
  my %vd = map { $_=>1 } grep { defined $a{$_}[0] && defined $a{$_}[1] && $a{$_}[0] ne $a{$_}[1] } keys %a;
  my $rep = $T{$name}{$v[0]}{file}; open my $r,'<',$rep or next; my ($open,$vdopen)=(0,0); while (<$r>) { my ($c,$from,$op) = /^(\S+)\s+(\S+)\s+--(\w+)\s*-->/ or next; $open++; $vdopen++ if $vd{"$c\t$from\t$op"} } close $r;
  $T{$name}{$v[0]}{open} = $open - $vdopen; $T{$name}{$v[0]}{match} = $T{$name}{$v[0]}{tr} - $open if $T{$name}{$v[0]}{tr} ne '-'; $T{$name}{$v[0]}{vdiv_open} = $vdopen }
# Path-based verdict (verdiv_paths.pl): for lanes with start files, open on 5.38.2 = agreeing-open paths, ver-div = divergent
# paths (shown on both rows); match = transitions - open - ver-div on every row.
for my $name (keys %T) { my @v = sort keys %{$T{$name}}; next unless @v==2; next unless -s "$ROOT/starts.suite_${name}_$v[0].txt" && -s "$ROOT/starts.suite_${name}_$v[1].txt";
  my $out = `perl $ROOT/verdiv_paths.pl $name $v[0] $v[1] 2>/dev/null`; my ($open,$vd) = $out =~ /open_agreeing=(\d+) version_divergent_paths=(\d+)/ or next;
  $T{$name}{$v[0]}{open} = $open; $T{$name}{$_}{vdiv} = $vd for @v }
for my $name (keys %T) { for my $ver (keys %{$T{$name}}) { my $t=$T{$name}{$ver}; next if $t->{tr} eq '-'; $t->{match} = $t->{tr} - $t->{open} - $t->{vdiv} } }
printf "%-8s %-8s %-8s %-24s %-5s %-12s %9s %7s %9s %6s %8s %8s\n", qw(lane perl holder opset depth projection transit states match open ver-div defined);
for my $l (@LANES) { my $n=$l->[0]; for my $ver (sort keys %{$T{$n}}) { my $t=$T{$n}{$ver};
  printf "%-8s %-8s %-8s %-24s %-5s %-12s %9s %7s %9s %6s %8s %8s\n", $n, $ver, $t->{holder}, $t->{ops}, $t->{depth}, $t->{proj}, $t->{tr}, $t->{st}, $t->{match}, $t->{open}, $t->{vdiv}, $t->{defined} } }
print "\nprojection column is the VF::Observe projection each lane records (flags = key only; full = key + Devel::Peek + fresh-per-block copy consumers); the key never changes between projections, so counts do not move.\n";
