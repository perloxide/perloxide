#!/usr/bin/perl
# pv_gen.pl -- UTF-8 flag / taint enumeration.  For each (string family, context, taint, op[, op2]) a child perl prints
# an observation record; PV.pm produces the same record from its transcription; mismatches are reported with recipes.
use strict; use warnings; use FindBin; use lib ($ENV{MODEL_ROOT} || "$FindBin::Bin/.."); my $WORK = $ENV{MODEL_WORK} || ($ENV{MODEL_ROOT} || "$FindBin::Bin/..") . "/work"; mkdir $WORK unless -d $WORK; require PV;
my $PERL = $ENV{ORACLE} || 'perl'; my $TAG = $ENV{TAG} || 'x'; my $DEPTH = $ENV{DEPTH} || 2;
my %fam = ( A => q{"abc"}, B => q{"\xB5\xE9"}, L => q{do { my $s = "\xB5\xE9"; utf8::upgrade($s); $s }}, H => q{"a\x{100}"},
            M => q{do { my $s = "\xC3\x28"; Encode::_utf8_on($s); $s }}, E => q{""} );
my @ctx = ( ['none', ''], ['feature', 'use feature "unicode_strings";'], ['locale', 'use locale; POSIX::setlocale(POSIX::LC_ALL(), "de_DE.UTF-8");'] );
# unary ops: code operates on $s and leaves the result in $r (a string) or a number
my %ops = (
  up=>'$r=$s; utf8::upgrade($r);', down=>'$r=$s; utf8::downgrade($r);', downok=>'$r=$s; my $ok = utf8::downgrade($r,1); $r .= ($ok ? "" : "");',
  enc=>'$r=$s; utf8::encode($r);', dec=>'$r=$s; utf8::decode($r);',
  len=>'$r=length($s);', rev=>'$r=reverse($s);', chop=>'$r=$s; chop $r;', chomp=>'$r=$s; chomp $r;',
  lc=>'$r=lc($s);', uc=>'$r=uc($s);', lcf=>'$r=lcfirst($s);', ucf=>'$r=ucfirst($s);', fc=>'$r=CORE::fc($s);',
  ord=>'$r=ord($s);', chr=>'$r=chr(ord($s));', sub1=>'$r=substr($s,0,1);', idx=>'$r=index($s,"\xB5");',
  sps=>'$r=sprintf("%s",$s);', spc=>'$r=sprintf("%c",ord($s));', rep=>'$r=$s x 2;', joinb=>'$r=join(",",$s,"\xB5");', joinu=>'$r=join(",",$s,"\x{100}");',
  split=>'my @p = split //, $s; $r = join("|", map { ord } @p);', tr=>'$r=$s; $r =~ tr/\xB5/X/;', trcnt=>'$r = ($s =~ tr/\xB5//);',
  unpU=>'$r=join(",",unpack("U*",$s));', unpC=>'$r=join(",",unpack("C*",$s));', unpU0C=>'$r=join(",",unpack("U0C*",$s));', unpC0U=>'$r=join(",",unpack("C0U*",$s));',
  packU=>'$r=pack("U",ord($s));', packa=>'$r=pack("a*",$s);', packA=>'$r=pack("A*",$s);',
  rew=>'$r=($s =~ /\w/) ? 1 : 0;', res=>'$r=($s =~ /\s/) ? 1 : 0;', red=>'$r=($s =~ /\d/) ? 1 : 0;', rewa=>'$r=($s =~ /\w/a) ? 1 : 0;', rewu=>'$r=($s =~ /\w/u) ? 1 : 0;', rewl=>'$r=($s =~ /\w/l) ? 1 : 0;',
  rei=>'$r=($s =~ /\x{39C}/i) ? 1 : 0;', reiu=>'$r=($s =~ /\x{39C}/iu) ? 1 : 0;', reia=>'$r=($s =~ /\x{39C}/ia) ? 1 : 0;',
  cap=>'($r) = $s =~ /(.*)/s;', hkey=>'my %h = ($s => 1); ($r) = keys %h;', hkey2=>'my %h; $h{$s}=1; my $t=$s; if (utf8::is_utf8($t)) { utf8::encode($t) } else { utf8::upgrade($t) } $h{$t}=2; $r = scalar(keys %h);',
  catb=>'$r = $s . "\xB5";', catu=>'$r = $s . "\x{100}";', catl=>'my $t="\xB5"; utf8::upgrade($t); $r = $s . $t;', apb=>'$r=$s; $r .= "\xB5";', apu=>'$r=$s; $r .= "\x{100}";', apl=>'my $t="\xB5"; utf8::upgrade($t); $r=$s; $r .= $t;',
  eqb=>'$r = ($s eq "\xB5\xE9") ? 1 : 0;', eql=>'my $t="\xB5\xE9"; utf8::upgrade($t); $r = ($s eq $t) ? 1 : 0;', cmpb=>'$r = ($s cmp "\xB5\xE9");',
  spd=>'$r=sprintf("%d", length($s));', arith=>'$r=length($s)+0;', copy=>'my $c=$s; $r=$c;',
);
my @unary = sort keys %ops;
my @chain = qw(up down enc dec lc uc rev sub1 cap catb catu apb);   # depth-2 second ops (string-valued)
my $head = <<'H';
use strict; no warnings; use POSIX (); use Encode (); use Scalar::Util qw(tainted); binmode(STDOUT, ":raw");
my @W; $SIG{__WARN__} = sub { my $m=$_[0]; $m =~ s/ at .*//s; $m =~ s/\s*\(.*//s; push @W, $m };
sub obs { my ($r) = @_; my $isnum = !defined($r) ? 0 : 0; my $b = defined $r ? $r : "undef";
  my $bytes = $b; my $f = utf8::is_utf8($b) ? 1 : 0; my $bb = $b; utf8::encode($bb) if $f;
  my $len = eval { length($b) } // "err"; my $ords = eval { join(",", map { ord } split //, $b) } // "err";
  join("\t", unpack("H*", $bb), $f, $len, $ords, (tainted($b) ? 1 : 0)) }
H
my ($ok,$bad,$n)=(0,0,0); my @rep; my %table;
for my $fam (sort keys %fam) { for my $c (@ctx) { for my $taint (0,1) {
  my @seqs = map { [$_] } @unary; if ($DEPTH >= 2) { push @seqs, map { my $a=$_; map { [$a,$_] } @chain } @chain }
  my $code = $head . "\n";
  my $init = $taint ? 'my $s = ' . $fam{$fam} . '; my $tsrc = substr($ENV{TSRC},0); $s = $s . substr($tsrc,0,0);' : 'my $s = ' . $fam{$fam} . ';';
  my $i=0; for my $seq (@seqs) { $i++; my $body = join(" ", map { "{ my \$s = \$r; my \$r; $ops{$_} \$r_out = \$r; }" } ()) ;
    my $ops = join(" ", map { "{ $ops{$_} \$rr = \$r; }" } @$seq);
    $code .= "{ $c->[1] \@W=(); $init my (\$r,\$rr); my \$ok = eval { { my \$r; $ops{$seq->[0]} \$rr=\$r; } " . ($seq->[1] ? "{ my \$s=\$rr; my \$r; $ops{$seq->[1]} \$rr=\$r; }" : "") . " 1 }; my \$err = \$ok ? '' : do { my \$e=\$@; \$e =~ s/ at .*//s; \$e =~ s/\\n.*//s; \$e }; print \"$i\\t\", obs(\$rr), \"\\t\", join('|',\@W), \"\\t\$err\\n\"; }\n" }
  open my $fh, '>', "$WORK/pv_child.pl" or die; print $fh $code; close $fh;
  my $cmd = "LC_ALL= LANG= TSRC=x timeout 20 $PERL " . ($taint ? "-T " : "") . "$WORK/pv_child.pl 2>/dev/null </dev/null"; my $out = `$cmd`;
  my %got; for (split /\n/, $out) { my ($k,@f) = split /\t/, $_, -1; $got{$k} = join("\t", @f) }
  $i=0; for my $seq (@seqs) { $i++; my $g = $got{$i} // "NO OUTPUT"; my $m = PV::Harness::Run($fam, $c->[0], $taint, $seq); $n++;
    my $key = "$fam.$c->[0]." . ($taint ? "T" : "U") . "." . join("+",@$seq); $table{$key} = $g;
    my ($gc,$mc) = map { my @f = split /\t/, $_, -1; $f[5] = ""; join("\t", @f) } ($g,$m);   # the warning column is recorded but not compared (warnings are not enumerated)
    if ($gc eq $mc) { $ok++ } else { $bad++; push @rep, "MISMATCH $key\n  perl:  $g\n  model: $m" } }
}}}
print "oracle=$PERL rows=$n ok=$ok bad=$bad\n"; print "$_\n" for @rep;
open my $t, '>', "$WORK/pv_table.$TAG.tsv" or die; print $t "$_\t$table{$_}\n" for sort keys %table; close $t;
