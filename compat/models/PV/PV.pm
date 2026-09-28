package PV;
# Executable transcription of perl 5.44.0's string-flag and taint semantics.  A string value is {b => bytes, u => SVf_UTF8,
# t => tainted}; the flag is an interpretation claim over the bytes (utf8.h), never a property of the content class.
use strict; use warnings; no warnings 'portable';
our $CTX = "none"; our @W; our $MAL; our @MALB;
sub PV::Harness::Warn { push @W, shift }
# ---- utf8.c: utf8n_to_uvchr / UTF8SKIP / uvchr_to_utf8 ----
sub UTF8SKIP { my $b=shift; $b < 0x80 ? 1 : $b < 0xC0 ? 1 : $b < 0xE0 ? 2 : $b < 0xF0 ? 3 : $b < 0xF8 ? 4 : $b < 0xFC ? 5 : $b < 0xFE ? 6 : 7 }
sub uvchr_to_utf8 { my $c=shift; return chr($c) if $c < 0x80; my $s = chr($c); utf8::encode($s); $s }
sub PV::Harness::Chars { my $v=shift; return map { ord } split //, $v->{b} unless $v->{u};
  my @c; my $s=$v->{b}; my $i=0; while ($i < length $s) { my $lead = ord substr($s,$i,1); my $n = UTF8SKIP($lead);
    my $chunk = substr($s,$i,$n); my $c = $chunk; my $ok = ($n == 1 && $lead < 0x80) || (length($chunk)==$n && $lead >= 0xC2 && $chunk =~ /^[\xC0-\xFD][\x80-\xBF]+\z/ && utf8::decode($c) && length($c)==1);
    if ($ok) { push @c, ord($c) } else { $MAL=1; push @c, 0; push @MALB, $chunk } $i += $n } @c }   # malformed: ord reads 0 (warnings are not enumerated here); the bytes travel with the character
