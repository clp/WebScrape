#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'WebScrape' ) || print "Bail out!
";
}

diag( "Testing WebScrape $WebScrape::VERSION, Perl $], $^X" );
