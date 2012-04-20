#!/usr/bin/env perl

use Test::More tests => 1;

# NOTE: Must be in the correct dir to run the program,
# for this test to pass, eg, the install dir.
my $program_under_test = "perl " . "./lib/Scraper.pm";
system $program_under_test;

my $diff_out_saved 
= qq{Files out/wsj/2012/0408_1903/01 and refout/wsj/2012/0408_1903/01 are identical
Files out/wsj/2012/0408_1903/02 and refout/wsj/2012/0408_1903/02 are identical
Files out/wsj/2012/0408_1903/03 and refout/wsj/2012/0408_1903/03 are identical
Files out/wsj/2012/0408_1903/04 and refout/wsj/2012/0408_1903/04 are identical
Files out/wsj/2012/0408_1903/05 and refout/wsj/2012/0408_1903/05 are identical
Files out/wsj/2012/0408_1903/06 and refout/wsj/2012/0408_1903/06 are identical
Files out/wsj/2012/0408_1903/07 and refout/wsj/2012/0408_1903/07 are identical
Files out/wsj/2012/0408_1903/08 and refout/wsj/2012/0408_1903/08 are identical
Files out/wsj/2012/0408_1903/09 and refout/wsj/2012/0408_1903/09 are identical
Files out/wsj/2012/0408_1903/10 and refout/wsj/2012/0408_1903/10 are identical
Files out/wsj/2012/0408_1903/11 and refout/wsj/2012/0408_1903/11 are identical
Files out/wsj/2012/0408_1903/12 and refout/wsj/2012/0408_1903/12 are identical
Files out/wsj/2012/0408_1903/wsj.ltte.raw and refout/wsj/2012/0408_1903/wsj.ltte.raw are identical
};

# Compare two dirs on disk: reference o/p and program under test o/p.
my $outdir = "out/wsj/2012/0408_1903";
my $ref_out = "refout/wsj/2012/0408_1903";
my $diff_out = `diff -s  $outdir $ref_out`;

# Compare entire o/p of diff cmd.
is( $diff_out, $diff_out_saved, "diff output is identical for 12 files.");

