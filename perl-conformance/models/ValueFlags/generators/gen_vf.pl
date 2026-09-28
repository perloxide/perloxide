#!/usr/bin/perl
use lib ($ENV{VF_ROOT} || '.'); our $ROOT = $ENV{VF_ROOT} || '.'; my $TAG = $ENV{TAG} || "matrix";
# Differential generator: perl (oracle) vs the design's value flags model, for
# __WARN__ handlers that mutate the scalar being converted.
use strict; use warnings; use POSIX ();
my $PERL = $ENV{ORACLE} || 'perl';
my @inputs = (['12x',q{'12x'}],['12.5x',q{'12.5x'}],['abc',q{'abc'}],['empty',q{''}],['sp12x',q{' 12x'}],
  ['1e3x',q{'1e3x'}],['Infx',q{'Infx'}],['nanx',q{'nanx'}],['-0x',q{'-0x'}],['0x1A',q{'0x1A'}],['1_000',q{'1_000'}],
  ['12U',q{"12\x{100}"}],['12',q{'12'}],['12.5',q{'12.5'}],['undef',q{undef}],['12n',q{12}],['12.5n',q{12.5}],['ref',q{\1}]);
my @repls = (['s99',q{$x='99';}],['s99.5',q{$x='99.5';}],['szz',q{$x='zz';}],['n99',q{$x=99;}],['n99.5',q{$x=99.5;}],['ref',q{$x=\1;}],['undef',q{undef $x;}],['keep',q{}]);
my @thens = (['iv',q{my $z=$x|0;}],['nv',q{my $z=sprintf('%.17g',$x);}],['none',q{}],['die',q{die "H\n";}]);
my @outers = (['add',q{0+$x}],['bor',q{$x|0}],['spg',q{sprintf('%g',$x)}],['cat',q{$x.""}]);

my $child_tmpl = <<'CHILD';
use strict; use warnings; use B; binmode(STDOUT, ":utf8");
my @F=(IOK=>B::SVf_IOK,NOK=>B::SVf_NOK,POK=>B::SVf_POK,pIOK=>B::SVp_IOK,pNOK=>B::SVp_NOK,pPOK=>B::SVp_POK,IsUV=>B::SVf_IVisUV,ROK=>B::SVf_ROK);
use lib ($ENV{VF_ROOT}||'.'); use VF::Observe; *fl = \&VF::Observe::flags;
my $ADDR; sub num { my $v=shift; ref $v ? "ADDR" : (defined $ADDR && $v == $ADDR) ? "ADDR" : sprintf("%.17g",$v) }
my $x = __INPUT__;
my $calls=0; my $depth=0;
my $h = sub { $calls++; return if $depth++; __REPL__ __THEN__ $depth--; };
my $n; my $died=0;
{ local $SIG{__WARN__}=$h; $n = eval { __OUTER__ }; $died = 1 if $@; }
{ local $SIG{__WARN__}=sub{}; $ADDR = 0+$x if ref $x; my $d = defined $x ? 1 : 0;
  my $nr = $died ? "die" : !defined $n ? "undef" : (__ISCAT__ ? "'$n'" : num($n)); $nr = "ADDR" if ref $x && $calls == 0 && !__ISCAT__ && !$died;
  my $f = fl(\$x);
  my $s = !defined $x ? "undef" : ref $x ? "ADDR" : "'$x'"; $s = "'ADDR'" if $s =~ /^'SCALAR\(0x/;
  $nr = "'ADDR'" if $nr =~ /^'SCALAR\(0x/;
  my $a = num(0+$x); my $o = num($x|0); my $g = num(0.0+$x);
  print join("\t", $nr, $s, $a, $o, $g, $f, $calls, $d), "\n";
}
CHILD

