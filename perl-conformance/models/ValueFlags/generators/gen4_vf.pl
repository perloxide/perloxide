#!/usr/bin/perl
our $ROOT = $ENV{MODEL_ROOT} || '.'; our $WORK = $ENV{MODEL_WORK} || "$ROOT/work"; mkdir $WORK unless -d $WORK;
# The locale axis: radix acceptance and caching under a comma-radix LC_NUMERIC.  The `de_*` ops (named for the de_DE
# locale the lane first used) run under the harness's compiled radix_comma locale (lib/Perl/Conformance/Locales.pm),
# never a system locale; a locale that cannot be selected is fatal.  Each op runs in its own eval block, so `copyf`'s
# temporary is freed before the observation -- unlike gen3_vf.pl's `copy`, whose temporary is still alive, which is why
# the two carry different names in the merged transitions table.  Every observed edge goes to $WORK/edges.$TAG.tsv
# as start, from-state, op, to-state and the recipe that reached the from-state in the sequence that observed the edge
# (`-` when it is the start); with REPLAY_EDGES=FILE the edges are read from FILE, in that form, instead of running
# perl, and only the model side runs.
use strict; use warnings;
use FindBin; use lib "$FindBin::Bin/../../../lib";
use Perl::Conformance::Model::ValueFlags; use Perl::Conformance::Model::ValueFlags::Observe; use Perl::Conformance::Locales;
my $PERL = $ENV{PERL_CONFORMANCE_PERL} || 'perl'; my $DEPTH = $ENV{DEPTH} || 3; my $TAG = $ENV{TAG} || 'loc';
my %starts = ( c35=>q{"3,5"}, d35=>q{"3.5"}, c35x=>q{"3,5x"}, e35=>q{"1e3,5"}, c15=>q{"1,5"}, s10=>q{"10"}, f35=>q{3.5}, abc=>q{"abc"}, c0=>q{"0,5"} );
my @ops = (de_iv=>q{{ use locale; POSIX::setlocale(POSIX::LC_NUMERIC(),"de_DE.UTF-8"); my $t = $x | 0; POSIX::setlocale(POSIX::LC_NUMERIC(),"C"); }}, de_nv=>q{{ use locale; POSIX::setlocale(POSIX::LC_NUMERIC(),"de_DE.UTF-8"); my $t = sprintf "%.17g", $x; POSIX::setlocale(POSIX::LC_NUMERIC(),"C"); }},
  de_add=>q{{ use locale; POSIX::setlocale(POSIX::LC_NUMERIC(),"de_DE.UTF-8"); my $t = 0 + $x; POSIX::setlocale(POSIX::LC_NUMERIC(),"C"); }}, de_str=>q{{ use locale; POSIX::setlocale(POSIX::LC_NUMERIC(),"de_DE.UTF-8"); my $t = "$x"; POSIX::setlocale(POSIX::LC_NUMERIC(),"C"); }},
  cl_iv=>q{{ use locale; POSIX::setlocale(POSIX::LC_NUMERIC(),"C"); my $t = $x | 0; }}, cl_nv=>q{{ use locale; POSIX::setlocale(POSIX::LC_NUMERIC(),"C"); my $t = sprintf "%.17g", $x; }},
  nl_iv=>q{{ no locale; my $t = $x | 0; }}, nl_nv=>q{{ no locale; my $t = sprintf "%.17g", $x; }}, nl_add=>q{{ no locale; my $t = 0 + $x; }}, nl_str=>q{{ no locale; my $t = "$x"; }},
  copyf=>q{my $y = $x; $x = $y;}, catx=>q{$x .= "x";});
my $LOCPATH = $ENV{REPLAY_EDGES} ? '' : Perl::Conformance::Locales::compile("$WORK/locales")
    || die "cannot compile the harness locales: $Perl::Conformance::Locales::WHY\n";
