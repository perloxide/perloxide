package VF::Observe;
# The one observation module for the value-flags lanes.  The KEY is the SV head and body, field by field, audited against
# sv.h (5.44.0, struct STRUCT_SV / SV_HEAD_UNION_ / XPV_HEAD_ / xivu_ / xnvu_ / the buffer):
#   sv_flags   -> the value flags (IOK NOK POK pIOK pNOK pPOK IsUV ROK UTF8 IsCOW) and SvTYPE (T:), the low byte;
#   xivu/xnvu  -> the exact integer or NV slot (N:), read through B without conversion;
#   sv_u.svu_pv, xpv_cur, xpv_len -> the bytes (P:) with LEN (L:) on a POK holder, or the stale buffer's CUR/LEN (B:cur/len)
#                 on a non-POK holder (Perl_sv_grow's minimum reads SvCUR at the moment of the grow);
#   OOK        -> the offset stored before PVX (O:), set by sv_chop; LEN is what Devel::Peek reports after the chop;
#   CowREFCNT  -> the byte at PVX + LEN - 1 (C:), read from Devel::Peek's COW_REFCNT; SV_COW_REFCNT_MAX saturation is a
#                 documented rule, not enumerated.
# Excluded, each with its reason (see the harness README, "Key exclusions"): sv_refcnt (enters only through the swipe arm,
# which reads the SOURCE of a copy; a named holder is never TEMP); SVs_TEMP/PADTMP/PADSTALE, SVs_OBJECT, GMG/SMG/RMG,
# AMAGIC, FAKE, BREAK, magic, stash -- never on a fresh package holder in these lanes, ASSERTED below (the observer dies if
# Dump ever shows one); LV fields (LVs are TARGs, never the holder); buffer bytes past CUR (writers NUL-terminate at CUR,
# readers clamp); sv_u pointer identity (single-holder lanes; a multi-holder lane must key buffer identity because of
# sv_setsv_flags's SvPVX(dsv) == SvPVX(ssv) early return).
# Projections: flags (key only) and full (key + Devel::Peek body/flags/CUR/LEN/COW_REFCNT per step); consumers run once,
# destructively, at the block's end on the original.  The key is identical under both projections.
use strict; use warnings; no warnings qw(experimental::builtin); use B; require Devel::Peek;
our $PROJ = $ENV{PROJ} || 'flags';
sub child_head { my $proj = shift || $PROJ; my $root = $ENV{VF_ROOT} || '.'; return <<"H" }
use strict; no warnings; use lib '$root'; use VF::Observe; binmode STDOUT, ":utf8"; \$VF::Observe::PROJ = '$proj';
our \@WARN; \$SIG{__WARN__} = sub { my \$m=\$_[0]; \$m =~ s/ at .*//s; \$m =~ s/\\n//; push \@WARN, \$m };
H
my @F=(IOK=>B::SVf_IOK(),NOK=>B::SVf_NOK(),POK=>B::SVf_POK(),pIOK=>B::SVp_IOK(),pNOK=>B::SVp_NOK(),pPOK=>B::SVp_POK(),IsUV=>B::SVf_IVisUV(),ROK=>B::SVf_ROK(),UTF8=>B::SVf_UTF8(),IsCOW=>B::SVf_IsCOW());
my %TYPE = (0=>'NULL',1=>'IV',2=>'NV',3=>'PV',4=>'INVLIST',5=>'PVIV',6=>'PVNV',7=>'PVMG',8=>'REGEXP',9=>'PVGV',10=>'PVLV',11=>'PVAV',12=>'PVHV',13=>'PVCV',14=>'PVFM',15=>'PVIO',16=>'PVOBJ');
my @FORBIDDEN = qw(TEMP PADTMP PADSTALE OBJECT GMG SMG RMG AMAGIC FAKE BREAK);
sub flags { my $f=B::svref_2object($_[0])->FLAGS; join(",", map { $f & $F[$_*2+1] ? $F[$_*2] : () } 0..$#F/2) || "-" }
sub slots { my $r=shift; my $o=B::svref_2object($r); my $f=$o->FLAGS;   # side-effect free: read slots through B, never convert
  ($f & B::SVf_POK()) ? "P:".$o->PV."|L:".$o->LEN : ($f & B::SVf_IOK()) ? "N:" . ($f & B::SVf_IVisUV() ? $o->UVX : $o->IV) : ($f & (B::SVf_NOK()|B::SVp_NOK())) ? sprintf("N:%.17g",$o->NV) : ($f & B::SVp_IOK()) ? "N:" . ($f & B::SVf_IVisUV() ? $o->UVX : $o->IV) : "-" }
sub peek { my $r=shift; my $buf=''; open my $save,'>&',\*STDERR; close STDERR; open STDERR,'>',\$buf; Devel::Peek::Dump($$r); close STDERR; open STDERR,'>&',$save;
  my ($type)=$buf=~/^SV = (\w+)/; my ($fl)=$buf=~/FLAGS = \(([^)]*)\)/; my ($cur)=$buf=~/CUR = (\d+)/; my ($len)=$buf=~/LEN = (\d+)/; my ($cow)=$buf=~/COW_REFCNT = (\d+)/; my ($off)=$buf=~/OFFSET = (\d+)/;
  for my $bad (@FORBIDDEN) { die "VF::Observe: forbidden flag $bad on the holder (lane design violated): $buf" if defined $fl && $fl =~ /\b$bad\b/ }
  die "VF::Observe: magic on the holder (lane design violated): $buf" if $buf =~ /^\s*MAGIC = /m;
  return { type=>$type//'?', flags=>$fl//'', cur=>$cur, len=>$len, cow=>$cow, off=>$off, text=>join("|", $type//'?', $fl//'', $cur//'-', $len//'-', $cow//'-') } }
sub key { my $r=shift; my $o = B::svref_2object($r); my $f = $o->FLAGS; my $p = peek($r);
  my $b = (!($f & B::SVf_POK()) && $p->{len}) ? "|B:" . ($p->{cur}//0) . "/" . $p->{len} : "";
  my $t = "|T:" . ($TYPE{$f & 0xff} // ($f & 0xff)); my $c = defined $p->{cow} ? "|C:$p->{cow}" : ""; my $oo = defined $p->{off} ? "|O:$p->{off}" : "";
  flags($r)."|".slots($r).$b.$t.$c.$oo }
sub consumers { my $r = shift; my @o; local @main::WARN=(); my $c = $$r;
  push @o, "$$r"; push @o, sprintf("%.17g", 0.0+$$r); push @o, sprintf("%.17g", $$r); push @o, (Scalar::Util::isdual($$r)?1:0); push @o, (builtin::created_as_number($$r)?"N":"-").(builtin::created_as_string($$r)?"S":"-");
  push @o, Data::Dumper::Dumper($$r); { local $Data::Dumper::Useperl=1; push @o, Data::Dumper::Dumper($$r) } push @o, JSON::PP::encode_json([$$r]); push @o, unpack("H*", substr(Storable::freeze([$$r]),12)); push @o, (eval { unpack("H*", pack("j",$$r)) } // "croak"); push @o, ($$r ? 1 : 0);
  return join("\x1e", @o) . "|W:" . join("/",@main::WARN) }
sub record { my ($id,$op,$r,$cr,$k) = @_; $k //= key($r); return "$id\t$op\t$k\n" if $PROJ eq 'flags'; my $px = peek($r)->{text}; return "$id\t$op\t$k\t$px\t-\t-\n" }
sub import { if ($PROJ eq 'full' || ($ENV{PROJ}//'') eq 'full') { require Scalar::Util; require Data::Dumper; require JSON::PP; require Storable; require builtin; $Data::Dumper::Indent=0; $Data::Dumper::Terse=1 } }
1;
