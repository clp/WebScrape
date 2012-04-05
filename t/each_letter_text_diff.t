#!/usr/bin/env perl

use Test::More tests => 3;

my $project_dir = "~/p/WebScrape/";
my $program_under_test = "perl " . $project_dir . "bin/scraper";

my $outdir = "wsj/2012/mmdd";

my $diff_out_saved 
= qq{Files wsj/2012/mmdd/1 and refout/wsj/2012/0323/1 are identical
Files wsj/2012/mmdd/10 and refout/wsj/2012/0323/10 are identical
Files wsj/2012/mmdd/11 and refout/wsj/2012/0323/11 are identical
Files wsj/2012/mmdd/12 and refout/wsj/2012/0323/12 are identical
Files wsj/2012/mmdd/13 and refout/wsj/2012/0323/13 are identical
Files wsj/2012/mmdd/2 and refout/wsj/2012/0323/2 are identical
Files wsj/2012/mmdd/3 and refout/wsj/2012/0323/3 are identical
Files wsj/2012/mmdd/4 and refout/wsj/2012/0323/4 are identical
Files wsj/2012/mmdd/5 and refout/wsj/2012/0323/5 are identical
Files wsj/2012/mmdd/6 and refout/wsj/2012/0323/6 are identical
Files wsj/2012/mmdd/7 and refout/wsj/2012/0323/7 are identical
Files wsj/2012/mmdd/8 and refout/wsj/2012/0323/8 are identical
Files wsj/2012/mmdd/9 and refout/wsj/2012/0323/9 are identical
};

# Compare two files on disk: reference o/p to program under test o/p.
my $ref_out = "refout/wsj/2012/0323";
my $diff_out = `diff -s  $outdir $ref_out`;
like( $diff_out, qr{Files wsj.*and refout/wsj.*are.identical.*}, "Some letter files are identical.");

# Compare two dirs on disk: reference o/p to program under test o/p.
my $diff_count = `diff -s  $outdir $ref_out|wc`;
like( $diff_count, qr{.*13.*78.*827.*}, "Found 13 o/p files.");

# Compare entire o/p from diff cmd.
is( $diff_out, $diff_out_saved, "diff output is identical for 13 files.");

