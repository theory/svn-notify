package SVN::Notify;

# $Id$

use strict;
$SVN::Notify::VERSION = '2.0';

# This hash will be used in several of the functions below.
my %map = ( U => 'Modified Files',
            A => 'Added Files',
            D => 'Removed Files',
            _ => 'Property Changed');

sub new {
    my ($class, %opts) = @_;
    return bless \%opts, $class;
}

##############################################################################

sub prepare {
    my $self = shift;
    $self->prepare_recipients;
    return $self unless $self->{to};
    $self->prepare_contents;
    $self->prepare_subject;
    $self->prepare_files;
}

##############################################################################

sub prepare_recipients {
    my $self = shift;
    return $self unless $self->{regex} || $self->{cx};
    my @to = $self->{to} ? ($self->{to}) : ();
    if (my $regexen = $self->{regex}) {
        for (values %$regexen) {
            # Remove initial slash and compile.
            s|^\^[/\\]|^|;
            $_ = qr/$_/;
        }
    }

    my ($len, $cx);
    my $fh = $self->_pipe($self->{svnlook}, 'dirs-changed', $self->{path},
                          '-r', $self->{rev});

    # Read in a list of the directories changed.
    while (<$fh>) {
        while (my ($email, $rx) = each %{$self->{regex}}) {
            # If the directory matches the regex, save the email.
            if (/$rx/) {
                push @to, $email;
                delete $self->{regex}{$email};
            }
        }
        # Grab the context if it's needed for the subject.
        if ($self->{cx}) {
            my $l = length;
            ($len, $cx) = ($l, $_) unless defined $len && $len < $l;
        }
    }
    $self->{to} = join ', ', @to;
    $self->{cx} = $cx;
    return $self;
}

##############################################################################

sub prepare_files {
    my $self = shift;
    my %files;
    my $fh = $self->_pipe($self->{svnlook}, 'changed', $self->{path},
                          '-r', $self->{rev});

    # Read in a list of changed files.
    while (<$fh>) {
        s/[\n\r]+$//;
        push @{$files{$1}}, $_ if s/^(.).\s+//;
    }

    if ($self->{cx} && keys %files == 1) {
        # There's only one file; it's the context.
        $self->{cx} = (values %files)[0]->[0];
    }
    $self->{files} = \%files;
    return $self;
}

##############################################################################
# This function builds an email subject. The subject may have a prefix defined
# but --subject-prefix, it has the revision number, it might have the context
# if --subject-cx is true, and it will have the first line of the commit. The
# subject may then be truncated to the maximum length specified by
# --max-sub-length.
##############################################################################

sub prepare_subject {
    my $self = shift;

    # Start with the optional message and revision number..
    $self->{subject} .= (defined $self->{subject} ?  ' ' : '')
      . "[$self->{rev}] ";

    # Add the context if there is one.
    $self->{subject} .= "$self->{cx} " if $self->{cx};

    # Truncate to first period after a minimum of 10 characters.
    my $i = index $self->{message}[0], '. ';
    $self->{subject} .= $i > 0
      ? substr($self->{message}[0], 0, $i + 1)
      : $self->{message}[0];

    # Truncate to the last word under 72 characters.
    $self->{subject} =~ s/^(.{0,$self->{sublength}}\s+).*$/$1/m
      if $self->{sublength} && length $self->{subject} > $self->{sublength};
    return $self;
}

##############################################################################

sub prepare_contents {
    my $self = shift;
    my $lines = $self->_read_pipe($self->{svnlook}, 'info', $self->{path},
                                  '-r', $self->{rev});
    $self->{user} = shift @$lines;
    $self->{date} = shift @$lines;
    $self->{message_size} = shift @$lines;
    $self->{message} = $lines;

    # Set up the from address.
    unless ($self->{from}) {
        $self->{from} = $self->{user}
          . ($self->{domain} ? "@$self->{domain}" : '');
    }
    return $self;
}

##############################################################################

