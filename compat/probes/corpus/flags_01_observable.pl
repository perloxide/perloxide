use strict; use warnings; use JSON::PP ();
my $s = "10"; my $js = JSON::PP->new->canonical;
print "before numify: ", $js->encode([$s]), "\n";
{ my $n = $s + 0; }
print "after numify:  ", $js->encode([$s]), "\n";
my $i = 10; { my $str = "$i"; }
print "int stringified: ", $js->encode([$i]), "\n";
if ($] >= 5.036) { no warnings; print "created_as_number(\$s)=", (builtin::created_as_number($s) ? 1 : 0), " created_as_string(\$i)=", (builtin::created_as_string($i) ? 1 : 0), "\n"; }
my $d = sprintf "%s", 3.0; print "Data::Dumper-ish of 1e21: ", 1e21, "  of 0.1+0.2: ", 0.1+0.2, "\n";
