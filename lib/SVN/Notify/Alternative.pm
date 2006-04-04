package SVN::Notify::Alternative;

use strict;
use SVN::Notify ();

$SVN::Notify::Alternative::VERSION = '1.0';
@SVN::Notify::Alternative::ISA = qw(SVN::Notify);

__PACKAGE__->register_attributes(
    alternatives  => 'alternative|alt=s@',
);

=head1 Name

SVN::Notify::Alternative - MIME multipart/alternative notification

=head1 Synopsis

Use F<svnnotify> in F<post-commit>:

  svnnotify --repos-path "$1" --revision "$2" \
    --to developers@example.com --handler Alternative [options]

For example:

  svnnotify --repos-path "$1" --revision "$2" \
    --to developers@example.com --handler Alternative \
    --alternative HTML::ColorDiff

Use the class in a custom script:

  use SVN::Notify::Alternative;

  my $notifier = SVN::Notify::Alternative->new(%params);
  $notifier->prepare;
  $notifier->execute;

=head1 Description

This subclass of L<SVN::Notify|SVN::Notify> sends MIME multipart/alternative
email messages for Subversion activitity. The messages contain both the
standard SVN::Notify plain text change notification and one or more
alternative formats of the message. The default alternative format is
L<HTML|SVN::Notify::HTML>.

Note that this means that many or all of the processing of a subversion commit
will be executed multiple times, once for the plain text version and then
again for each alternative version. This will therfore increase resource
usage on your Subversion server (mainly processor time, but also possibly memory).

It also means that the size of the outgoing message will increase for each
alternative. If you're using C<--with-diff>, then those messages could be very
large indeed for large commits. If, however, you use C<--attach-diff>, the
diff will only be attached to the last alternative.

=head1 Usage

To use SVN::Notify::Alternative, simply follow the
L<instructions|SVN::Notify/Usage> in SVN::Notify, but when using F<svnnotify>,
use the C<--alternative> option to add one or more alternative formats.

=cut

##############################################################################

=head1 Class Interface

=head2 Constructor

=head3 new

  my $notifier = SVN::Notify::Alternative->new(%params);

Constructs and returns a new SVN::Notify object. All parameters supported by
SVN::Notity are supported here, as are the options of all specified
alternative formats, but SVN::Notify::Alternative supports an additional
parameter:

=over

=item alternatives

  svnnotify --alternative HTML
  svnnotify --alt HTML --alt HTML::ColorDiff

An array reference that specifies the SVN::Notify handlers (subclasses) to be
used for formatting the alternative parts of the notification message. The
command-line option may be called as either C<--alternative> or C<--alt>, and
the value is the same as that of the SVN::Notify C<--handler> parameter, i.e.
the module name without the "SVN::Notify::" prefix. Specify the option
multiple times to specify multiple alternative handlers. Defaults to
C<['HTML']> if not specified.

=back

=cut

##############################################################################

=head1 Instance Interface

=head2 Instance Methods

=head3 output

  $notifier->output($file_handle);

Overrides the C<output()> method of SVN::Notify to replace the standard
message output with a MIME C<multipart/alternative> skeleton. It then creates
new instances of the standard SVN::Notify plain text formatter and each of the
configured alternative formatters, and uses those instances to fill in the
alternative parts of the message. If C<attach_diff> is true, it will be used
only in the last alternative to be output, which should also be the richest
format.

=cut

sub output {
    my ($self, $out) = @_;

    # Output the headers. Leave out the attachment header.
    my $attach = $self->attach_diff;
    if ($attach) {
        $self->attach_diff(undef);
        $self->with_diff(undef);
    }
    $self->output_headers($out);

    # Output the multipart/alternative header.
    my $salt = join '', ('.', '/', 0..9, 'A'..'Z', 'a'..'z')[rand 64, rand 64];
    my $bound = crypt $self->subject, $salt;
    print $out qq{Content-Type: multipart/alternative; boundary="$bound"\n},
                 "Content-Transfer-Encoding: 8bit\n\n";

    # Determine all of the handlers to use.
    my $alts = $self->{alternatives};
    $alts = ['HTML'] unless $alts;
    unshift @$alts, ''; # Plain text first.

    # Now output each of the alternatives.
    while (@$alts) {
        print $out "--$bound\n";
        # Attach diff only to last version.
        SVN::Notify->new(
            %$self,
            handler => shift @$alts,
            ($attach && !@$alts ? ( attach_diff => 1) : ()),
        )->output($out, 1);
    }

    # Finish up!
    print $out "--$bound--\n";
    return $self;
}

##############################################################################

=head2 Accessors

In addition to those supported by L<SVN::Notify|SVN::Notify/Accessors>,
SVN::Notify::Alternative supports the following accessors:

=head3 alternatives

  my $alts = $notify->alternatives;
  $notify->alternatives($alts);

Gets or sets the value of the C<alternatives> attribute, which must always be
set to an array reference.

=cut

1;
__END__

=head1 See Also

=over

=item L<SVN::Notify|SVN::Notify>

=back

=head1 Authors

Jukka Zitting <jz@yukatan.fi>

David Wheeler <david@kineticode.com>

=head1 Copyright and License

Copyright (c) 2005-2006 Jukka Zitting and Kineticode, Inc. All Rights Reserved.

This module is free software; you can redistribute it and/or modify it under the
same terms as Perl itself.

=cut