sub notify {
    my $self = shift;
    return $self unless $self->{to};
    open(SENDMAIL, "|$self->{sendmail} -oi -t")
      or mydie("Cannot fork for $self->{sendmail}: $!\n");
    # Output the headers.
    print SENDMAIL
      "MIME-Version: 1.0\n",
      "From: $self->{from}\n",
      "To: $self->{to}\n",
      "Subject: $self->{subject}\n";
    print SENDMAIL "Reply-To: $self->{replyto}\n" if $self->{replyto};
    print SENDMAIL "X-Mailer: " . ref($self) . " " . $self->VERSION .
                   ", http://search.cpan.org/dist/activitymail/\n";

    # Determine the content-type.
    my $ctype = $self->{format} eq 'text'
      ? 'text/plain'
      :  "text/$self->{format}";

    # Output the content type.
    if ($self->{attach}) {
        # We need a boundary string.
        my $salt = join '',
          ('.', '/', 0..9, 'A'..'Z', 'a'..'z')[rand 64, rand 64];
        $self->{attach} = crypt($self->{subject}, $salt);
        print SENDMAIL
          qq{Content-Type: multipart/mixed; boundary="$self->{attach}"\n\n}
          . "--$self->{attach}\nContent-Type: $ctype\n";
    } else {
        # Just output a content-type header.
        print SENDMAIL "Content-Type: $ctype\n\n";
    }

    # Output the message.
    my $method = "output_as_$self->{format}";
    $self->$method(\*SENDMAIL);

    print SENDMAIL "--$self->{attach}--\n" if $self->{attach};
    close SENDMAIL;
}

sub output_as_text {
    my ($self, $out) = @_;
    print $out "Log Message:\n-----------\n",
      join("\n", @{$self->{message}}), "\n";

    # Create the lines that will go underneath the above in the message.
    my %dash = ( map { $_ => '-' x length($map{$_}) } keys %map );

    my $files = $self->{files} or return $self;
    foreach my $type (qw(U A D _)) {
        # Skip it if there's nothing to report.
        next unless @{ $files->{$type} };

        # Identify the action.
        print $out "\n$map{$type}:\n$dash{$type}\n";
        print $out "    $_\n" for @{ $files->{$type} };
    }
    return $self;
}

##############################################################################
# This function gets a list of all the files affected by the commit, and
# stores them in array references in a hash, where the hash keys identify
# the type of change to the file: Add, Delete, or Updated.
##############################################################################

##############################################################################
# This function forks off a process to execute an external program and any
# associated arguments and returns an array reference of the lines output by
# the program. It also safely strips out and replaces any newlines and
# carriage returns.
##############################################################################

##############################################################################

sub _read_pipe {
    my $self = shift;
    my $fh = $self->_pipe(@_);
    local $/; my @lines = split /[\r\n]+/, <$fh>;
    close $fh;
    return \@lines;
}

##############################################################################

sub _pipe {
    my $self = shift;

    # Safer version of backtick (see perlipc(1)).
    my $pid = open(PIPE, '-|');
    mydie("Cannot fork: $!") unless defined $pid;

    if ($pid) {
        # Parent process. Return the file handle.
        return \*PIPE;
    } else {
        # Child process. Execute the commands.
        exec(@_) or mydie("Can't exec $_[0]: $!");
        # Not reached.
    }
}

##############################################################################
# This function takes an error message for its argument, prints it, and exits.
# The reason it's a separate function is that it prepends a string to the
# error message so that it'll stand out during commits, and so that the
# program won't actually die. XXX But don't we want it to die with SVN?
##############################################################################

sub mydie { print "######## activitymail error: $_[0]"; exit }

##############################################################################
# This function prints debug messages. The reason it's a separate function is
# that it prepends a string to the message so that it'll stand out during
# commits.
##############################################################################

sub dbpnt { print "\n" if $_[1]; print "@@@@@@@@ activitymail debug: $_[0]" }

=head1 Name

SVN::Notify - Subversion activity notification

=head1 Synopsis



=head1 Description



=head1 Bugs

Report all bugs via the CPAN Request Tracker at
L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=SVN-Notify>.

=head1 Author

David Wheeler <david@kineticode.com>

=head1 Copyright and License

Copyright (c) 2004 Kineticode, Inc. All Rights Reserved.

This module is free software; you can redistribute it and/or modify it under the
same terms as Perl itself.

=cut

1;
__DATA__
