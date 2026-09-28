#!/usr/bin/perl
use lib ($ENV{VF_ROOT} || '.'); our $ROOT = $ENV{VF_ROOT} || '.';
# BFS over (start value, op sequence): records every (state, op) -> state transition observed on the oracle perl via
# B::FLAGS plus a side-effect-free value fingerprint, then replays the same recipes through VF.pm and reports mismatches.
use strict; use warnings; use lib '$ROOT'; require VF;
my $PERL = $ENV{ORACLE} || 'perl'; my $DEPTH = $ENV{DEPTH} || 3; my $TAG = $ENV{TAG} || 'x';
my %starts = ( s10=>q{"10"}, sUV=>q{"18446744073709551615"}, s1_5=>q{"1.5"}, s1e19=>q{"1e19"}, sabc=>q{"abc"}, s12x=>q{"12x"},
  sInf=>q{"Inf"}, sNaN=>q{"NaN"}, sInfx=>q{"Infx"}, sEmpty=>q{""}, sNeg0=>q{"-0"}, s09=>q{"09"}, sAz=>q{"Az"},
  i10=>q{10}, iMax=>q{9223372036854775807}, f3=>q{3.0}, f3_5=>q{3.5}, f1e19=>q{1e19} ,  f0=>q{0.0}, i0=>q{0}, s00=>q{"0.0"}, s0but=>q{"0 but true"}, sLong=>q{"abcdefghijklmnopqrstuvwxyz0123456789"}, sdot5=>q{".5"}, );
