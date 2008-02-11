package SVN::Notify::Filter::Trac;

use strict;
#use Text::Trac;

sub filter_log_messge {
    my $notify = shift;
    [ Text::Trac->new->parse( join '', @{ +shift } )->html ]
}

1;
