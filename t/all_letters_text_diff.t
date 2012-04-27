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
my $diff_out = `diff -s  "./out/wsj/raw/all_letters" "./test/out/wsj/raw/all_letters_text_2012_0408"`;
like( $diff_out, qr{Files.*are.identical.*}, "Run program w/ local data file for 2012_0408.");

