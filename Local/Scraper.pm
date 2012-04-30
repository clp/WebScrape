#! /usr/bin/env perl

# scraper  clpoda  2012_0323
# PC-batbug:/home/clpoda/p/WebScrape/bin
# Time-stamp: <Sun 2012 Apr 29 11:47:58 PMPM clpoda>
# Scrape the wsj.com site for letters to the editor
#
# Plan
# Build a release from this experimental code.
# Divide this code into a back-end web scraping module,
# and a program w/ site-specific code & data for wsj.com
# Status
# Fri2012_0323_12:51  Scraper works; now parse the data.
# Thu2012_0329_09:24  Parsing topics OK; get author data OK.
# Fri2012_0330_14:41  Extract each letter & save for analysis.
#   Extract is OK; but no metadata fields are stored for simple
#   retrieval & analysis.
# Wed2012_0404_21:07  Save letter text & metadata into a structure.
# Thu2012_0412_22:07  Fix parse bugs-not separating letters into files properly.
# Fri2012_0413_12:09  Handle letter w/ >1 author correctly.
#
# ---------------------------------------------------------------

# For format of the web page: see codenotes.otl file.

=head1 scraper

scraper - Get a web page, select data, show & save the results.


=head1 DESCRIPTION

This program is part of a project to test concepts and
Perl code for web scraping, parsing, and analysis.

It uses WWW::Mechanize to get the web page;
HTML::TreeBuilder, HTML::Element::Library, and regular expressions
to organize, navigate, and extract desired content.
A formatted copy of the content is saved and
shown on screen;
and each letter can be saved to disk
in a JSON file
for more detailed analysis.

This experimental version is hard-coded to use
The Wall Street Journal
newspaper's web page that contains
the letters to the editor.
Those letters are extracted,
along with author name(s) and data.
The headline for each letter is stored as its topic.
Some of this documentation is specific to the WSJ web site
and its pages.
Future versions might get other data from the WSJ,
and might get data from other sites.
Also,
the code might be divided into core components
holding the main functionality,
and separate modules
that are customized for the various
data sources.

For casual use,
the program can simply show the retrieved content
without using a web browser.

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

my $DEBUGMODE = 1
    ;   # 1: don't print everything; 2: print more; 5: print most
my $USE_LOCAL_DATA = 1;    # 0=Query the web site.
our $VERSION = '0.11';

# Initialize
my $source_id = 'wsj';
my $start_url
    = q{http://online.wsj.com/public/page/letters.html};    #CFG

my $program = 'Scraper';
my %current_letter = ();
my $daily_dir;
my $dt;
my $letters_count;

my $log_dir = './log';
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

my $directory;
my $quiet;
parse_cmd_line();

# Modulino: use as a module if a caller exists; otherwise run as a program.
__PACKAGE__->new->run if !caller;

sub run { #------------------------------------------------------
  my ($application) = @_;
  my $start_time = localtime;

  DEBUG("$program: Started run() at $start_time");

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
  if ($USE_LOCAL_DATA) {
    ## Read the local file into $start_page for correct handling
    ## of raw data by TreeBuilder.
    ##
    $start_page = read_file(
      "$input_dir/test/in/wsj/wsj.ltte.full.2012_0408.raw");
    $data_src = 'local copy of web page';
  }
  else {
    $start_page = get_web_page( $mech, $start_url );
    $data_src = 'web';
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

The first line with a <b> tag
marks the end of the body text,
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

  DEBUG($end_msg1);

  print { $application->{output_fh} } $end_msg1 . "\n";
  return;

}    # End of run().

1;

#
#
# Other Subroutines ---------------------------------------------------
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

  #TBD Include return for PBP?
  return;
}

=head2 output_fh

Use application object and set output filehandle as an
attribute,
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
    --directory <outpath>: Specify the parent path for o/p data,
        and write o/p data to disk files.
        Default is 'no directory'.
    --getwebpage: Query web server for i/p data.
        Default is 'no getwebpage'.
    --help: Show the brief usage message, then exit.
    --test: Read i/p data from a file, instead of querying a web
        server.
        Default is 'test'.
    --quiet: Do not show the fetched data on the screen;
        only show summary data.
        Default is 'no quiet'.

The program requests a page from a web site, extracts the
specified content, saves it, and displays it.

This version is hard-coded to get letters to the editor, ltte,
from the Wall Street Journal newspaper web site.

Temporary output files are stored under the raw dir,
<outpath>/out/wsj/raw/.  The program overwrites all files
in this dir every time it runs.

Permanent output files are stored under the <outpath>/out/ dir
tree, but only when the --directory option is specified, eg,
  perl ./lib/Scraper.pm --directory /tmp/Scraper

See the content collected each day that the program was run
in JSON formatted files at
<outpath>/out/wsj/YYYY/MMDD/ltte_NN.json.
The path depends on year, month, and day specified in the
web page.  That date can be different from the date that those
letters were published in the printed newspaper.
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

The original web page is also saved in a permanent directory
based on the web page date,
for future use.

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

  ## Also save original web page in the permanent dir.
  if ($DEBUGMODE) {
    write_file( "$daily_dir/$page_file", { binmode => ':utf8' },
      $start_page )
        or DEBUG("ERR save_raw_data(): $!");
  }
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
permanent output data files,
remove the dir if it exists (erasing any prior data),
and make the directory.

The path will be:
  <outpath>/out/wsj/YYYY/MMDD/

  where <outpath> is specified by the --directory command-line
  option;

  out/wsj/ are hard-coded dir names;

  YYYY and MM and DD are year, month, and date based on the date
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

  $daily_dir
      = "$rootdir/out/wsj/" . $dt->year . "/$m$d" . "_$hh$mm";
  ## TBD Check for success of init_dir here & in init_dir?:
  init_dir($daily_dir);
  return $daily_dir;
}

