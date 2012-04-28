#! /usr/bin/env perl

# scraper  clpoda  2012_0323
# PC-batbug:/home/clpoda/p/WebScrape/bin
# Time-stamp: <Sat 2012 Apr 28 11:44:58 AMAM clpoda>
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
Perl code
for web scraping, parsing, and analysis.

It uses WWW::Mechanize to get the web page;
HTML::TreeBuilder, HTML::Element::Library, and regular expressions
to organize, navigate, and extract desired content.
A formatted copy of the content is saved and
shown on screen;
and each letter can be saved to disk
in a JSON file
for more detailed analysis.

This version is hard-coded to use The Wall Street Journal
newspaper's web page that contains
the letters to the editor.
Those letters are extracted,
along with author name(s) and data.
The headline for each letter is stored as its topic.
Some of this documentation is specific to the WSJ web site
and its pages.
Future versions might get other data from the WSJ,
and might get data from other sites.
At that point,
the code might be divided into a core component
holding the main functionality,
that is used by modules customized for the various
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
use feature qw( switch say );

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
our $VERSION = '0.10';

# Initialize
my $source_id = 'wsj';
my $start_url
    = q{http://online.wsj.com/public/page/letters.html};    #CFG

my $program = $0;
$program =~ s{\A.*/}{};    # strip leading path, if any
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

  DEBUG("$0: Started run() at $start_time");

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
    $start_page = get_web_page($mech, $start_url);
    $data_src   = 'web';
  }
  $tree = HTML::TreeBuilder->new_from_content($start_page);

  ##TBD Verify page title: </script><title>Letters - WSJ.com</title>

  ## TBF b.9. serverTime may be different from the date when
  ## the letters are printed in the newspaper.
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
    DEBUG $date_parser->error;
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
          "\$topic_start not found for number: ,$topic_number,";
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


