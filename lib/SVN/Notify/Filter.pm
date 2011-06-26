=head1 Name

SVN::Notify::Filter - Create output filters for SVN::Notify

=head1 Synopsis

  package SVN::Notify::Filter::Textile;
  use Text::Textile ();

  sub log_message {
      my ($notifier, $lines) = @_;
      return $lines unless $notify->content_type eq 'text/html';
      return [ Text::Textile->new->process( join $/, @$lines ) ];
  }

=head1 Description

This document covers the output filtering capabilities of
L<SVN::Notify|SVN::Notify>. Output filters are simply subroutines that modify
content before SVN::Notify outputs it. The idea is to provide a simple
interface for anyone to use to change the format of the messages that
SVN::Notify creates. Filters are loaded by the C<filter> parameter to C<new()>
or by the C<--filter> option to the C<svnnotify> command-line program.

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
      return $lines unless $notify->content_type eq 'text/html';
      return [ Text::Markdown->new->markdown( join $/, @$lines ) ];
  }

Put this code in a file named F<SVN/Notify/Filter/Markdown.pm> somewhere in
your Perl's path. The way that SVN::Notify filters work is that you simply
define a subroutine named for what you want to filter. The subroutine's first
argument will always be the SVN::Notify object that's generating the
notification message, and the second argument will always be the content to be
filtered.

In this example, we wanted to filter the commit log message, so we just
defined a subroutine named C<log_message()> and, if the message will be HTML,
passed the lines of the commit message to L<Text::Markdown|Text::Markdown> to
format, returning a new array reference. And that's all there is to writing
SVN::Notify filters: Define a subroutine, process the second argument, and
return a data structure in the same format as that argument (usually an array
reference).

Now, to use this filter, just use the C<--filter> option:

  svnnotify -p "$1" -r "$2" --handler HTML --filter Markdown

SVN::Notify will assume that a filter option without "::" is in the
SVN::Notify::Filter name space, and will load it accordingly. If you instead
created your filter in some other name space, say C<My::Filter::Markdown>,
then you'd specify the full package name in the C<--filter> option:

  svnnotify -p "$1" -r "$2" --handler HTML --filter My::Filter::Markdown

And that's it! The filter modifies the contents of the log message before
SVN::Notify::HTML spits it out.

=head2 The Details

Writing SVN::Notify filters is easy. The name of each subroutine in a filter
module determines what content it filters. The filter subroutines take two
arguments: the SVN::Notify object that's creating the notification message,
and the content to be filtered. They should return the filtered content in the
same data structure as that in which it was passed. This makes it easy to
change the output of SVN::Notify without the hassle of subclassing or sending
patches to the maintainer.

The names of the filter subroutines and the types of their content arguments
and return values are as follows, in the order in which they execute:

  Sub Name     | Second Argument
  -------------+---------------------------------------------------------------
  pre_prepare  | undef
  recipients   | Array reference of email addresses.
  from         | String with sender address.
  subject      | String with the subject line.
  post_prepare | undef
  pre_execute  | undef
  headers      | Array reference of individual email headers lines.
  start_html   | An array of lines starting an SVN::Notify::HTML document.
  css          | An array of lines of CSS. Used only by SVN::Notify::HTML.
  start_body   | Array reference of lines at the start of the message body.
  metadata     | Array reference of lines of the metadata part of the message.
  log_message  | Array reference of lines of log message.
  file_lists   | Array reference of lines of file names. The first line will
               | be the type of change for the list, the next a simple line of
               | dashes, and each of the rest of the lines a file name.

  diff         | A file handle reference to the diff.
  end_body     | Array reference of lines at the end of the message body.
  post_execute | undef

Note that the data passed to the filters by SVN::Notify subclasses
(L<SVN::Notify::HTML|SVN::Notify::HTML> and
L<SVN::Notify::HTML::ColorDiff|SVN::Notify::HTML::ColorDiff>) may be in a
slightly different format than documented here. Consult the documentation for
the relevant methods in those classes for details.

There are four special filter subroutines that are called at the beginning and
at the end of the execution of the C<prepare()> and C<execute()> methods,
named C<pre_prepare>, C<post_prepare>, C<pre_execute>, and C<post_execute>. No
data is passed to them and their return values are ignored, but they are
included to enable callbacks at the points at which they execute. If, for
example, you wanted to set the value of the C<to> attribute before SVN::Notify
checks to make sure that there are recipients to whom to send an email, you'd
want to do so in a C<pre_prepare> filter.

The package name of the filter module can be anything you like; just pass it
via the C<filter> parameter, e.g., C<< filter => [ 'My::Filter' ] >> (or
C<--filter My::Filter> on the command-line). If, however, it's in the
C<SVN::Notify::Filter> name space, you can just pass the last bit as the
filter name, for example C<< filter => [ 'NoSpam' ] >> (or C<--filter NoSpam>
on the command-line) for C<SVN::Notify::Filter::NoSpam>.

The first argument to a filter subroutine is always the SVN::Notify object
that's generating the message to be delivered. This is so that you can access
its attributes for your own nefarious purposes in the filter, as in the L<first
example|"Map committers to senders"> below.

But more importantly -- and more hackerously -- you can add attributes to the
SVN::Notify class from your filters. Just call C<<
SVN::Notify->register_attributes >> to do so, as in the L<final
example|"Filter based on parameter"> below. below.

=head2 Examples

First, see the L<"Synopsis"> for an example that converts Textile-formatted
log messages to HTML, and L<"A Quick Example"> for a filter that converts a
Markdown-formatted log message to HTML. If you format your log messages for
Trac, just use the included
L<SVN::Notify::Filter::Trac|SVN::Notify::Filter::Trac> filter. There is
also L<SVN::Notify::Filter::Markdown|SVN::Notify::Filter::Markdown> on CPAN,
and maybe other filters as well.

