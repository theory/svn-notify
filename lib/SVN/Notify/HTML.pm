package SVN::Notify::HTML;

# $Id$

use strict;
use HTML::Entities;
use SVN::Notify ();

$SVN::Notify::HTML::VERSION = '2.50';
@SVN::Notify::HTML::ISA = qw(SVN::Notify);

__PACKAGE__->register_attributes(
    linkize      => 'linkize',
);

=head1 Name

SVN::Notify::HTML - Subversion activity HTML notification

=head1 Synopsis

Use F<svnnotify> in F<post-commit>:

  svnnotify --repos-path "$1" --revision "$2" \
    --to developers@example.com --handler HTML [options]

Use the class in a custom script:

  use SVN::Notify::HTML;

  my $notifier = SVN::Notify::HTML->new(%params);
  $notifier->prepare;
  $notifier->execute;

=head1 Description

This subclass of L<SVN::Notify|SVN::Notify> sends HTML formatted email
messages for Subversion activity, rather than the default plain text.

=head1 Prerequisites

In addition to the modules required by SVN::Notify, this class requires:

=over

=item HTML::Entities

=back

=head1 Usage

To use SVN::Notify::HTML, simply follow the L<instructions|SVN::Notify/Usage>
in SVN::Notify, but when using F<svnnotify>, specify C<--handler HTML>.

=cut

##############################################################################

=head1 Class Interface

=head2 Constructor

=head3 new

=head3 new

  my $notifier = SVN::Notify->new(%params);

Constructs and returns a new SVN::Notify object. All parameters supported by
SVN::Notity are supported here, but SVN::Notify::HTML supports a few
additional parameters:

=over

=item linkize

  svnnotify --linkize

A boolean attribute to specify whether or not to "linkize" the SVN log
message--that is, to turn any URLs or email addresses in the log message into
links.

=item ticket_regex

  svnnotify --ticket-regex '\[?\s*(Ticket\s*#\s*(\d+))\s*\]?'

This attribute is inherited from L<SVN::Notify|SVN::Notify>, but its semantics
are slightly different: it should return I<two> matches instead of one: the
text to linkify and the ticket ID itself. The example shown matches
("[Ticket#1234]", "1234") or ("[ Ticket # 1234 ]", "1234"). Make your regex as
specific as possible, preferably wrapped in "\b" tags and the like.

=back

=cut

##############################################################################

=head2 Class Methods

=head3 content_type

Returns the content type of the notification message, "text/html". Used to set
the Content-Type header for the message.

=cut

sub content_type { 'text/html' }

##############################################################################

=head1 Instance Interface

=head2 Instance Methods

=head3 start_body

  $notifier->start_body($file_handle);

This method starts the body of the notification message. It outputs the
opening C<< <html> >>, C<< <head> >>, C<< <style> >>, and C<< <body> >>
tags. Note that if the C<language> attribute is set to a value, it will be
specified in the C<< <html> >> tag.

=cut

