package SVN::Notify::HTML;

# $Id$

use strict;
use HTML::Entities;
use SVN::Notify ();

$SVN::Notify::HTML::VERSION = '2.21';
@SVN::Notify::HTML::ISA = qw(SVN::Notify);

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
opening C<< <html> >>, C<< <head> >>, C<< <style> >>, and C<< <body> >> tags.

=cut

sub start_body {
    my ($self, $out) = @_;
    print $out qq{<html>\n<head><style type="text/css"><!--\n};
    $self->output_css($out);
    print $out qq{--></style>\n</head>\n<body>\n\n<div id="msg">\n};
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
      qq(body {background:#ffffff;font-family:Verdana,Helvetica,Arial,sans-serif;}\n),
      qq(h3 {margin:15px 0;padding:0;line-height:0;}\n),
      qq(#msg {margin: 0 0 2em 0;}\n),
      qq(#msg dl, #msg ul, #msg pre {padding:1em;border:1px dashed black;),
        qq(margin: 10px 0 30px 0;}\n),
      qq(#msg dl {background:#ccccff;}\n),
      qq(#msg pre {background:#ffffcc;}\n),
      qq(#msg ul {background:#cc99ff;list-style:none;}\n),
      qq(#msg dt {font-weight:bold;float:left;width: 6em;}\n),
      qq(#msg dt:after { content:':';}\n);
    return $self;
}

##############################################################################

=head3 output_metadata

  $notifier->output_metadata($file_handle);

This method outputs a definition list containting the metadata of the commit,
including the revision number, author (user), and date of the revision. If the
C<viewcvs_url> attribute has been set, then the appropriate URL for the
revision will be used to turn the revision number into a link.

=cut

sub output_metadata {
    my ($self, $out) = @_;
    print $out "<dl>\n<dt>Revision</dt> <dd>";

    if ($self->{viewcvs_url}) {
        # Make the revision number a URL.
        print $out qq{<a href="$self->{viewcvs_url}?rev=$self->{revision}},
          qq{&amp;view=rev">$self->{revision}</a>};
    } else {
        # Just output the revision number.
        print $out $self->{revision};
    }

    print $out "</dd>\n",
      "<dt>Author</dt> <dd>", encode_entities($self->{user}), "</dd>\n",
      "<dt>Date</dt> <dd>", encode_entities($self->{date}), "</dd>\n",
      "</dl>\n\n";

    return $self;
}

##############################################################################

=head3 output_log_message

  $notifier->output_log_message($file_handle);

Outputs the commit log message in C<< <pre> >> tags, and the label "Log
Message" in C<< <h3> >> tags.

=cut

sub output_log_message {
    my ($self, $out) = @_;
    $self->_dbpnt( "Outputting log message as HTML") if $self->{verbose} > 1;
    print $out "<body>\n<h3>Log Message</h3>\n<pre>",
      HTML::Entities::encode_entities(join("\n", @{$self->{message}})),
      "</pre>\n\n";
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
    my $files = $self->{files} or return $self;
    my $map = $self->file_label_map;
    # Create the lines that will go underneath the above in the message.
    my %dash = ( map { $_ => '-' x length($map->{$_}) } keys %$map );

    foreach my $type (qw(U A D _)) {
        # Skip it if there's nothing to report.
        next unless $files->{$type};

        # Identify the action and output each file.
        print $out "<h3>$map->{$type}</h3>\n<ul>\n";
        if ($self->{with_diff} && !$self->{attach_diff} && $type ne '_') {
            for (@{ $files->{$type} }) {
                my $file = encode_entities($_);
                print $out qq{<li><a href="#$file">$file</a></li>\n};
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
    $self->_dbpnt( "Ending body") if $self->{verbose} > 2;
    print $out "\n</div>" unless $self->{with_diff} && !$self->{attach_diff};
    print $out "\n</body>\n</html>\n";
    return $self;
}

##############################################################################

=head3 output_diff

  $notifier->output_diff($file_handle);

Sends the output of C<svnlook diff> to the specified file handle for inclusion
in the notification message. The diff is output between C<< <pre> >> tags, and
Each line of the diff file is escaped by C<HTML::Entities::encode_entities>.

=cut

sub output_diff {
    my ($self, $out) = @_;
    $self->_dbpnt( "Outputting HTML diff") if $self->{verbose} > 1;

    # Get the diff and output it.
    my $diff = $self->_pipe('-|', $self->{svnlook}, 'diff',
                            $self->{repos_path}, '-r', $self->{revision});

    print $out qq{</div>\n<div id="patch"><pre>\n};
    while (<$diff>) {
        s/[\n\r]+$//;
        if (/^Modified: (.*)/) {
            my $f = encode_entities($1);
            print $out qq{<a id="$f">Modified: $f</a>\n"};
        }
        print $out encode_entities($_), "\n";
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

=head1 To Do

=over

=item *

Add support for Bugzilla, RT, and Jira links, so that text in the log message that
looks like it refers to them will link to them.

=item *

Turn email addresses and URLs in the log message into actual links.

=back

=head1 Author

David Wheeler <david@kineticode.com>

=head1 Copyright and License

Copyright (c) 2004 Kineticode, Inc. All Rights Reserved.

This module is free software; you can redistribute it and/or modify it under the
same terms as Perl itself.

=cut
