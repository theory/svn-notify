package SVN::Notify::Filter::Trac;

use strict;
use Text::Trac;
use SVN::Notify;

$SVN::Notify::Filter::Trac::VERSION = '2.84';

=begin comment

Fake out Test::Pod::Coverage.

=head3 log_message

=head3 css

=end comment

=cut

SVN::Notify->register_attributes( trac_url => 'trac-url=s' );

sub log_message {
    my ($notify, $lines) = @_;
    return $lines unless $notify->content_type eq 'text/html';
    my $trac = Text::Trac->new( trac_url => $notify->trac_url );
    my $msg = join $/, @{ $lines };
    $msg =~ s/^\n+//g;
    $msg =~ s/\n+$//g;
    return [ $trac->parse( $msg ) ];
}

sub css {
    my ($notify, $css)= @_;
    return $css unless $notify->content_type eq 'text/html';
    push @$css, (
        qq(#logmsg blockquote.citation { padding: 0; border: 0; border-left: solid 2px #b44; padding-left: .75em; background: transparent; }\n),
        qq(#logmsg blockquote.citation .citation { border-color: #4b4; }\n),
        qq(#logmsg blockquote.citation .citation .citation  { border-color: #44b; }\n),
        qq(#logmsg blockquote.citation .citation .citation .citation { border-color: #c55; }\n),
        qq(#logmsg ol.loweralpha { list-style-type: lower-alpha; }\n),
        qq(#logmsg ol.upperalpha { list-style-type: upper-alpha; }\n),
        qq(#logmsg ol.lowerroman { list-style-type: lower-roman; }\n),
        qq(#logmsg ol.upperroman { list-style-type: upper-roman; }\n),
        qq(#logmsg ol.arabic     { list-style-type: decimal; }\n),
    );
    return $css;
}

1;

=head1 Name

SVN::Notify::Filter::Trac - Filter SVN::Notify output in Trac format

=head1 Synopsis

Use F<svnnotify> in F<post-commit>:

  svnnotify --p "$1" --r "$2" --to you@example.com --handler HTML \
  --filter Trac --trac-url http://trac.example.com

Use the class in a custom script:

  use SVN::Notify;

  my $notifier = SVN::Notify->new(
      repos_path => $path,
      revision   => $rev,
      to         => 'you@example.com',
      handler    => 'HTML::ColorDiff',
      filters    => [ 'Trac' ],
      trac_url   => 'http://trac.example.com/',
  );
  $notifier->prepare;
  $notifier->execute;

=head1 Description

This module filters SVN::Notify log message output from Trac markup into HTML.
Essentially, this means that if you write your commit log messages using Trac
wiki markup and like to use L<SVN::Notify::HTML|SVN::Notify::HTML> or
L<SVN::Notify::HTML::ColorDiff|SVN::Notify::HTML::ColorDiff> to format your
commit notifications, you can use this filter to convert the Trac formatting
in the log message to HTML.

If you specify an extra argument, C<trac_url> (or the C<--trac-url> parameter
to C<svnnotify>), it will be used to generate Trac links for revision numbers
and the like in your log messages.

=head1 See Also

=over

=item L<SVN::Notify|SVN::Notify>

=item L<svnnotify|svnnotify>

=back

=head1 Author

David E. Wheeler <david@justatheory.com>

=head1 Copyright and License

Copyright (c) 2008-2011 David E. Wheeler. Some Rights Reserved.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
