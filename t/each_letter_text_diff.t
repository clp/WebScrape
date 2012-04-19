#!/usr/bin/env perl

use Test::More tests => 1;

# NOTE: Must be in the correct dir to run the program,
# for this test to pass, eg, the install dir.
my $program_under_test = "perl " . "./bin/scraper.pm";
system $program_under_test;

my $diff_out_saved 
= qq{Files out/wsj/2012/0408/01 and refout/wsj/2012/0408/01 are identical
Files out/wsj/2012/0408/02 and refout/wsj/2012/0408/02 are identical
Files out/wsj/2012/0408/03 and refout/wsj/2012/0408/03 are identical
Files out/wsj/2012/0408/04 and refout/wsj/2012/0408/04 are identical
Files out/wsj/2012/0408/05 and refout/wsj/2012/0408/05 are identical
Files out/wsj/2012/0408/06 and refout/wsj/2012/0408/06 are identical
Files out/wsj/2012/0408/07 and refout/wsj/2012/0408/07 are identical
Files out/wsj/2012/0408/08 and refout/wsj/2012/0408/08 are identical
Files out/wsj/2012/0408/09 and refout/wsj/2012/0408/09 are identical
Files out/wsj/2012/0408/10 and refout/wsj/2012/0408/10 are identical
Files out/wsj/2012/0408/11 and refout/wsj/2012/0408/11 are identical
Files out/wsj/2012/0408/12 and refout/wsj/2012/0408/12 are identical
};

# Compare two dirs on disk: reference o/p to program under test o/p.
my $outdir = "out/wsj/2012/0408";
my $ref_out = "refout/wsj/2012/0408";
my $diff_out = `diff -s  $outdir $ref_out`;

# Compare entire o/p of diff cmd.
is( $diff_out, $diff_out_saved, "diff output is identical for 12 files.");

