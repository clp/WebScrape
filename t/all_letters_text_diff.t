#!/usr/bin/env perl

use Test::More tests => 1;

my $project_dir = "~/p/WebScrape/";
my $program_under_test = "perl " . $project_dir . "bin/scraper";

#TBD1 Add $infile - PUT must handle i/p file argument.
#ORG my $infile = 'data/9999-lines.mx';
my $test_output_filename = "all_letters";
my $ref_output_filename = "all_letters_text_94lines";
#TBD #ORG my $outdir = "tmp/";
my $outdir = ".";

# Compare two files on disk: reference o/p to program under test o/p.
my $ref_out = "refout/$ref_output_filename";
my $diff_out = `diff -s  "$outdir/$test_output_filename" $ref_out`;
like( $diff_out, qr{Files.*are.identical.*}, "Found all 94 o/p lines for wsj_2011_03_17_06_00 i/p data.");

