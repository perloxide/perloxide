#!/usr/bin/perl
use lib ($ENV{VF_ROOT} || '.'); our $ROOT = $ENV{VF_ROOT} || '.';
# gen_copycheck.pl -- for every state of the 12-op core lane (bare ops, fresh holder, depth D): Dump the original, Dump the copy
# `my $c = $x` and the original again (COW share), run the consumers on the copy, then run them DESTRUCTIVELY on the original.
use strict; use warnings;
my $PERL = $ENV{ORACLE} || 'perl'; my $DEPTH = $ENV{DEPTH} || 2; my $TAG = $ENV{TAG} || 'cc';
my %starts = ( s10=>q{"10"}, sUV=>q{"18446744073709551615"}, s1_5=>q{"1.5"}, s1e19=>q{"1e19"}, sabc=>q{"abc"}, s12x=>q{"12x"}, sInf=>q{"Inf"}, sNaN=>q{"NaN"},
  sInfx=>q{"Infx"}, sEmpty=>q{""}, sNeg0=>q{"-0"}, s09=>q{"09"}, sAz=>q{"Az"}, i10=>q{10}, iMax=>q{9223372036854775807}, f3=>q{3.0}, f3_5=>q{3.5}, f1e19=>q{1e19},
  s0but=>q{"0 but true"}, s00=>q{"0.0"}, sdot5=>q{".5"}, i0=>q{0}, f0=>q{0.0}, sLong=>q{"abcdefghijklmnopqrstuvwxyz0123456789"} );
my @core = (iv=>q{my $t = $x | 0;}, nv=>q{my $t = sprintf "%.17g", $x;}, str=>q{my $t = "$x";}, add=>q{my $t = 0 + $x;}, inc=>q{$x++;}, dec=>q{$x--;},
  bors=>q{my $t = $x | "";}, rng=>q{my @r = ($x .. "3");}, utf8=>q{utf8::upgrade($x);}, catx=>q{$x .= "x";}, copy=>q{my $y = $x; $x = $y;}, asgs=>q{$x = "10";});
my %core=@core; my @names = map { $core[$_*2] } 0..$#core/2;
my $head = <<'H';
use strict; no warnings; use Devel::Peek (); use B; use Scalar::Util qw(isdual); use Data::Dumper; use JSON::PP; use Storable qw(freeze);
use builtin qw(created_as_number created_as_string); no warnings 'experimental::builtin'; binmode STDOUT, ":utf8";
$Data::Dumper::Indent=0; $Data::Dumper::Terse=1; our @WARN; $SIG{__WARN__} = sub { my $m=$_[0]; $m =~ s/ at .*//s; $m =~ s/\n//; push @WARN, $m };
use lib ($ENV{VF_ROOT}||'.'); use VF::Observe; sub peek { my $r=shift; join("|", VF::Observe::peek($r)->{text}, VF::Observe::key($r)) }
sub cons_on { my $r = shift; my @o; local @WARN=(); my $c = $$r;   # runs the consumer chain on the scalar behind $r, in place
  push @o, "$$r"; push @o, sprintf("%.17g", 0.0+$$r); push @o, sprintf("%.17g", $$r); push @o, (isdual($$r)?1:0); push @o, (created_as_number($$r)?"N":"-").(created_as_string($$r)?"S":"-");
  push @o, Dumper($$r); { local $Data::Dumper::Useperl=1; push @o, Dumper($$r) } push @o, encode_json([$$r]); push @o, unpack("H*", substr(freeze([$$r]),12)); push @o, (eval { unpack("H*", pack("j",$$r)) } // "croak"); push @o, ($$r ? 1 : 0);
  return join("\x1e", @o) . "|W:" . join("/",@WARN) }
sub observe2 { my ($r,$cr,$px) = @_; my $pc = peek($cr); my $px2 = peek($r); my $cc = cons_on($cr); my $co = cons_on($r); return join("\t", $px, $pc, $px2, $cc, $co) }
H
my (%rows,%seen); my $SEP="\x01";
for my $c (sort keys %starts) { my @frontier=([]);
  for my $d (0..$DEPTH) { my $code=$head; my @seqs;
    for my $r (@frontier) { for my $op (@names) { my @seq=(@$r,$op); push @seqs,\@seq;
      my $ops = join(" ", map { $core{$_} } @seq);   # observe only the final state: the destructive read forbids observing intermediates in place
      $code .= "{ package B" . scalar(@seqs) . "; our \$x = $starts{$c}; $ops my \$px = main::peek(\\\$x); our \$c = \$x; print \"" . scalar(@seqs) . "\\t\", main::observe2(\\\$x, \\\$c, \$px), \"\\n\"; }\n" } }
    last unless @seqs; open my $fh,'>',"$ROOT/cc_child_${TAG}_$c.pl" or die; print $fh $code; close $fh;
    my $out=`timeout 600 $PERL $ROOT/cc_child_${TAG}_$c.pl 2>/dev/null`; utf8::decode($out); my @next;
    for (split /\n/, $out) { my ($i,$px,$pc,$px2,$cc,$co)=split /\t/,$_,-1; my $seq=$seqs[$i-1]; my $key="$c$SEP$px"; next if $seen{$key}++;
      $rows{$key} = {start=>$c, recipe=>join(",",@$seq), px=>$px, pc=>$pc, px2=>$px2, cc=>$cc, co=>$co}; push @next, $seq } @frontier=@next } }
my ($n,$copydiff,$consdiff)=(0,0,0); my (%kind,@cd,@cons);
for my $k (sort keys %rows) { my $r=$rows{$k}; $n++;
  my @x=split /\|/,$r->{px}; my @c=split /\|/,$r->{pc}; my @x2=split /\|/,$r->{px2};
  my @d; push @d,"type:$x[0]->$c[0]" if $x[0] ne $c[0]; push @d,"flags:$x[1]->$c[1]" if $x[1] ne $c[1]; push @d,"cur:$x[2]->$c[2]" if $x[2] ne $c[2]; push @d,"len:$x[3]->$c[3]" if $x[3] ne $c[3]; push @d,"cow:$x[4]->$c[4]" if $x[4] ne $c[4]; push @d,"pv:$x[7]->$c[7]" if $x[7] ne $c[7]; push @d,"src_cow:$x[4]->$x2[4]" if $x[4] ne $x2[4];
  if (@d) { $copydiff++; $kind{$_}++ for map { s/:.*//r } @d; push @cd, "COPYDIFF [$r->{start}: $r->{recipe}] " . join(" ", @d) . "\n   x: $r->{px}\n   c: $r->{pc}" }
  if ($r->{cc} ne $r->{co}) { $consdiff++; push @cons, "CONSDIFF [$r->{start}: $r->{recipe}]\n   copy:     $r->{cc}\n   original: $r->{co}" } }
print "oracle=$PERL depth=$DEPTH states=$n copy_differs=$copydiff (" . join(", ", map { "$_=$kind{$_}" } sort keys %kind) . ") consumer_copy_vs_original_differs=$consdiff\n";
print "$_\n" for @cons; print "$_\n" for @cd;
