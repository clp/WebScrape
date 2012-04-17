#!/usr/bin/env perl

use Test::More tests => 1;

# NOTE: Must be in the correct dir to run the program,
# for this test to pass, eg, the install dir.
my $program_under_test = "perl " . "./bin/scraper.pm";
system $program_under_test;

my $test_output_filename = "all_letters";
my $ref_output_filename = "all_letters_text_2012_0408";

# Compare two files on disk: reference o/p to program under test o/p.
my $ref_out = "refout/$ref_output_filename";
my $diff_out = `diff -s  "./$test_output_filename" $ref_out`;
like( $diff_out, qr{Files.*are.identical.*}, "Found all 127 o/p lines for wsj_2012_04_08 i/p data.");

