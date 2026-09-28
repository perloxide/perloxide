#!/usr/bin/perl
use lib ($ENV{VF_ROOT} || '.'); our $ROOT = $ENV{VF_ROOT} || '.';
use strict; use warnings; use lib ($ENV{VF_ROOT}||'.'); require VF;
my $PERL = $ENV{ORACLE} || 'perl'; my $DEPTH = $ENV{DEPTH} || 3; my $TAG = $ENV{TAG} || 'loc';
my %starts = ( c35=>q{"3,5"}, d35=>q{"3.5"}, c35x=>q{"3,5x"}, e35=>q{"1e3,5"}, c15=>q{"1,5"}, s10=>q{"10"}, f35=>q{3.5}, abc=>q{"abc"}, c0=>q{"0,5"} );
my @ops = (de_iv=>q{{ use locale; POSIX::setlocale(POSIX::LC_NUMERIC(),"de_DE.UTF-8"); my $t = $x | 0; POSIX::setlocale(POSIX::LC_NUMERIC(),"C"); }}, de_nv=>q{{ use locale; POSIX::setlocale(POSIX::LC_NUMERIC(),"de_DE.UTF-8"); my $t = sprintf "%.17g", $x; POSIX::setlocale(POSIX::LC_NUMERIC(),"C"); }},
  de_add=>q{{ use locale; POSIX::setlocale(POSIX::LC_NUMERIC(),"de_DE.UTF-8"); my $t = 0 + $x; POSIX::setlocale(POSIX::LC_NUMERIC(),"C"); }}, de_str=>q{{ use locale; POSIX::setlocale(POSIX::LC_NUMERIC(),"de_DE.UTF-8"); my $t = "$x"; POSIX::setlocale(POSIX::LC_NUMERIC(),"C"); }},
  cl_iv=>q{{ use locale; POSIX::setlocale(POSIX::LC_NUMERIC(),"C"); my $t = $x | 0; }}, cl_nv=>q{{ use locale; POSIX::setlocale(POSIX::LC_NUMERIC(),"C"); my $t = sprintf "%.17g", $x; }},
  nl_iv=>q{{ no locale; my $t = $x | 0; }}, nl_nv=>q{{ no locale; my $t = sprintf "%.17g", $x; }}, nl_add=>q{{ no locale; my $t = 0 + $x; }}, nl_str=>q{{ no locale; my $t = "$x"; }},
  copy=>q{my $y = $x; $x = $y;}, catx=>q{$x .= "x";});
