package SVN::Notify;

# $Id$

use strict;
$SVN::Notify::VERSION = '2.00_1';

=head1 Name

SVN::Notify - Subversion activity notification

=head1 Synopsis

Use F<svnnotify> in F<post-commit>:

  svnnotify --repos-path "$1" --rev "$2" \
    --to developers@example.com [options]

  svnnotify --repos-path "$1" --rev "$2" \
    --to-cx-regex i10n@example.com=I10N [options]

Use the class in a custom script:

  use SVN::Notify;

  my $notifier = SVN::Notify->new(%params);
  $notifier->prepare;
  $notifier->send;

=head1 Description

This program may be used for sending email messages for Subversion repository
activity. There are a number of different modes supported. A list of all the
files affected by the commit will be assembled and listed in the single
message. An additional option allows for diffs to be calculated for the recent
changes, and either appended to the message or added as an attachment. See the
C<with_diff> and C<attach_diff> options below.

=head1 Prerequisites

=over

=item Getopt::Long

This script requires L<Getopt::Long|Getopt::Long>, which is included with
Perl.

=back

=head1 Corequisites

=over

=item Pod::Usage

For calling F<svnnotify> with the C<--help> or C<--man> options, or when it
fails to process the command-line options, usage output will be triggered by
L<Pod::Usage|Pod::Usage>, which has been included with Perl since 5.6.0.

=item HTML::Entities

For sending HTML formatted email, this script requires
L<HTML::Entities|HTML::Entities>, which is available from CPAN.

=back

=head1 Usage

To use SVN::Notify, simply add a call to F<svnnotify> to your Subversion
repository's F<post-commit> script. This script lives at the root of the
repository directory; consult the documentation in F<post-commit.tmpl> for
details. Make sure that you specify the complete path to F<svnnotify>, as well
as to F<svnlook> and F<sendmail> in the options passed to F<svnnotify> so that
everything executes properly.

=cut

# Map the svnlook changed codes to nice labels.
my %map = ( U => 'Modified Files',
            A => 'Added Files',
            D => 'Removed Files',
            _ => 'Property Changed');

sub _dbpnt($) { print __PACKAGE__, ": $_[0]\n" }

##############################################################################

=head1 Class Interface

=head2 Constructor

=head3 new

  my $notifier = SVN::Notify->new(%params);

Constructs and returns a new SVN::Notify object. This object is a handle on
the whole process of collecting metadata and content for the commit email and
then sending it. As such, it takes a number of parameters to affect that
process.

Each of these parameters has a corresponding command-line option that can be
passed to F<svnnotify>. The options have the same names as these parameters,
but any underscores you see here should be replaced with dashes when passed to
F<svnnotify>. Each also has a corresponding single-character option. All of
these are documented here.

Supported parameters:

=over

=item repos_path

  svnnotify --repos-path "$PATH"
  svnnotify -p "$PATH"

The path to the Subversion repository. The path is passed as the first
argument when Subversion executes F<post-commit>. So you can simply pass C<$1>
to this parameter if you like. See the documentation in F<post-commit> for
details. Required.

=item revision

  svnnotify --revision "$REV"
  svnnotify -r "$REV"

The revision number for the current commit. The revision number is passed as
the second argument when Subversion executes F<post-commit>. So you can
simply pass C<$2> to this parameter if you like. See the documentation in
F<post-commit> for details. Required.

=item to

  svnnotify --to commiters@example.com
  svnnotify -t commiters@example.com

The address or addresses to which to send the notification email. To specify
multiple addresses, simply put them all into a comma-delimited list suitable
for an SMTP "From" header. This parameter is required unless C<to_regex_map>
is specified.

=item to_regex_map

  svnnotify --to-regex-map translate@example.com=L18N \
            -x legal@example.com=License

This parameter specifies a hash reference of email addresses to regular
expression strings. SVN::Notify will compile the regular expression strings
into regular expression objects, and then send notification messages if and
only if the name of one or more of the directories affected by a commit
matches the regular expression. This is a good way to have a notification
email sent to a particular mail address (or comma-delimited list of addresses)
only for certain parts of the subversion tree. This parameter is required
unless C<to> is specified.

