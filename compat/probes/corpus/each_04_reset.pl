# Which operations reset the iterator.
use strict; use warnings; no warnings 'void';
sub fresh { my %h = map { $_ => 1 } 'a'..'j'; my ($first) = each %h; (\%h, $first) }
sub test { my ($name, $op) = @_; my ($h, $first) = fresh(); $op->($h);
    my ($next) = each %$h; printf "%-28s %s\n", $name, ($next eq $first ? "RESETS" : "no reset") }
test('keys (void)',            sub { keys %{$_[0]} });
test('keys (scalar)',          sub { my $n = keys %{$_[0]} });
test('keys (list)',            sub { my @k = keys %{$_[0]} });
test('values (scalar)',        sub { my $n = values %{$_[0]} });
test('scalar(%h)',             sub { my $n = scalar %{$_[0]} });
test('if (%h)',                sub { if (%{$_[0]}) {} });
test('exists',                 sub { my $e = exists $_[0]{a} });
test('fetch $h{a}',            sub { my $v = $_[0]{a} });
test('store existing key',     sub { $_[0]{a} = 2 });
test('each in list ctx copy',  sub { my %copy = %{$_[0]} });
test('delete (other key)',     sub { my ($k) = grep { 1 } 'zz'; delete $_[0]{$k} });
# each on an exhausted iterator restarts from the beginning
my %h = (x => 1, y => 2); 1 while each %h; my ($r) = each %h;
print "after exhaustion, next each returns a key again: ", (defined $r ? "yes" : "no"), "\n";
