use strict; use warnings; use threads; use threads::shared; use Time::HiRes qw(sleep);
my %h :shared = (k => 1); our $s :shared = "S"; my @a :shared = (1,2,3);
my $t = async { { local $h{k} = 2; local $a[0] = 9; sleep 0.4; } "child done" };
sleep 0.15; print "main sees during child's local: h{k}=$h{k} a[0]=$a[0]\n"; $t->join; print "after join: h{k}=$h{k} a[0]=$a[0]\n";
my $t2 = async { my $r = eval { local $s = "L"; sleep 0.4; "ok" }; $r // "died: $@" };
sleep 0.15; print "main sees during child's 'local \$s': $s\n"; my $res = $t2->join; print "child: $res; after: $s\n";
{ local $h{k} = 7; delete $h{k}; } print "single-thread: local then delete, after unwind: ", (exists $h{k} ? "k=$h{k}" : "gone"), "\n";
{ local $h{new} = 3; } print "absent key localized: ", (exists $h{new} ? "leaked" : "deleted at unwind"), "\n";
{ local $h{k} = 5; $h{k} = 7; } print "assigned during local, after: k=$h{k}\n";
# what does a non-shared local on a hash elem do if the key is deleted and re-created meanwhile?
my %p = (k => 1); { local $p{k} = 2; delete $p{k}; $p{k} = "replaced"; } print "plain hash: local, delete, recreate, unwind: k=$p{k}\n";
# threads->create clones lexicals: child increments its own copy
my $lex = 1; my $t3 = threads->create(sub { $lex++; $lex }); my $child = $t3->join; print "ithreads clone: parent lex=$lex child saw=$child\n";
our $pkg = "p"; my $t4 = threads->create(sub { $pkg = "child"; 1 }); $t4->join; print "package var after child assignment: $pkg\n";