=head2 parse_cmd_line

Use C<GetOptions> to specify command line arguments
and what to do with them.

=cut

sub parse_cmd_line {

  my $getwebpage;
  my $help;
  my $test;
  my $result = GetOptions(
    'help'        => \$help,
    'directory=s' => \$directory,
    'getwebpage'  => \$getwebpage,
    'quiet'       => \$quiet,
    'test'        => \$test,
  );

  if ($help) { usage; exit; }
  if ($quiet)      { $quiet          = 1; }
  if ($test)       { $USE_LOCAL_DATA = 1; }
  if ($getwebpage) { $USE_LOCAL_DATA = 0; }
}

__END__


=head2 ASSUMPTIONS

The assumptions about the web site content
are based on reading the
code on the web pages of interest over some time.
The site can change and make these assumptions false.
At that point,
the code might need to be modified to handle the new data format.

TBD Document any major assumptions not already listed.





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

If you specify a directory on the command line,
that path is assigned to C<$input_dir>,
which will affect where the program looks for this file.



=head1 DIAGNOSTICS

A list of every error & warning msg that the app can
generate (even the ones that will "never happen"), w/ a full
explanation of each problem, one or more likely causes, and
any suggested remedies.  If the app generates exit status
codes (eg, under Unix), then list the exit status associated
w/ each error.

See the log/*.debug.log files for messages about the program's
operation.

TBD.



=head1 DEPENDENCIES

Several modules listed below are not part of the standard Perl
distribution,
and you can download them from CPAN if they are not already
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

This program is an experiment in web site scraping.
It is hard-coded to use wsj.com,
the web site of the Wall Street Journal newspaper.

It gets the web page with letters to the editor.

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
file, as NN.

Each time you run this command, any files in the dir will
be overwritten.  When the date in the web page changes, a new
directory will be made to store its data.


You can also use this code as a module.

  use lib qw ( Local );
  use Local::Scraper;

  my $scraper = Local::Scraper->new();

  $scraper->run();



=head1 FAQ: FREQUENTLY ASKED QUESTIONS

TBD Correct answers to common questions.


=head1 COMMON USAGE MISTAKES

TBD List of common misunderstandings, misconceptions, & correct
alternatives.  Eg, perltrap manpage.


=head1 TODO

TBD 
Notes on bugs to be fixed, 
features to be added,
design issues to be considered.

Bugs and features can be officially entered and tracked in
the bug data base.


=head1 HISTORY

TBD 
Some notes on changes made to the program design or code
over time, before it was committed to the version control
system, eg, CVS.


=head1 SEE ALSO

TBD 
Other modules and apps to this program.
Other documentation that can help users, including books,
articles, web pages.

Engineering Wiki at TBD.
Search for TBD.

Documents for the project at TBD server:
http://TBD




=head1 (DISCLAIMER OF) WARRANTY

TBD 
Provide real, legal notice for any s/w that might be used
outside the organization.
Maybe start w/ GPL clauses 11 & 12 at
http://www.gnu.org/copyleft/gpl.html.


=head1 ACKNOWLEDGEMENTS

Identify contributors, bug fixers, to encourage others.



=head1 AUTHOR

C. Poda  clp78 at poda dot net


=head1 LICENSE AND COPYRIGHT

Copyright (c) C. Poda
clp78 at poda dot net.  All rights reserved.

This program is free software; you can redistribute it
and/or modify it under the same terms as Perl itself.  See
L<Perl Artistic License|perlartistic>.

This program is distributed in the hope that it will be
useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
PURPOSE.


