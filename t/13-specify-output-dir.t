#!/usr/bin/env perl
 
use Test::More tests => 1;

# TBD: Must be in the correct dir to run the program,
# for this test to pass, eg, the install dir.
# TBD: Erase ./tmp/test/out before running this test, to avoid using stale data.
use File::Path qw(remove_tree make_path);
use autodie qw(remove_tree);
my $d = "./tmp/test/out";
if ( -d $d ) {
  remove_tree($d);
}
make_path($d);

my $program_under_test = "perl " . "./lib/Scraper.pm --directory ./tmp/test";
system $program_under_test;

# Compare two files on disk: program under test o/p and reference o/p.
my $diff_out = `diff -sr  "./tmp/test/out" "./refout/test/out"`;
like( $diff_out, qr{Files.*are.identical$}, "Output files saved in specified directory.");

