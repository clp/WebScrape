#!perl
# Was #!perl -T

use Test::More tests => 3;

my $class = 'Scraper';
  use_ok( $class ) || print "Bail out! 
  ";

my $application = $class->new;
isa_ok( $application , $class );

my $output_string;
open my ($fh), '>:utf8', \$output_string;

$application->output_fh($fh);

$application->run;
like( $output_string, 
  qr{Using data src ,.*, for letters to the editor in wsj.} ,
  "Got WSJ letters summary line.");

diag( "Testing Scraper $Scraper::VERSION, Perl $], $^X" );
