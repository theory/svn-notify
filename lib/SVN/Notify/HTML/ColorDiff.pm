package SVN::Notify::HTML::ColorDiff;

# $Id$

use strict;
use HTML::Entities;
use SVN::Notify::HTML ();

$SVN::Notify::HTML::ColorDiff::VERSION = '2.21';
@SVN::Notify::HTML::ColorDiff::ISA = qw(SVN::Notify::HTML);

=head1 Name

SVN::Notify::HTML::ColorDiff - Subversion activity HTML notification with colorized diff

=head1 Synopsis

Use F<svnnotify> in F<post-commit>:

  svnnotify --repos-path "$1" --revision "$2" \
    --to developers@example.com --handler HTML::ColorDiff [options]

Use the class in a custom script:

  use SVN::Notify::HTML::ColorDiff;

  my $notifier = SVN::Notify::HTML::ColorDiff->new(%params);
  $notifier->prepare;
  $notifier->execute;

=head1 Description

This subclass of L<SVN::Notify::HTML|SVN::Notify::HTML> sends HTML formatted
email messages for Subversion activity, and if the C<with_diff> parameter is
specified (but not C<attach_diff>), then a pretty colorized version of the
diff will be included, rather than the plain text diff output by
SVN::Notify::HTML.

=head1 Usage

To use SVN::Notify::HTML::ColorDiff, simply follow the
L<instructions|SVN::Notify/Usage> in SVN::Notify, but when using F<svnnotify>,
specify C<--handler HTML::ColorDiff>.

=cut

##############################################################################

=head1 Instance Interface

=head2 Instance Methods

=head3 output_css

  $notifier->output_css($file_handle);

This method starts outputs the CSS for the HTML message. It overrides the
same method on SVN::Notify::HTML to add CSS for the colorized diff.

=cut

sub output_css {
    my ($self, $out) = @_;
    $self->SUPER::output_css($out);
    print $out
      qq(#patch .file h3 {padding: 0 10px;line-height:1.5em;),
        qq(margin:0;background:#ccffff;border-bottom:1px solid black;),
        qq(margin:0 0 10px 0;}\n),
      qq(#patch pre {padding:0;line-height:1.2em;),
        qq(margin:0;}\n),
      qq(#patch .diff {background:#eeeeee;padding: 0 0 10px 0;}\n),
      qq(#patch span {display:block;padding:0 10px;}\n),
      qq(#patch .file {border:1px solid black;margin:10px 0;}\n),
      qq(#patch .add {background:#ddffdd;}\n),
      qq(#patch .rem {background:#ffdddd;}\n),
      qq(#patch .lines, .info {color:#888888;background:#ffffff;}\n);
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
    $self->_dbpnt( "Outputting colorized HTML diff") if $self->{verbose} > 1;

    # Get the diff and output it.
    my $diff = $self->_pipe('-|', $self->{svnlook}, 'diff',
                            $self->{repos_path}, '-r', $self->{revision});

    my $in_div;
    my $in_span = '';
    print $out qq{</div>\n<div id="patch">\n<h3>Diff</h3>\n};
    while (my $line = <$diff>) {
        $line =~ s/[\n\r]+$//;
        next unless $line;
        if ($line =~ /^Modified: (.*)/) {
            my $file = encode_entities($1);
            # Dump line.
            <$diff>;

            # Get the revision numbers.
            my $before = <$diff>;
            chomp $before;
            my ($rev1) = $before =~ /\(rev (\d+)\)$/;
            my $after = <$diff>;
            chomp $after;
            my ($rev2) = $after =~ /\(rev (\d+)\)$/;

            # Output the headers.
            print $out "</span>" if $in_span;
            print $out "</pre></div>\n" if $in_div;
            print $out qq{<a id="$file"></a>\n<div class="file"><h3>$file},
              " ($rev1 => $rev2)</h3>\n";
            print $out qq{<pre class="diff">\n<span class="info">};
            $in_div = 1;
            print $out encode_entities($_), "\n" for ($before, $after);
            print $out "</span>";
            $in_span = '';
        } elsif ($line =~ /^\@\@/) {
            print $out "</span>" if $in_span;
            print $out qq{<span class="lines">}, encode_entities($line),
              "\n</span>";
            $in_span = '';
        } elsif ($line =~ /^([-+])/) {
            my $type = $1;
            if ($in_span eq $type) {
                print $out encode_entities($line), "\n";
            } else {
                my $class = $type eq '+' ? 'add' : 'rem';
                print $out "</span>" if $in_span;
                print $out qq{<span class="$class">}, encode_entities($line), "\n";
                $in_span = $type;
            }
        } else {
            if ($in_span eq 'cx') {
                print $out encode_entities($line), "\n";
            } else {
                print $out "</span>" if $in_span;
                print $out qq{<span class="cx">}, encode_entities($line), "\n";
                $in_span = 'cx';
            }
        }
    }
    print $out "</span>\n" if $in_span;
    print $out "</pre>\n</div>\n" if $in_div;
    print $out "</div>\n";

    close $diff or warn "Child process exited: $?\n";
    return $self;
}

1;
__END__

=head1 See Also

=over

=item L<SVN::Notify|SVN::Notify>

=item L<SVN::Notify::HTML|SVN::Notify::HTML>

=item CVSspam: L<http://www.badgers-in-foil.co.uk/projects/cvsspam/>

=back

=head1 To Do

=over

=item *

Add inline bolding just on the text that changed between two lines, like this:
L<http://www.badgers-in-foil.co.uk/projects/cvsspam/example.html>.

=item *

Add links to ToDo stuff to the top of the email, as pulled in from the
diff. This might be tricky, since the diff is currently output I<afte> the
message body.

=back

=head1

=head1 Author

David Wheeler <david@kineticode.com>

=head1 Copyright and License

Copyright (c) 2004 Kineticode, Inc. All Rights Reserved.

This module is free software; you can redistribute it and/or modify it under the
same terms as Perl itself.

=cut