The command-line options, C<--to-regex_map> and C<-x>, can be specified any
number of times, once for each entry in the hash to be passed to C<new()>. The
value passed to the option must be in the form of the key and the value
separated by an equal sign. Consult the L<Getopt::Long> documentation for more
information.

=item from

  svnnotify --from somewhere@example.com
  svnnotify -f elsewhere@example.com

The email address to use in the "From" line of the email. If not specified,
SVN::Notify will use the username from the commit, as returned by C<svnlook
info>.

=item user_domain

  svnnotify --user-domain example.com
  svnnotify -D example.net

A domain name to append to the username for the "From" header of the email.
During a Subversion commit, the username returned by C<svnlook info> is
usually something like a Unix login name. SVN::Notify will use this username
in the email "From" header unless the C<from> parameter is specified. If you
wish to have the username take the form of a real email address, specify a
domain name and SVN::Notify will append C<\@$domain_name> to the username in
order to create a real email address. This can be useful if all of your
committers have an email address that corresponds to their username at the
domain specified by the C<user_domain> parameter.

=item svnlook

  svnnotify --svnlook /path/to/svnlook
  svnnotify --l /path/to/svnlook

The location of the F<svnlook> executable. The default is
F</usr/local/bin/svnlook>. Specify a different path or set the C<$SVNLOOK>
environment variable if this is not the location of F<svnlook> on your
box. It's important to provide a complete path to F<svnlook> because the
environment during the execution of F<post-commit> is anemic, with nary a
C<$PATH> environment variable to be found. So if F<svnnotify> appears not to
be working at all (and Subversion seems loathe to log when it dies!), make
sure that you have specified the complete path to a working F<svnlook>
executable.

=item sendmail

  svnnotify --sendmail /path/to/sendmail
  svnnotify --s /path/to/sendmail

The location of the F<sendmail> executable. The default is
F</usr/sbin/sendmail>. Specify a different path or set the C<$SENDMAIL>
environment variable if this is not the location of F<sendmail> on your box.
The same caveats as applied to the location of the F<svnlook> executable
apply here.

=item charset

  svnnotify --charset UTF-8
  svnnotify -c Big5

The character set typically used on the repository for log messages, file
names, and file contents. Used to specify the character set in the email
Content-Type headers. Defaults to UTF-8.

=item with_diff

  svnnotify --with-diff
  svnnotify -d

A boolean value specifying whether or not to include the output of C<svnlook
diff> in the notification email. The diff will be inline at the end of the
email unless the C<attach_diff> parameter specifies a true value.

=item attach_diff

  svnnotify --attach-diff
  svnnotify -a

A boolean value specifying whether or not to attach the output of C<svnlook
diff> to the notification email. Rather than being inline in the body of the
email, this parameter causes SVN::Notify to attach the diff as a separate
file, named for the user who triggered the commit and the date and time UTC at
which the commit took place. Specifying this parameter to a true value
implicitly sets the C<with_diff> parameter to a true value.

=item reply_to

  svnnotify --reply-to devlist@example.com
  svnnotify --R developers@example.net

The email address to use in the "Reply-To" header of the notification email.
No "Reply-To" header will be added to the email if no value is specified for
the C<reply_to> parameter.

=item subject_prefix

  svnnotify --subject-prefix [Devlist]
  svnnotify -P (Our-Developers)

An optional string to prepend to the beginning of the subject line of the
notification email.

=item subject_cx

  svnnotify --subject-cx
  svnnotify -C

A boolean value indicating whether or not to include a the context of the
commit in the subject line of the email. In a commit that affects multiple
files, the context will be the name of the shortest directory affected by the
commit. This should indicate up to how high up the Subversion repository tree
the commit had an effect. If the commit affects a single file, then the
context will simply be the name of that file.

=item max_sub_length

  svnnotify --max-sub-length 72
  svnnotify -i 76

The maximum length of the notification email subject line. SVN::Notify
includes the first line of the commit log message, or the first sentence of
the message (defined as any text up to the string ". "), whichever is
shorter. This could potentially be quite long. To prevent the subject from
being over a certain number of characters, specify a maximum length here, and
SVN::Notify will truncate the subject to the last word under that length.

=item format

  svnnotify --format text
  svnnotify -A html