#TBR =back

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
            if ( $directory) {
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
        if ( $directory) {
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
  if (!$quiet) {
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
      = "\nSummary of $0:\n"
      . "  Using data src ,$data_src, for letters to the editor"
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

=over 4

=item run()

The main routine for the program or module.
The main routine for the program or module.
The main routine for the program or module.
The main routine for the program or module.

=back

=cut


=over 4

=item new()

Make an object,
which is only used to call methods for now.

=cut

sub new { #------------------------------------------------------
  my ($class) = @_;
  my $application = bless {}, $class;
  $application->init;

  #TBD Include return for PBP?
  return $application;
}


=item init()

Initialize the object.

=cut


sub init { #-----------------------------------------------------
  ## TBD Add some or all init code here later.
  my ($application) = @_;
  $application->{output_fh} = \*STDOUT;

  #TBD Include return for PBP?
  return;
}


=item output_fh()

TBDsubdescription.

=cut

sub output_fh { #------------------------------------------------
  my ( $application, $fh ) = @_;
  if ($fh) {
    $application->{output_fh} = $fh;
  }

  #TBD Include return for PBP?
  return $application->{output_fh};
}


=item usage()

TBDsubdescription.

=cut

sub usage { #----------------------------------------------------
  print <<"END_USAGE";
Usage:
  perl Scraper.pm [options]

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
<outpath>/out/wsj/yyyy/mmdd/ltte_NN.json.
The path depends on year, month, and day specified in the
web page.  That date can be different from the date that those
letters were published in the printed newspaper.
END_USAGE
}


=item init_dir()

TBDsubdescription.

=cut

sub init_dir {  #------------------------------------------------
  my ($dir) = @_;
  if ( -d $dir ) {
    remove_tree("$dir");
  }
  make_path("$dir");
  return $dir;
}


#TBR =back

=item C<get_web_page( $mech )>

This sub includes a try+catch block
around the request to the web server for the desired page.
A failure is caught and logged,
so the program does not crash or die silently.

The $mech parameter is a WWW::Mechanize object.

=cut


=item get_web_page()

TBDsubdescription.

=cut

sub get_web_page { #-------------------------------------------
  my ($mech, $url) = @_;
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


=item save_letter_to_file()

TBDsubdescription.

=cut

## Write each letter to a separate file.
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


=item save_raw_data()

TBDsubdescription.

=cut

sub save_raw_data { #--------------------------------------------
  my ( $raw_dir, $start_page, $tree ) = @_;

  ## Save structured view of web page.
  open my $treeout, '>', "$raw_dir/wsj.ltte.treedump";
  binmode $treeout, ':utf8';
  $tree->dump($treeout);
  close $treeout;

  ## Save temporary copy of raw downloaded page & decoded
  ## content for debugging.  Overwrite these files each
  ## time the program runs.
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

  ## Save a permanent copy while debugging.
  if ($DEBUGMODE) {
    write_file( "$daily_dir/$page_file", { binmode => ':utf8' },
      $start_page )
        or DEBUG("ERR save_raw_data(): $!");
  }
  return;
}

=item TBD Description of sub C<extract_topics()>

A headline, or topic,
can have one or more letters below it.
Each topic is inside a set of h1 tags,
with the specified attribute.

All topics are gathered into an array and returned
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


=item initialize_output_dir()

TBDsubdescription.

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


=item parse_cmd_line()

Use C<GetOptions> to specify command line arguments
and what to do with them.

You can specify the minimal unique text to specify any
argument to invoke it.

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

  if ($help)       { usage; exit; }
  if ($quiet)      { $quiet        = 1; }
  if ($test)       { $USE_LOCAL_DATA = 1; }
  if ($getwebpage) { $USE_LOCAL_DATA = 0; }
}



__END__

=back

=head2 ASSUMPTIONS

The assumptions about the web site content
are based on reading the
code on the web pages of interest over some time.
The site can change and make these assumptions false.
At that point,
the code might need to be modified to handle the new data format.

TBD Document any major assumptions not already listed.





=head2 TBD Description of configuration settings required.

TBD

=head2 TBD Description of inputs required.

This i/p file is needed for certain tests to run:
  C<$rootdir/data/wsj/wsj.ltte.full.2012_0408.raw>

The tests are not required for the program to operate,
and they can help to ensure it has been installed
properly and is working in your environment.

The default value of C<$rootdir> is the current dir
in which the program is run.

If you specify a directory on the cmd line,
that is assigned to C<$rootdir>,
which will affect where the program looks for this file.

TBD: Maybe don't use CLI -d arg for $rootdir?



=head1 DIAGNOSTICS

A list of every error & warning msg that the app can
generate (even the ones that will "never happen"), w/ a full
explanation of each problem, one or more likely causes, and
any suggested remedies.  If the app generates exit status
codes (eg, under Unix), then list the exit status associated
w/ each error.


=head1 CONFIGURATION AND ENVIRONMENT

A full explanation of any config systems used by the app,
including names & locations of any config files, & the
meaning of any env vars or properties that can be set.
These descriptions must also include details of any config
language used.


=head1 DEPENDENCIES

A list of all the other programs & modules that this one
relies on, including any restrictions on versions, & an
indication of whether these required modules are part of the
standard Perl distribution, part of the program's
distribution, or must be installed separately.


=head1 INCOMPATIBILITIES

A list of any programs or modules that this program cannot
be used in conjunction with.  This may be due to name
conflicts in the i/f, or competition for system or program
resources, or due to internal limitations of Perl (eg, many
modules that use source code filters are mutually
incompatible).


=head1 BUGS AND LIMITATIONS

A list of known problems, together w/ some indication of
whether they are likely to be fixed in an upcoming release.

Also a list of restrictions on the features the module does
provide: data types that cannot be handled, performance
issues and the circumstances in which they may arise,
practical limitations on the size of data sets, special
cases that are not (yet) handled, etc.

There are no known bugs in this program.
Please report problems to the maintainer,
C. Poda, at
clp78 at poda dot net
Patches are welcome.


=head1 EXAMPLES

Provide a /demo dir w/ well-commented examples.
Add examples in the documentation, because the demos might
not always be avbl.


=head1 FAQ: FREQUENTLY ASKED QUESTIONS

Correct answers to common questions.


=head1 COMMON USAGE MISTAKES

List of common misunderstandings, misconceptions, & correct
alternatives.  Eg, perltrap manpage.


=head1 TODO

Notes on bugs to be fixed, 
features to be added,
design issues to be considered.

Bugs and features can be officially entered and tracked in
the bug data base.


=head1 HISTORY

Some notes on changes made to the program design or code
over time, before it was committed to the version control
system, eg, CVS.


=head1 SEE ALSO

Other modules and apps to this program.
Other documentation that can help users, including books,
articles, web pages.

Engineering Wiki at TBD.
Search for TBD.

Documents for the project at TBD server:
http://TBD




=head1 (DISCLAIMER OF) WARRANTY

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