my %opcode = @ops; my @opnames = map { $ops[$_*2] } 0..$#ops/2;
my $head = <<'H';
use strict; no warnings; use B; use POSIX qw(setlocale LC_NUMERIC); binmode STDOUT, ":utf8";
my @F=(IOK=>B::SVf_IOK,NOK=>B::SVf_NOK,POK=>B::SVf_POK,pIOK=>B::SVp_IOK,pNOK=>B::SVp_NOK,pPOK=>B::SVp_POK,IsUV=>B::SVf_IVisUV,UTF8=>B::SVf_UTF8);
use lib ($ENV{VF_ROOT}||'.'); use VF::Observe; *fl = \&VF::Observe::flags; *fp = \&VF::Observe::slots;
H
my (%edges, %rep); my $SEP = "\x01";
for my $c (sort keys %starts) {
  my @frontier = ([]); my %seen;
  for my $d (0..$DEPTH) {
    my $code = $head; my @seqs;
    for my $recipe (@frontier) { for my $op (@opnames) { my @seq=(@$recipe,$op); push @seqs, \@seq;
      my $body = join "", map { "eval { $opcode{$_} 1 }; print \"" . scalar(@seqs) . "\\t$_\\t\", VF::Observe::key(\\\$x), \"\\n\"; " } @seq;
      $code .= "{ package B" . scalar(@seqs) . "; our \$x = $starts{$c}; print \"" . scalar(@seqs) . "\\tSTART\\t\", VF::Observe::key(\\\$x), \"\\n\"; $body }\n" } }
    last unless @seqs;
    open my $fh, '>', "$ROOT/child4_${TAG}_$c.pl" or die; print $fh $code; close $fh;
    my $out = `LC_ALL= LANG= timeout 120 $PERL $ROOT/child4_${TAG}_$c.pl 2>/dev/null`; utf8::decode($out);
    my %lines; for (split /\n/, $out) { my ($i,$op,$st) = split /\t/, $_, 3; push @{$lines{$i}}, [$op,$st] }
    my @next;
    for my $i (1..@seqs) { my $seq = $seqs[$i-1]; my $steps = $lines{$i} or next; my $prev = $steps->[0][1];
      for my $k (1..$#$steps) { my ($op,$st) = @{$steps->[$k]}; $edges{"$c$SEP$prev$SEP$op"} //= $st; my $key="$c$SEP$st";
        if (!$seen{$key}++) { $rep{$key} = [ @$seq[0..$k-1] ]; push @next, $rep{$key} } $prev = $st } }
    @frontier = @next;
  }
}
sub mstart { my $c=shift; return VF::Harness::number(3.5) if $c eq 'f35'; my $s = $starts{$c}; $s =~ s/^"(.*)"$/$1/; return VF::Harness::string($s) }
sub mfp { my $h=shift; my $b = VF::Harness::KeyTail($h); return ($h->{kind} eq "S" ? "P:$h->{pv}|L:".($h->{len}//0) : $h->{int_form}==2 ? sprintf("N:%.17g",$h->{iv}) : $h->{num_form} ? sprintf("N:%.17g",$h->{nv}) : $h->{int_form} ? sprintf("N:%.17g",$h->{iv}) : "-") . $b }
my $q = { warn => sub {} };
my %mop = (de_iv=>sub { my $h=shift; VF::Harness::WithRadix(",", sub { VF::sv_2iv_flags($h,$q) }) }, de_nv=>sub { my $h=shift; VF::Harness::WithRadix(",", sub { VF::sv_2nv_flags($h,$q) }) },
  de_add=>sub { my $h=shift; VF::Harness::WithRadix(",", sub { VF::pp_add($h,$q) }) }, de_str=>sub { my $h=shift; VF::Harness::WithRadix(",", sub { VF::sv_2pv_flags($h,$q) }) },
  cl_iv=>sub { VF::sv_2iv_flags($_[0],$q) }, cl_nv=>sub { VF::sv_2nv_flags($_[0],$q) }, nl_iv=>sub { VF::sv_2iv_flags($_[0],$q) }, nl_nv=>sub { VF::sv_2nv_flags($_[0],$q) },
  nl_add=>sub { VF::pp_add($_[0],$q) }, nl_str=>sub { VF::sv_2pv_flags($_[0],$q) }, copy=>sub { VF::Harness::CopyOp($_[0]) }, catx=>sub { VF::pp_multiconcat($_[0],$q,"x") });
my ($n,$bad)=(0,0); my @mis;
for my $e (sort keys %edges) { my ($c,$from,$op) = split /$SEP/, $e, 3; my $to = $edges{$e};
  my $recipe = $rep{"$c$SEP$from"} // []; my $h = VF::Harness::SeedBody(mstart($c)); for (@$recipe, $op) { $mop{$_}->($h); VF::body_type($h) }
  my $m = VF::Harness::FlagsProjection($h)."|".mfp($h); $n++;
  if ($m ne $to) { $bad++; push @mis, sprintf "%-6s %-40s --%-6s--> perl: %-40s model: %s   [recipe: %s]", $c, $from, $op, $to, $m, join(",",@$recipe) } }
print "oracle=$PERL depth=$DEPTH transitions=$n model_mismatches=$bad states=".scalar(keys %rep)."\n"; print "$_\n" for @mis;
open my $t, '>', "$ROOT/transitions.$TAG.txt" or die; for my $e (sort keys %edges) { my ($c,$from,$op)=split /$SEP/,$e,3; print $t "$c\t$from\t$op\t$edges{$e}\n" } close $t;
