# $Id$

=head1 Name

SVN::Notify::Filter - SVN::Notify output filtering

=head1 Synopsis

  svnnotify -p "$1" -r "$2" --filter Trac -F My::Filter

=head1 Description

This document covers the output filtering capabilities of
L<SVN::Notify|SVN::Notify>. Output filters are simply subroutines defined in a
package that modify content output by SVN::Notify. Filters are loaded by the
C<filter> parameter to C<new()> or by the C<--filter> option to C<svnnotify>.

=head2 A Quick Example

The most common use for an output filter is to modify the format of log commit
messages. Say that your developers write their commit messages in Markdown
format, and you'd like it to be reformatted as HTML in the messages sent by
L<SVN::Notify::HTML|SVN::Notify::HTML>. To do so, just create a Perl module
and put it somewhere in the Perl path. Something like this:

  package SVN::Notify::Filter::Markdown;
  use strict;
  use Text::Markdown ();

  sub log_message {
      my ($notifier, $lines) = @_;
      return [ Text::Markdown->new->markdown( join '', @$lines ) ];
  }

Put this in a file named F<SVN/Notify/Filter/Markdown.pm> somewhere in your
Perl's path. The way that SVN::Notify filters work is that you simply define a
subroutine named for what you want to filter. The subroutine's first argument
will always be the SVN::Notify object that's generating the notification
message, and the second argument will always be the content to be filtered.

In this example, we wanted to filter the commit log message, so we just
defined a subroutine named C<log_message()> and passed the lines of the commit
message to L<Text::Markdown|Text::Markdown> to format, returning a new array.
And that's all there is to writing SVN::Notify filters: Define a subroutine,
process the second argument, and rturn a data structure in the same format as
that argument (usually an array reference).

Now, to use this filter, just use the C<--filter> option:

  svnnotify -p "$1" -r "$2" --handler HTML --filter Markdown

SVN::Notify will assume that a filter option without "::" is in the
SVN::Notify::Filter namespace, and will load it accorddingly. If you instead
created your filter in the package My::Filter::Markdown, then you'd specify
the full package hame in the C<--filter> option:

  svnnotify -p "$1" -r "$2" --handler HTML --filter My::Filter::Markdown

And that's it! The filter modify the contents of the log message before
SVN::Notify::HTML spits it out.

=head2 The Details

Writing SVN::Notify filters is easy. The name of each subroutine in a filter
module determines what content it filters. The filters take two arguments: the
SVN::Notify object that's creating the notification message, and the content
to be filtered. They should return the filtered content in the same manner as
it was passed. This makes it easy to change the output of SVN::Notify without
the hassle of subclassing or sending patches to the maintainer.

The names of the filter subroutines and the types of their second arguments
and return values are as follows:

  Sub Name    | Second Argument
  ------------+---------------------------------------------------------------
  headers     | Array reference of individual headers lines.
  from        | String with sender address.
  recipients  | Array reference of email addresses.
  subject     | String with the subject line.
  metadata    | Array reference of lines of metadata.
  log_message | Array reference of lines of log message.
  file_lists  | Array reference of lines of files. The first line will be
              | they type of change for the list, the next a simle line of
              | dasshes, and each of the rest of the lines a file name.
  diff        | A file handle reference to the diff.
  css         | An array of lines of CSS. Used only by SVN::Notify::HTML.
  start_html  | An array of lines starting an SVN::Notify::HTML document.
  start_body  | Array reference of lines at the start of the message body.
  end_body    | Array reference of lines at the end of the message body.

The module name can be anything you like; just pass it via the C<filter>
parameter, e.g., C<< filter => [ 'My::Filter' ] >> (or C<--filter My::Filter>
on the command-line). If, however, it's in the C<SVN::Notify::Filter>
namespace, you can just pass the last bit as the filter name, for example C<<
filter => [ 'NoSpam' ] >> (or C<--filter NoSpam> on the command-line) for
C<SVN::Notify::Filter::NoSpam>.

=head2 Examples

Some examples:

=over

=item * Map committers to senders

Map committer user names to email addresses using a lookup table. The "from"
filter gets and returns a string representing the sender:

  package SVN::Notify::Filter::FromTable;
  my %committers = (
      'homer' => 'homer@simpson.com',
      'bart'  => 'bart@gmail.com',
      'marge' => 'marge@urbanmamas.com',
  );
  sub from {
      my ($notifier, $from) = @_;
      return $committers{ $notifier->user } || $from;
  }

=item * Add a recipient