But if you can't find anything that does what you want, here are some examples
to get you started writing your own filters:

=over

=item * Map committers to senders

Map committer user names to email addresses using a lookup table. The "from"
filter gets and returns a string representing the sender. Note how this
example makes use of the SVN::Notify object to get the username of the
committer:

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

This emulates C<add_header> to demonstrate header filtering. Maybe you have a
special header that tells your spam filtering service to skip filtering for
certain messages (not a good idea, but what the hell?):

  package SVN::Notify::Filter::NoSpam;
  sub headers {
      my ($notifier, $headers) = @_;
      push @$headers, 'X-NotSpam: true';
      return $headers;
  }

=item * Uppercase meta data labels

Change the format of the commit meta data section of the message to uppercase
all of the headers, so that "Revision: 111" becomes "REVISION: 111":

Note that this example also makes use of the C<content_type()> method of
SVN::Notify to determine whether or not to actually do the filtering. This
prevents it from being applied to HTML messages, where it likely wouldn't be
able to do much.

  package SVN::Notify::Filter::UpLabels;
  sub metadata {
      my ($notifier, $lines) = @_;
      return $lines unless $notify->content_type eq 'text/plain';
      s/([^:]+:)/uc $1/eg for @$lines;
      return $lines;
  }

=item * Wrap your log message

Log message filtering will probably be quite common, generally to reformat it
(see, for example, the included
L<SVN::Notify::Filter::Trac|SVN::Notify::Filter::Trac> filter, as well as
L<SVN::Notify::Filter::Markdown|SVN::Notify::Filter::Markdown> on CPAN). If
the Markdown and Textile examples above are more than you need, here's a
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
and outputting each in turn so as to avoid loading the entire diff into
memory. To retain this pattern, the best approach is to tie the file handle to
a class that does the filtering one line at a time. The requisite C<tie> class
needs only three methods: C<TIEHANDLE> C<READLINE>, and C<CLOSE>. In this
example, I've defined them in a different name space than the filter
subroutine, so as to simplify SVN::Notify's loading of filters and to keep
thing neatly packaged. Note that this filter is applied before
SVN::Notify::HTML outputs its diff, so you can modify things before they get
marked up by, say, SVN::Notify::HTML::ColorDiff.

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

However, if you don't mind loading the entire diff into memory (because you
just I<know> that all of your commits are small [you know that's not true,
right?]), you can simplify things by using a data structure and an existing IO
module to do the same thing:

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

=item * Filter based on parameter

You can also add attributes (and therefor command-line options) to SVN::Notify
in your filter in order to alter its behavior. This is precisely what the
included L<SVN::Notify::Filter::Trac|SVN::Notify::Filter::Trac> module does:
it adds a new attribute, C<trac_url()>, so that it can create the proper Trac
links in your commit messages. See the documentation for
L<register_attributes()|SVN::Notify/"register_attributes"> for details on its
arguments mapping attribute names to L<Getopt::Long|Getopt::Long> rules.

Note that this example also makes use of the C<content_type()> method of
SVN::Notify to determine whether or not to actually do the filtering. This
prevents it from inadvertently converting the log file to HTML in plain text
messages, such as those sent by default by SVN::Notify, or the plain text part
sent by L<SVN::Notify::Alternative|SVN::Notify::Alternative>.

  package SVN::Notify::Filter::Trac;

  SVN::Notify->register_attributes( trac_url => 'trac-url=s' );

  sub log_message {
      my ($notify, $lines) = @_;
      return $lines unless $notify->content_type eq 'text/html';
      my $trac = Text::Trac->new( trac_url => $notify->trac_url );
      return [ $trac->parse( join $/, @{ $lines } ) ];
  }

=back

=head1 Contributing Filters

I created the filtering feature of SVN::Notify in the hopes that all those
folks who want new features for SVN::Notify will stop asking me for them and
instead start writing them themselves. I should have thought to do it a long
time ago, because, in truth, about half the features of SVN::Notify could have
been implemented as filters (maybe more than half).

So by all means write your filters for SVN::Notify. If you've think you've got
a really good one, or a filter that others will find useful, please B<do not
send it to me.> A better option is to package it up and put it on the CPAN. Go
ahead! Take an example from this document, if you want, put it in a module,
write a few tests, and upload the distribution. Model your distribution on
L<SVN::Notify::Filter::Markdown|SVN::Notify::Filter::Markdown>, which is
already separately distributed on CPAN. Let's create a mini-ecosystem of
SVN::Notify filters, all available via CPAN. That way, lots of people can take
advantage of them, new "features" can be added on a regular basis, and I don't
have to keep adding cruft to SVN::Notify itself!

=head1 See Also

=over

=item L<SVN::Notify|SVN::Notify>

The class that makes this stuff all work.

=item L<SVN::Notify::HTML|SVN::Notify::HTML>

The SVN::Notify class that likely will be most often used when filtering
messages. Check its documentation for variations on filter handling from
SVN::Notify.

=item L<SVN::Notify::Filter::Trac|SVN::Notify::Filter::Trac>

Filters log messages to convert them from Trac wiki format to HTML. Also
demonstrates the ability to add attributes to SVN::Notify (and options to
F<svnnotify> for added functionality of the filter.

=item L<SVN::Notify::Filter::Markdown|SVN::Notify::Filter::Markdown>

A separate CPAN distribution that filters log messages to convert them from
Markdown format to HTML. Check it out to get an idea how to create your own
filter distributions on CPAN.

=back

=head1 Author

David E. Wheeler <david@justatheory.com>

=head1 Copyright and License

Copyright (c) 2008-2011 David E. Wheeler. Some Rights Reserved.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
