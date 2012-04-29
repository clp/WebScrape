#!perl
# Was #!perl -T

#NOTNEEDED  use lib qw ( Local );

use Test::More tests => 4;

my $class;
BEGIN {
  $class = 'Local::Scraper';
    use_ok( $class ) || print "Bail out! 
    ";
}

my $application = $class->new();
isa_ok( $application , $class );

my $output_string;
open my ($fh), '>:utf8', \$output_string;

$application->output_fh($fh);

$application->run;
like( $output_string, 
  qr{Letters to the Editor from wsj web site.} ,
  "Get WSJ letters introduction line.");

like( $output_string, 
  qr{Using data src \[local.*\] for letters to the editor in wsj} ,
  "Get WSJ letters summary line.");

diag( "Testing Scraper $Local::Scraper::VERSION, Perl $], $^X" );