sub PV::Harness::FromCps { my ($cps,$u,$t)=@_; $u = 1 if grep { $_ > 0xFF } @$cps; my @mb = @MALB; my $b = $u ? join("", map { $_ == 0 && @mb ? shift(@mb) : uvchr_to_utf8($_) } @$cps) : join("", map { chr } @$cps); { b=>$b, u=>$u?1:0, t=>$t?1:0 } }
sub sv_len_utf8 { my $v=shift; $v->{u} ? scalar(PV::Harness::Chars($v)) : length($v->{b}) }   # Perl_utf8_length counts by UTF8SKIP
# ---- sv.c sv_utf8_upgrade_flags_grow / sv_utf8_downgrade_flags ----
sub sv_utf8_upgrade_flags_grow { my $v=shift; return $v if $v->{u}; { b=>join("", map { uvchr_to_utf8(ord $_) } split //, $v->{b}), u=>1, t=>$v->{t} } }
sub sv_utf8_downgrade_flags { my ($v,$failok)=@_; return ($v,1) unless $v->{u}; my @c = PV::Harness::Chars($v);
  if ($MAL || grep { $_ > 0xFF } @c) { die "Wide character in subroutine entry\n" unless $failok; return ($v,0) }
  return ({ b=>join("", map { chr } @c), u=>0, t=>$v->{t} },1) }
# ---- the Unicode bug: which rules apply to a byte string (pp.c pp_lc/pp_uc, regcomp.c charset) ----
sub PV::Harness::UnicodeRules { my $v=shift; $v->{u} || $CTX eq 'feature' || $CTX eq 'locale' }   # a UTF-8 locale under use locale behaves as unicode_strings
my %UC = (0xB5=>[0x39C], 0xDF=>[0x53,0x53], 0xFF=>[0x178]); my %LC = (); my %FC = (0xB5=>[0x3BC], 0xDF=>[0x73,0x73]);
sub PV::Harness::CaseMap { my ($v,$kind,$firstonly)=@_; my @c = PV::Harness::Chars($v); my $uni = PV::Harness::UnicodeRules($v); my @out;
  for my $i (0..$#c) { my $c=$c[$i]; my @m=($c);
    if ($firstonly && $i>0) { push @out,$c; next }
    if ($c < 0x80) { my $ch = chr $c; $ch = $kind eq 'uc' ? uc $ch : lc $ch; @m=(ord $ch) }
    elsif ($uni) { if ($kind eq 'uc') { @m = $UC{$c} ? @{$UC{$c}} : ($c >= 0xE0 && $c <= 0xFE && $c != 0xF7 ? ($c-0x20) : ($c > 0xFF ? (ord uc chr $c) : ($c))) }
      elsif ($kind eq 'lc') { @m = ($c >= 0xC0 && $c <= 0xDE && $c != 0xD7) ? ($c+0x20) : ($c > 0xFF ? (ord lc chr $c) : ($c)) }
      else { @m = $FC{$c} ? @{$FC{$c}} : ($c >= 0xC0 && $c <= 0xDE && $c != 0xD7) ? ($c+0x20) : ($c > 0xFF ? (map { ord } split //, CORE::fc chr $c) : ($c)) } }
    push @out, @m }
  PV::Harness::FromCps(\@out, $v->{u}, $v->{t}) }
sub PV::Harness::Run { my ($fam,$ctx,$taint,$seq)=@_; local $CTX=$ctx; local @W=(); local $MAL=0; local @MALB=();
  my %init = ( A=>{b=>"abc",u=>0}, B=>{b=>"\xB5\xE9",u=>0}, L=>{b=>"\xC2\xB5\xC3\xA9",u=>1}, H=>{b=>"a\xC4\x80",u=>1}, M=>{b=>"\xC3\x28",u=>1}, E=>{b=>"",u=>0} );
  my $v = { %{$init{$fam}}, t=>$taint?1:0 }; my $err='';
  my $ok = eval { for my $op (@$seq) { $MAL=0; @MALB=(); $v = PV::Harness::Op($op,$v) } 1 }; if (!$ok) { $err=$@; $err =~ s/\n\z//; $v = "undef" }   # a croaking op leaves the result undefined
  my $r = $v; my $bytes = ref $r ? $r->{b} : "$r"; my $u = ref $r ? $r->{u} : 0; my $t = ref $r ? $r->{t} : 0;
  my $len = ref $r ? sv_len_utf8($r) : length($bytes); my @o = ref $r ? PV::Harness::Chars($r) : map { ord } split //, $bytes;
  my $ords = join(",", @o); my $hex = unpack("H*", $bytes);
  return join("\t", $hex, $u, $len, $ords, $t, "", $err) }
sub PV::Harness::Num { my ($n,$t)=@_; { b=>"$n", u=>0, t=>$t?1:0, num=>1 } }
sub PV::Harness::Op { my ($op,$v)=@_; my $t=$v->{t};
  return sv_utf8_upgrade_flags_grow($v) if $op eq 'up';
  if ($op eq 'down') { my ($r)=sv_utf8_downgrade_flags($v,0); return $r } if ($op eq 'downok') { my ($r)=sv_utf8_downgrade_flags($v,1); return $r }
  if ($op eq 'enc') { my $u = sv_utf8_upgrade_flags_grow($v); return { b=>$u->{b}, u=>0, t=>$t } }                                 # sv_utf8_encode: upgrade then SvUTF8_off
  if ($op eq 'dec') { my ($d,$ok) = sv_utf8_downgrade_flags($v,1); return $v unless $ok;                                   # sv_utf8_decode: sv_utf8_downgrade(sv, TRUE) first
    my $c=$d->{b}; return { b=>$d->{b}, u=>($d->{b} =~ /[\x80-\xFF]/ && utf8::decode($c) ? 1 : 0), t=>$t } }
  if ($op eq 'len') { return PV::Harness::Num(sv_len_utf8($v),$t) }
  if ($op eq 'rev') { my @c = reverse PV::Harness::Chars($v); return PV::Harness::FromCps(\@c,$v->{u},$t) }
  if ($op eq 'chop') { my @c = PV::Harness::Chars($v); pop @c; return PV::Harness::FromCps(\@c,$v->{u},$t) }
  if ($op eq 'chomp') { return $v }
  return PV::Harness::CaseMap($v,'lc',0) if $op eq 'lc'; return PV::Harness::CaseMap($v,'uc',0) if $op eq 'uc'; return PV::Harness::CaseMap($v,'lc',1) if $op eq 'lcf'; return PV::Harness::CaseMap($v,'uc',1) if $op eq 'ucf'; return PV::Harness::CaseMap($v,'fc',0) if $op eq 'fc';
  if ($op eq "ord") { my @c=PV::Harness::Chars($v); return PV::Harness::Num($c[0]//0,0) }
  if ($op eq "chr" || $op eq "spc") { my @c=PV::Harness::Chars($v); my $c=$c[0]//0; return PV::Harness::FromCps([$c],0,0) }
  if ($op eq 'sub1') { my @c=PV::Harness::Chars($v); return PV::Harness::FromCps([@c[0..0]],$v->{u},$t) if @c; return { b=>"", u=>$v->{u}, t=>$t } }
  if ($op eq 'idx') { my @c=PV::Harness::Chars($v); for my $i (0..$#c) { return PV::Harness::Num($i,$t) if $c[$i]==0xB5 } return PV::Harness::Num(-1,$t) }
  if ($op eq 'sps' || $op eq 'copy') { return { %$v } }
  if ($op eq 'rep') { return { b=>$v->{b} x 2, u=>$v->{u}, t=>$t } }
  if ($op eq 'joinb') { my @c=(PV::Harness::Chars($v),0x2C,0xB5); return PV::Harness::FromCps(\@c,$v->{u},$t) }
  if ($op eq 'joinu') { my @c=(PV::Harness::Chars($v),0x2C,0x100); return PV::Harness::FromCps(\@c,1,$t) }
  if ($op eq 'split') { return PV::Harness::Num(join("|",PV::Harness::Chars($v)),$t) }
  if ($op eq 'tr') { my @c = map { $_==0xB5 ? 0x58 : $_ } PV::Harness::Chars($v); return PV::Harness::FromCps(\@c,$v->{u},$t) }
  if ($op eq 'trcnt') { my $n = grep { $_==0xB5 } PV::Harness::Chars($v); return PV::Harness::Num($n,$t) }
  if ($op eq "unpU") { return PV::Harness::Num(join(",",PV::Harness::Chars($v)),$t) }                                                        # "U*" reads characters of the string as it is
  if ($op eq 'unpC') { my @c = map { $_ > 255 ? do { PV::Harness::Warn("Character in 'C' format wrapped in unpack"); $_ & 0xFF } : $_ } PV::Harness::Chars($v); return PV::Harness::Num(join(",",@c),$t) }
  if ($op eq 'unpU0C') { my $u = sv_utf8_upgrade_flags_grow($v); return PV::Harness::Num(join(",", map { ord } split //, $u->{b}),$t) }             # U0: the UTF-8 encoded bytes
  if ($op eq "unpC0U") { my $raw = $v->{u} ? $v : {b=>$v->{b},u=>1,t=>$t}; my @c = PV::Harness::Chars($raw); @c = map { $_==0 && $MAL ? 0xFFFD : $_ } @c; return PV::Harness::Num(join(",",@c),$t) }   # C0 then U: the bytes are decoded as UTF-8, malformed bytes read as U+FFFD
  if ($op eq 'packU') { my @c=PV::Harness::Chars($v); return PV::Harness::FromCps([$c[0]//0],1,$t) }
  if ($op eq 'packa' || $op eq 'packA') { return { %$v } }
  if ($op =~ /^re(w|s|d)(a|u|l)?$/) { my ($cls,$mod)=($1,$2); my @c=PV::Harness::Chars($v); my $uni = ($mod//'') eq 'u' || (($mod//'') eq 'l') || (!$mod && PV::Harness::UnicodeRules($v)); $uni = 0 if ($mod//'') eq 'a';
    my $m=0; for my $c (@c) { if ($cls eq 'w') { $m=1 if ($c<0x80 && chr($c) =~ /\w/a) || ($uni && $c>=0x80 && chr($c) =~ /\w/u) } elsif ($cls eq 's') { $m=1 if ($c<0x80 && chr($c) =~ /\s/a) || ($uni && chr($c) =~ /\s/u) } else { $m=1 if $c>=0x30 && $c<=0x39 } } return PV::Harness::Num($m,0) }
  if ($op =~ /^rei(u|a)?$/) { my @c=PV::Harness::Chars($v); my $m = (grep { $_==0xB5 || $_==0x39C || $_==0x3BC } @c) ? 1 : 0; return PV::Harness::Num($m,0) }   # the pattern contains U+039C, so it is compiled under Unicode rules regardless of the string
  if ($op eq 'cap') { return { b=>$v->{b}, u=>$v->{u}, t=>0 } }                                                # captures are untainted; the flag is inherited from the target
  if ($op eq 'hkey') { my ($d,$ok)=sv_utf8_downgrade_flags($v,1); return { b=>$v->{b}, u=>$v->{u}, t=>0 } unless $ok; return $d->{u} ? {b=>$v->{b},u=>1,t=>0} : ($v->{u} ? {b=>$v->{b},u=>1,t=>0} : {b=>$d->{b},u=>0,t=>0}) }   # HVhek_WASUTF8 keys are returned upgraded; keys are never tainted
  if ($op eq 'hkey2') { my ($d,$ok)=sv_utf8_downgrade_flags($v,1); if ($v->{u}) { return PV::Harness::Num($ok ? 2 : 2, 0) } else { return PV::Harness::Num(1,0) } }
  if ($op eq 'catb' || $op eq 'apb') { my @c=(PV::Harness::Chars($v),0xB5); return PV::Harness::FromCps(\@c,$v->{u},$t) }
  if ($op eq 'catu' || $op eq 'apu') { my @c=(PV::Harness::Chars($v),0x100); return PV::Harness::FromCps(\@c,1,$t) }
  if ($op eq 'catl' || $op eq 'apl') { my @c=(PV::Harness::Chars($v),0xB5); return PV::Harness::FromCps(\@c,1,$t) }
  if ($op eq 'eqb' || $op eq 'eql') { my @c=PV::Harness::Chars($v); return PV::Harness::Num(("@c" eq "181 233") ? 1 : 0, 0) }
  if ($op eq 'cmpb') { my @c=PV::Harness::Chars($v); my $s = join("",map{chr}@c); my $r = ($s cmp "\xB5\xE9"); return PV::Harness::Num($r,$t) }
  if ($op eq 'spd') { return PV::Harness::Num(sv_len_utf8($v),0) }
  if ($op eq 'arith') { return PV::Harness::Num(sv_len_utf8($v),$t) }
  die "op $op" }
1;
package PV;
# ops whose decoders are strict croak on a malformed flagged string: pp_lc/pp_uc/pp_lcfirst/pp_ucfirst/pp_fc (utf8n_to_uvchr_msgs with fatal flags), do_trans, pp_unpack 'C'/'C0U'
my %STRICT = map { $_=>1 } qw(lc uc lcf ucf fc tr trcnt unpC unpC0U unpU);
{ no warnings 'redefine'; my $op_orig = \&PV::Harness::Op;
  *PV::Harness::Op = sub { my ($op,$v)=@_;
    if ($STRICT{$op} && ref $v && $v->{u}) { my @c = PV::Harness::Chars($v); die "Malformed UTF-8 character (fatal)\n" if $MAL }
    if ($op eq 'unpC') { my @c = PV::Harness::Chars($v); return PV::Harness::Num(join(",",@c),$v->{t}) }                                 # C in C0 mode: full code points, no wrap
    if ($op eq 'unpC0U') { my @c = PV::Harness::Chars($v); my @o;
      if (!$v->{u}) { my $raw = {b=>$v->{b},u=>1,t=>0}; local $MAL=0; local @MALB=(); @o = PV::Harness::Chars($raw); @o = map { $_==0 && $MAL ? 0xFFFD : $_ } @o }   # byte string: decoded as UTF-8, malformed -> U+FFFD
      else { die "Malformed UTF-8 character (fatal)\n" if grep { $_ >= 0x80 && $_ <= 0xFF } @c; @o = map { $_ > 0xFF ? 0 : $_ } @c }   # flagged: characters re-read as octets; a wide character reads as 0
      return PV::Harness::Num(join(",",@o),$v->{t}) }
    if ($op =~ /^re(w|s|d)l$/) { my $cls=$1; my @c=PV::Harness::Chars($v); my $uni = $v->{u}; my $m=0;                      # /l under a UTF-8 locale: Unicode rules only for a flagged string
      for my $c (@c) { if ($cls eq 'w') { $m=1 if ($c<0x80 && chr($c) =~ /\w/a) || ($uni && $c>=0x80 && chr($c) =~ /\w/u) } elsif ($cls eq 's') { $m=1 if ($c<0x80 && chr($c) =~ /\s/a) || ($uni && chr($c) =~ /\s/u) } else { $m=1 if $c>=0x30 && $c<=0x39 } } return PV::Harness::Num($m,0) }
    if ($op eq 'split') { my @c=PV::Harness::Chars($v); return PV::Harness::Num(join("|",@c), @c ? $v->{t} : 0) }
    return $op_orig->($op,$v) } }
1;
