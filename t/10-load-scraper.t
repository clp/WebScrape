#!perl
# Was #!perl -T

use Test::More tests => 1;

BEGIN {
  my $class = 'Local::Scraper';
    use_ok( $class ) || print "Bail out!  ";
}

diag( "Testing Scraper $Local::Scraper::VERSION, Perl $], $^X" );