sub start_body {
    my ($self, $out) = @_;
    my $lang = $self->language;
    print $out qq{<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN"\n},
      qq{"http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">\n},
      qq{<html xmlns="http://www.w3.org/1999/xhtml"},
        ($lang ? qq{ xml:lang="$lang"} : ()),
      qq{>\n<head><style type="text/css"><!--\n};
    $self->output_css($out);
    print $out qq{--></style>\n<title>}, encode_entities($self->subject),
      qq{</title>\n</head>\n<body>\n\n<div id="msg">\n};
    return $self;
}

##############################################################################

=head3 output_css

  $notifier->output_css($file_handle);

This method starts outputs the CSS for the HTML message. It is called by
C<start_body()>, and which wraps the output of C<output_css()> in the
appropriate C<< <style> >> tags.

=cut

sub output_css {
    my ($self, $out) = @_;
    print $out
      qq(#msg dl { border: 1px #006 solid; background: #369; ),
        qq(padding: 6px; color: #fff; }\n),
      qq(#msg dt { float: left; width: 6em; font-weight: bold; }\n),
      qq(#msg dt:after { content:':';}\n),
      qq(#msg dl, #msg dt, #msg ul, #msg li { font-family: ),
          qq(verdana,arial,helvetica,sans-serif; font-size: 10pt;  }\n),
      qq(#msg dl a { font-weight: bold}\n),
      qq(#msg dl a:link    { color:#fc3; }\n),
      qq(#msg dl a:active  { color:#ff0; }\n),
      qq(#msg dl a:visited { color:#cc6; }\n),
      qq(h3 { font-family: verdana,arial,helvetica,sans-serif; ),
          qq(font-size: 10pt; font-weight: bold; }\n),
      qq(#msg pre { overflow: auto; background: #ffc; ),
          qq(border: 1px #fc0 solid; padding: 6px; }\n),
      qq(#msg ul, pre { overflow: auto; }\n),
      qq(#patch { width: 100%; }\n);
    return $self;
}

##############################################################################

=head3 output_metadata

  $notifier->output_metadata($file_handle);

This method outputs a definition list containting the metadata of the commit,
including the revision number, author (user), and date of the revision. If the
C<svnweb_url> or C<viewcvs_url> attribute has been set, then the appropriate
URL for the revision will be used to turn the revision number into a link.

=cut

sub output_metadata {
    my ($self, $out) = @_;
    print $out "<dl>\n<dt>Revision</dt> <dd>";

    my $rev = $self->revision;
    if (my $url = $self->svnweb_url || $self->viewcvs_url) {
        $url = encode_entities($url);
        # Make the revision number a URL.
        printf $out qq{<a href="$url">$rev</a>}, $rev;
    } else {
        # Just output the revision number.
        print $out $rev;
    }

    print $out "</dd>\n",
      "<dt>Author</dt> <dd>", encode_entities($self->user), "</dd>\n",
      "<dt>Date</dt> <dd>", encode_entities($self->date), "</dd>\n",
      "</dl>\n\n";

    return $self;
}

##############################################################################

=head3 output_log_message

  $notifier->output_log_message($file_handle);

Outputs the commit log message in C<< <pre> >> tags, and the label "Log
Message" in C<< <h3> >> tags. If the C<bugzilla_url> attribute is set, then
any strings like "Bug 2" or "bug # 567" will be turned into links.

=cut

sub output_log_message {
    my ($self, $out) = @_;
    $self->_dbpnt( "Outputting log message as HTML") if $self->verbose > 1;

    # Assemble the message.
    my $msg = encode_entities(join("\n", @{$self->message}));

    # Turn URLs and email addresses into links.
    if ($self->linkize) {
        # These regular expressions modified from "Mastering Regular
        # Expressions" 2ed., pp 70-75.

        # Make email links.
        $msg =~ s{\b(\w[-.\w]*\@[-a-z0-9]+(?:\.[-a-z0-9]+)*\.[-a-z0-9]+)\b}
          {<a href="mailto:$1">$1</a>}gi;

        # Make URLs linkable.
        $msg =~ s{\b([a-z0-9]+://[-a-z0-9]+(?:\.[-a-z0-9]+)*\.[-a-z0-9]+\b(?:/(?:[-a-z0-9_:\@?=+,.!/~*I'%\$]|&amp;)*(?<![.,?!]))?)}
          {<a href="$1">$1</a>}gi;

    }

    # Make SVNWeb/ViewCVS links.
    if (my $url = $self->svnweb_url || $self->viewcvs_url) {
        $url = encode_entities($url);
        $msg =~ s|\b(rev(?:ision)?\s*#?\s*(\d+))\b|sprintf qq{<a href="$url">$1</a>}, $2|ige;
    }

    # Make Bugzilla links.
    if (my $url = $self->bugzilla_url) {
        $url = encode_entities($url);
        $msg =~ s|\b(bug\s*#?\s*(\d+))\b|sprintf qq{<a href="$url">$1</a>}, $2|ige;
    }

    # Make RT links.
    if (my $url = $self->rt_url) {
        $url = encode_entities($url);
        $msg =~ s|\b((?:rt-)?ticket:?\s*#?\s*(\d+))\b|sprintf qq{<a href="$url">$1</a>}, $2|ige;
    }

    # Make JIRA links.
    if (my $url = $self->jira_url) {
        $url = encode_entities($url);
        $msg =~ s|\b([A-Z]+-\d+)\b|sprintf qq{<a href="$url">$1</a>}, $1|ge;
    }

    # Make GNATS links.
    if (my $url = $self->gnats_url) {
        $url = encode_entities($url);
        $msg =~ s|\b(PR\s*(\d+))\b|sprintf qq{<a href="$url">$1</a>}, $2|ge;
    }

    # Make custom ticketing system links.
    if (my $url = $self->ticket_url) {
        my $regex = $self->ticket_regex
            or die q{Missing "ticket_regex" parameter to accompany }
            . q{"ticket_url" parameter};
        $url = encode_entities($url);
        $msg =~ s|$regex|sprintf qq{<a href="$url">$1</a>}, $2|ige;
    }

    else {
        die q{Missing "ticket_url" parameter to accompany }
            . q{"ticket_regex" parameter}
            if $self->ticket_regex;
    }

    # Print it out and return.
    print $out "<h3>Log Message</h3>\n<pre>$msg</pre>\n\n";
    return $self;
}

##############################################################################

=head3 output_file_lists

  $notifier->output_log_message($file_handle);

Outputs the lists of modified, added, deleted, files, as well as the list of
files for which properties were changed as unordered lists. The labels used
for each group are pulled in from the C<file_label_map()> class method and
output in C<< <h3> >> tags.

=cut

sub output_file_lists {
    my ($self, $out) = @_;
    my $files = $self->files or return $self;
    my $map = $self->file_label_map;
    # Create the lines that will go underneath the above in the message.
    my %dash = ( map { $_ => '-' x length($map->{$_}) } keys %$map );

    foreach my $type (qw(U A D _)) {
        # Skip it if there's nothing to report.
        next unless $files->{$type};

        # Identify the action and output each file.
        print $out "<h3>$map->{$type}</h3>\n<ul>\n";
        if ($self->with_diff && !$self->attach_diff) {
            for (@{ $files->{$type} }) {
                my $file = encode_entities($_);
                if ($file =~ m{/$}) {
                    # Directories don't link to the diff.
                    print $out qq{<li>$file</li>\n};
                } else {
                    # Strip out letters illegal for IDs.
                    (my $id = $file) =~ s/[^\w_]//g;
                    print $out qq{<li><a href="#$id">$file</a></li>\n};
                }
            }
        } else {
            print $out "  <li>" . encode_entities($_) . "</li>\n"
              for @{ $files->{$type} };
        }
        print $out "</ul>\n\n";
    }
}

##############################################################################

=head3 end_body

  $notifier->end_body($file_handle);

Closes out the body of the email by outputting the closing C<< </body> >> and
C<< </html> >> tags. Designed to be called when the body of the message is
complete, and before any call to C<output_attached_diff()>.

=cut

sub end_body {
    my ($self, $out) = @_;
    $self->_dbpnt( "Ending body") if $self->verbose > 2;
    print $out "\n</div>" unless $self->with_diff && !$self->attach_diff;
    print $out "\n</body>\n</html>\n";
    return $self;
}

##############################################################################

=head3 output_diff

  $notifier->output_diff($out_file_handle, $diff_file_handle);

Sends the output of C<svnlook diff> to the specified file handle for inclusion
in the notification message. The diff is output between C<< <pre> >> tags, and
Each line of the diff file is escaped by C<HTML::Entities::encode_entities()>.
The diff data will be read from C<$diff_file_handle> and printed to
C<$out_file_handle>.

=cut

sub output_diff {
    my ($self, $out, $diff) = @_;
    $self->_dbpnt( "Outputting HTML diff") if $self->verbose > 1;

    print $out qq{</div>\n<div id="patch"><pre>\n};
    my %seen;
    while (<$diff>) {
        s/[\n\r]+$//;
        if (/^(Modified|Added|Deleted|Copied|Property changes on): (.*)/
            && !$seen{$2}++)
        {
            my $action = $1;
            my $file = encode_entities($2);
            (my $id = $file) =~ s/[^\w_]//g;
            print $out qq{<a id="$id">$action: $file</a>\n};
        }
        else {
            print $out encode_entities($_), "\n";
        }
    }
    print $out "</pre></div>\n";

    close $diff or warn "Child process exited: $?\n";
    return $self;
}

1;
__END__

=head1 See Also

=over

=item L<SVN::Notify|SVN::Notify>

=back

=head1 Author

David Wheeler <david@kineticode.com>

=head1 Copyright and License

Copyright (c) 2004-2005 Kineticode, Inc. All Rights Reserved.

This module is free software; you can redistribute it and/or modify it under the
same terms as Perl itself.

=cut