Easily done from the command-line using C<--to>, but hey, why not just filter
it?

  package SVN::Notify::Filter::Cc;
  sub recipients {
      my ($notifier, $recip) = @_;
      push @$recip, 'boss@example.com';
      return $recip;
  }

=item * Clean up the subject

Need to keep the subject line clean? Just modify the string and return it:

  package SVN::Notify::Filter::FromTable;
  my $nasties = qr/\b(?:golly|shucks|darn)\b/i;
  sub subject {
      my ($notifier, $subject) = @_;
      $subject =~ s/$nasties/[elided]/g;
      return $subject;
  }

=item * Add an extra header

This emulates C<add_header> to demonstrate header filtering:

  package SVN::Notify::Filter::NoSpam;
  sub headers {
      my ($notifier, $headers) = @_;
      push @$headers, 'X-NotSpam: true';
      return $headers;
  }

=item * Uppercase metadata labels

Change the format of the commit metadata section of the message to read
"REVISION: 111" instead of "Revision: 111":

  package SVN::Notify::Filter::UpLabels;
  sub metadata {
      my ($notifier, $lines) = @_;
      s/([^:]+:)/uc $1/eg for @$lines;
      return $lines;
  }

=item * Wrap your log message

Log message filtering will probably be quite common, generally to reformat it
(see, for example, the included
L<SVN::Notify::Filter::Trac|SVN::Notify::Filter::Trac> filter). Here's a
simple filter that reformats the log message so that paragraphs are wrapped.

  package SVN::Notify::Filter::WrapMessage;
  use Text::Wrap ();
  sub log_message {
      my ($notifier, $lines) = @_;
      return [ Text::Wrap::wrap( '', '', @$lines ) ];
  }

=item * Remove leading "trunk/" from file names

Just to demonstrate how to filter file lists:

  package SVN::Notify::Filter::StripTrunk;
  sub file_lists {
      my ($notifier, $lines) = @_;
      s{^(\s*)trunk/}{$1} for @$lines;
      return $lines;
  }

=item * Remove leading "trunk/" from file names in a diff

This one is a little more complicated because diff filters need to return a
file handle. SVN::Notify tries to be as efficient with resources as it can, so
it reads each line of the diff from the file handle one-at-a-time, processing
and outputing each in turn so as to avoid loading the entire diff into memory.
To retain this pattern, the best approach is to tie the file handle to a class
that does the filtering one line at a time. The requisite C<tie> class needs
only three methods: C<TIEHANDLE> C<READLINE>, and C<CLOSE>. In this example,
I've defined them in a different namespace than the filter subroutine, so as
to simplify SVN::Notify's loading of filters and to keep thing neatly
packaged:

  package My::IO::TrunkStripper;
  sub TIEHANDLE {
      my ($class, $fh) = @_;
      bless { fh => $fh }, $class;
  }

  sub READLINE {
      my $fh = shift->{fh};
      defined( my $line = <$fh> ) or return;
      $line =~ s{^((?:-{3}|[+]{3})\s+)trunk/}{$1};
      return $line;
  }

  sub CLOSE {
      close shift->{fh} or die $! ? "Error closing diff pipe: $!"
                                  : "Exit status $? from diff pipe";
  }

  package SVN::Notify::Filter::StripTrunkDiff;
  use Symbol ();

  sub diff {
      my ($notifier, $fh) = @_;
      my $filter = Symbol::gensym;
      tie *{ $filter }, 'My::IO::TrunkStripper', $fh;
      return $filter;
  }

However, if you don't mind loading the entire diff into memory, you can
simplify things by using a data structure and an exsiting IO module to do the
same thing:

  package SVN::Notify::Filter::StripTrunkDiff;
  use IO::ScalarArray;

  sub diff {
      my ($notifier, $fh) = @_;
      my @lines;
      while (<$fh>) {
          s{^((?:-{3}|[+]{3})\s+)trunk/}{$1};
          push @lines, $_;
      }
      return IO::ScalarArray->new(\@lines);
  }

But do beware of this approach if you're likely to commit changes that would
generate very larges diffs!

=item * Filter based on Parameter.

You can also add attributes (and therefor command-line options) to SVN::Notify
in your filter in order to alter its behavior. This is precisely what the
included L<SVN::Notify::Filter::Trac|SVN::Notify::Filter::Trac> module does:

  package SVN::Notify::Filter::Trac;

  SVN::Notify->register_attributes(
      trac_url => 'trac-url=s',
  );

  sub log_message {
      my $notify = shift;
      my $trac = Text::Trac->new(
          trac_url => $notify->trac_url,
      );
      $trac->parse(  join $/, @{ +shift } );
      return [ $trac->html ];
  }

=back

=cut