# ---------------- model of the design ----------------
use lib ($ENV{VF_ROOT}||'.'); require VF;
package VF;
# handler-matrix driver (uses the M2 primitives)
sub run_model { my ($in,$repl,$then,$outer)=@_;
  my $h = $in eq 'undef' ? { kind=>'U',iv=>0,nv=>0,int_form=>0,num_form=>0,is_uv=>0,stringified=>0} : $in eq "12n" ? { kind=>"I",iv=>12,nv=>0,int_form=>2,num_form=>0,is_uv=>0,stringified=>0}
        : $in eq "12.5n" ? { kind=>"N",iv=>0,nv=>12.5,int_form=>0,num_form=>2,is_uv=>0,stringified=>0} : $in eq 'ref' ? { kind=>'R',iv=>0,nv=>0,int_form=>0,num_form=>0,is_uv=>0,stringified=>0}
        : VF::Harness::string($in eq 'empty' ? '' : $in eq 'sp12x' ? ' 12x' : $in eq '12U' ? "12\x{100}" : $in);
  my $calls=0; my $depth=0; my $died=0;
  my $ctx; $ctx = { warn => sub { my $hh=shift; $calls++; return if $depth++;
     my %set = (s99=>sub{ @$hh{qw(kind pv int_form num_form is_uv stringified)}=('S','99',0,0,0,0); $hh->{cow}=1; $hh->{cow}=1 }, 's99.5'=>sub{ @$hh{qw(kind pv int_form num_form is_uv stringified)}=('S','99.5',0,0,0,0); $hh->{cow}=1; $hh->{cow}=1 },
                szz=>sub{ @$hh{qw(kind pv int_form num_form is_uv stringified)}=('S','zz',0,0,0,0); $hh->{cow}=1; $hh->{cow}=1 }, n99=>sub{ @$hh{qw(kind iv int_form num_form is_uv stringified)}=("I",99,2,0,0,0); $hh->{cow}=0 },
                'n99.5'=>sub{ @$hh{qw(kind nv int_form num_form is_uv stringified)}=('N',99.5,0,2,0,0); $hh->{cow}=0 }, ref=>sub{ @$hh{qw(kind int_form num_form is_uv stringified)}=('R',0,0,0,0); $hh->{cow}=0 },
                undef=>sub{ @$hh{qw(kind int_form num_form is_uv stringified)}=('U',0,0,0,0); $hh->{cow}=0 }, keep=>sub{});
     $set{$repl}->();
     if ($then eq 'iv') { sv_2iv_flags($hh,$ctx) } elsif ($then eq 'nv') { sv_2nv_flags($hh,$ctx) } elsif ($then eq 'die') { die "H\n" }
     $depth--; } };
  my $n = eval { my %ops=(add=>\&pp_add,bor=>\&pp_bit_or,spg=>\&sv_vcatpvfn_flags_g,cat=>\&sv_2pv_flags); $ops{$outer}->($h,$ctx) };
  if ($@) { return ("UB", "", "", "", "", "", $calls) if $@ =~ /^UB/; $died=1 }
  my $nr = $died ? "die" : $outer eq 'cat' ? "'$n'" : VF::Harness::Num($n);
  my $quiet = { warn => sub { $calls++ } };   # post-reads under a no-op handler (perl side counts them too? no: perl's post handler is sub{} which does not count)
  $quiet = { warn => sub {} };
  my $f = VF::Harness::FlagsProjection($h);
  my $d = ($h->{kind} eq "S" || $h->{kind} eq "R" || $h->{int_form} || $h->{num_form}) ? 1 : 0;
  my $s = !$d ? "undef" : $h->{kind} eq "R" ? "ADDR" : "'".sv_2pv_flags($h,$quiet)."'";
  my $a = VF::Harness::Num(pp_add($h,$quiet)); my $o = VF::Harness::Num(pp_bit_or($h,$quiet)); my $g = VF::Harness::Num(sv_2nv_flags($h,$quiet));
  return ($nr,$s,$a,$o,$g,$f,$calls,$d);
}
package main;
my ($rows,$ok,$bad,$crash,$ub,$flagbad)=(0,0,0,0,0,0); my @report;
for my $in (@inputs) { for my $re (@repls) { for my $th (@thens) { for my $ou (@outers) {
  my $code = $child_tmpl; $code =~ s/__INPUT__/$in->[1]/; $code =~ s/__REPL__/$re->[1]/; $code =~ s/__THEN__/$th->[1]/; $code =~ s/__OUTER__/$ou->[1]/;
  $code =~ s/__ISCAT__/($ou->[0] eq "cat" ? 1 : 0)/ge;
  open my $fh, '>', "$ROOT/child_$TAG.pl" or die; print $fh $code; close $fh;
  my $out = `timeout 5 $PERL $ROOT/child_$TAG.pl 2>/dev/null`; my $st = $?; utf8::decode($out);
  my $key = "$in->[0]/$re->[0]/$th->[0]/$ou->[0]"; $rows++;
  if ($st & 127 || ($st >> 8) >= 124) { $crash++; push @report, "CRASH  $key (signal ".($st&127).")"; next }
  chomp $out; my @p = split /\t/, $out; my @m = VF::run_model($in->[0],$re->[0],$th->[0],$ou->[0]);
  if ($m[0] eq "UB") { $ub++; local $VF::DESIGN_DEFINED = 1; my @d = VF::run_model($in->[0],$re->[0],$th->[0],$ou->[0]); push @report, "DIVERGES-defined $key perl=[@p[0..4]] design=[@d[0..4]]"; next }
  my $vals_ok = join("|",@p[0..4],$p[7]//"") eq join("|",@m[0..4],$m[7]);
  if ($vals_ok) { $ok++ } else { $bad++; push @report, "VALUE  $key\n         perl : @p[0..4]\n         model: @m[0..4]" }
  if ($p[5] ne $m[5]) { $flagbad++; push @report, "FLAGS  $key perl=$p[5] model=$m[5]" if $vals_ok }
}}}}
print "rows=$rows values_ok=$ok values_bad=$bad flag_mismatch_on_value_ok_rows=$flagbad crash=$crash ub_rows=$ub\n";
print "$_\n" for @report;
