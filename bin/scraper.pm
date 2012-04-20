#! /usr/bin/env perl

# scraper  clpoda  2012_0323
# PC-batbug:/home/clpoda/p/WebScrape/bin
# Time-stamp: <Fri 2012 Apr 20 11:34:51 AMAM clpoda>
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

package scraper;

use strict;
use warnings;

use Carp;
use Data::Dumper;
use File::Path qw(remove_tree make_path);
use File::Slurp;
use HTML::Element::Library;
use HTML::TreeBuilder;
use JSON;
use Log::Log4perl qw(:easy);
use WWW::Mechanize;
use DateTime::Format::Natural;
use Try::Tiny;
use feature qw( switch say );

my $DEBUGMODE      = 1;
my $USE_LOCAL_DATA = 0;    # 1=Do not query web site.
our $VERSION = '0.10';

# Initialize
my $source_id   = "wsj";
my $domain_name = "wsj.com";
my $start_url
    = qq{http://online.wsj.com/public/page/letters.html};    #CFG

my $program = $0;
$program =~ s{\A.*/}{};    # strip leading path, if any
my $authors_count;
my %current_letter = ();
my $daily_dir;
my $data_src = "unknown, maybe __DATA__";
my $dt;
my $letters_count;

my $log_dir = "./log";
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

unless ($start_url) {
  die
      "$program died: No url found in file or on command line.\n\n",
      usage();
}

#TBD Based on Index.pm modulino code, Sun2012_0318_16:46: keep or toss?
__PACKAGE__->new->run unless caller;

sub run { #------------------------------------------------------
  my ($application) = @_;
  my $start_time = localtime();

  DEBUG("$0: Started run() at $start_time");

  ## Initialize --------------------------------------------------
  $authors_count = 0;
  $letters_count = 0;
  my $rootdir = ".";    #CFG

  ## Get start page w/ data.  ------------------------------------
  my $mech = WWW::Mechanize->new();
  $mech->agent_alias('Linux Mozilla');
  my $start_page;
  my $tree;
  if ($USE_LOCAL_DATA) {
    ## Read the local file into $start_page for correct handling
    ## of raw data, regardless of which branch is taken.
    $start_page = read_file(
      "$rootdir/data/wsj/wsj.ltte.full.2012_0408.raw");
    $data_src = "local copy of web page";
  }
  else {
    $start_page = get_start_page( $mech, $start_url );
    $data_src = "web";
  }
  $tree = HTML::TreeBuilder->new_from_content($start_page);

  ##TBD Verify page title: </script><title>Letters - WSJ.com</title>

  ## TBF b.9. serverTime may be different from the date when
  ## the letters are printed in the newspaper.
  ## Format of serverTime = new Date("April 06, 2012 00:45:28");
  my ($pub_date_raw)
      = $tree->as_HTML =~ qr{serverTime = new Date\("(.*?)"\)};
  my $date_parser = DateTime::Format::Natural->new();
  $dt = $date_parser->parse_datetime($pub_date_raw);

  ## TBD Move to where $dt is used?
  if ( $date_parser->success ) {
    $daily_dir = initialize_output_dir();
  }
  else {
    carp $date_parser->error;
    DEBUG $date_parser->error;
  }

  ## This save step uses $dt during debug.
  my ($raw_dir) = init_dir( $rootdir . "/raw/wsj/ltte" );
  save_raw_data( $source_id, $raw_dir, $start_page, $tree );

  ## Get topic data.
  my @all_letters_to_editor;
  my @topics = extract_topics($tree);

  my $topic_parent = $tree->look_down(
    _tag  => 'div',
    class => "",
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

    my $current_author      = '';
    my $current_letter_text = '';
    my $prior_author        = '';
    my $letter_line;

    ## Add newline for better readability on screen.
    push @all_letters_to_editor, "\n";

    ## First loop for letters.
LINE:
    while (@lines_under_a_topic) {
      $letter_line = shift @lines_under_a_topic;

      if ($letter_line) {
        push @all_letters_to_editor, $letter_line->as_text;
        $current_letter_text .= $letter_line->as_text;
      }
      else {
        next LINE;
      }

      ## Author handling code.
      ## Extract all remaining data to end of letter as
      ## author data, then return to LINE loop.
      if ( $letter_line->as_HTML =~ /<b>/ ) {

        ## Handle all following lines # as author data,
        ## until end of current letter.
        $authors_count++;
        $current_author = $letter_line->as_text;
        $current_letter{author}{$current_author}{name}
            = $current_author;

        ## Assume the <b> tag marks end of letter body.
        $current_letter{body}  = $current_letter_text;
        $current_letter{topic} = $current_topic;
        my $current_category = "LTTE";
        $current_letter{category}      = $current_category;
        $current_letter{source_id}     = $source_id;
        $current_letter{web_page_date} = $pub_date_raw;

        ## Clear the var to prepare for next letter.
        $current_letter_text = '';

        ## Loop to get current author data.
        my $current_line;
        while (@lines_under_a_topic) {
          $current_line = shift @lines_under_a_topic;

          push @all_letters_to_editor, $current_line->as_text;

          if ( $current_line->as_HTML =~ /<a/ ) {
            ## b.21: Not reliable marker for end of letter.

            push @all_letters_to_editor, "\n";

            $letters_count++;
            save_letter_to_file( \%current_letter );
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

            ## Handle the new author for an existing letter.
            $current_author = $current_line->as_text;
            push @{ $current_letter{author}{$current_author}
                  {name} },
                $current_author;

            $authors_count++;
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
        save_letter_to_file( \%current_letter );

        push @all_letters_to_editor, "\n";

      }    # End of <b> loop for Authors.
    }    # End LINE loop.
  }    # End TOPIC loop.

  $tree->delete;

  ##---------------------------------------------------------------
  ## Save data from all letters found.
  write_file( "$raw_dir/all_letters", "" );
  foreach (@all_letters_to_editor) {
    append_file( "$raw_dir/all_letters", { binmode => ':utf8' },
      $_ )
        or
        DEBUG("ERR Failed to write to $raw_dir/all_letters: $!");
    append_file( "$raw_dir/all_letters", { binmode => ':utf8' },
      "\n" );
  }

  ## Print all letters to screen.
  use Text::Wrap;
  say "\nLetters to the Editor from $source_id",
      " web site, dated $pub_date_raw\n";
  binmode $application->{output_fh}, ':utf8';
  foreach (@all_letters_to_editor) {
    say { $application->{output_fh} } wrap( "\t", '  ', $_ );
  }

  ##---------------------------------------------------------------
  ## Print summary stats at end of the program.

  my $done_time = localtime();
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

}    # End of run().

#TBR exit 1;
1;

#
#
# Subroutines ---------------------------------------------------
#
#
sub new { #------------------------------------------------------
  my ($class) = @_;
  my $application = bless {}, $class;
  $application->init;
  $application;
}

sub init { #-----------------------------------------------------
  ## TBD Add some or all init code here later.
  my ($application) = @_;
  $application->{output_fh} = \*STDOUT;
}

sub output_fh { #------------------------------------------------
  my ( $application, $fh ) = @_;
  if ($fh) {
    $application->{output_fh} = $fh;
  }
  $application->{output_fh};
}

sub usage { #----------------------------------------------------
  return <<"eousage";
Usage:
  $program

$program requests a page from the Wall Street Journal web site,
then extracts letters to the editor,
and saves them and displays them.

Output data is stored by default in and below the dir
where the program was run.

See all letters for one day in the file ./<raw_dir>/all_letters,
where <raw_dir> is source/category, eg, wsj/ltte.  The program
overwrites this file every time it runs.

See the letters collected each day that the program was run
in JSON formatted files at ./wsj/yyyy/mmdd/NN,
where the path depends on year, month, and day on the
web page, which can be different from the newspaper's 
publication date.

eousage
}

sub init_dir {  #------------------------------------------------
  my ($dir) = @_;
  if ( -d $dir ) {
    remove_tree("$dir");
  }
  make_path("$dir");
  return $dir;
}

sub get_start_page { #-------------------------------------------
  my ( $mech, $start_url ) = @_;
  my $response = '';
  try {
    $response = $mech->get($start_url);
  }
  catch {
    ## TBD Use $! or $_ or $response?
    DEBUG($_);
    die "ERR: Cannot get web page [$start_url]; try later.";
  };

  if ( !$response->is_success ) {
    my $msg = "Bad response to request for [$start_url]: "
        . $response->status_line;
    DEBUG($msg);
    die
        "ERR: Got bad response to request for [$start_url]; try later.";
  }
  return $mech->content();
}

## Write each letter to a separate file.
sub save_letter_to_file { #--------------------------------------
  my $ref_current_letter = shift;
  my $count              = $letters_count;

  ## Add leading zeroes to get 2-character strings.
  for ($count) {
    $_ = "0" . $_ if $_ <= 9;
  }

  write_file(
    "./$daily_dir/$count",
    { binmode => ':utf8' },
    encode_json($ref_current_letter)
      )
      or
      DEBUG("ERR Failed to write to file $daily_dir/$count: $!");

  %current_letter = ();
}

sub save_raw_data { #--------------------------------------------
  my ( $source_id, $raw_dir, $start_page, $tree ) = @_;

  ## Save structured view of web page.
  my $treeout;
  open( $treeout, '>', "$raw_dir/wsj.ltte.treedump" );
  binmode $treeout, ':utf8';
  $tree->dump($treeout);
  close($treeout);

  ## Save temporary copy of raw downloaded page & decoded
  ## content for debugging.  These files are overwritten each
  ## time the program is run.
  my $page_file = "$source_id.ltte.raw";
  write_file( "$raw_dir/$page_file", { binmode => ':utf8' },
    $start_page )
      or DEBUG("ERR save_raw_data(): $!");
  write_file( "$raw_dir/tree_builder_dump_as_html",
    $tree->as_HTML )
      or DEBUG("ERR save_raw_data(): $!");
  write_file(
    "$raw_dir/tree_builder_dump_as_text",
    { binmode => ':utf8' },
    $tree->as_text
  ) or DEBUG("ERR save_raw_data(): $!");

  ## Save a permanent copy while debugging.
  if ($DEBUGMODE) {
    write_file( "$daily_dir/$page_file", { binmode => ':utf8' },
      $start_page )
        or DEBUG("ERR save_raw_data(): $!");
  }
}

sub extract_topics { #-------------------------------------------
  my $tree   = shift;
  my @topics = $tree->look_down(
    '_tag'  => 'h1',
    'class' => 'boldEighteenTimes',
  );
  return @topics;
}

sub initialize_output_dir {
  my $m = $dt->month;
  my $d = $dt->day;
  my $H = $dt->hour;
  my $M = $dt->minute;

  ## Add leading zeroes to values used in path, including file
  ## name, to get 2-digit strings.
  for ( $m, $d, $H, $M ) {
    $_ = "0" . $_ if $_ <= 9;
  }

  my $daily_dir
      = "./out/wsj/" . $dt->year . "/" . $m . $d . "_" . $H . $M;
  init_dir($daily_dir);
  return $daily_dir;
}

# Comment template
#########################################################
# Usage      : n/a
# Purpose    : Hold useful code & notes for Perl programs.
# Returns    : n/a
# Parameters : n/a
# Throws     : no exceptions
# Comments   : Copy this file into a new program file
#            : and remove what is not needed and customize
#            : what remains.
# See Also   : n/a
# Status     : Usable as-is, and needs clean-up.
#########################################################

__END__

=head1 scraper

scraper - Get a web page, select data, show & save the results.


=head1 DESCRIPTION

A full description of the app & features.
May include many subsections (ie, =head2, =head3, etc).

This program is part of a project to test concepts and code
for a Perl module
for web scraping, parsing, interpretation, and analysis.

This program uses WWW::Mechanize to get the web page;
HTML::TreeBuilder, HTML::Element::Library, and regular expressions
to organize, navigate, and extract desired content.
Output data is shown on screen, and
is saved to disk
in JSON formatted files
for analysis.

This test code is hard-coded to use The Wall Street Journal's
web page that contains
the letters to the editor.
Those letters are extracted,
along with author name(s) and data.
The headline for each letter is stored as its topic.



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
L<perlartistic>.

This program is distributed in the hope that it will be
useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
PURPOSE.


