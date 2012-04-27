#!perl
# Was #!perl -T

use Test::More tests => 1;

BEGIN {
  my $class = 'Scraper';
    use_ok( $class ) || print "Bail out!  ";
}

diag( "Testing Scraper $Scraper::VERSION, Perl $], $^X" );