The format of the notification email. Two formats are supported, "text" and
"html". If "html" is specified, HTML::Entities B<must> be installed to ensure
that the log message, file names, and diff are properly escaped.

=item viewcvs_url

  svnnotify --viewcvs-url http://svn.example.com/viewcvs/
  svnnotify -U http://viewcvs.example.net/

If a URL is specified for this parameter, then it will be used to create links
to the files affected by the commit on the relevant Website. The URL is
assumed to be the base URL for a ViewCVS script; the file name of the affected
file will simply be appended to it. For modified files, the link will be to
the ViewCVS diff output for the commit on that file, although in HTML mode
both links will be specified.

=item verbose

  svnnotify --verbose -V

A value between 0 and 3 specifying how verbose SVN::Notify should be. The
default is 0, meaning that SVN::Notify will be silent. A value of 1 causes
SVN::Notify to output some information about what it's doing, while 2 and 3
each cause greater verbosity. To set the verbosity on the command line, simply
pass the C<--verbose> or C<-V> option once for each level of verbosity, up to
three times.

=back

=cut

sub new {
    my ($class, %params) = @_;

    # Check for required parameters.
    _dbpnt "Checking required parameters to new()" if $params{verbose};
    die qq{Missing required "repos_path" parameter}
      unless $params{repos_path};
    die qq{Missing required "revision" parameter}
      unless $params{revision};
    die qq{Missing required "to" or "to_regex_map" parameter}
      unless $params{to} || $params{to_regex_map};

    # Set up default values.
    $params{svnlook}   ||= $ENV{SVNLOOK}  || '/usr/local/bin/svnlook';
    $params{sendmail}  ||= $ENV{SENDMAIL} || '/usr/sbin/sendmail';
    $params{format}    ||= 'text';
    $params{with_diff} ||= $params{attach_diff};
    $params{verbose}   ||= 0;
    $params{charset}   ||= 'UTF-8';

    # Append slash to viewcvs_url, if necessary.
    $params{viewcvs_url} .= '/'
      if $params{viewcvs_url} && $params{viewcvs_url} !~ m{/$};

    # Make it so!
    _dbpnt "Instantiating $class object" if $params{verbose};
    return bless \%params, $class;
}

##############################################################################

=head1 Instance Interface

=head2 Instance Methods

=head3 prepare

  $notifier->prepare;

Prepares the SVN::Notify object, collecting all the data it needs in
preparation for sending the notification email. Really it's just a shortcut
for:

  $self->prepare_recipients;
  $self->prepare_contents;
  $self->prepare_files;
  $self->prepare_subject;

Only it returns after the call to C<prepare_recipients()> if there are no
recipients (that is, as when recipients are specified solely by the
C<to_regex_map> parameter and none of the regular expressions match any of the
affected directories).

=cut

sub prepare {
    my $self = shift;
    $self->prepare_recipients;
    return $self unless $self->{to};
    $self->prepare_contents;
    $self->prepare_files;
    $self->prepare_subject;
}

##############################################################################

=head3 prepare_recipients

  $notifier->prepare_recipients;

Collects and prepares a list of the notification recipients. The recipients
are a combination of the value passed to the C<to> parameter as well as any
email addresses specified as keys in the hash reference passed C<to_regex_map>
parameter, where the regular expressions stored in the values match one or
more of the names of the directories affected by the commit.

If the F<subject_cx> parameter to C<new()> has a true value,
C<prepare_recipients()> also determines the directory name to use for the
context.

=cut

sub prepare_recipients {
    my $self = shift;
    _dbpnt "Preparing recipients list" if $self->{verbose};
    return $self unless $self->{to_regex_map} || $self->{subject_cx};
    my @to = $self->{to} ? ($self->{to}) : ();
    my $regexen = delete $self->{to_regex_map};
    if ($regexen) {
        _dbpnt "Compiling regex_map regular expressions"
          if $self->{verbose} > 1;
        for (values %$regexen) {
            _dbpnt qq{Compiling "$_"} if $self->{verbose} > 2;
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
                _dbpnt qq{"$_" matched $rx} if $self->{verbose} > 2;
                push @to, $email;
                delete $regexen->{$email};
            }
        }
        # Grab the context if it's needed for the subject.
        if ($self->{subject_cx}) {
            # XXX Do we need to set utf8 here?
            my $l = length;
            ($len, $cx) = ($l, $_) unless defined $len && $len < $l;
            _dbpnt qq{Context is "$cx"} if $self->{verbose} > 1;
        }
    }
    $self->{to} = join ', ', @to;
    $self->{cx} = $cx;
    _dbpnt qq{Recipients: "$self->{to}"} if $self->{verbose} > 1;
    return $self;
}

