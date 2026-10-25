#!/usr/bin/perl
our $ROOT = $ENV{MODEL_ROOT} || '.';
# BFS over (start value, op sequence): records every (state, op) -> state transition observed on the reference perl via
# B::FLAGS plus a side-effect-free value fingerprint, then replays the same recipes through ValueFlags.pm and reports mismatches.
use strict; use warnings; require "$ROOT/ValueFlags.pm";
my $PERL = $ENV{PERL_CONFORMANCE_PERL} || 'perl'; my $DEPTH = $ENV{DEPTH} || 3; my $TAG = $ENV{TAG} || 'x';
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
require "$ROOT/Observe.pm"; my $PROJ = $ENV{PROJ} || "flags"; my $head = Perl::Conformance::Model::ValueFlags::Observe::child_head($PROJ);
my (%edges, %rep, %full); my $SEP = "\x01"; my %startkey;
my $WALK = $ENV{WALK}; my $SEED = $ENV{SEED} // 20260924; srand($SEED) if $WALK;
for my $c (@only) {
  my @frontier = ([]); my %seen;
  for my $d (0..$DEPTH) {
    my $code = $head; my @seqs;
    my @units = $WALK ? (map { my @w = map { $opnames[int rand @opnames] } 1..$DEPTH; [@w] } 1..$WALK) : (map { my $r=$_; map { [@$r,$_] } @opnames } @frontier);
    for my $seq0 (@units) { { my @seq=@$seq0; push @seqs, \@seq;
      my $body = join "", map {; my $o=$_; $opcode{$o} . " { my \$k = Perl::Conformance::Model::ValueFlags::Observe::key(\\\$x); print Perl::Conformance::Model::ValueFlags::Observe::record(" . scalar(@seqs) . ", \"$o\", \\\$x, undef, \$k); } " } @seq;
      $code .= "{ package B" . scalar(@seqs) . "; our \$x = $starts{$c}; { my \$k = Perl::Conformance::Model::ValueFlags::Observe::key(\\\$x); print Perl::Conformance::Model::ValueFlags::Observe::record(" . scalar(@seqs) . ", \"START\", \\\$x, undef, \$k); } eval { $body 1 } or print \"" . scalar(@seqs) . "\\tCROAK\\t\", (\$@ =~ s/ at .*//sr), \"\\n\"; print \"" . scalar(@seqs) . "\\tCONSUMERS\\t-\\t\", (\$Perl::Conformance::Model::ValueFlags::Observe::PROJ eq \"full\" ? Perl::Conformance::Model::ValueFlags::Observe::consumers(\\\$x) : \"-\"), \"\\n\"; }\n" } }
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
  return Perl::Conformance::Model::ValueFlags::Harness::integer(10) if $c eq 'i10'; return Perl::Conformance::Model::ValueFlags::Harness::integer(9223372036854775807) if $c eq 'iMax'; return Perl::Conformance::Model::ValueFlags::Harness::number(3.0) if $c eq 'f3';
  return Perl::Conformance::Model::ValueFlags::Harness::number(3.5) if $c eq 'f3_5'; return Perl::Conformance::Model::ValueFlags::Harness::number(1e19) if $c eq 'f1e19'; return Perl::Conformance::Model::ValueFlags::Harness::integer(0) if $c eq 'i0'; return Perl::Conformance::Model::ValueFlags::Harness::number(0.0) if $c eq 'f0';
  my $s = $starts{$c}; $s =~ s/^"(.*)"$/$1/; return Perl::Conformance::Model::ValueFlags::Harness::string($s) }
sub mfp { my $h=shift; my $b = Perl::Conformance::Model::ValueFlags::Harness::KeyTail($h); return ($h->{kind} eq "S" ? "P:$h->{pv}|L:".($h->{len}//0) : $h->{int_form}==2 ? "N:$h->{iv}" : $h->{num_form} ? sprintf("N:%.17g",$h->{nv}) : $h->{int_form} ? "N:$h->{iv}" : "-") . $b }
my $quiet = { warn => sub {} };
my %mop = (iv=>\&Perl::Conformance::Model::ValueFlags::sv_2iv_flags, nv=>\&Perl::Conformance::Model::ValueFlags::sv_2nv_flags, str=>\&Perl::Conformance::Model::ValueFlags::sv_2pv_flags, add=>\&Perl::Conformance::Model::ValueFlags::pp_add, inc=>\&Perl::Conformance::Model::ValueFlags::sv_inc_nomg, dec=>\&Perl::Conformance::Model::ValueFlags::sv_dec_nomg, bors=>\&Perl::Conformance::Model::ValueFlags::pp_bit_or_string_other,
  fbors=>\&Perl::Conformance::Model::ValueFlags::pp_sbit_or, rng=>\&Perl::Conformance::Model::ValueFlags::pp_flop, utf8=>\&Perl::Conformance::Model::ValueFlags::sv_utf8_upgrade_flags_grow, catx=>sub { Perl::Conformance::Model::ValueFlags::pp_multiconcat($_[0],$_[1],"x") }, cat0=>sub { Perl::Conformance::Model::ValueFlags::pp_multiconcat($_[0],$_[1],"") }, copy=>\&Perl::Conformance::Model::ValueFlags::Harness::CopyOp,
  spd=>\&Perl::Conformance::Model::ValueFlags::sv_vcatpvfn_flags_d, sps=>\&Perl::Conformance::Model::ValueFlags::sv_2pv_flags, spg=>\&Perl::Conformance::Model::ValueFlags::sv_2nv_flags, spg15=>\&Perl::Conformance::Model::ValueFlags::sv_2nv_flags, int=>\&Perl::Conformance::Model::ValueFlags::pp_int, abs=>\&Perl::Conformance::Model::ValueFlags::pp_abs, neg=>\&Perl::Conformance::Model::ValueFlags::pp_negate,
  eq1=>\&Perl::Conformance::Model::ValueFlags::do_ncmp, eq1r=>\&Perl::Conformance::Model::ValueFlags::do_ncmp, eq15=>\&Perl::Conformance::Model::ValueFlags::do_ncmp_nv_partner, ncmp1=>\&Perl::Conformance::Model::ValueFlags::do_ncmp, ncmp1r=>\&Perl::Conformance::Model::ValueFlags::do_ncmp, eqs=>\&Perl::Conformance::Model::ValueFlags::sv_2pv_flags, cmps=>\&Perl::Conformance::Model::ValueFlags::sv_2pv_flags,
  bool=>\&Perl::Conformance::Model::ValueFlags::pp_null, not=>\&Perl::Conformance::Model::ValueFlags::pp_null, aidx=>\&Perl::Conformance::Model::ValueFlags::sv_2iv_flags, hkey=>\&Perl::Conformance::Model::ValueFlags::sv_2pv_flags, xl=>\&Perl::Conformance::Model::ValueFlags::pp_repeat_count, xr=>\&Perl::Conformance::Model::ValueFlags::Harness::RepeatOp, chr=>\&Perl::Conformance::Model::ValueFlags::pp_chr, len=>\&Perl::Conformance::Model::ValueFlags::pp_length,
  cpl=>\&Perl::Conformance::Model::ValueFlags::pp_complement, fcpl=>\&Perl::Conformance::Model::ValueFlags::sv_2iv_flags, fscpl=>\&Perl::Conformance::Model::ValueFlags::sv_2pv_flags, sortn=>\&Perl::Conformance::Model::ValueFlags::pp_sort_numeric, sorts=>\&Perl::Conformance::Model::ValueFlags::Harness::SortStrOp, packj=>\&Perl::Conformance::Model::ValueFlags::pp_pack_j, packw=>\&Perl::Conformance::Model::ValueFlags::pp_pack_w,
  subr=>\&Perl::Conformance::Model::ValueFlags::sv_2pv_flags, subw=>\&Perl::Conformance::Model::ValueFlags::sv_insert_flags, snom=>\&Perl::Conformance::Model::ValueFlags::pp_subst_nomatch, smat=>\&Perl::Conformance::Model::ValueFlags::pp_subst, trc=>\&Perl::Conformance::Model::ValueFlags::do_trans_count, vec=>\&Perl::Conformance::Model::ValueFlags::do_vecset, chop=>\&Perl::Conformance::Model::ValueFlags::do_chop, chomp=>\&Perl::Conformance::Model::ValueFlags::do_chomp,
  catl=>\&Perl::Conformance::Model::ValueFlags::sv_2pv_flags, catr=>\&Perl::Conformance::Model::ValueFlags::sv_2pv_flags, local=>\&Perl::Conformance::Model::ValueFlags::pp_null, asgs=>\&Perl::Conformance::Model::ValueFlags::Harness::assign_string, asgi=>\&Perl::Conformance::Model::ValueFlags::Harness::assign_integer, asgn=>\&Perl::Conformance::Model::ValueFlags::Harness::assign_number, asgu=>\&Perl::Conformance::Model::ValueFlags::sv_set_undef, undefx=>\&Perl::Conformance::Model::ValueFlags::pp_undef, chopl=>sub { Perl::Conformance::Model::ValueFlags::sv_chop($_[0],$_[1],1) });
my ($n,$bad)=(0,0); my @mis;
for my $e (sort keys %edges) { my ($c,$from,$op) = split /$SEP/, $e, 3; my $to = $edges{$e};
  next if $op eq "CROAK" || $op eq "CONSUMERS";   # a croak is the block's terminal observation, not a transition
  my $recipe = $rep{"$c$SEP$from"} // []; my $h = Perl::Conformance::Model::ValueFlags::Harness::SeedBody(mstart($c)); for my $o (@$recipe, $op) { eval { $mop{$o}->($h,$quiet); Perl::Conformance::Model::ValueFlags::body_type($h); 1 } or do { die $@ unless $@ =~ /^croak/ } }
  my $m = Perl::Conformance::Model::ValueFlags::Harness::FlagsProjection($h)."|".mfp($h); $n++;
  if ($m ne $to) { $bad++; push @mis, sprintf "%-8s %-44s --%-5s--> perl: %-44s model: %s   [recipe: %s]", $c, $from, $op, $to, $m, join(",",@$recipe) } }
print "oracle=$PERL projection=$PROJ " . ($WALK ? "walks=$WALK seed=$SEED " : "") . "depth=$DEPTH starts=".scalar(@only)." transitions=$n model_mismatches=$bad states=".scalar(keys %rep)."\n"; print "$_\n" for @mis;
{ open my $s, ">", "$ROOT/starts.$TAG.txt" or die; print $s "$_\t$startkey{$_}\n" for sort keys %startkey; close $s } open my $t, '>', "$ROOT/transitions.$TAG.txt" or die; for my $e (sort keys %edges) { my ($c,$from,$op)=split /$SEP/,$e,3; print $t "$c\t$from\t$op\t$edges{$e}\n" } close $t;
