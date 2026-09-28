#!/usr/bin/perl
# fz_gen.pl -- scenario generator + differential runner for FZ.pm (finalization / temporary lifetime).
# Each scenario is an IR program; the same IR is emitted as perl source (oracle) and executed by FZ.
use strict; use warnings; use FindBin; use lib ($ENV{MODEL_ROOT} || "$FindBin::Bin/.."); my $WORK = $ENV{MODEL_WORK} || ($ENV{MODEL_ROOT} || "$FindBin::Bin/..") . "/work"; mkdir $WORK unless -d $WORK; require FZ;
my $PERL = $ENV{ORACLE} || 'perl';

# ---------------- IR -> perl source ----------------
my %CLASS = (O=>'plain', K=>'selfcopy', W=>'weakcopy', R=>'rebless', X=>'dies');
sub emit_expr { my $e=shift; my ($t,@a)=@$e;
  return "$a[1]->new('$a[0]')" if $t eq 'new';
  return "\$$a[0]" if $t eq 'var';
  return "$a[0](" . join(", ", map { emit_expr($_) } @{$a[1]}) . ")" if $t eq 'call';
  return "cnt()" if $t eq 'cnt';
  return "5" if $t eq 'plain';
  die "expr $t" }
sub emit_stmt { my ($s,$ind)=@_; my ($t,@a)=@$s; my $p = "  " x $ind;
  if ($t eq 'stmt') { return $p . join(" ", map { emit_op($_) } @a) . "\n" }
  if ($t eq 'block') { return $p."{\n" . join("", map { emit_stmt($_,$ind+1) } @{$a[0]}) . $p."}\n" }
  if ($t eq 'if')    { return $p."if (" . emit_expr($a[0]) . ") {\n" . join("", map { emit_stmt($_,$ind+1) } @{$a[1]}) . $p."}\n" }
  if ($t eq 'while') { return $p."while (" . emit_expr($a[0]) . ") {\n" . join("", map { emit_stmt($_,$ind+1) } @{$a[1]}) . $p."}\n" }
  if ($t eq "postwhile") { my $o = emit_op($a[0]); $o =~ s/;\z//; return $p . $o . " while " . emit_expr($a[1]) . ";\n" }
  if ($t eq 'dowhile') { return $p."do {\n" . join("", map { emit_stmt($_,$ind+1) } @{$a[0]}) . $p."} while (" . emit_expr($a[1]) . ");\n" }
  if ($t eq "cfor")  { return $p."for (my \$i = 0; " . emit_expr($a[0]) . "; " . ($a[2] ? "\$i++" : "") . ") {\n" . join("", map { emit_stmt($_,$ind+1) } @{$a[1]}) . $p."}\n" }
  if ($t eq 'eval')  { return $p."eval {\n" . join("", map { emit_stmt($_,$ind+1) } @{$a[0]}) . $p."};\n" . $p."print 'E:', (\$@ =~ s/\\n.*//sr), \"\\n\";\n" }
  if ($t eq 'grep')  { return $p."my \@g = grep { my \$t = $a[0]->new('$a[1]'); 1 } (1, 2);\n" }
  die "stmt $t" }
sub emit_op { my $o=shift; my ($t,@a)=@$o;
  return "print \"m$a[0]\\n\";" if $t eq 'mark';
  return "my \$$a[0];" if $t eq 'my';
  return "my \$$a[0] = " . emit_expr($a[1]) . ";" if $t eq "myasg";
  return "\$$a[0] = " . emit_expr($a[1]) . ";" if $t eq "ourasg";
  return "\$$a[0] = " . emit_expr($a[1]) . ";" if $t eq 'assign';
  return "undef \$$a[0];" if $t eq 'undef';
  return "\$$a[0] .= 's';" if $t eq 'cat';
  return "weaken(\$$a[0]);" if $t eq "weaken";
  return "tie \$$a[0], '$a[1]', '$a[0]';" if $t eq "tie";
  return "our \$$a[0];" if $t eq 'our';
  return "my \@$a[0] = (" . emit_expr($a[1]) . ");" if $t eq 'myarr';
  return "my \%$a[0] = (k => " . emit_expr($a[1]) . ");" if $t eq 'myhash';
  return "delete \$$a[0]\{k\};" if $t eq 'delete';
  return "\@$a[0] = ();" if $t eq 'clear';
  return emit_expr($a[0]) . ";" if $t eq 'expr';
  return "my \@l = " . emit_expr($a[0]) . ";" if $t eq 'listctx';
  return "my \$s = " . emit_expr($a[0]) . ";" if $t eq 'scalarctx';
  return "die \"$a[0]\\n\";" if $t eq 'die';
  return "local \$::G = " . emit_expr($a[0]) . ";" if $t eq 'local';
  return "1;" if $t eq 'one';
  die "op $t" }
my $prelude = <<'P';
use strict; use warnings; no warnings 'once'; use Scalar::Util qw(weaken); $| = 1;
our @WEAK; our $keep; our $wk; our $G; our ($h, $w, $t, $ta, $tb);
sub FZ::Harness::WeakFlags { join "", map { defined($$_) ? 1 : 0 } @WEAK }
package O; sub new { my ($c,$id)=@_; bless {id=>$id}, $c } sub DESTROY { print "D$_[0]{id}:", ref($_[0]), "[", main::FZ::Harness::WeakFlags(), "]\n" }
package K; our @ISA=('O'); sub DESTROY { $_[0]->O::DESTROY; $main::keep = $_[0] }
package W; our @ISA=('O'); sub DESTROY { $_[0]->O::DESTROY; $main::wk = $_[0]; Scalar::Util::weaken($main::wk) }
package R; our @ISA=('O'); sub DESTROY { $_[0]->O::DESTROY; bless $_[0], 'P' }
package P; our @ISA=('O');
package X; our @ISA=('O'); sub DESTROY { $_[0]->O::DESTROY; die "dd\n" }
package T; sub TIESCALAR { bless {n=>$_[1]}, $_[0] } sub FETCH { undef } sub STORE { print "S$_[0]{n}(", (defined $_[1] ? "def" : "undef"), ")\n" }
package TX; our @ISA=("T"); sub STORE { $_[0]->T::STORE($_[1]); die "sd\n" if $_[0]{n} eq "ta" && !defined $_[1] }
package main;
my $n = 0; sub cnt { $n++ < 1 ? O->new('c') : 0 }
sub foo { print "m-foo\n"; 1 }
sub o { O->new('o') }
sub vq { my $q = O->new('q'); O->new('h') }
sub vh { O->new('h'); my $q = O->new('q'); 1 }
END { print "END\n" }
P
sub emit_program { my $ir=shift; my $src = $prelude; $src .= join("", map { emit_stmt($_,0) } @$ir); $src .= "print \"m-end\\n\";\n"; $src }

# ---------------- scenarios ----------------
my @scen;
my $S = sub { my ($name,$ir)=@_; push @scen, [$name,$ir] };
my @cls = qw(O K W R X);
for my $c (@cls) {
  # scope-exit orders
  $S->("scope3.$c", [ ['block', [ ['stmt',['myasg','a',['new','a',$c]]], ['stmt',['myasg','b',['new','b','O']]], ['stmt',['myasg','c',['new','c','O']]] ]], ['stmt',['mark',1]] ]);
  $S->("scope3one.$c", [ ['block', [ ['stmt',['myasg','a',['new','a',$c]]], ['stmt',['myasg','b',['new','b','O']]], ['stmt',['myasg','c',['new','c','O']]], ['stmt',['one']] ]], ['stmt',['mark',1]] ]);
  # triggers on a lexical holder, with a weak ref
  for my $trig (qw(undef assign cat)) {
    $S->("$trig.$c", [ ['stmt',['our','WEAK']], ["stmt",["ourasg","h",["new","a",$c]]], ["stmt",["ourasg","w",["var","h"]]], ['stmt',['weaken','w','h']], ['stmt',['expr',['call','push_weak',[]]]],
       ['stmt',['mark',1]], ['stmt', $trig eq 'assign' ? ['assign','h',['plain']] : [$trig,'h']], ['stmt',['mark',2]] ]);
  }
  $S->("delete.$c", [ ['stmt',['myhash','hh',['new','a',$c]]], ['stmt',['mark',1]], ['stmt',['delete','hh']], ['stmt',['mark',2]] ]);
  $S->("clear.$c",  [ ['stmt',['myarr','aa',['new','a',$c]]], ['stmt',['mark',1]], ['stmt',['clear','aa']], ['stmt',['mark',2]] ]);
  # temporaries in constructs
  $S->("if1.$c",   [ ['if', ['new','a',$c], [ ['stmt',['mark',1]] ]], ['stmt',['mark',2]] ]);
  $S->("if2.$c",   [ ['if', ['new','a',$c], [ ['stmt',['mark',1]], ['stmt',['mark',2]] ]], ['stmt',['mark',3]] ]);
  $S->("while.$c", [ ['while', ['cnt'], [ ['stmt',['mark',1]] ]], ['stmt',['mark',2]] ]);
  $S->("postwhile.$c", [ ['postwhile', ['mark',1], ['cnt']], ['stmt',['mark',2]] ]);
  $S->("dowhile.$c", [ ['dowhile', [ ['stmt',['mark',1]] ], ['cnt']], ['stmt',['mark',2]] ]);
  $S->("cfor.$c",  [ ["cfor", ["cnt"], [ ["stmt",["mark",1]] ], 1], ["stmt",["mark",2]] ]);
  $S->("cfor0.$c", [ ["cfor", ["cnt"], [ ["stmt",["mark",1]] ], 0], ["stmt",["mark",2]] ]);
  $S->("cfor2.$c", [ ["cfor", ["cnt"], [ ["stmt",["mark",1]], ["stmt",["mark",3]] ], 1], ["stmt",["mark",2]] ]);
  $S->("callarg.$c", [ ['stmt',['expr',['call','foo',[['new','a',$c]]]]], ['stmt',['mark',1]] ]);
  $S->("plainstmt.$c", [ ['stmt',['expr',['new','a',$c]]], ['stmt',['mark',1]] ]);
  $S->("eval.$c",  [ ['eval', [ ['stmt',['myasg','h',['new','a',$c]]], ['stmt',['die','boom']] ]], ['stmt',['mark',1]] ]);
  $S->("evaltmp.$c", [ ['eval', [ ['stmt',['expr',['new','a',$c]]], ['stmt',['die','boom']] ]], ['stmt',['mark',1]] ]);
  $S->("grep.$c",  [ ['grep', $c, 'g'], ['stmt',['mark',1]] ]);
  $S->("local.$c", [ ['block', [ ['stmt',['local',['new','a',$c]]], ['stmt',['myasg','b',['new','b','O']]] ]], ['stmt',['mark',1]] ]);
}
$S->("vq.void",   [ ['stmt',['expr',['call','vq',[]]]], ['stmt',['mark',1]] ]);
$S->("vq.list",   [ ['stmt',['listctx',['call','vq',[]]]], ['stmt',['mark',1]] ]);
$S->("vq.scalar", [ ['stmt',['scalarctx',['call','vq',[]]]], ['stmt',['mark',1]] ]);
$S->("vh.void",   [ ['stmt',['expr',['call','vh',[]]]], ['stmt',['mark',1]] ]);
$S->("vh.list",   [ ['stmt',['listctx',['call','vh',[]]]], ['stmt',['mark',1]] ]);
for my $tc (qw(T TX)) {
  $S->("tiedweak.$tc", [ ["stmt",["our","WEAK"]], ["stmt",["tie","ta",$tc]], ["stmt",["tie","tb",$tc]], ["block", [ ["stmt",["myasg","x",["new","a","O"]]], ["stmt",["assign","ta",["var","x"]]], ["stmt",["weaken","ta","x"]], ["stmt",["assign","tb",["var","x"]]], ["stmt",["weaken","tb","x"]], ["stmt",["expr",["call","push_weak",[]]]], ["stmt",["mark",1]], ["eval", [ ["stmt",["undef","x"]] ]], ["stmt",["mark",2]] ]], ["stmt",["mark",3]] ]);
}
# global destruction: objects left in file-scope lexicals and globals
$S->("global.lex", [ ["stmt",["myasg","p",["new","a","O"]]], ["stmt",["myasg","q",["new","b","O"]]], ["stmt",["mark",1]] ]);
$S->("global.weak", [ ["stmt",["our","WEAK"]], ["stmt",["ourasg","h",["new","a","O"]]], ["stmt",["ourasg","w",["var","h"]]], ['stmt',['weaken','w','h']], ['stmt',['expr',['call','push_weak',[]]]], ['stmt',['mark',1]] ]);

# ---------------- run ----------------
my ($ok,$bad,$allowed)=(0,0,0); my @rep; my %out;
for my $s (@scen) { my ($name,$ir)=@$s;
  my $src = emit_program($ir); $src =~ s/sub cnt \{/sub push_weak { push \@WEAK, \\\$_ for grep { defined } (\$main::w_ref); }\nsub cnt {/;
  # weak refs are registered by name: the generator knows which lexicals were weakened
  my @weak = map { $_->[1] } grep { $_->[0] eq 'weaken' } map { @{$_}[1..$#$_] } grep { $_->[0] eq 'stmt' } @$ir;
  $src =~ s/sub push_weak \{.*?\}\n/"sub push_weak { \@WEAK = (" . join(",", map { "\\\$$_" } @weak) . "); }\n"/e;
  $src =~ s/^(sub push_weak)/$1/m; $src = "no strict 'refs';\n$src" if 0;
  # lexical weak holders must be visible to push_weak: hoist them to file-scope 'our' vars for the oracle
  open my $fh, '>', "$WORK/fz_child.pl" or die; print $fh $src; close $fh;
  my $got = `timeout 10 $PERL $WORK/fz_child.pl 2>&1`; $got =~ s/^[ \t]*\(in cleanup\)[^\n]*\n/W\n/mg; $got =~ s{ at \Q$WORK\E/fz_child\.pl line \d+\.\n}{\n}g;
  my $exp = FZ::Harness::Run($ir, {weak=>\@weak});
  my $isglobal = $name =~ /^global/;
  my $cmp = sub { my ($a,$b)=@_; return $a eq $b unless $isglobal; my @x = sort split /\n/, $a; my @y = sort split /\n/, $b; "@x" eq "@y" };
  if ($cmp->($got,$exp)) { $ok++; $allowed++ if $isglobal } else { $bad++; push @rep, "MISMATCH $name\n--- perl:\n$got--- FZ:\n$exp" }
  $out{$name} = $got;
}
print "oracle=$PERL scenarios=".scalar(@scen)." ok=$ok bad=$bad (allowed-state rows: $allowed)\n"; print "$_\n" for @rep;
open my $t, '>', "$WORK/fz_traces.$ENV{TAG}.txt" or die; for (sort keys %out) { print $t "### $_\n$out{$_}" } close $t;
