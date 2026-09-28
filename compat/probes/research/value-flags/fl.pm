package fl; use strict; use warnings; use B;
my @F = (IOK=>B::SVf_IOK, NOK=>B::SVf_NOK, POK=>B::SVf_POK, pIOK=>B::SVp_IOK, pNOK=>B::SVp_NOK, pPOK=>B::SVp_POK, IsUV=>B::SVf_IVisUV, ROK=>B::SVf_ROK);
sub fl { my $f = B::svref_2object($_[0])->FLAGS; my @o; for (my $i=0;$i<@F;$i+=2){ push @o,$F[$i] if $f & $F[$i+1] } join(",",@o) || "-" }
sub show { my ($l,$r)=@_; printf "%-36s %s\n",$l,fl($r) }
1;
