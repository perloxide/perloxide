use strict; use warnings; use Scalar::Util qw(refaddr);
# Which list-returning builtins hand back the argument SVs themselves, and which hand back copies, in each syntactic
# form.  The helper reads addresses through @_, which aliases its arguments; a `my (...) = @_` copy would have hidden
# the answer.
sub same { my $src = shift; my %a = map { refaddr(\$_) => 1 } @$src; my $hit = grep { $a{refaddr(\$_)} } @_; $hit == @_ && @_ == @$src ? "alias" : "copy" }
sub byn { $a <=> $b }
my $cmp = sub { $a <=> $b };
my @a = (3, 1, 2);
print "sort block:      ", same(\@a, sort { $a <=> $b } @a), "\n";
print "sort bare:       ", same(\@a, sort @a), "\n";
print "sort subname:    ", same(\@a, sort byn @a), "\n";
print "sort subref:     ", same(\@a, sort $cmp @a), "\n";
print "reverse sort:    ", same(\@a, reverse sort @a), "\n";
print "reverse:         ", same(\@a, reverse @a), "\n";
print "grep block:      ", same(\@a, grep { 1 } @a), "\n";
print "grep expr:       ", same(\@a, grep(1, @a)), "\n";
print "map block:       ", same(\@a, map { $_ } @a), "\n";
print "map block (;):   ", same(\@a, map {; $_ } @a), "\n";
print "map expr:        ", same(\@a, map($_, @a)), "\n";
my @copy = sort @a;
print "list assign:     ", same(\@a, @copy), "\n";
# Writes through the returned list reach the originals where they are aliases.
my @w = (3, 1, 2); $_ *= 10 for sort { $a <=> $b } @w;  print "write via sort:     @w\n";
my @x = (3, 1, 2); $_ *= 10 for grep { $_ > 1 } @x;      print "write via grep:     @x\n";
my @y = (3, 1, 2); $_ *= 10 for map { $_ } @y;           print "write via map:      @y\n";
my @v = (3, 1, 2); $_ *= 10 for map($_, @v);             print "write via map expr: @v\n";
my @z = (3, 1, 2); $_ *= 10 for reverse @z;              print "write via reverse:  @z\n";
