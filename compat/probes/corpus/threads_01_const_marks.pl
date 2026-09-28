# oracle-requires: threads
# Flag marks on literal constants under ithreads: each thread clones the op tree, so marks are per-interpreter.
use strict; use warnings;
use threads; use threads::shared; use Thread::Queue;
use JSON::PP ();
$| = 1;
# Each scenario uses its own sub so its "zz" literal starts unmarked.
sub span1 { my $l = shift; my @r = ($l .. "zz"); scalar @r }
sub span2 { my $l = shift; my @r = ($l .. "zz"); scalar @r }
sub span3 { my $l = shift; my @r = ($l .. "zz"); scalar @r }
sub span4 { my $l = shift; my @r = ($l .. "zz"); scalar @r }
# 1. Two live threads cloned from an unmarked parent: one marks its clone, then the other reads.
{
    my $marked = Thread::Queue->new; my $read = Thread::Queue->new;
    my $t1 = threads->create(sub { my $x = span1(5); $marked->enqueue(1); $read->dequeue; "marker: span1('a') after marking = " . span1("a") });
    my $t2 = threads->create(sub { $marked->dequeue; my $r = span1("a"); $read->enqueue(1); "reader: span1('a') while marker is alive = $r" });
    print "(1) ", $t1->join, "\n(1) ", $t2->join, "\n(1) parent: span1('a') = ", span1("a"), "\n";
}
# 2. Parent marks before creating a thread: does the clone inherit the mark?
{
    my $x = span2(5);
    my $t = threads->create(sub { "child created after parent marked: span2('a') = " . span2("a") });
    print "(2) ", $t->join, "\n(2) parent: span2('a') = ", span2("a"), "\n";
}
# 3. Child marks; parent reads after join.
{
    my $t = threads->create(sub { my $x = span3(5); "child marked: span3('a') in child = " . span3("a") });
    print "(3) ", $t->join, "\n(3) parent after join: span3('a') = ", span3("a"), "\n";
}
# 4. The foreach-alias JSON case, per thread.
sub enc_twice { my $json = JSON::PP->new; my @out; for my $pass (1, 2) { for my $v ("10") { push @out, $json->encode([$v]); my $n = $v + 0 } } "@out" }
{
    my $t = threads->create(\&enc_twice);
    print "(4) child: ", $t->join, "\n(4) parent after child: ", enc_twice(), "\n";
    my $t2 = threads->create(\&enc_twice);
    print "(4) child created after parent marked: ", $t2->join, "\n";
}
