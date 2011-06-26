package SVN::Notify::HTML::ColorDiff;

use strict;
use HTML::Entities;
use SVN::Notify::HTML ();

$SVN::Notify::HTML::ColorDiff::VERSION = '2.83';
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

This method starts outputs the CSS for the HTML message.
SVN::Notify::HTML::ColorDiff adds extra CSS to its output so that it can
nicely style the diff.

=cut

# We use _css() so that ColorDiff can override it and the filters then applied
# only one to all of the CSS.

##############################################################################

=head3 output_diff

  $notifier->output_diff($out_file_handle, $diff_file_handle);

Reads the diff data from C<$diff_file_handle> and prints it to
C<$out_file_handle> for inclusion in the notification message. The diff is
output with nice colorized HTML markup. Each line of the diff file is escaped
by C<HTML::Entities::encode_entities()>.

If there are any C<diff> filters, this method will do no HTML formatting, but
redispatch to L<SVN::Notify::output_diff|SVN::Notify/"output_diff">. See
L<Writing Output Filters|SVN::Notify/"Writing Output Filters"> for details on
filters.

=cut

my %types = (
    Modified => 'modfile',
    Added    => 'addfile',
    Deleted  => 'delfile',
    Copied   => 'copfile',
);

sub output_diff {
    my ($self, $out, $diff) = @_;
    if ( $self->filters_for('diff') ) {
        return $self->SUPER::output_diff($out, $diff);
    }
    $self->_dbpnt( "Outputting colorized HTML diff") if $self->verbose > 1;

    my $in_div;
    my $in_span = '';
    print $out qq{</div>\n<div id="patch">\n<h3>Diff</h3>\n};
    my ($length, %seen) = 0;
    my $max = $self->max_diff_length;

    while (my $line = <$diff>) {
        $line =~ s/[\n\r]+$//;
        next unless $line;
        if ( $max && ( $length += length $line ) >= $max ) {
            print $out "</$in_span>" if $in_span;
            print $out qq{<span class="lines">\@\@ Diff output truncated at $max characters. \@\@\n</span>};
            $in_span = '';
            last;
        } else {
            if ($line =~ /^(Modified|Added|Deleted|Copied): (.*)/) {
                my $class = $types{my $action = $1};
                ++$seen{$2};
                my $file = encode_entities($2, '<>&"');
                (my $id = $file) =~ s/[^\w_]//g;

                print $out "</$in_span>" if $in_span;
                print $out "</span></pre></div>\n" if $in_div;

                # Dump line, but check it's content.
                if (<$diff> !~ /^=/) {
                    # Looks like they used --no-diff-added or --no-diff-deleted.
                    ($in_span, $in_div) = '';
                    print $out qq{<a id="$id"></a>\n<div class="$class">},
                        qq{<h4>$action: $file</h4></div>\n};
                    next;
                }

                # Get the revision numbers.
                my $before = <$diff>;
                $before =~ s/[\n\r]+$//;

                if ($before =~ /^\(Binary files differ\)/) {
                    # Just output the whole file div.
                    print $out qq{<a id="$id"></a>\n<div class="binary"><h4>},
                      qq{$action: $file</h4>\n<pre class="diff"><span>\n},
                      qq{<span class="cx">$before\n</span></span></pre></div>\n};
                    ($in_span, $in_div) = '';
                    next;
                }

                my ($rev1) = $before =~ /\(rev (\d+)\)$/;
                my $after = <$diff>;
                $after =~ s/[\n\r]+$//;
                my ($rev2) = $after =~ /\(rev (\d+)\)$/;

                # Output the headers.
                print $out qq{<a id="$id"></a>\n<div class="$class"><h4>$action: $file},
                  " ($rev1 => $rev2)</h4>\n";
                print $out qq{<pre class="diff"><span>\n<span class="info">};
                $in_div = 1;
                print $out encode_entities($_, '<>&"'), "\n" for ($before, $after);
                print $out "</span>";
                $in_span = '';
            } elsif ($line =~ /^Property changes on: (.*)/ && !$seen{$1}) {
                # It's just property changes.
                my $file = encode_entities($1, '<>&"');
                (my $id = $file) =~ s/[^\w_]//g;
                # Dump line.
                <$diff>;

                # Output the headers.
                print $out "</$in_span>" if $in_span;
                print $out "</span></pre></div>\n" if $in_div;
                print $out qq{<a id="$id"></a>\n<div class="propset">},
                  qq{<h4>Property changes: $file</h4>\n<pre class="diff"><span>\n};
                $in_div = 1;
                $in_span = '';
            } elsif ($line =~ /^\@\@/) {
                print $out "</$in_span>" if $in_span;
                print $out (
                    qq{<span class="lines">},
                    encode_entities($line, '<>&"'),
                    "\n</span>",
                );
                $in_span = '';
            } elsif ($line =~ /^([-+])/) {
                my $type = $1 eq '+' ? 'ins' : 'del';
                if ($in_span eq $type) {
                    print $out encode_entities($line, '<>&"'), "\n";
                } else {
                    print $out "</$in_span>" if $in_span;
                    print $out (
                        qq{<$type>},
                        encode_entities($line, '<>&"'),
                        "\n",
                    );
                    $in_span = $type;
                }
            } else {
                if ($in_span eq 'cx') {
                    print $out encode_entities($line, '<>&"'), "\n";
                } else {
                    print $out "</$in_span>" if $in_span;
                    print $out (
                        qq{<span class="cx">},
                        encode_entities($line, '<>&"'),
                        "\n",
                    );
                    $in_span = 'span';
                }
            }
        }
    }
    print $out "</$in_span>" if $in_span;
    print $out "</span></pre>\n</div>\n" if $in_div;
    print $out "</div>\n";

    close $diff or warn "Child process exited: $?\n";
    return $self;
}

