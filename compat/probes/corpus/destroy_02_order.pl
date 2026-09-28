use strict; use warnings;
package Obj; our @log; sub new { bless { n => $_[1] }, $_[0] } sub DESTROY { push @log, $_[0]{n} }
package main;
sub mk { Obj->new(@_) }
{ my $a = mk('a'); my $b = mk('b'); my $c = mk('c'); }           print "block, last stmt is my \$c=...: @Obj::log\n"; @Obj::log = ();
{ my $a = mk('a'); my $b = mk('b'); my $c = mk('c'); 1; }        print "block ending in 1;:            @Obj::log\n"; @Obj::log = ();
if (1) { my $a = mk('a'); my $b = mk('b'); my $c = mk('c'); }    print "if-block, last stmt my \$c:     @Obj::log\n"; @Obj::log = ();
sub g { my $a = mk('a'); my $b = mk('b'); my $c = mk('c'); return } g(); print "sub with bare return:           @Obj::log\n"; @Obj::log = ();
{ my %h = map { ($_ => mk("$_")) } 'a'..'h'; print "keys order: @{[keys %h]}\n"; } print "hash destruction order:         @Obj::log\n"; @Obj::log = ();
