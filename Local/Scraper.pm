#! /usr/bin/env perl

=head1 NAME

Local::Scraper - Get a web page, select data, show & save the results.


=head1 SYNOPSIS

As a module.

  use Local::Scraper;
  use lib qw ( Local );
  my $scraper = Local::Scraper->new();
  $scraper->run();

As a program.

  Local/Scraper.pm [options]


=head1 DESCRIPTION

This program is part of a project to test concepts and
Perl code for web scraping, parsing, and analysis.

It uses CPAN modules such as WWW::Mechanize to get the web page;
HTML::TreeBuilder, HTML::Element::Library, and regular
expressions to organize, navigate, and extract desired content.

This experimental version is hard-coded to use
The Wall Street Journal
newspaper's web page that contains the letters to the editor.
Those letters are extracted,
along with author name(s) and data.

A formatted copy of the content is both saved and
shown on screen;
and each letter can be saved to disk in a JSON file
for more detailed analysis.

Some of this documentation is specific to the WSJ web site
and its pages.

For casual use,
the program can simply show the retrieved content without using a
web browser.


=head1 OPTIONS

All options can be shortened to the smallest set of unique
characters.

Either one or two hyphens can be used to prefix an option name.

=over 4

=item B<--debuglevel I<NUM>>

Set a level for debugging data written to the screen;
used during development.

Enable debuglevel by setting it to an integer value, eg 1-5.
More debug data is shown when the value is higher.

Default is 0, to disable all debuglevel output.

=item B<--directory I<outpath>>

Specify the parent path for storing output data,
and write the processed output data to a set of files
in this tree:
  I<outpath>/out/I<source>/YYYY/MMDD/ltte_NN.json.

where I<source> is hard-coded in the program;
the year, month, and day are extracted from the web page;
and NN is a unique sequence number for each file.
The web page's date can be different from the date when
this material appeared in the printed newspaper.

These data are intended for later examination and analysis,
but will be overwritten whenever a page is fetched and
processed that has the same date stamp.

Some data that can help with debugging are stored here,
and overwritten on each run:
  I<outpath>/out/raw/

Default I<outpath> is the current directory.

=item B<--getwebpage>

Query web server for the desired input data.

Default is do not query a web server.

=item B<--help|?>

Show a brief usage message, then exit.

=item B<--test>

Read input data from a local data file,
instead of querying a web server.

By default test mode is ON and no web query is made
unless the --getwebpage option is specified.

=item B<--quiet>

Do not show the fetched data on the screen;
only show summary data.

Default is 'quiet OFF',
and show the fetched data.

=back

=cut

package Local::Scraper;

use strict;
use warnings;

use autodie;
use charnames qw( :full );
use feature qw( say );

use Carp;
use Data::Dumper;
use DateTime::Format::Natural;
use File::Path qw(remove_tree make_path);
use File::Slurp;
use Getopt::Long;
use HTML::Element::Library;
use HTML::TreeBuilder;
use JSON;
use Log::Log4perl qw(:easy);
use Try::Tiny;
use WWW::Mechanize;

my $getwebpage = 0;    # 1=Query the web site.
our $VERSION = '0.11';

