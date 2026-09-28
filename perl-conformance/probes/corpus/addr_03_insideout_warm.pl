# Inside-out attributes keyed by refaddr on hash-based objects, without cleanup, after the class destructor lookup is cached.
use strict; use warnings; use Scalar::Util qw(refaddr); use Hash::Util::FieldHash ();
package Point; my %x;
sub new { my ($c, $v) = @_; my $self = bless {}, $c; $x{ Scalar::Util::refaddr $self } = $v if defined $v; $self }
sub x { $x{ Scalar::Util::refaddr $_[0] } // 'undef' }
package FPoint; Hash::Util::FieldHash::fieldhash my %fx;
sub new { my ($c, $v) = @_; my $self = bless {}, $c; $fx{$self} = $v if defined $v; $self }
sub x { $fx{ $_[0] } // 'undef' }
package main;
{ my $warm = Point->new; undef $warm; }          # first free populates the DESTROY lookup cache
my $p = Point->new(42); undef $p;
my $q = Point->new;
print "refaddr-keyed attribute on a fresh object after warm-up: ", $q->x, "\n";
{ my $warm = FPoint->new; undef $warm; }
my $fp = FPoint->new(42); undef $fp;
my $fq = FPoint->new;
print "Hash::Util::FieldHash attribute on a fresh object after warm-up: ", $fq->x, "\n";