my @only = $ENV{STARTS} ? split(/,/, $ENV{STARTS}) : sort keys %starts;
my @ops = (iv=>q{my $t = $x | 0;}, nv=>q{my $t = sprintf "%.17g", $x;}, str=>q{my $t = "$x";}, add=>q{my $t = 0 + $x;},
  inc=>q{$x++;}, dec=>q{$x--;}, bors=>q{my $t = $x | "";}, fbors=>q{{ use feature "bitwise"; my $t = $x |. ""; }},
  rng=>q{my @r = ($x .. "3");}, utf8=>q{utf8::upgrade($x);}, catx=>q{$x .= "x";}, cat0=>q{$x .= "";}, copy=>q{my $y = $x; $x = $y;},
  spd=>q{my $t = sprintf "%d", $x;}, sps=>q{my $t = sprintf "%s", $x;}, spg=>q{my $t = sprintf "%g", $x;}, spg15=>q{my $t = sprintf "%.15g", $x;},
  int=>q{my $t = int $x;}, abs=>q{my $t = abs $x;}, neg=>q{my $t = -$x;},
  eq1=>q{my $t = ($x == 1);}, eq1r=>q{my $t = (1 == $x);}, eq15=>q{my $t = ($x == 1.5);}, ncmp1=>q{my $t = ($x <=> 1);}, ncmp1r=>q{my $t = (1 <=> $x);},
  eqs=>q{my $t = ($x eq "1");}, cmps=>q{my $t = ($x cmp "1");}, bool=>q{my $t = $x ? 1 : 0;}, not=>q{my $t = !$x;},
  aidx=>q{my @a=(1,2,3); my $t = $a[$x];}, hkey=>q{my %h; my $t = $h{$x};}, xl=>q{my $t = "" x $x;}, xr=>q{my $t = $x x 2;},
  chr=>q{my $t = chr $x;}, len=>q{my $t = length $x;}, cpl=>q{my $t = ~$x;}, fcpl=>q{{ use feature "bitwise"; my $t = ~$x; }}, fscpl=>q{{ use feature "bitwise"; my $t = ~.$x; }},
  sortn=>q{my @s = sort { $a <=> $b } ($x, 1);}, sorts=>q{my @s = sort ($x, 1);}, packj=>q{my $t = pack "j", $x;}, packw=>q{my $t = pack "w", $x;},
  subr=>q{my $t = substr($x, 0, 1);}, subw=>q{substr($x, 0, 1, "y");}, snom=>q{$x =~ s/zzz//;}, smat=>q{$x =~ s/./X/;}, trc=>q{my $t = ($x =~ tr/0-9//);},
  vec=>q{vec($x, 0, 8) = 65;}, chop=>q{chop $x;}, chomp=>q{chomp $x;}, catl=>q{my $t = $x . "y";}, catr=>q{my $t = "y" . $x;},
  local=>q{{ local $x = 5; }}, asgs=>q{$x = "10";}, asgi=>q{$x = 10;}, asgn=>q{$x = 3.5;}, asgu=>q{$x = undef;}, undefx=>q{undef $x;}, chopl=>q{substr($x, 0, 1, "");});
my %opcode = @ops; my @opnames = map { $ops[$_*2] } 0..$#ops/2; if ($ENV{OPS}) { my %k = map { $_=>1 } split /,/, $ENV{OPS}; @opnames = grep { $k{$_} } @opnames }
use lib "$ROOT"; use VF::Observe; my $PROJ = $ENV{PROJ} || "flags"; my $head = VF::Observe::child_head($PROJ);
my (%edges, %rep, %full); my $SEP = "\x01"; my %startkey;
my $WALK = $ENV{WALK}; my $SEED = $ENV{SEED} // 20260924; srand($SEED) if $WALK;
for my $c (@only) {
  my @frontier = ([]); my %seen;
  for my $d (0..$DEPTH) {
    my $code = $head; my @seqs;
    my @units = $WALK ? (map { my @w = map { $opnames[int rand @opnames] } 1..$DEPTH; [@w] } 1..$WALK) : (map { my $r=$_; map { [@$r,$_] } @opnames } @frontier);
    for my $seq0 (@units) { { my @seq=@$seq0; push @seqs, \@seq;
      my $body = join "", map {; my $o=$_; $opcode{$o} . " { my \$k = VF::Observe::key(\\\$x); print VF::Observe::record(" . scalar(@seqs) . ", \"$o\", \\\$x, undef, \$k); } " } @seq;
      $code .= "{ package B" . scalar(@seqs) . "; our \$x = $starts{$c}; { my \$k = VF::Observe::key(\\\$x); print VF::Observe::record(" . scalar(@seqs) . ", \"START\", \\\$x, undef, \$k); } eval { $body 1 } or print \"" . scalar(@seqs) . "\\tCROAK\\t\", (\$@ =~ s/ at .*//sr), \"\\n\"; print \"" . scalar(@seqs) . "\\tCONSUMERS\\t-\\t\", (\$VF::Observe::PROJ eq \"full\" ? VF::Observe::consumers(\\\$x) : \"-\"), \"\\n\"; }\n" } }
    last unless @seqs; last if $WALK && $d > 0;
    open my $fh, '>', "$ROOT/child2_${TAG}_$c.pl" or die; print $fh $code; close $fh;
    my $out = `timeout 600 $PERL $ROOT/child2_${TAG}_$c.pl 2>/dev/null`; utf8::decode($out);
    my %lines; for (split /\n/, $out) { my ($i,$op,$st,@obs) = split /\t/, $_, -1; next if $op eq "CROAK" || $op eq "CONSUMERS"; $startkey{$c} = $st if $op eq "START"; $full{"$i\t$op\t$st"} = join("\t",@obs) if @obs; push @{$lines{$i}}, [$op,$st] }
    my @next;
    for my $i (1..@seqs) { my $seq = $seqs[$i-1]; my $steps = $lines{$i} or next; my $prev = $steps->[0][1];
      for my $k (1..$#$steps) { my ($op,$st) = @{$steps->[$k]}; $edges{"$c$SEP$prev$SEP$op"} //= $st; my $key="$c$SEP$st";
        if (!$seen{$key}++) { $rep{$key} = [ @$seq[0..$k-1] ]; push @next, $rep{$key} } $prev = $st } }
    @frontier = @next;
  }
}
sub mstart { my $c=shift;
  return VF::Harness::integer(10) if $c eq 'i10'; return VF::Harness::integer(9223372036854775807) if $c eq 'iMax'; return VF::Harness::number(3.0) if $c eq 'f3';
  return VF::Harness::number(3.5) if $c eq 'f3_5'; return VF::Harness::number(1e19) if $c eq 'f1e19'; return VF::Harness::integer(0) if $c eq 'i0'; return VF::Harness::number(0.0) if $c eq 'f0';
  my $s = $starts{$c}; $s =~ s/^"(.*)"$/$1/; return VF::Harness::string($s) }
sub mfp { my $h=shift; my $b = VF::Harness::KeyTail($h); return ($h->{kind} eq "S" ? "P:$h->{pv}|L:".($h->{len}//0) : $h->{int_form}==2 ? "N:$h->{iv}" : $h->{num_form} ? sprintf("N:%.17g",$h->{nv}) : $h->{int_form} ? "N:$h->{iv}" : "-") . $b }
my $quiet = { warn => sub {} };
my %mop = (iv=>\&VF::sv_2iv_flags, nv=>\&VF::sv_2nv_flags, str=>\&VF::sv_2pv_flags, add=>\&VF::pp_add, inc=>\&VF::sv_inc_nomg, dec=>\&VF::sv_dec_nomg, bors=>\&VF::pp_bit_or_string_other,
  fbors=>\&VF::pp_sbit_or, rng=>\&VF::pp_flop, utf8=>\&VF::sv_utf8_upgrade_flags_grow, catx=>sub { VF::pp_multiconcat($_[0],$_[1],"x") }, cat0=>sub { VF::pp_multiconcat($_[0],$_[1],"") }, copy=>\&VF::Harness::CopyOp,
  spd=>\&VF::sv_vcatpvfn_flags_d, sps=>\&VF::sv_2pv_flags, spg=>\&VF::sv_2nv_flags, spg15=>\&VF::sv_2nv_flags, int=>\&VF::pp_int, abs=>\&VF::pp_abs, neg=>\&VF::pp_negate,
  eq1=>\&VF::do_ncmp, eq1r=>\&VF::do_ncmp, eq15=>\&VF::do_ncmp_nv_partner, ncmp1=>\&VF::do_ncmp, ncmp1r=>\&VF::do_ncmp, eqs=>\&VF::sv_2pv_flags, cmps=>\&VF::sv_2pv_flags,
  bool=>\&VF::pp_null, not=>\&VF::pp_null, aidx=>\&VF::sv_2iv_flags, hkey=>\&VF::sv_2pv_flags, xl=>\&VF::pp_repeat_count, xr=>\&VF::Harness::RepeatOp, chr=>\&VF::pp_chr, len=>\&VF::pp_length,
  cpl=>\&VF::pp_complement, fcpl=>\&VF::sv_2iv_flags, fscpl=>\&VF::sv_2pv_flags, sortn=>\&VF::pp_sort_numeric, sorts=>\&VF::Harness::SortStrOp, packj=>\&VF::pp_pack_j, packw=>\&VF::pp_pack_w,
  subr=>\&VF::sv_2pv_flags, subw=>\&VF::sv_insert_flags, snom=>\&VF::pp_subst_nomatch, smat=>\&VF::pp_subst, trc=>\&VF::do_trans_count, vec=>\&VF::do_vecset, chop=>\&VF::do_chop, chomp=>\&VF::do_chomp,
  catl=>\&VF::sv_2pv_flags, catr=>\&VF::sv_2pv_flags, local=>\&VF::pp_null, asgs=>\&VF::Harness::assign_string, asgi=>\&VF::Harness::assign_integer, asgn=>\&VF::Harness::assign_number, asgu=>\&VF::sv_set_undef, undefx=>\&VF::pp_undef, chopl=>sub { VF::sv_chop($_[0],$_[1],1) });
my ($n,$bad)=(0,0); my @mis;
for my $e (sort keys %edges) { my ($c,$from,$op) = split /$SEP/, $e, 3; my $to = $edges{$e};
  next if $op eq "CROAK" || $op eq "CONSUMERS";   # a croak is the block's terminal observation, not a transition
  my $recipe = $rep{"$c$SEP$from"} // []; my $h = VF::Harness::SeedBody(mstart($c)); for my $o (@$recipe, $op) { eval { $mop{$o}->($h,$quiet); VF::body_type($h); 1 } or do { die $@ unless $@ =~ /^croak/ } }
  my $m = VF::Harness::FlagsProjection($h)."|".mfp($h); $n++;
  if ($m ne $to) { $bad++; push @mis, sprintf "%-8s %-44s --%-5s--> perl: %-44s model: %s   [recipe: %s]", $c, $from, $op, $to, $m, join(",",@$recipe) } }
print "oracle=$PERL projection=$PROJ " . ($WALK ? "walks=$WALK seed=$SEED " : "") . "depth=$DEPTH starts=".scalar(@only)." transitions=$n model_mismatches=$bad states=".scalar(keys %rep)."\n"; print "$_\n" for @mis;
{ open my $s, ">", "$ROOT/starts.$TAG.txt" or die; print $s "$_\t$startkey{$_}\n" for sort keys %startkey; close $s } open my $t, '>', "$ROOT/transitions.$TAG.txt" or die; for my $e (sort keys %edges) { my ($c,$from,$op)=split /$SEP/,$e,3; print $t "$c\t$from\t$op\t$edges{$e}\n" } close $t;