# Initialize
my $source_id = 'wsj';
my $start_url
    = q{http://online.wsj.com/public/page/letters.html};    #CFG

my $program        = 'Scraper';
my %current_letter = ();
my $daily_dir;
my $dt;
my $letters_count;

my $debuglevel = 0;
my $directory  = q{.};
my $quiet      = 0;
if ( !parse_cmd_line() ) {
  usage();
  exit;
}

my $log_dir = './log';    #CFG
$log_dir = '/var/local/data/Scraper/log' if $debuglevel > 4; #CFG
if ( !-d $log_dir ) {
  make_path("$log_dir");
}

# Set up logging.  Specify level, eg:
# level => $DEBUG,
# level => $INFO,
# level  => $WARN,
Log::Log4perl->easy_init(
  { level => $DEBUG,
    file  => ">>$log_dir/$program.debug.log"
  }
);

if ( !$start_url ) {
  carp "Die: No URL found in file or on command line.";
  usage();
  exit;
}

# Modulino: use as a module if a caller exists; otherwise run as a program.
__PACKAGE__->new->run if !caller;

sub run { #------------------------------------------------------
  my ($application) = @_;
  my $start_time = localtime;

  DEBUG("$program: Started run() at $start_time") if ($debuglevel > 4);

  ## Initialize -------------------------------------------------
  my $authors_count = 0;
  my $data_src      = 'unknown, maybe __DATA__';
  $letters_count = 0;
  my $rootdir = $directory ? $directory : q{.};    #CFG
  my $input_dir = q{.};                            #CFG

  ## Prepare to get data from local file or web -----------------
  my $mech = WWW::Mechanize->new();
  $mech->agent_alias('Linux Mozilla');
  my $start_page;
  my $tree;
  if ($getwebpage) {
    $start_page = get_web_page( $mech, $start_url );
    $data_src = 'web';
  }
  else {
    ## Read the local file into $start_page for correct handling
    ## of raw data by TreeBuilder.
    ##
    $start_page = read_file(
      "$input_dir/test/in/wsj/wsj.ltte.full.2012_0408.raw");
    $data_src = 'local_file';
  }
  $tree = HTML::TreeBuilder->new_from_content($start_page);

  ##TBD Verify page title: </script><title>Letters - WSJ.com</title>

  ## Format of serverTime = new Date("April 06, 2012 00:45:28");
  my ($pub_date_raw) = $tree->as_HTML =~ qr{
        serverTime \s+ = \s+ new \s+ Date
        \N{LEFT PARENTHESIS}
        "(.*?)"                 # Date & time inside quotes
        \N{RIGHT PARENTHESIS}
      }msx;
  my $date_parser = DateTime::Format::Natural->new();
  $dt = $date_parser->parse_datetime($pub_date_raw);

  if ( $date_parser->success ) {
    $daily_dir = initialize_output_dir($rootdir);
  }
  else {
    carp $date_parser->error;
    DEBUG "Error parsing date: ", $date_parser->error;
  }

  my ($raw_dir) = init_dir( $rootdir . '/out/wsj/raw' );
  save_raw_data( $raw_dir, $start_page, $tree );

  ## Get topic data.
  my @all_letters_to_editor;
  my @topics = extract_topics($tree);

  my $topic_parent = $tree->look_down(
    _tag  => 'div',
    class => q{},     # Empty string
  );

  my @lines_under_a_topic;
  my $topic_number = 0;
  my $topic_start;

  ## Loop on each topic. -----------------------------------------
TOPIC:
  foreach (@topics) {
    my $current_topic = $_->{_content}[0];
    $current_topic =~ s/\s+$//;

    $topic_start = $topic_parent->look_down(
      _tag => 'h1',
      sub { $_[0]->as_text =~ qr{$current_topic}i }
    );

    if ($topic_start) {
      @lines_under_a_topic = $topic_start->siblings;
      $topic_number++;
    }
    else {
      DEBUG
          "\$topic_start not found for topic_number: ,$topic_number,";
      $topic_number++;
      next TOPIC;
    }

    my $current_author      = q{};    # Empty string
    my $current_letter_text = q{};    # Empty string
    my $prior_author        = q{};    # Empty string
    my $current_line;

    ## Add newline for better readability on screen.
    push @all_letters_to_editor, "\n";

    ## Loop to get letter data under a topic.
LINE:
    while (@lines_under_a_topic) {
      $current_line = shift @lines_under_a_topic;

      if ($current_line) {
        push @all_letters_to_editor, $current_line->as_text;
        $current_letter_text .= $current_line->as_text;
      }
      else {
        next LINE;
      }

=head2 Letter-to-the-Editor Structure

=head3 Content of a Letter-to-the-Editor

Each letter to the editor comprises these parts:
body text,
author name,
author data
(eg, title, affiliation, location, comment).

Also,
each letter can have other metadata associated with it,
including:
source,
topic,
date.


=head3 HTML Structure of a Letter-to-the-Editor

A topic is marked by <h1> tags.

The first line of text after a topic is the start of a letter's
body text.

The first line with a <b> tag marks the end of the body text,
and the start of the first author's name.

The following lines with <i> tags are data about the first
author.

Any additional lines with <b> then <i> tags
describe additional authors.


The end of the author block and the current letter
is marked by one of these constructs.

- The first anchor tag found while reading lines from the
author block.

- The first line with no <b>, <i>, or <a> tag found
while reading lines from the
author block.

=cut

      ## AUTHOR handling code.
      if ( $current_line->as_HTML =~ /<b>/ ) {

        ## Extract all remaining data to end of letter as
        ## author data, then return to LINE loop.
        $authors_count++;
        $current_author = $current_line->as_text;
        $current_letter{author}{$current_author}{name}
            = $current_author;

        ## Assume the first <b> tag marks end of letter body.
        $current_letter{body}  = $current_letter_text;
        $current_letter{topic} = $current_topic;
        $current_letter{category}
            = 'LTTE';    # Letters to the Editor
        $current_letter{source_id}     = $source_id;
        $current_letter{web_page_date} = $pub_date_raw;

        ## Clear the var to prepare for next letter.
        $current_letter_text = q{};    # Empty string

        ## Loop to get current author data.
        while (@lines_under_a_topic) {
          $current_line = shift @lines_under_a_topic;

          push @all_letters_to_editor, $current_line->as_text;

          if ( $current_line->as_HTML =~ /<a/ ) {
            ## b.21: Not reliable marker for end of letter.

            push @all_letters_to_editor, "\n";

            $letters_count++;
            if ($directory) {
              save_letter_to_file( \%current_letter );
            }
            %current_letter = ();
            next LINE;
          }

          elsif ( $current_line->as_HTML =~ /<i>/ ) {
            push @{ $current_letter{author}{$current_author}
                  {details} },
                $current_line->as_text;
          }

          elsif ( $current_line->as_HTML =~ /<b>/ ) {
            if ( $current_line->as_text eq $current_author ) {
              ## Skip $current_author - already handled.
              next;
            }

            ## Handle the new author for the current letter.
            $current_author = $current_line->as_text;
            push @{ $current_letter{author}{$current_author}
                  {name} },
                $current_author;

            $authors_count++;

            #TBD Add label for this next to jump to.
            next;    # Get data for this new author.
          }
          else {
            ## Assume end of the letter found.
            last;
          }

        }    # End of while for author loop.

        ## If no more lines are under the topic, save the letter
        ## to a file.  This saves letters that do not have an
        ## <a> tag that can mark the end of a letter (see b.21).
        $letters_count++;
        if ($directory) {
          save_letter_to_file( \%current_letter );
        }
        %current_letter = ();

        push @all_letters_to_editor, "\n";

      }    # End of <b> loop for Authors.
    }    # End LINE loop.
  }    # End TOPIC loop.

  $tree->delete;

  ##---------------------------------------------------------------
  ## Save data from all letters found and overwrite any prior file.
  write_file( "$raw_dir/all_letters", q{} )
      ;    # Init to empty string
  foreach (@all_letters_to_editor) {
    append_file( "$raw_dir/all_letters", { binmode => ':utf8' },
      $_ )
        or
        DEBUG("ERR Failed to write to $raw_dir/all_letters: $!");
    append_file( "$raw_dir/all_letters", { binmode => ':utf8' },
      "\n" );
  }

  use Text::Wrap qw(wrap);
  ##---------------------------------------------------------------
  ## Save formatted letters and overwrite any prior file.
  write_file( "$raw_dir/all_letters.fmt", q{} )
      ;    # Init to empty string
  foreach (@all_letters_to_editor) {
    append_file(
      "$raw_dir/all_letters.fmt",
      { binmode => ':utf8' },
      wrap( "\t", q{  }, $_ )
        )
        or DEBUG(
      "ERR Failed to write to $raw_dir/all_letters.fmt: $!");
    append_file( "$raw_dir/all_letters.fmt",
      { binmode => ':utf8' }, "\n" );
  }

  ## Print all letters to screen.
  if ( !$quiet ) {
    say { $application->{output_fh} }
        "\nLetters to the Editor from $source_id",
        " web site, dated $pub_date_raw\n";
    binmode $application->{output_fh}, ':utf8';
    foreach (@all_letters_to_editor) {
      say { $application->{output_fh} } wrap( "\t", q{  }, $_ );
    }
  }

  ##---------------------------------------------------------------
  ## Print summary stats at end of the program.

  my $done_time = localtime;
  my ($end_msg1);
  $end_msg1
      = "\nSummary of $program:\n"
      . "  Using data src [$data_src] for letters to the editor"
      . " in $source_id.\n"
      . "  Found $authors_count authors for"
      . " $letters_count letters to the editor\n"
      . "  in $source_id, for web site content dated $pub_date_raw.\n";

  DEBUG("Run: $program|$source_id|$data_src|$pub_date_raw"
      . "|$authors_count|$letters_count");

  print { $application->{output_fh} } $end_msg1 . "\n";
  return;

}    # End of run().

1;

#
#
# Other Functions -----------------------------------------------
#
#

=head1 FUNCTIONS

=head2 run

The main routine for the program.

=head2 new

Make an object.

=cut

sub new { #------------------------------------------------------
  my ($class) = @_;
  my $application = bless {}, $class;
  $application->init;

  $application;
}

=head2 init

Initialize the object.

=cut

sub init { #-----------------------------------------------------
  ## TBD Add some or all init code here later.
  my ($application) = @_;
  $application->{output_fh} = \*STDOUT;

  return;
}

=head2 output_fh

Use application object and set output filehandle as an attribute,
for easier module testing.

=cut

sub output_fh { #------------------------------------------------
  my ( $application, $fh ) = @_;
  if ($fh) {
    $application->{output_fh} = $fh;
  }

  $application->{output_fh};
}

=head2 usage

Show a brief help message on screen.

=cut

sub usage { #----------------------------------------------------
  print <<"END_USAGE";
Usage:
  perl Local/Scraper.pm [options]

  Options:
    --debuglevel N: Set a debug level.
    --directory <outpath>: Specify parent path for o/p data,
        and write o/p to disk.
    --getwebpage: Query web server for i/p data.
    --help: Show a brief usage message, then exit.
    --test: Read i/p data from a file.
    --quiet: Do not show fetched data on screen;
        only show summary data.

The program requests a page from a web site, extracts the
specified content, saves it, and displays it.

This version is hard-coded to get letters to the editor, ltte,
from the Wall Street Journal newspaper web site.

Some output files for debugging are stored under the raw dir,
I<outpath>/out/wsj/raw/.  The program overwrites files
in this dir every time it runs.

Output files intended for later examination and analysis
are stored under the I<outpath>/out/wsj/ dir tree.

END_USAGE
}

=head2 init_dir

Remove any existing directory (and its entire subtree) with the
given name;
then make a new empty directory with that same name.

=cut

sub init_dir {  #------------------------------------------------
  my ($dir) = @_;
  if ( -d $dir ) {
    remove_tree("$dir");
  }
  make_path("$dir");
  return $dir;
}

=head2 get_web_page

Use a WWW::Mechanize object to request the desired web page,
inside a try+catch block.
A failure is caught and logged,
so that the program does not crash or die silently.

=cut

sub get_web_page {   #-------------------------------------------
  my ( $mech, $url ) = @_;
  my $response = q{};    # Empty string
  try {
    $response = $mech->get($url);
  }
  catch {
    ## TBD Use $! or $_ or $response?
    DEBUG($_);
    croak "ERR: Cannot get web page [$url]; try later.";
  };

  if ( !$response->is_success ) {
    my $msg = "Bad response to request for [$url]: "
        . $response->status_line;
    DEBUG($msg);
    croak
        "ERR: Got bad response to request for [$url]; try later.";
  }
  return $mech->content();
}

=head2 save_letter_to_file

Write each letter to the editor to a separate file.

=cut

sub save_letter_to_file { #--------------------------------------
  my $ref_current_letter = shift;
  my $count              = $letters_count;

  ## Add leading zeroes to get 2-character strings, eg, 01-09.
  ## Must use a temp var here instead of $letters_count.
  for ($count) {
    $_ = '0' . $_ if $_ <= 9;
  }

  write_file(
    "$daily_dir/ltte_$count.json",
    { binmode => ':utf8' },
    encode_json($ref_current_letter)
      )
      or
      DEBUG("ERR Failed to write to file $daily_dir/$count: $!");

  return;
}

=head2 save_raw_data

Save several formats of the raw data to files for debugging
purposes,
including:

the original web page;

a dump of the HTML::TreeBuilder tree in HTML form
($raw_dir/wsj.ltte.dump.html);

a dump of that tree in text form
(contains only letter-to-the-editor text with no HTML)
($raw_dir/wsj.ltte.dump.txt);

and an abridged tree dump showing the tree structure
in an outline form,
but without all the content of the page
($raw_dir/wsj.ltte.treedump).

The above files are overwritten every time the program runs.

The original web page is also saved in a different directory,
based on the web page date,
where it is not overwritten
(unless the new page has the same date as the old page).

=cut

sub save_raw_data { #--------------------------------------------
  my ( $raw_dir, $start_page, $tree ) = @_;

  ## Save structured tree view of web page.
  open my $treeout, '>', "$raw_dir/wsj.ltte.treedump";
  binmode $treeout, ':utf8';
  $tree->dump($treeout);
  close $treeout;

  my $page_file = "$source_id.ltte.raw";
  write_file( "$raw_dir/$page_file", { binmode => ':utf8' },
    $start_page )
      or DEBUG("ERR save_raw_data(): $!");

  write_file( "$raw_dir/wsj.ltte.dump.html", $tree->as_HTML )
      or DEBUG("ERR save_raw_data(): $!");

  write_file( "$raw_dir/wsj.ltte.dump.txt",
    { binmode => ':utf8' },
    $tree->as_text )
      or DEBUG("ERR save_raw_data(): $!");

  ## Also save original web page in another dir.
  write_file( "$daily_dir/$page_file", { binmode => ':utf8' },
    $start_page )
      or DEBUG("ERR save_raw_data(): $!");
  return;
}

=head2 extract_topics

A headline, or topic,
can have one or more letters below it.
Each topic is inside a set of h1 tags,
with the specified attribute.

All topics on the page are gathered into an array and returned
to the caller.

The letters under a topic are examined as a group
in the main routine.

=cut

sub extract_topics { #-------------------------------------------
  my $tree   = shift;
  my @topics = $tree->look_down(
    '_tag'  => 'h1',
    'class' => 'boldEighteenTimes',
  );
  return @topics;
}

=head2 initialize_output_dir

Create a unique name for each directory that stores
individual output data files,
remove the dir if it exists (erasing any prior data),
and make the directory.

The path will be:
  <outpath>/out/wsj/YYYY/MMDD/

  where <outpath> is specified by the --directory command-line
  option;

  out/wsj/ are hard-coded dir names;

  YYYY, MM, and DD are year, month, and date based on the date
  string on the web page.

=cut

sub initialize_output_dir {
  my $rootdir = shift;
  my $m       = $dt->month;
  my $d       = $dt->day;
  my $hh      = $dt->hour;
  my $mm      = $dt->minute;

  ## Add leading zeroes to values used in path, including file
  ## name, to get 2-digit strings, eg, 01-09.
  for ( $m, $d, $hh, $mm ) {
    $_ = "0" . $_ if $_ <= 9;
  }

  $daily_dir = "$rootdir/out/wsj/" . $dt->year . "/$m$d";

  if ( $debuglevel > 4 ) {
    ## Add suffix to dir name for hour & minute & pid.
    $daily_dir .= "_$hh$mm" . "_$$";
  }

  ## TBD Check for success of init_dir here & in init_dir?:
  init_dir($daily_dir);
  return $daily_dir;
}

=head2 parse_cmd_line

Use C<GetOptions> to specify command line arguments
and what to do with them.

=cut

#TBD Document CLI options in more detail here, or elsewhere in pod?

sub parse_cmd_line {

  my $help;
  my $test;
  my $result = GetOptions(
    'debuglevel=i' => \$debuglevel,
    'directory=s'  => \$directory,
    'help|?'       => \$help,
    'getwebpage'   => \$getwebpage,
    'quiet'        => \$quiet,
    'test'         => \$test,
  );

  if ($help) { usage; exit; }

  if ( !$debuglevel ) { $debuglevel = 0; }
  if ($quiet)         { $quiet      = 1; }
  if ($test)          { $getwebpage = 0; }
  return $result;
}

__END__


=head2 ASSUMPTIONS

The assumptions about the web site content
are based on reading the
code on the web pages of interest over some time.
The site can change and make these assumptions false.
At that point,
the code might need to be modified to handle the new data format.




=head1 CONFIGURATION

There are no configuration settings required.


=head1 INPUTS

This file is needed for test mode:
  C<$input_dir/test/in/wsj/wsj.ltte.full.2012_0408.raw>

Test mode is entered by specifying the --test command-line
option.
This mode is not required for the program to fetch a page
from a web server,
but it can help to ensure that the software has been installed
properly and is working in your environment.

The default value of C<$input_dir> is the current dir
in which the program is run.



=head1 DIAGNOSTICS

See the ./log/*.log files for messages about the program's
operation.

TBD.



=head1 DEPENDENCIES

Several modules listed below are not part of the standard Perl
distribution;
download them from CPAN if they are not already
installed on your system.

  use autodie;
  use charnames qw( :full );
  use feature qw( say );

  use Carp;
  use Data::Dumper;
  use DateTime::Format::Natural;
  use File::Path qw(remove_tree make_path);
  use File::Slurp;
  use Getopt::Long;
  use HTML::Element::Library;
  use HTML::TreeBuilder;
  use JSON;
  use Log::Log4perl qw(:easy);
  use Try::Tiny;
  use WWW::Mechanize;

  use Text::Wrap qw(wrap);

Also, you might find that Test::XML is required
by one of these modules,
but is not a 'formal' dependency.
You may have to install it manually.



=head1 INCOMPATIBILITIES

No known incompatibilities.



=head1 LIMITATIONS

=head2 Hard-Coded URL

This program is an experiment in web site scraping.
It is hard-coded to request the page with
letters to the editor at wsj.com,
the web site of the Wall Street Journal newspaper.

Future work may include other data sources,
and various content from those sources.

The project should evolve to comprise
a set of components that provide
core functions,
and customized configuration code and data,
to retrieve and to organize
content from many different web sites.



=head1 BUGS

Please report problems to the maintainer,
C. Poda, at
  clp78 at poda dot net

Patches are welcome.



=head2 Unsigned text can cause parsing to fail.

Some items do not have an author,
eg, Clarifications or Corrections.

The current parsing scheme relies on an author's name
inside <b> tags.
Without such a marker,
the text in these items may or may not be included in the
output stream.

A different parsing technique might be used in a future
version,
and this is one of the cases that it will attempt
to fix.


=head2 Date mismatch between web page and printed text.

The date on the web page for a set of data
may be different from the date when that data appeared
in the hard-copy published source.

The program gets the date from the web page
and saves it with the data retrieved from that page.

There are no current plans to modify the date that is stored
with the data,
to make it the same as the date when it was published
in a hard-copy edition.




=head1 EXAMPLES

Some ways to run the code as a program are shown below.

B<perl Local/Scraper.pm --test>

Run the program using a static local data file for input.
Do not query the web site for its current data.
Using local data is the default behavior.

B<perl Local/Scraper.pm --getwebpage>

Get the current web page from the hard-coded URL in the
source code.
This option is required to get current data.

B<perl Local/Scraper.pm -g --directory /tmp/Scraper>

Get the current web page from the hard-coded URL in the
source code and save the result.

Save the retrieved data into one file per letter at
/tmp/Scraper/out/wsj/YYYY/MMDD/ltte_NN.json.
The year, month, and date are from the date found in the
web page.  A unique number is assigned to each saved
file in a directory, as NN.

When you run this command and the web page has the same date
as stored data,
the files in that directory will be overwritten.
When the date in the web page changes,
a new directory will be made to store its data.


You can also use this code as a module.

  use lib qw ( Local );
  use Local::Scraper;
  my $scraper = Local::Scraper->new();
  $scraper->run();



=head1 FAQ: FREQUENTLY ASKED QUESTIONS

TBD


=head1 COMMON USAGE MISTAKES

By default,
the program uses a local data file instead of requesting a
web page from a server on the Internet.
Use the '--getwebpage' command-line option to fetch the current
web page at the specified URL.


=head1 TODO

Scrape more data sources.

Scrape more categories of data from each source.

Divide the code into a core component with common functionality
used by scrapers for different sources and categories of data.




=head1 SEE ALSO

CPAN modules at cpan.org:
  WebFetch
  Web::Scrape.



=head1 ACKNOWLEDGEMENTS

Thanks to all contributors to CPAN, Perl, and open source
software in general.



=head1 AUTHOR

C. Poda,  clp78 at poda dot net


=head1 LICENSE AND COPYRIGHT

Copyright 2012 (c) C. Poda
clp78 at poda dot net.  All rights reserved.

This program is free software; you can redistribute it
and/or modify it under the same terms as Perl itself.

This program is distributed in the hope that it will be
useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
PURPOSE.