##############################################################################

=head3 prepare_contents

  $notifier->prepare_contents;

Prepares the contents of the commit message, including the name of the user
who triggered the commit (and therefore the contents of the "From" header to
be used in the email) and the log message.

=cut

sub prepare_contents {
    my $self = shift;
    _dbpnt "Preparing contents" if $self->{verbose};
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
    if ($self->{verbose} > 1) {
        _dbpnt "From: $self->{from}";
        _dbpnt "Message: @$lines";
    }
    return $self;
}

##############################################################################

=head3 prepare_files

  $notifier->prepare_files;

Prepares the lists of files affected by the commit, sorting them into their
categories: modified files, added files, and deleted files. It also compiles a
list of files wherein a property was set, which might have some overlap with
the list of modified files (if a single commit both modified a file and set a
property on it).

If the C<subject_cx> parameter was specified and a single file was affected by
the commit, then C<prepare_files()> will also specifythat file name as the
context to be used in the subject line of the commit email.

=cut

sub prepare_files {
    my $self = shift;
    _dbpnt "Preparing file lists" if $self->{verbose};
    my %files;
    my $fh = $self->_pipe($self->{svnlook}, 'changed', $self->{repos_path},
                          '-r', $self->{revision});

    # Read in a list of changed files.
    my $cx = $_ = <$fh>;
    do {
        s/[\n\r]+$//;
        if (s/^(.)(.)\s+//) {
            _dbpnt "$1 => $_" if $self->{verbose} > 2;
            push @{$files{$1}}, $_;
            push @{$files{_}}, $_ if $2 ne ' ' && $1 ne '_';
        }
    } while (<$fh>);

    if ($self->{subject_cx} && $. == 1) {
        # There's only one file; it's the context.
        $cx =~ s/[\n\r]+$//;
        ($self->{cx} = $cx) =~ s/^..\s+//;
        _dbpnt qq{Directory context is "$self->{cx}"} if $self->{verbose} > 1;
    }
    $self->{files} = \%files;
    return $self;
}

##############################################################################

=head3 prepare_subject

  $notifier->prepare_subject;

Prepares the subject line for the notification email. This method B<must> be
called after C<prepare_recipients()> and C<prepare_files()>, since each of
those methods potentially sets up the context for use in the the subject
line. The subject may have a prefix defined by the C<subject_prefix> parameter
to C<new()>, it has the revision number, it might have the context if the
C<subject_cx> specified a true value, and it will have the first sentence or
line of the commit, whichever is shofter. The subject may then be truncated to
the maximum length specified by the C<max_sub_length> parameter.

=cut

sub prepare_subject {
    my $self = shift;
    _dbpnt "Preparing subject" if $self->{verbose};

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

    _dbpnt qq{Subject is "$self->{subject}"} if $self->{verbose};
    return $self;
}

##############################################################################

=head3 send

  $notifier->send;

Sends the notification message. This involves opening a connection to
F<sendmail>, sending the appropriate headers, calling the appropriate
formatting method (See L</"output_as_text"> and L</"output_as_html"> below),
and then closing the connection so that sendmail can send the email.

=cut

sub send {
    my $self = shift;
    _dbpnt "Sending message" if $self->{verbose};
    return $self unless $self->{to};

    open(SENDMAIL, "|$self->{sendmail} -oi -t")
      or die "Cannot fork for $self->{sendmail}: $!\n";
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
    print SENDMAIL "Content-Type: $ctype; charset=$self->{charset}\n",
      "Content-Transfer-Encoding: 8bit\n\n";

    # Output the message.
    my $method = "output_as_$self->{format}";
    $self->$method(\*SENDMAIL);

    print SENDMAIL "--$self->{attach_diff}--\n" if $self->{attach_diff};
    close SENDMAIL;
    _dbpnt "Message sent" if $self->{verbose};
    return $self;
}

