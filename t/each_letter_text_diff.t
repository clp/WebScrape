#!/usr/bin/env perl

use Test::More tests => 1;

# NOTE: Must be in the correct dir to run the program,
# for this test to pass, eg, the install dir.
my $program_under_test = "perl ./lib/Scraper.pm --directory .";
system $program_under_test;

my $diff_out_saved 
= qq{Files out/wsj/2012/0408_1903/ltte_01.json and refout/wsj/2012/0408_1903/ltte_01.json are identical
Files out/wsj/2012/0408_1903/ltte_02.json and refout/wsj/2012/0408_1903/ltte_02.json are identical
Files out/wsj/2012/0408_1903/ltte_03.json and refout/wsj/2012/0408_1903/ltte_03.json are identical
Files out/wsj/2012/0408_1903/ltte_04.json and refout/wsj/2012/0408_1903/ltte_04.json are identical
Files out/wsj/2012/0408_1903/ltte_05.json and refout/wsj/2012/0408_1903/ltte_05.json are identical
Files out/wsj/2012/0408_1903/ltte_06.json and refout/wsj/2012/0408_1903/ltte_06.json are identical
Files out/wsj/2012/0408_1903/ltte_07.json and refout/wsj/2012/0408_1903/ltte_07.json are identical
Files out/wsj/2012/0408_1903/ltte_08.json and refout/wsj/2012/0408_1903/ltte_08.json are identical
Files out/wsj/2012/0408_1903/ltte_09.json and refout/wsj/2012/0408_1903/ltte_09.json are identical
Files out/wsj/2012/0408_1903/ltte_10.json and refout/wsj/2012/0408_1903/ltte_10.json are identical
Files out/wsj/2012/0408_1903/ltte_11.json and refout/wsj/2012/0408_1903/ltte_11.json are identical
Files out/wsj/2012/0408_1903/ltte_12.json and refout/wsj/2012/0408_1903/ltte_12.json are identical
Files out/wsj/2012/0408_1903/wsj.ltte.raw and refout/wsj/2012/0408_1903/wsj.ltte.raw are identical
};

# Compare two dirs on disk: reference o/p and program under test o/p.
my $outdir = "out/wsj/2012/0408_1903";
my $ref_out = "refout/wsj/2012/0408_1903";
my $diff_out = `diff -s  $outdir $ref_out`;

# Compare entire o/p of diff cmd.
is( $diff_out, $diff_out_saved, "diff output is identical for 12 files.");

