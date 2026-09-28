package HV;
# Executable transcription of perl 5.44.0's hash engine on a 64-bit build configured with
# PERL_HASH_FUNC_SIPHASH13 + SBOX32 (SBOX32_MAX_LEN 24), PERL_HASH_RANDOMIZE_KEYS, PERL_HASH_DEFAULT_HvMAX 7.
# Every routine names the C function or macro it mirrors.
use strict; use warnings; no warnings 'portable';
my $M64 = 0xFFFFFFFFFFFFFFFF; my $M32 = 0xFFFFFFFF;
sub add64 { my ($a,$b)=@_; my $r; { use integer; $r = $a + $b } $r & $M64 }
sub rotl64 { my ($x,$r)=@_; (($x << $r) | ($x >> (64-$r))) & $M64 }
sub rotl32 { my ($x,$r)=@_; ((($x << $r) & $M32) | ($x >> (32-$r))) & $M32 }
sub rotr32 { my ($x,$r)=@_; rotl32($x, 32-$r) }
sub u8to64 { my ($s,$o)=@_; unpack("Q<", substr($s,$o,8)) }
# ---- perl_siphash.h: SIPHASH_SEED_STATE, S_perl_hash_siphash_1_3_with_state ----
sub perl_siphash_seed_state { my $seed=shift; my ($v0,$v1) = (u8to64($seed,0), u8to64($seed,8));
  return [ $v0 ^ 0x736f6d6570736575, $v1 ^ 0x646f72616e646f6d, $v0 ^ 0x6c7967656e657261, $v1 ^ 0x7465646279746573 ] }
sub SIPROUND { my $v=shift; my ($v0,$v1,$v2,$v3)=@$v;
  $v0=add64($v0,$v1); $v1=rotl64($v1,13); $v1^=$v0; $v0=rotl64($v0,32);
  $v2=add64($v2,$v3); $v3=rotl64($v3,16); $v3^=$v2;
  $v0=add64($v0,$v3); $v3=rotl64($v3,21); $v3^=$v0;
  $v2=add64($v2,$v1); $v1=rotl64($v1,17); $v1^=$v2; $v2=rotl64($v2,32);
  @$v=($v0,$v1,$v2,$v3) }
sub perl_hash_siphash_1_3_with_state { my ($state,$in)=@_; my $len=length $in; my @v=@$state; my $b = ($len << 56) & $M64;
  my $end = $len - ($len % 8);
  for (my $i=0; $i<$end; $i+=8) { my $m = u8to64($in,$i); $v[3]^=$m; SIPROUND(\@v); $v[0]^=$m }
  for my $k (0 .. ($len % 8) - 1) { $b |= ord(substr($in,$end+$k,1)) << (8*$k) }
  $v[3]^=$b; SIPROUND(\@v); $v[0]^=$b; $v[2]^=0xff; SIPROUND(\@v) for 1..3;
  my $h = $v[0]^$v[1]^$v[2]^$v[3]; return (($h & $M32) ^ ($h >> 32)) & $M32 }   # h32[0] ^ h32[1]
# ---- sbox32_hash.h: sbox32_seed_state128, sbox32_hash_with_state ----
sub SBOX32_MIX4 { my $s=shift; my ($v0,$v1,$v2,$v3)=@$s;
  $v0 = (rotl32($v0,13) - $v3) & $M32; $v1 ^= $v2; $v3 = (rotl32($v3,9) + $v1) & $M32; $v2 ^= $v0;
  $v0 = rotl32($v0,14) ^ $v3; $v1 = (rotl32($v1,25) - $v2) & $M32; $v3 ^= $v1; $v2 = (rotl32($v2,4) - $v0) & $M32;
  @$s=($v0,$v1,$v2,$v3) }
sub XORSHIFT128_set { my $s=shift; my ($x,$y,$z,$w)=@$s; my $t = ($x ^ (($x << 5) & $M32)) & $M32;
  $x=$y; $y=$z; $z=$w; $w = (($w ^ ($w >> 29)) ^ ($t ^ ($t >> 12))) & $M32; @$s=($x,$y,$z,$w); $w }
sub sbox32_seed_state128 { my $seed=shift; my @sd = unpack("V4", $seed);
  my @s = ($sd[1]^0x786f6273, $sd[0]^0x68736168, $sd[2]^0x646f6f67, $sd[3]^0x74736166);
  $s[0] ||= 1; $s[1] ||= 2; $s[2] ||= 4; $s[3] ||= 8; SBOX32_MIX4(\@s) for 1..128;
  $s[0] ^= (~$sd[3]) & $M32; $s[1] ^= (~$sd[2]) & $M32; $s[2] ^= (~$sd[1]) & $M32; $s[3] ^= (~$sd[0]) & $M32;
  $s[0] ||= 8; $s[1] ||= 4; $s[2] ||= 2; $s[3] ||= 1; SBOX32_MIX4(\@s) for 1..128;
  my @table = map { XORSHIFT128_set(\@s) } 1 .. 256*24; my $s0 = XORSHIFT128_set(\@s);
  return { s0=>$s0, t=>\@table } }
