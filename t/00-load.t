#!perl -T
#OK w/ taint b/c no real code exists in the program yet.

use lib qw(Local);
use Test::More tests => 1;

BEGIN {
    use_ok( 'WebScrape' ) || print "Bail out!
";
}

diag( "Testing WebScrape $Local::WebScrape::VERSION, Perl $], $^X" );
