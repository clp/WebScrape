#!perl
#F Was #!perl -T

use lib qw( Local);
use Test::More tests => 1;

BEGIN {
  my $class = 'Scraper';
    use_ok( $class ) || print "Bail out!
";
}

diag( "Testing Scraper $Local::Scraper::VERSION, Perl $], $^X" );
