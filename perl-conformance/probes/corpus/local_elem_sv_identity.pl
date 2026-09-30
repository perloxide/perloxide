#!/usr/bin/env perl

use feature 'say';

use Data::Dump qw[dump];

print "my \@x = (1, 2, 3);";
my @x = (1, 2, 3);
say "  # \@x  = @{[dump(@x)]}              => @{[\(@x)]}";

print "my \$r = \\\$x[2];";
my $r = \$x[2];
say "     # \$r  = @{[dump($r)]}                     => @{[$r]} => @{[$$r]}";

print "my \$r2 = \$r;";
my $r2 = $r;
say "        # \$r2 = @{[dump($r2)]}                     => @{[$r2]} => @{[$$r2]}";
say;

say "do {                # scope begins";
do {
  say;

  print "  local \$x[2] = 5;";
  local $x[2] = 5;
  say "  # \@x  = @{[dump(@x)]}              => @{[\(@x)]}";
  say "                    # \$r  = @{[dump($r)]}                     => @{[$r]} => @{[$$r]}";
  say "                    # \$r2 = @{[dump($r2)]}                     => @{[$r2]} => @{[$$r2]}";
  say;

  print "  \$r2 = \\shift \@x;";
  $r2 = \shift @x;
  say "  # \@x  = @{[dump(@x)]}                 => @{[\(@x)]}";
  say "                    # \$r  = @{[dump($r)]}                     => @{[$r]} => @{[$$r]}";
  say "                    # \$r2 = @{[dump($r2)]}                     => @{[$r2]} => @{[$$r2]}";
  say;

  print "  \$\$r **= 3;";
  $$r **= 3;
  say "        # \$r  = @{[dump($r)]}                    => @{[$r]} => @{[$$r]}";
  say;

  print "  \$r2 = \\shift \@x;";
  $r2 = \shift @x;
  say "  # \@x  = (@{[dump(@x)]})                    => @{[\(@x)]}";
  say "                    # \$r  = @{[dump($r)]}                    => @{[$r]} => @{[$$r]}";
  say "                    # \$r2 = @{[dump($r2)]}                     => @{[$r2]} => @{[$$r2]}";
  say;

  print "  \$\$r **= 2;";
  $$r **= 2;
  say "        # \$r  = @{[dump($r)]}                   => @{[$r]} => @{[$$r]}";
  say "                    # \$r2 = @{[dump($r2)]}                     => @{[$r2]} => @{[$$r2]}";
  say;

  print "  \$r2 = \\shift \@x;";
  $r2 = \shift @x;
  say "  # \@x  = @{[dump(@x)]}";
  say "                    # \$r  = @{[dump($r)]}                   => @{[$r]} => @{[$$r]}";
  say "                    # \$r2 = @{[dump($r2)]}                     => @{[$r2]} => @{[$$r2]}";
  say;

  say "                    # \$#x = @{[$#x]}                     => scalar(\@x) = @{[scalar(@x)]}";
  say "                    # " . (exists $x[0] ? "\$x[0] exists" : "\$x[0] does not exist");
  say "                    # " . (exists $x[1] ? "\$x[1] exists" : "\$x[1] does not exist");
  say "                    # " . (exists $x[2] ? "\$x[2] exists" : "\$x[2] does not exist");
  say;

  say "}                   # scope ends";
};

say;
say "                    # \$#x = @{[$#x]}                      => scalar(\@x) = @{[scalar(@x)]}";
say "                    # " . (exists $x[0] ? "\$x[0] exists" : "\$x[0] does not exist");
say "                    # " . (exists $x[1] ? "\$x[1] exists" : "\$x[1] does not exist");
say "                    # " . (exists $x[2] ? "\$x[2] exists" : "\$x[2] does not exist");
say;

print "my \@y = \\(\@x);";
my @y = \(@x);
say "      # \@y  = @{[dump(@y)]} => @y => @{[map $$_ // q{undef}, @y]}";
say;

say "                    # \$#x = @{[$#x]}                      => scalar(\@x) = @{[scalar(@x)]}";
say "                    # " . (exists $x[0] ? "\$x[0] exists" : "\$x[0] does not exist");
say "                    # " . (exists $x[1] ? "\$x[1] exists" : "\$x[1] does not exist");
say "                    # " . (exists $x[2] ? "\$x[2] exists" : "\$x[2] does not exist");
say;

say "                    # \@x  = @{[dump(@x)]}    => @{[\(@x)]}";
say "                    # \$r  = @{[dump($r)]}                   => @{[$r]} => @{[$$r]}";
say "                    # \$r2 = @{[dump($r2)]}                     => @{[$r2]} => @{[$$r2]}";
say;

print "\$\$r **= 2;";
$$r **= 2;
say "          # \$r  = @{[dump($r)]}                => @{[$r]} => @{[$$r]}";
say;

say "                    # \@x  = @{[dump(@x)]} => @{[\(@x)]}";
say "                    # \$r  = @{[dump($r)]}                => @{[$r]} => @{[$$r]}";
say "                    # \$r2 = @{[dump($r2)]}                     => @{[$r2]} => @{[$$r2]}";