my $RADIX = Perl::Conformance::Locales::locale_name('radix_comma');
s/de_DE\.UTF-8/$RADIX/g for @ops[ map { $_ * 2 + 1 } 0 .. $#ops / 2 ];
my %opcode = @ops; my @opnames = map { $ops[$_*2] } 0..$#ops/2;
my $head = <<'H';
use strict; no warnings; use B; use POSIX qw(setlocale LC_NUMERIC); binmode STDOUT, ":utf8";
BEGIN { POSIX::setlocale(POSIX::LC_NUMERIC(), $ENV{RADIX_LOCALE}) or do { print "LOCALE FAIL $ENV{RADIX_LOCALE}\n"; exit 3 }; POSIX::setlocale(POSIX::LC_NUMERIC(), "C") }
my @F=(IOK=>B::SVf_IOK,NOK=>B::SVf_NOK,POK=>B::SVf_POK,pIOK=>B::SVp_IOK,pNOK=>B::SVp_NOK,pPOK=>B::SVp_POK,IsUV=>B::SVf_IVisUV,UTF8=>B::SVf_UTF8);
use lib '__LIB__'; use Perl::Conformance::Model::ValueFlags::Observe; *fl = \&Perl::Conformance::Model::ValueFlags::Observe::flags; *fp = \&Perl::Conformance::Model::ValueFlags::Observe::slots;
H
$head =~ s/__LIB__/Perl::Conformance::Model::ValueFlags::Observe::lib_dir()/e;
my (%edges, %evia, %rep); my $SEP = "\x01";
for my $c ($ENV{REPLAY_EDGES} ? () : sort keys %starts) {
  my @frontier = ([]); my %seen;
  for my $d (0..$DEPTH) {
    my $code = $head; my @seqs;
    for my $recipe (@frontier) { for my $op (@opnames) { my @seq=(@$recipe,$op); push @seqs, \@seq;
      my $body = join "", map { "eval { $opcode{$_} 1 }; print \"" . scalar(@seqs) . "\\t$_\\t\", Perl::Conformance::Model::ValueFlags::Observe::key(\\\$x), \"\\n\"; " } @seq;
      $code .= "{ package B" . scalar(@seqs) . "; our \$x = $starts{$c}; print \"" . scalar(@seqs) . "\\tSTART\\t\", Perl::Conformance::Model::ValueFlags::Observe::key(\\\$x), \"\\n\"; $body }\n" } }
    last unless @seqs;
    open my $fh, '>', "$WORK/child4_${TAG}_$c.pl" or die; print $fh $code; close $fh;
    my $out = `LC_ALL= LANG= LOCPATH="$LOCPATH" RADIX_LOCALE="$RADIX" timeout 120 $PERL $WORK/child4_${TAG}_$c.pl 2>/dev/null`; utf8::decode($out);
    die "the locale lane's locale could not be selected: $1\n" if $out =~ /^LOCALE FAIL (.*)/m;
    my %lines; for (split /\n/, $out) { my ($i,$op,$st) = split /\t/, $_, 3; push @{$lines{$i}}, [$op,$st] }
    my @next;
    for my $i (1..@seqs) { my $seq = $seqs[$i-1]; my $steps = $lines{$i} or next; my $prev = $steps->[0][1];
      for my $k (1..$#$steps) { my ($op,$st) = @{$steps->[$k]}; my $ek = "$c$SEP$prev$SEP$op"; unless (exists $edges{$ek}) { $edges{$ek} = $st; $evia{$ek} = [ @$seq[0..$k-2] ] } my $key="$c$SEP$st";
        if (!$seen{$key}++) { $rep{$key} = [ @$seq[0..$k-1] ]; push @next, $rep{$key} } $prev = $st } }
    @frontier = @next;
  }
}
if (my $file = $ENV{REPLAY_EDGES}) {
  open my $in, '<:utf8', $file or die "cannot read $file: $!\n";
  while (<$in>) { chomp; my ($c,$from,$op,$to,$via) = split /\t/, $_, -1; $edges{"$c$SEP$from$SEP$op"} = $to; $evia{"$c$SEP$from$SEP$op"} = [ $via eq q{-} ? () : split /,/, $via ]; $rep{"$c$SEP$from"} //= $evia{"$c$SEP$from$SEP$op"} }
  close $in;
}
sub mstart { my $c=shift; return Perl::Conformance::Model::ValueFlags::Harness::number(3.5) if $c eq 'f35'; my $s = $starts{$c}; $s =~ s/^"(.*)"$/$1/; return Perl::Conformance::Model::ValueFlags::Harness::string($s) }
sub mfp { my $h=shift; my $b = Perl::Conformance::Model::ValueFlags::Harness::KeyTail($h); return ($h->{kind} eq "S" ? "P:$h->{pv}|L:".($h->{len}//0) : $h->{int_form}==2 ? sprintf("N:%.17g",$h->{iv}) : $h->{num_form} ? sprintf("N:%.17g",$h->{nv}) : $h->{int_form} ? sprintf("N:%.17g",$h->{iv}) : "-") . $b }
my $q = { warn => sub {} };
my %mop = (de_iv=>sub { my $h=shift; Perl::Conformance::Model::ValueFlags::Harness::WithRadix(",", sub { Perl::Conformance::Model::ValueFlags::sv_2iv_flags($h,$q) }) }, de_nv=>sub { my $h=shift; Perl::Conformance::Model::ValueFlags::Harness::WithRadix(",", sub { Perl::Conformance::Model::ValueFlags::sv_2nv_flags($h,$q) }) },
  de_add=>sub { my $h=shift; Perl::Conformance::Model::ValueFlags::Harness::WithRadix(",", sub { Perl::Conformance::Model::ValueFlags::pp_add($h,$q) }) }, de_str=>sub { my $h=shift; Perl::Conformance::Model::ValueFlags::Harness::WithRadix(",", sub { Perl::Conformance::Model::ValueFlags::sv_2pv_flags($h,$q) }) },
  cl_iv=>sub { Perl::Conformance::Model::ValueFlags::sv_2iv_flags($_[0],$q) }, cl_nv=>sub { Perl::Conformance::Model::ValueFlags::sv_2nv_flags($_[0],$q) }, nl_iv=>sub { Perl::Conformance::Model::ValueFlags::sv_2iv_flags($_[0],$q) }, nl_nv=>sub { Perl::Conformance::Model::ValueFlags::sv_2nv_flags($_[0],$q) },
  nl_add=>sub { Perl::Conformance::Model::ValueFlags::pp_add($_[0],$q) }, nl_str=>sub { Perl::Conformance::Model::ValueFlags::sv_2pv_flags($_[0],$q) }, copyf=>sub { Perl::Conformance::Model::ValueFlags::Harness::CopyOp($_[0]) }, catx=>sub { Perl::Conformance::Model::ValueFlags::pp_multiconcat($_[0],$q,"x") });
my ($n,$bad)=(0,0); my @mis;
for my $e (sort keys %edges) { my ($c,$from,$op) = split /$SEP/, $e, 3; my $to = $edges{$e};
  my $recipe = $evia{$e} // []; my $h = Perl::Conformance::Model::ValueFlags::Harness::SeedBody(mstart($c)); for (@$recipe, $op) { $mop{$_}->($h); Perl::Conformance::Model::ValueFlags::body_type($h) }
  my $m = Perl::Conformance::Model::ValueFlags::Harness::FlagsProjection($h)."|".mfp($h); $n++;
  if ($m ne $to) { $bad++; push @mis, sprintf "%-6s %-40s --%-6s--> perl: %-40s model: %s   [recipe: %s]", $c, $from, $op, $to, $m, join(",",@$recipe) } }
print "perl=$PERL depth=$DEPTH transitions=$n model_mismatches=$bad states=".scalar(keys %rep)."\n"; print "$_\n" for @mis;
exit 0 if $ENV{REPLAY_EDGES};
open my $ob, '>:utf8', "$WORK/edges.$TAG.tsv" or die; for my $e (sort keys %edges) { my ($c,$from,$op)=split /$SEP/,$e,3; my $via = $evia{$e}; print $ob join("\t", $c, $from, $op, $edges{$e}, ($via && @$via ? join(",", @$via) : '-')), "\n" } close $ob;
open my $t, '>', "$WORK/transitions.$TAG.txt" or die; for my $e (sort keys %edges) { my ($c,$from,$op)=split /$SEP/,$e,3; print $t "$c\t$from\t$op\t$edges{$e}\n" } close $t;
