use strict; use warnings; use lib '/tmp/probe'; use fl; *fl=\&fl::fl;
{ my $s; local $SIG{__WARN__} = sub { $s = "77" }; $s = "3abc"; my $n = $s + 0; print "mutating handler: n=$n s=$s s+0=", $s+0, " s*1.0=", $s*1.0, " flags=", fl(\$s), "\n"; }
{ my $s; local $SIG{__WARN__} = sub { $s = "77" }; $s = "abc"; my $n = $s * 1.5; print "mutating handler via nv: n=$n s=$s s+0=", $s+0, " flags=", fl(\$s), "\n"; }
{ my $s; local $SIG{__WARN__} = sub { die "in handler\n" }; $s = "3abc"; my $n = eval { $s + 0 }; print "dying handler: err=", ($@ =~ s/\n//r), " flags=", fl(\$s), " s+0 now=", eval { $s+0 } // "died again", "\n"; }
{ my $s; local $SIG{__WARN__} = sub { $s = 99 }; $s = "abc"; my $n = $s + 0; print "handler assigns number: n=$n s=$s flags=", fl(\$s), "\n"; }
