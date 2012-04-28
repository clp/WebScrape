#!/usr/bin/env perl
 
use Test::More tests => 1;

# TBD: Must be in the correct dir to run the program,
# for this test to pass, eg, the install dir.
# TBD: Erase ./tmp/usage_msg before running this test, to avoid using stale data.
unlink "./tmp/usage_msg" ;
my $program_under_test = "perl ./Local/Scraper.pm --help > ./tmp/usage_msg";
system $program_under_test;

# Compare two files on disk: program under test o/p and reference o/p.
my $diff_out = `diff -s  "./tmp/usage_msg" "./test/out/usage_msg"`;
like( $diff_out, qr{Files.*are.identical}, "Get usage note w/ --help option.");