##############################################################################

=head3 output_as_text

  $notifier->output_as_text($file_handle);

Called internally by C<send> to output a text version of the commit email. The
file handle passed is a piped connection to F<sendmail>, so that
C<output_as_text()> can print directly to sendmail. C<output_as_text()> also
appends or attaches a diff if the C<with_diff> or C<attach_diff> parameter to
C<new()> specified a true value.

=cut

sub output_as_text {
    my ($self, $out) = @_;
    _dbpnt "Outputting text message" if $self->{verbose} > 1;

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
                # XXX Do we need to convert the directory separators on Win32?
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

##############################################################################

=head3 output_as_html

  $notifier->output_as_html($file_handle);

Called internally by C<send> to output an HTML version of the commit
email. The file handle passed is a piped connection to F<sendmail>, so that
C<output_as_html()> can print directly to sendmail. C<output_as_html()> also
appends or attaches a diff if the C<with_diff> or C<attach_diff> parameter to
C<new()> specified a true value.

=cut

sub output_as_html {
    my ($self, $out) = @_;
    _dbpnt "Outputting HTML message" if $self->{verbose} > 1;

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
                # XXX Do we need to convert the directory separators on Win32?
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

##############################################################################

=head3 output_diff

  $notifier->output_diff($file_handle);

Called internally by C<output_as_text()> and C<output_as_html()> to send the
output of C<svnlook diff> to the specified file handle. That file handle is
an open pipe to sendmail.

C<output_diff()> is also aware of whether the format of the notification email
is text or HTML, so that it can properly escape the diff for HTML emaill when
the C<attach_diff> parameter to C<new()> has a false value.

=cut

sub output_diff {
    my ($self, $out) = @_;
    _dbpnt "Outputting diff" if $self->{verbose} > 1;

    # Output the content type headers.
    print $out "\n";
    if ($self->{attach_diff}) {
        _dbpnt "Attaching diff" if $self->{verbose} > 2;
        # Get the date (UTC).
        my @gm = gmtime;
        $gm[5] += 1900;
        $gm[4] += 1;
        my $file = $self->{user}
          . sprintf '-%04s-%02s-%02sT%02s-%02s-%02sZ.diff', @gm[5,4,3,2,1,0];
        print $out "--$self->{attach_diff}\n",
          "Content-Disposition: attachment; filename=$file\n",
          "Content-Type: text/plain; charset=$self->{charset}\n",
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
# This function forks off a process to execute an external program and any
# associated arguments and returns a file handle that can be read to fetch
# the output of the external program.
##############################################################################

sub _pipe {
    my $self = shift;
    _dbpnt "Piping execution of '" . join("', '", @_) . "'"
      if $self->{verbose};
    # Safer version of backtick (see perlipc(1)).
    # XXX Use Win32::Pipe on Win32? This doesn't seem to work as-is on Win32.
    my $pid = open(PIPE, '-|');
    die "Cannot fork: $!\n" unless defined $pid;

    if ($pid) {
        # Parent process. Return the file handle.
        return \*PIPE;
    } else {
        # Child process. Execute the commands.
        exec(@_) or die "Cannot exec $_[0]: $!\n";
        # Not reached.
    }
}

##############################################################################
# This method passes its arguments to _pipe(), but then fetches each line
# off output from the returned file handle, safely strips out and replaces any
# newlines and carriage returns, and returns an array refernce of those lines.
##############################################################################

sub _read_pipe {
    my $self = shift;
    my $fh = $self->_pipe(@_);
    local $/; my @lines = split /[\r\n]+/, <$fh>;
    close $fh;
    return \@lines;
}

1;
__END__

=head1 Bugs

Report all bugs via the CPAN Request Tracker at
L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=SVN-Notify>.

=head1 To Do

=over

=item *

Add tests for verbose modes.

=item *

Port to Win32.

=back

=head1 Author

David Wheeler <david@kineticode.com>

=head1 Copyright and License

Copyright (c) 2004 Kineticode, Inc. All Rights Reserved.

This module is free software; you can redistribute it and/or modify it under the
same terms as Perl itself.

=cut