##############################################################################

sub _css {
    my $css = shift->SUPER::_css;
    push @$css,
        qq(#patch h4 {font-family: verdana,arial,helvetica,sans-serif;),
            qq(font-size:10pt;padding:8px;background:#369;color:#fff;),
            qq(margin:0;}\n),
        qq(#patch .propset h4, #patch .binary h4 {margin:0;}\n),
         qq(#patch pre {padding:0;line-height:1.2em;margin:0;}\n),
        qq(#patch .diff {width:100%;background:#eee;padding: 0 0 10px 0;),
            qq(overflow:auto;}\n),
        qq(#patch .propset .diff, #patch .binary .diff  {padding:10px 0;}\n),
        qq(#patch span {display:block;padding:0 10px;}\n),
        qq(#patch .modfile, #patch .addfile, #patch .delfile, #patch .propset, ),
            qq(#patch .binary, #patch .copfile {border:1px solid #ccc;),
            qq(margin:10px 0;}\n),
        qq(#patch ins {background:#dfd;text-decoration:none;display:block;),
            qq(padding:0 10px;}\n),
        qq(#patch del {background:#fdd;text-decoration:none;display:block;),
            qq(padding:0 10px;}\n),
        qq(#patch .lines, .info {color:#888;background:#fff;}\n);
    return $css;
}

1;
__END__

=head1 See Also

=over

=item L<SVN::Notify|SVN::Notify>

=item L<SVN::Notify::HTML|SVN::Notify::HTML>

=item L<CVSspam|http://www.badgers-in-foil.co.uk/projects/cvsspam/>

=back

=head1 To Do

=over

=item *

Add inline emphasis just on the text that changed between two lines, like
this: L<http://www.badgers-in-foil.co.uk/projects/cvsspam/example.html>.

=item *

Add links to To Do stuff to the top of the email, as pulled in from the diff.
This might be tricky, since the diff is currently output I<after> the message
body. Maybe use absolute positioning CSS?

=back

=head1

=head1 Author

David E. Wheeler <david@justatheory.com>

=head1 Copyright and License

Copyright (c) 2004-2011 David E. Wheeler. Some Rights Reserved.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
