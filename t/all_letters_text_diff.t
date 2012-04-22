#!/usr/bin/env perl
 
use Test::More tests => 1;

# TBD This test compares a file made by the program 
# processing data in a file on disk, to a reference file made
# by a previous version of the program.  It cannot
# pass when the program processes data from the web.

# TBD: Must be in the correct dir to run the program,
# for this test to pass, eg, the install dir.
my $program_under_test = "perl " . "./lib/Scraper.pm --test";
system $program_under_test;

# Compare two files on disk: program under test o/p and reference o/p.
my $diff_out = `diff -s  "./raw/wsj/ltte/all_letters" "./refout/all_letters_text_2012_0408"`;
#ORG like( $diff_out, qr{Files.*are.identical.*}, "Found all 127 o/p lines for wsj_2012_04_08 i/p data.");
like( $diff_out, qr{Files.*are.identical.*}, "Run program w/ local test data file for 2012_0408.");

