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
    $opts{svnlook} ||= 'svnlook';
    $opts{sendmail} ||= 'sendmail';
    $opts{format} ||= 'text';
    $opts{with_diff} ||= $opts{attach_diff};
    $opts{viewcvs_url} .= '/'
      if $opts{viewcvs_url} && $opts{viewcvs_url} !~ m{/$};
    return bless \%opts, $class;
}

##############################################################################

sub prepare {
    my $self = shift;
    $self->prepare_recipients;
    return $self unless $self->{to};
    $self->prepare_contents;
    $self->prepare_files;
    $self->prepare_subject;
}

##############################################################################

sub prepare_recipients {
    my $self = shift;
    return $self unless $self->{to_regex_map} || $self->{subject_cx};
    my @to = $self->{to} ? ($self->{to}) : ();
    my $regexen = delete $self->{to_regex_map};
    if ($regexen) {
        for (values %$regexen) {
            # Remove initial slash and compile.
            s|^\^[/\\]|^|;
            $_ = qr/$_/;
        }
    } else {
        $regexen = {};
    }

    my ($len, $cx);
    my $fh = $self->_pipe($self->{svnlook}, 'dirs-changed', $self->{repos_path},
                          '-r', $self->{revision});

    # Read in a list of the directories changed.
    while (<$fh>) {
        s/[\n\r\/\\]+$//;
        while (my ($email, $rx) = each %$regexen) {
            # If the directory matches the regex, save the email.
            if (/$rx/) {
                push @to, $email;
                delete $regexen->{$email};
            }
        }
        # Grab the context if it's needed for the subject.
        if ($self->{subject_cx}) {
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
    my $fh = $self->_pipe($self->{svnlook}, 'changed', $self->{repos_path},
                          '-r', $self->{revision});

    # Read in a list of changed files.
    my $cx = $_ = <$fh>;
    do {
        s/[\n\r]+$//;
        if (s/^(.)(.)\s+//) {
            push @{$files{$1}}, $_;
            push @{$files{_}}, $_ if $2 ne ' ' && $1 ne '_';
        }
    } while (<$fh>);

    if ($self->{subject_cx} && $. == 1) {
        # There's only one file; it's the context.
        $cx =~ s/[\n\r]+$//;
        ($self->{cx} = $cx) =~ s/^..\s+//;
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
    $self->{subject} .=
      (defined $self->{subject_prefix} ?  "$self->{subject_prefix} " : '')
      . "[$self->{revision}] ";

    # Add the context if there is one.
    $self->{subject} .= "$self->{cx}: " if $self->{cx};

    # Truncate to first period after a minimum of 10 characters.
    my $i = index $self->{message}[0], '. ';
    $self->{subject} .= $i > 0
      ? substr($self->{message}[0], 0, $i + 1)
      : $self->{message}[0];

    # Truncate to the last word under 72 characters.
    $self->{subject} =~ s/^(.{0,$self->{max_sub_length}})\s+.*$/$1/m
      if $self->{max_sub_length}
      && length $self->{subject} > $self->{max_sub_length};
    return $self;
}

##############################################################################

sub prepare_contents {
    my $self = shift;
    my $lines = $self->_read_pipe($self->{svnlook}, 'info', $self->{repos_path},
                                  '-r', $self->{revision});
    $self->{user} = shift @$lines;
    $self->{date} = shift @$lines;
    $self->{message_size} = shift @$lines;
    $self->{message} = $lines;

    # Set up the from address.
    unless ($self->{from}) {
        $self->{from} = $self->{user}
          . ($self->{user_domain} ? "\@$self->{user_domain}" : '');
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
    print SENDMAIL "Reply-To: $self->{reply_to}\n" if $self->{reply_to};
    print SENDMAIL "X-Mailer: " . ref($self) . " " . $self->VERSION .
                   ", http://search.cpan.org/dist/SVN-Notify/\n";

    # Determine the content-type.
    my $ctype = $self->{format} eq 'text'
      ? 'text/plain'
      :  "text/$self->{format}";

    # Output the content type.
    if ($self->{attach_diff}) {
        # We need a boundary string.
        my $salt = join '',
          ('.', '/', 0..9, 'A'..'Z', 'a'..'z')[rand 64, rand 64];
        $self->{attach_diff} = crypt($self->{subject}, $salt);
        print SENDMAIL
          qq{Content-Type: multipart/mixed; boundary="$self->{attach_diff}"\n},
          "--$self->{attach_diff}\n";
    }

    # Output content-type and encoding headers.
    print SENDMAIL "Content-Type: $ctype; charset=UTF-8\n",
      "Content-Transfer-Encoding: 8bit\n\n";

    # Output the message.
    my $method = "output_as_$self->{format}";
    $self->$method(\*SENDMAIL);

    print SENDMAIL "--$self->{attach_diff}--\n" if $self->{attach_diff};
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
        next unless $files->{$type};

        # Identify the action.
        print $out "\n$map{$type}:\n$dash{$type}\n";
        if ($self->{viewcvs_url}) {
            # Append the ViewCVS URL to each file.
            my $append = $type eq 'U'
              ? "?r1=" . ($self->{revision} - 1) . "&r2=$self->{revision}"
              : '';
            for (@{ $files->{$type} }) {
                print $out "    $_\n",
                           "       $self->{viewcvs_url}$_$append\n";
            }
        } else {
            # Just output each file.
            print $out "    $_\n" for @{ $files->{$type} };
        }
    }

    $self->output_diff($out) if $self->{with_diff};
    return $self;
}

sub output_as_html {
    my ($self, $out) = @_;
    require HTML::Entities;
    print $out "<body>\n<h3>Log Message</h3>\n<pre>",
      HTML::Entities::encode_entities(join("\n", @{$self->{message}})),
      "</pre>\n\n";

    my $files = $self->{files} or return $self;
    foreach my $type (qw(U A D _)) {
        # Skip it if there's nothing to report.
        next unless $files->{$type};

        # Identify the action.
        print $out "<h3>$map{$type}</h3>\n<ul>\n";
        if ($self->{viewcvs_url}) {
            my $prev = $self->{revision} - 1;
            # Make each file name a link.
            for (@{ $files->{$type} }) {
                my $file = HTML::Entities::encode_entities($_);
                print $out qq{  <li><a href="$self->{viewcvs_url}$file">$file</a>};
                # Add a diff link for modified files.
                print $out qq{ (<a href="$self->{viewcvs_url}$file\?r1=$prev&amp;},
                  qq{r2=$self->{revision}">Diff</a>)}
                  if $type eq 'U';
                print $out "</li>\n"
            }
        } else {
            # Just output each file.
            print $out "  <li>" . HTML::Entities::encode_entities($_) . "</li>\n"
              for @{ $files->{$type} };
        }
        print $out "</ul>\n\n";
    }
    if ($self->{with_diff}) {
        unless ($self->{attach_diff}) {
            print $out "<pre>";
            $self->output_diff($out);
            print $out "</pre>\n";
        } else {
            $self->output_diff($out);
        }
    }

    return $self;
}

sub output_diff {
    my ($self, $out) = @_;
    # Output the content type headers.
    print $out "\n";
    if ($self->{attach_diff}) {
        # Get the date (UTC).
        my @gm = gmtime;
        $gm[5] += 1900;
        $gm[4] += 1;
        my $file = $self->{user}
          . sprintf '-%04s-%02s-%02sT%02s-%02s-%02sZ.diff', @gm[5,4,3,2,1,0];
        print $out "--$self->{attach_diff}\n",
          "Content-Disposition: attachment; filename=$file\n",
          "Content-Type: text/plain; charset=UTF-8\n",
          "Content-Transfer-Encoding: 8bit\n\n";
    }

    # Get the diff and output it.
    my $fh = $self->_pipe($self->{svnlook}, 'diff', $self->{repos_path}, '-r',
                          $self->{revision});

    if ($self->{format} eq 'text' || $self->{attach_diff}) {
        while (<$fh>) {
            s/[\n\r]+$//;
            print $out "$_\n";
        }
    } else {
        while (<$fh>) {
            s/[\n\r]+$//;
            print $out HTML::Entities::encode($_), "\n";
        }
    }
    close $fh;
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

sub mydie { print "######## SVN::Notify error: $_[0]"; exit }

##############################################################################
# This function prints debug messages. The reason it's a separate function is
# that it prepends a string to the message so that it'll stand out during
# commits.
##############################################################################

sub dbpnt { print "\n" if $_[1]; print "@@@@@@@@ SVN::Notify debug: $_[0]" }

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