sub sbox32_hash_with_state { my ($st,$key)=@_; my $h = $st->{s0}; my $t=$st->{t};
  for my $i (0 .. length($key)-1) { $h ^= $t->[ 256*$i + ord(substr($key,$i,1)) ] } $h }
# ---- hv_func.h PVT_PERL_HASH_SEED_STATE / PVT_PERL_HASH_WITH_STATE; util.c Perl_get_hash_seed ----
sub HV::Harness::NewProcess { my ($seedhex,$perturb)=@_; my $seed = "\0" x 32;
  if (defined $seedhex && $seedhex ne '') { my $h = $seedhex; $h =~ s/^0x//i; my $n=0; for my $i (0..31) { last unless length $h; my $byte = substr($h,0,2,''); $byte .= '0' if length($byte)==1; substr($seed,$i,1,chr(hex $byte)) } }
  my $mode = defined $perturb ? $perturb : ($seedhex eq '0' ? 0 : 1);           # PERL_HASH_SEED=0 implies PERL_PERTURB_KEYS=0 unless overridden
  my $bits = 0xbe49d17f;                                                            # "I just picked a number"
  for my $i (0..7) { $bits ^= ord(substr($seed, $i % 32, 1)); $bits = rotl64($bits, 8) }   # mix in the leading seed bytes
  $bits = 0x0000ffff if !$bits;
  return bless { seed=>$seed, sip=>perl_siphash_seed_state(substr($seed,0,16)), sbox=>sbox32_seed_state128(substr($seed,16,16)), mode=>$mode, rand_bits=>$bits }, 'HV::Process' }
sub HV::Process::PERL_HASH_WITH_STATE { my ($p,$key)=@_; length($key) <= 24 ? sbox32_hash_with_state($p->{sbox},$key) : perl_hash_siphash_1_3_with_state($p->{sip},$key) }   # SBOX32_MAX_LEN
sub HV::Process::UPDATE_HASH_RAND_BITS { my $p=shift; return unless $p->{mode}; my $x=$p->{rand_bits};                          # PERL_XORSHIFT64_A
  $x ^= ($x << 13) & $M64; $x ^= $x >> 7; $x ^= ($x << 17) & $M64; $p->{rand_bits} = $x & $M64 }
# ---- an HV: HvARRAY / HvMAX / xhv_keys / HvAUX (riter, eiter, rand, last_rand) ----
sub HV::Harness::NewHV { my $p=shift; bless { p=>$p, max=>7, a=>[ map { [] } 1..8 ], keys=>0, aux=>undef, lazydel=>undef, order=>[] }, 'HV' }
sub hv_auxinit { my $hv=shift; return $hv->{aux} if $hv->{aux};                                # S_hv_auxinit
  $hv->{aux} = { riter=>-1, eiter=>undef, rand=>$hv->{p}{rand_bits} & $M32 }; $hv->{aux}{last_rand} = $hv->{aux}{rand}; $hv->{aux} }
sub hv_common_key_normalize { my $k=shift; if (utf8::is_utf8($k)) { my $c=$k; if (utf8::downgrade($c,1)) { return ($c,'WASUTF8') } return ($k,'UTF8') } return ($k,'') }   # hv_common: bytes_from_utf8, HVhek_WASUTF8
sub hv_common { my ($hv,$key,$val)=@_; my $p=$hv->{p}; my ($k,$kf)=hv_common_key_normalize($key); my $h = $p->PERL_HASH_WITH_STATE($k);
  my $chain = $hv->{a}[$h & $hv->{max}];
  for my $e (@$chain) { if ($e->{k} eq $k && $e->{kf} eq $kf) { $e->{v}=$val; return } }
  my $e = {k=>$k, kf=>$kf, h=>$h, v=>$val}; my $collision = @$chain > 0;
  if ($collision && $p->{mode}) { $p->UPDATE_HASH_RAND_BITS; if ($p->{rand_bits} & 1) { splice(@$chain,1,0,$e) } else { unshift @$chain,$e } }   # UPDATE_HASH_RAND_BITS_KEY, insert after or before the head
  else { unshift @$chain, $e }                                                                                                              # HeNEXT(entry) = *oentry; *oentry = entry
  if ($hv->{aux}) { $hv->{aux}{rand} = $p->{rand_bits} & $M32 if $p->{mode} }
  $hv->{keys}++;
  if ($collision && ($hv->{keys} + ($hv->{keys} >> 1)) > $hv->{max}) { hsplit($hv, $hv->{max}+1, 2*($hv->{max}+1)) }                    # in_collision && DO_HSPLIT
}
sub hsplit { my ($hv,$oldsize,$newsize)=@_; my $p=$hv->{p}; my $a=$hv->{a}; push @$a, map { [] } 1..($newsize-$oldsize); $hv->{max}=$newsize-1;
  $p->UPDATE_HASH_RAND_BITS if $p->{mode};                                                                                                  # MAYBE_UPDATE_HASH_RAND_BITS
  my $mask = $newsize-1;
  for my $i (0..$oldsize-1) { my @stay; for my $e (@{$a->[$i]}) { my $j = $e->{h} & $mask;
      if ($j != $i) { if (@{$a->[$j]} && $p->{mode}) { $p->UPDATE_HASH_RAND_BITS; if ($p->{rand_bits} & 1) { splice(@{$a->[$j]},1,0,$e) } else { unshift @{$a->[$j]},$e } } else { unshift @{$a->[$j]}, $e } }
      else { push @stay, $e } } $a->[$i] = \@stay }
  if ($hv->{aux}) { $hv->{aux}{rand} = $p->{rand_bits} & $M32 if $p->{mode} } }
sub PERL_HASH_ITER_BUCKET { my ($hv,$aux)=@_; ($aux->{riter} ^ $aux->{rand}) & $hv->{max} }                                                     # PERL_HASH_ITER_BUCKET
sub hv_iternext_flags { my ($hv,$warn)=@_; my $aux = hv_auxinit($hv); my $old = $aux->{eiter};                                                       # Perl_hv_iternext_flags
  if ($aux->{last_rand} != $aux->{rand}) { if ($aux->{riter} != -1) { $$warn = 1 if $warn } $aux->{last_rand} = $aux->{rand} }     # "Use of each() on hash after insertion without resetting hash iterator results in undefined behavior"
  my $entry;
  if ($old) { my $chain = $hv->{a}[$old->{h} & $hv->{max}]; my $found=0; for my $i (0..$#$chain) { if ($chain->[$i] == $old) { $entry = $chain->[$i+1]; $found=1; last } } $entry = $old->{next_after_delete} unless $found }   # HeNEXT(oldentry)
  while (!$entry) { $aux->{riter}++;
    if ($aux->{riter} > $hv->{max}) { $aux->{riter} = -1; $aux->{last_rand} = $aux->{rand}; last }
    $entry = $hv->{a}[ PERL_HASH_ITER_BUCKET($hv,$aux) ][0] }
  if ($old && $hv->{lazydel} && $hv->{lazydel} == $old) { $hv->{lazydel} = undef; push @{$hv->{order}}, "free:$old->{k}" }             # HvLAZYDEL: free the deferred entry now
  $aux->{eiter} = $entry; return $entry }
sub HV::Harness::Keys { my $hv=shift; my $aux=hv_auxinit($hv); $aux->{riter}=-1; $aux->{eiter}=undef; my @k; while (my $e = hv_iternext_flags($hv)) { push @k, $e->{k} } @k }   # keys/values reset the iterator
sub hv_delete_common { my ($hv,$key)=@_; my ($k,$kf)=hv_common_key_normalize($key); my $h=$hv->{p}->PERL_HASH_WITH_STATE($k); my $chain=$hv->{a}[$h & $hv->{max}];
  for my $i (0..$#$chain) { my $e=$chain->[$i]; next unless $e->{k} eq $k && $e->{kf} eq $kf;
    $e->{next_after_delete} = $chain->[$i+1]; splice(@$chain,$i,1); $hv->{keys}--;
    if ($hv->{aux} && $hv->{aux}{eiter} && $hv->{aux}{eiter} == $e) { $hv->{lazydel} = $e; return $e }                                # HvLAZYDEL_on: the current entry survives until the next iternext
    push @{$hv->{order}}, "free:$k"; return $e } return undef }
sub hfree_next_entry_all { my $hv=shift; my @gone; for my $i (0..$hv->{max}) { for my $e (@{$hv->{a}[$i]}) { push @gone, $e->{k} } $hv->{a}[$i]=[] } $hv->{keys}=0; $hv->{lazydel}=undef; if ($hv->{aux}) { $hv->{aux}{riter}=-1; $hv->{aux}{eiter}=undef } @gone }   # Perl_hfree_next_entry: raw bucket order, chain order
sub hv_clear { my $hv=shift; hfree_next_entry_all($hv) }                                                                                                # Perl_hv_clear: entries freed, bucket array kept
sub hv_undef_flags { my $hv=shift; my @g = hfree_next_entry_all($hv); $hv->{a} = [ map { [] } 1..8 ]; $hv->{max}=7; $hv->{aux}=undef; @g }                  # Perl_hv_undef_flags: array released, next fill starts at HvMAX 7
sub HV::Harness::BucketArray { my $hv=shift; my @out; my $empty=0; for my $i (0..$hv->{max}) { my $c=$hv->{a}[$i]; if (@$c) { push @out, $empty if $empty; $empty=0; push @out, [ map { $_->{k} } @$c ] } else { $empty++ } } push @out, $empty if $empty; \@out }   # Hash::Util::bucket_array encoding
1;
