use strict; use warnings; use Scalar::Util qw(weaken);
package Obj; my @log;
sub new { my ($c, $n) = @_; bless { n => $n }, $c }
sub DESTROY { my $s = shift; push @log, "D:$s->{n}" . (defined $s->{peer} ? '(peer-defined)' : '');
  if (my $w = $main::weak) { push @log, "weak-in-DESTROY defined=" . (defined $$w ? 1 : 0) } }
package main;
our $weak;
{ my $o = Obj->new('w'); my $wr = $o; weaken($wr); $weak = \$wr; undef $o; push @log, "after undef: weak defined=" . (defined $wr ? 1 : 0); $weak = undef }
print join("\n", @log), "\n"; @log = ();
# scope exit order of lexicals, die unwinding, temporaries
sub mk { Obj->new($_[0]) }
{ my $a = mk('a'); my $b = mk('b'); my $c = mk('c'); }
push @log, '|block|';
mk('temp1'); push @log, '|after temp statement|';
print "len=", length(ref(mk('temp2'))), "\n"; push @log, '|after temp2 statement|';
sub f { my $x = mk('in-f'); return mk('ret') } my $r = f(); push @log, '|after f|'; undef $r;
eval { my $e1 = mk('e1'); my $e2 = mk('e2'); die "x\n" }; push @log, "|after die: \$\@=" . ($@ =~ s/\n//r) . '|';
{ my @arr = (mk('arr0'), mk('arr1'), mk('arr2')); } push @log, '|array|';
{ my %h = map { ($_ => mk("h$_")) } 1..3; } push @log, '|hash|';
{ my $p = mk('p'); my $q = mk('q'); $p->{peer} = $q; $q->{peer} = $p; weaken($q->{peer}); } push @log, '|weak cycle|';
print join(' ', @log), "\n";
our $global1 = mk('global1'); our $global2 = mk('global2'); my $file_lex = mk('file-lexical');
END { print "END block\n" }
package Obj; sub DESTROY_GLOBAL {}
package main;
$SIG{__WARN__} = sub {};
{ no warnings 'redefine'; *Obj::DESTROY = sub { my $s = shift; print "D:$s->{n} phase=${^GLOBAL_PHASE}\n" }; }
