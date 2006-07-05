package SVN::Notify;

# $Id$

use strict;
use constant WIN32  => $^O eq 'MSWin32';
use constant PERL58 => $] > 5.007;
$SVN::Notify::VERSION = '2.63';

=begin comment

Fake-out Module::Build. Delete if it ever changes to support =head1 headers
other than all uppercase.

=head1 NAME

SVN::Notify - Subversion activity notification

=end comment

=head1 Name

SVN::Notify - Subversion activity notification

=head1 Synopsis

Use F<svnnotify> in F<post-commit>:

  svnnotify --repos-path "$1" --revision "$2" \
    --to developers@example.com [options]

  svnnotify --repos-path "$1" --revision "$2" \
    --to-cx-regex i10n@example.com=I10N [options]

Use the class in a custom script:

  use SVN::Notify;

  my $notifier = SVN::Notify->new(%params);
  $notifier->prepare;
  $notifier->execute;

=head1 Description

This class may be used for sending email messages for Subversion repository
activity. There are a number of different modes supported, and SVN::Notify is
fully subclassable to easily add new functionality. By default, A list of all
the files affected by the commit will be assembled and listed in a single
message. An additional option allows diffs to be calculated for the changes
and either appended to the message or added as an attachment. See the
C<with_diff> and C<attach_diff> options below.

=head1 Usage

To use SVN::Notify, simply add a call to F<svnnotify> to your Subversion
repository's F<post-commit> script. This script lives at the root of the
repository directory; consult the documentation in F<post-commit.tmpl> for
details. Make sure that you specify the complete path to F<svnnotify>, as well
as to F<svnlook> and F<sendmail> in the options passed to F<svnnotify> so that
everything executes properly.

=head2 Windows Usage

Go get SVN::Notify to work properly in a F<post-commit> script, you must set
the following environment variables, as they will likley not be present inside
Apache:

=over

=item PATH=C:\perl\bin

=item OS=Windows_NT

=item SystemRoot=C:\WINDOWS

=back

See L<http://svn.haxx.se/users/archive-2006-05/0593.shtml> for more detailed
information on getting SVN::NOtify running on Windows.

=cut

# Map the svnlook changed codes to nice labels.
my %map = (
    U => 'Modified Paths',
    A => 'Added Paths',
    D => 'Removed Paths',
    _ => 'Property Changed',
);

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
  svnnotify -t commiters@example.com --to managers@example.com

The address or addresses to which to send the notification email. Can be used
multiple times to specify multiple addresses. This parameter is required
unless C<to_regex_map> is specified.

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
  svnnotify -l /path/to/svnlook

The location of the F<svnlook> executable. If not specified, SVN::Notify will
search through the directories in the C<$PATH> environment variable, plus in
F</usr/local/bin> and F</usr/sbin>, for an F<svnlook> executable. Specify a
full path to F<svnlook> via this option or by setting the C<$SVNLOOK>
environment variable if F<svnlook> isn't in your path or to avoid loading
L<File::Spec|File::Spec>.

It's important to provide a complete path to F<svnlook> because the
environment during the execution of F<post-commit> is anemic, with nary a
C<$PATH> environment variable to be found. So if F<svnnotify> appears not to
be working at all (and Subversion seems loathe to log when it dies!), make
sure that you have specified the complete path to a working F<svnlook>
executable.

=item sendmail

  svnnotify --sendmail /path/to/sendmail
  svnnotify -s /path/to/sendmail

The location of the F<sendmail> executable. If neither the C<sendmail> nor the
C<smtp> parameter is specified, SVN::Notify will search through the
directories in the C<$PATH> environment variable, plus in F</usr/local/bin>
and F</usr/sbin>, for an F<sendmail> executable. Specify a full path to
F<sendmail> via this option or by setting the C<$SENDMAIL> environment
variable if F<sendmail> isn't in your path or to avoid loading
L<File::Spec|File::Spec>. The same caveats as applied to the location of the
F<svnlook> executable apply here.

=item set_sender

  svnnotify --set-sender
  svnnotify -E

Uses the C<-f> option to C<sendmail> to set the envelope sender address of the
email to the same address as is used for the "From" header. If you're also
using the C<from> option, be sure to make it B<only> an email address. Don't
include any other junk in it, like a sender's name. Ignored when using
C<smtp>.

=item smtp

  svnnotify --smtp smtp.example.com

The address for an SMTP server through which to send the notification email.
If unspecified, SVN::Notify will use F<sendmail> to send the message. If
F<sendmail> is not installed locally (such as on Windows boxes!), you I<must>
specify an SMTP server.

=item smtp_user

  svnnotify --smtp-user myuser

The user name for SMTP authentication. If this option is specified,
SVN::Notify will use L<Net::SMTP_auth|Net::SMTP_auth> to send the notification
message, and will of course authenticate to the SMTP server.

=item smtp_pass

  svnnotify --smtp-pass mypassword

The password for SMTP authentication. Use in parallel with C<smtp_user>.

=item smtp_authtype

  svnnotify --smtp-authtype authtype

The authentication method to use for authenticating to the SMTP server. The
available authentication types include "PLAIN", "NTLM", "CRAM_MD5", and
others. Consult the L<Authen::SASL|Authen::SASL> documentation for a complete
list. Defaults to "PLAIN".

=item charset

  svnnotify --charset UTF-8
  svnnotify -c Big5

The character set typically used on the repository for log messages, file
names, and file contents. Used to specify the character set in the email
Content-Type headers. Defaults to "UTF-8".

=item io_layer

  svnnotify --io-layer raw
  svnnotify -o bytes

The Perl IO layer to use for inputting and outputting data. See
L<perlio|perlio> for details. Defaults to "encoding($charset)". If your
repository uses different character encodings, C<charset> should be set to
whatever is the most common character encoding, and C<io_layer> is best set to
C<raw>. In that case, some characters might not look right in the commit
messaage (because an email can manage only one character encoding at a time),
but then C<svnnotify> won't get stuck inssuing a slew of warnings.

=item language

  svnnotify --language fr
  svnnotify -g i-klingon

The language typically used on the repository for log messages, file names,
and file contents. Used to specify the email Content-Language header.
Undefined by default, meaning that no Content-Language header is output.

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

=item diff_switches

  svnnotify --diff-switches '--no-diff-added'
  svnnotify -w '--no-diff-deleted'

Switches to pass to C<svnlook diff>, such as C<--no-diff-deleted> and
C<--no-diff-added>. And who knows, maybe someday it will support the same
options as C<svn diff>, such as C<--diff-cmd> and C<--extensions>. Only
relevant when used with C<with_diff> or C<attach_diff>.

=item reply_to

  svnnotify --reply-to devlist@example.com
  svnnotify -R developers@example.net

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

=item strip_cx_regex

  svnnotify --strip-cx-regex '^trunk/'
  svnnotify --strip-cx-regex '^trunk/' --strip-cx-regex '^branches/'
  svnnotify -X '^trunk'
  svnnotify -X '^trunk' -X '^branches'

One or more regular expressions to be used to strip out parts of the subject
context. This can be useful for very deep Subversion trees, where the commits
you're sending will always be sent from a particular subtree, so you'd like to
remove part of the tree. Used only if C<subject_cx> is set to a true value.
Pass an array reference if calling C<new()> directly.

=item no_first_line

  svnnotify --no-first-line
  svnnotify -O

Omits the first line of the log message from the subject. This is most useful
when used in combination with the C<subject_cx> parameter, so that just the
commit context is displayed in the subject and no part of the log message.

=item header

  svnnotify --header 'SVN::Notify is brought to you by Kineticode.

Adds a specified text to each message as a header at the beginning of the
body of the message.

=item footer

  svnnotify --footer 'Copyright (R) by Kineticode, Inc.'

Adds a specified text to each message as a footer at the end of the body of
the message.

=item max_sub_length

  svnnotify --max-sub-length 72
  svnnotify -i 76

The maximum length of the notification email subject line. SVN::Notify
includes the first line of the commit log message, or the first sentence of
the message (defined as any text up to the string ". "), whichever is
shorter. This could potentially be quite long. To prevent the subject from
being over a certain number of characters, specify a maximum length here, and
SVN::Notify will truncate the subject to the last word under that length.

=item max_diff_length

  svnnotify --max-diff-length 1024

The maximum length of the diff (attached or in the body). The diff output is
truncated at the last line under the maximum character count specified and
then outputs an additional line indicating that the maximum diff size was
reached and output truncated. This is helpful when a large diff output could
cause a message to bounce due to message size.

=item handler

  svnnotify --handler HTML
  svnnotify -H HTML

Specify the subclass of SVN::Notify to be constructed and returned, and
therefore to handle the notification. Of course you can just use a subclass
directly, but this parameter is designed to make it easy to just use
C<< SVN::Notify->new >> without worrying about loading subclasses, such as in
F<svnnotify>. Be sure to read the documentation for your subclass of choice,
as there may be additional parameters and existing parameters may behave
differently.

=item author_url

  svnnotify --author-url 'http://svn.example.com/changelog/~author=%s/repos'
  svnnotify --A 'mailto:%s@example.com'

If a URL is specified for this parameter, then it will be used to create a
link for the current author. The URL can have the "%s" format where the
author's username should be put into the URL.

=item revision_url

  svnnotify --revision-url 'http://svn.example.com/changelog/?cs=%s'
  svnnotify -U 'http://svn.example.com/changelog/?cs=%s'

If a URL is specified for this parameter, then it will be used to create a
link to the Subversion browser URL corresponding to the current revision
number. It will also be used to create links to any other revision numbers
mentioned in the commit message. The URL must have the "%s" format where the
Subversion revision number should be put into the URL.

=item svnweb_url

  svnnotify --svnweb-url 'http://svn.example.com/index.cgi/revision/?rev=%s'
  svnnotify -S 'http://svn.example.net/index.cgi/revision/?rev=%s'

Deprecated. Use C<revision_url> instead.

=item viewcvs_url

  svnnotify --viewcvs-url 'http://svn.example.com/viewcvs/?rev=%s&view=rev'

Deprecated. Use C<revision_url> instead.

=item rt_url

  svnnotify --rt-url 'http://rt.cpan.org/NoAuth/Bugs.html?id=%s'
  svnnotify -T 'http://rt.perl.org/NoAuth/Bugs.html?id=%s'

The URL of a Request Tracker (RT) server. If passed in, any strings in the log
message of the form "Ticket # 12" or "ticket 6" or even "Ticket#1066" will be
turned into links to the RT server. The URL must have the "%s" format where
the RT ticket ID should be put into the URL.

=item bugzilla_url

  svnnotify --bugzilla-url 'http://bugzilla.mozilla.org/show_bug.cgi?id=%s'
  svnnotify -B 'http://bugs.bricolage.cc/show_bug.cgi?id=%s'

The URL of a Bugzilla server. If passed in, any strings in the log message of
the form "Bug # 12" or "bug 6" or even "Bug#1066" will be turned into links to
the Bugzilla server. The URL must have the "%s" format where the Bugzilla Bug
ID should be put into the URL.

=item jira_url

  svnnotify --jira-url 'http://jira.atlassian.com/secure/ViewIssue.jspa?key=%s'
  svnnotify -J 'http://nagoya.apache.org/jira/secure/ViewIssue.jspa?key=%s'

The URL of a JIRA server. If passed in, any strings in the log message that
appear to be JIRA keys (such as "JRA-1234") will be turned into links to the
JIRA server. The URL must have the "%s" format where the Jira key should be
put into the URL.

=item gnats_url

  svnnotify --gnats-url 'http://gnatsweb.example.com/cgi-bin/gnatsweb.pl?cmd=view&pr=%s'
  svnnotify -G 'http://gnatsweb.example.com/cgi-bin/gnatsweb.pl?cmd=view&pr=%s'

The URL of a GnatsWeb server. If passed in, any strings in the log message
that appear to be GNATS PRs (such as "PR 1234") will be turned into links to
the GnatsWeb server. The URL must have the "%s" format where the GNATS PR
number should be put into the URL.

=item ticket_url

  svnnotify --ticket-url 'http://ticket.example.com/showticket.html?id=%s'

The URL of a custom ticket system. If passed in, any strings in the log
message that match C<ticket_regex> will be turned into links to the custom
ticket system. The URL must have the "%s" format where the first match
(usually the ticket identifier) in the regex should be put into the URL.

=item ticket_regex

  svnnotify --ticket-regex '\[?#\s*(\d+)\s*\]?'

The regex to match a ticket tag of a custom ticket system. This should return
a single match to be interpolated into the C<ticket_url> option. The example
shown matches "[#1234]" or "#1234" or "[# 1234]". This regex should be as
specific as possible, preferably wrapped in "\b" to match word boundaries. If
you're using L<SVN::Notify::HTML|SVN::Notify::HTML>, be sure to read its
documentation for a different syntax for C<ticket_regex>!

=item verbose

  svnnotify --verbose -V

A value between 0 and 3 specifying how verbose SVN::Notify should be. The
default is 0, meaning that SVN::Notify will be silent. A value of 1 causes
SVN::Notify to output some information about what it's doing, while 2 and 3
each cause greater verbosity. To set the verbosity on the command line, simply
pass the C<--verbose> or C<-V> option once for each level of verbosity, up to
three times.

=item boundary

The boundary to use between email body text and attachments. This is normally
generated by SVN::Notify.

=item subject

The subject of the email to be sent. This attribute is normally generated by
C<prepare_subject()>.

=back

=cut

sub new {
    my ($class, %params) = @_;

    # Delegate to a subclass if requested.
    if (my $handler = delete $params{handler}) {
        my $subclass = __PACKAGE__ . "::$handler";
        unless ($subclass eq $class) {
            eval "require $subclass" or die $@;
            return $subclass->new(%params);
        }
    }

    # Make sure that the tos are an arrayref.
    $params{to} = [ $params{to} || () ] unless ref $params{to};

    # Check for required parameters.
    $class->_dbpnt( "Checking required parameters to new()")
      if $params{verbose};
    die qq{Missing required "repos_path" parameter}
      unless $params{repos_path};
    die qq{Missing required "revision" parameter}
      unless $params{revision};
    die qq{Missing required "to" or "to_regex_map" parameter}
      unless @{ $params{to} } || $params{to_regex_map};

    # Set up default values.
    $params{svnlook}        ||= $ENV{SVNLOOK}  || $class->find_exe('svnlook');
    $params{with_diff}      ||= $params{attach_diff};
    $params{verbose}        ||= 0;
    $params{charset}        ||= 'UTF-8';
    $params{io_layer}       ||= "encoding($params{charset})";
    $params{smtp_authtype}  ||= 'PLAIN';
    $params{sendmail}       ||= $ENV{SENDMAIL} || $class->find_exe('sendmail')
        unless $params{smtp};

    die qq{Cannot find sendmail and no "smtp" parameter specified}
        unless $params{sendmail} || $params{smtp};

    # Set up the revision URL.
    $params{revision_url} ||= delete $params{svnweb_url}
                          ||  delete $params{viewcvs_url};
    if ($params{revision_url} && $params{revision_url} !~ /%s/) {
        warn "--revision-url must have '%s' format\n";
        $params{revision_url} .= '/revision/?rev=%s&view=rev'
    }


    # Make it so!
    $class->_dbpnt( "Instantiating $class object") if $params{verbose};
    return bless \%params, $class;
}

##############################################################################

=head2 Class Methods

=head3 content_type

  my $content_type = SVN::Notify->content_type;

Returns the content type of the notification message, "text/plain". Used to
set the Content-Type header for the message.

=cut

sub content_type { 'text/plain' }

##############################################################################

=head3 register_attributes

  SVN::Notify::Subclass->register_attributes(
      foo_attr => 'foo-attr=s',
      bar      => 'bar',
      bat      => undef,
  );

This class method is used by subclasses to register new attributes. Pass in a
list of key/value pairs, where the keys are the attribute names and the values
are option specifications in the format required by Getopt::Long. SVN::Notify
will create accessors for each attribute, and if the corresponding value is
defined, it will be used by the C<get_options()> class method to get a
command-line option value.

See <LSVN::Notify::HTML|SVN::Notify::HTML> for an example usage of
C<register_attributes()>.

=cut

my %OPTS;

sub register_attributes {
    my $class = shift;
    my @attrs;
    while (@_) {
        push @attrs, shift;
        if (my $opt = shift) {
            $OPTS{$attrs[-1]} = $opt;
        }
    }
    $class->_accessors(@attrs);
}

##############################################################################

=head3 get_options

  my $options = SVN::Notify->get_options;

Parses the command-line options in C<@ARGV> to a hash reference suitable for
passing as the parameters to C<new()>. See L<"new"> for a complete list of the
supported parameters and their corresponding command-line options.

This method use Getopt::Long to parse C<@ARGV>. It then looks for a C<handler>
option and, if it finds one, loads the appropriate subclass and parsed any
options it requires from C<@ARGV>. Subclasses should use
C<register_attributes()> to register any attributes and options they require.

=cut

sub get_options {
    my ($class, $opts) = @_;
    require Getopt::Long;

    # Enable bundling and, at the same time, case-sensitive matching of
    # single character options. Also enable pass-through so that subclasses
    # can grab more options.
    Getopt::Long::Configure (qw(bundling pass_through));

    # Get options.
    Getopt::Long::GetOptions(
        'repos-path|p=s'      => \$opts->{repos_path},
        'revision|r=s'        => \$opts->{revision},
        'to|t=s@'             => \$opts->{to},
        'to-regex-map|x=s%'   => \$opts->{to_regex_map},
        'from|f=s'            => \$opts->{from},
        'user-domain|D=s'     => \$opts->{user_domain},
        'svnlook|l=s'         => \$opts->{svnlook},
        'sendmail|s=s'        => \$opts->{sendmail},
        'set-sender|E'        => \$opts->{set_sender},
        'smtp=s'              => \$opts->{smtp},
        'charset|c=s'         => \$opts->{charset},
        'io-layer|o=s'        => \$opts->{io_layer},
        'language|g=s'        => \$opts->{language},
        'with-diff|d'         => \$opts->{with_diff},
        'attach-diff|a'       => \$opts->{attach_diff},
        'diff-switches|w=s'   => \$opts->{diff_switches},
        'reply-to|R=s'        => \$opts->{reply_to},
        'subject-prefix|P=s'  => \$opts->{subject_prefix},
        'subject-cx|C'        => \$opts->{subject_cx},
        'strip-cx-regex|X=s@' => \$opts->{strip_cx_regex},
        'no-first-line|O'     => \$opts->{no_first_line},
        'max-sub-length|i=i'  => \$opts->{max_sub_length},
        'max-diff-length|e=i' => \$opts->{max_diff_length},
        'handler|H=s'         => \$opts->{handler},
        'author-url|A=s'      => \$opts->{author_url},
        'rt-url|T=s'          => \$opts->{rt_url},
        'bugzilla-url|B=s'    => \$opts->{bugzilla_url},
        'jira-url|J=s'        => \$opts->{jira_url},
        'gnats-url|G=s'       => \$opts->{gnats_url},
        'ticket-url=s'        => \$opts->{ticket_url},
        'ticket-regex=s'      => \$opts->{ticket_regex},
        'verbose|V+'          => \$opts->{verbose},
        'help|h'              => \$opts->{help},
        'man|m'               => \$opts->{man},
        'version|v'           => \$opts->{version},
        'header=s'            => \$opts->{header},
        'footer=s'            => \$opts->{footer},
        'smtp-user=s'         => \$opts->{smtp_user},
        'smtp-pass=s'         => \$opts->{smtp_pass},
        'smtp-authtype=s'     => \$opts->{smtp_authtype},
        'revision-url|U|svnweb-url|S|viewcvs-url=s' => \$opts->{revision_url},
    ) or return;

    # Load a subclass if one has been specified.
    return $opts unless $opts->{handler};
    eval "require " . __PACKAGE__ . "::$opts->{handler}" or die $@;

    # Load any options for the subclass.
    return $opts unless %OPTS;
    Getopt::Long::GetOptions(
        map { delete $OPTS{$_} => \$opts->{$_} } keys %OPTS
    ) or return;

    return $opts;
}

##############################################################################

=head3 file_label_map

  my $map = SVN::Notify->file_label_map;

Returns a hash reference of the labels to be used for the lists of files. A
hash reference of file lists is stored in the C<files> attribute after
C<prepare_files()> has been called. The hash keys in that list correspond to
Subversion status codes, and these are mapped to their appropriate labels by
the hash reference returned by this method:

  { U => 'Modified Paths',
    A => 'Added Paths',
    D => 'Removed Paths',
    _ => 'Property Changed'
  }

=cut

sub file_label_map { \%map }

##############################################################################

=head3 find_exe

  my $exe = SVN::Notify->find_exe($exe_name);

This method searches through the system path, as well as the extra directories
F</usr/local/bin> and F</usr/sbin> (because they're common paths for
C<svnlook> and C<sendmail> for an executable file with the name C<$exe_name>.
The first one it finds is returned with its full path. If none is found,
C<find_exe()> returns undef.

=cut

sub find_exe {
    my ($class, $exe) = @_;
    $exe .= '.exe' if WIN32;
    require File::Spec;
    for my $path (
        File::Spec->path, qw(/usr/local/bin /usr/bin /usr/sbin),
        'C:\\program files\\subversion\\bin'
    ) {
        my $file = File::Spec->catfile($path, $exe);
        return $file if -f $file && -x _;
    }
    return;
}

##############################################################################

=head1 Instance Interface

=head2 Instance Methods

=head3 prepare

  $notifier->prepare;

Prepares the SVN::Notify object, collecting all the data it needs in
preparation for sending the notification email. Really it's just a shortcut
for:

  $notifier->prepare_recipients;
  $notifier->prepare_contents;
  $notifier->prepare_files;
  $notifier->prepare_subject;

Only it returns after the call to C<prepare_recipients()> if there are no
recipients (that is, as when recipients are specified solely by the
C<to_regex_map> parameter and none of the regular expressions match any of the
affected directories).

=cut

sub prepare {
    my $self = shift;
    $self->prepare_recipients;
    return $self unless @{ $self->{to} };
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
    $self->_dbpnt( "Preparing recipients list") if $self->{verbose};
    return $self unless $self->{to_regex_map} || $self->{subject_cx};
    my $tos = $self->{to};
    my $regexen = $self->{to_regex_map};
    if ($regexen) {
        $regexen = {%$regexen};
        $self->_dbpnt( "Compiling regex_map regular expressions")
          if $self->{verbose} > 1;
        for (values %$regexen) {
            $self->_dbpnt( qq{Compiling "$_"}) if $self->{verbose} > 2;
            # Remove initial slash and compile.
            s|^\^[/\\]|^|;
            $_ = qr/$_/;
        }
    } else {
        $regexen = {};
    }

    my $cx;
    my $fh = $self->_pipe('-|', $self->{svnlook}, 'dirs-changed',
                          $self->{repos_path}, '-r', $self->{revision});

    # Read in a list of the directories changed.
    while (<$fh>) {
        s/[\n\r\/\\]+$//;
        while (my ($email, $rx) = each %$regexen) {
            # If the directory matches the regex, save the email.
            if (/$rx/) {
                $self->_dbpnt( qq{"$_" matched $rx}) if $self->{verbose} > 2;
                push @$tos, $email;
                delete $regexen->{$email};
            }
        }
        # Grab the context if it's needed for the subject.
        if ($self->{subject_cx}) {
            # XXX Do we need to set utf8 here?
            my $l = length;
            $cx ||= $_;
            $cx =~ s{[/\\]?[^/\\]+$}{} until !$cx || /^$cx/;
        }
    }
    $self->_dbpnt( qq{Context is "$cx"})
        if $self->{subject_cx} && $self->{verbose} > 1;
    close $fh or warn "Child process exited: $?\n";
    $self->{cx} = $cx;
    $self->_dbpnt( 'Recipients: "', join(', ', @$tos), '"')
        if $self->{verbose} > 1;
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
    $self->_dbpnt( "Preparing contents") if $self->{verbose};
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
        $self->_dbpnt( "From: $self->{from}");
        $self->_dbpnt( "Message: @$lines");
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
the commit, then C<prepare_files()> will also specify that file name as the
context to be used in the subject line of the commit email.

=cut

sub prepare_files {
    my $self = shift;
    $self->_dbpnt( "Preparing file lists") if $self->{verbose};
    my %files;
    my $fh = $self->_pipe('-|', $self->{svnlook}, 'changed',
                          $self->{repos_path}, '-r', $self->{revision});

    # Read in a list of changed files.
    my $cx = $_ = <$fh>;
    do {
        s/[\n\r]+$//;
        if (s/^(.)(.)\s+//) {
            $self->_dbpnt( "$1,$2 => $_") if $self->{verbose} > 2;
            push @{$files{$1}}, $_;
            push @{$files{_}}, $_ if $2 ne ' ' && $1 ne '_';
        }
    } while (<$fh>);

    if ($self->{subject_cx} && $. == 1) {
        # There's only one file; it's the context.
        $cx =~ s/[\n\r]+$//;
        ($self->{cx} = $cx) =~ s/^..\s+//;
        $self->_dbpnt( qq{File context is "$self->{cx}"})
          if $self->{verbose} > 1;
    }
    # Wait till we get here to close the file handle, otherwise $. gets reset
    # to 0!
    close $fh or warn "Child process exited: $?\n";
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
line of the commit, whichever is shorter. The subject may then be truncated to
the maximum length specified by the C<max_sub_length> parameter.

=cut

sub prepare_subject {
    my $self = shift;
    $self->_dbpnt( "Preparing subject") if $self->{verbose};

    # Start with the optional message and revision number..
    $self->{subject} .=
      (defined $self->{subject_prefix} ?  "$self->{subject_prefix} " : '')
      . "[$self->{revision}] ";

    # Add the context if there is one.
    if ($self->{cx}) {
        if (my $rx = $self->{strip_cx_regex}) {
            $self->{cx} =~ s/$_// for @$rx;
        }
        my $space = $self->{no_first_line} ? '' : ': ';
        $self->{subject} .= $self->{cx}. $space if $self->{cx};
    }

    # Add the first sentence/line from the log message.
    unless ($self->{no_first_line}) {
        # Truncate to first period after a minimum of 10 characters.
        my $i = index $self->{message}[0], '. ';
        $self->{subject} .= $i > 0
          ? substr($self->{message}[0], 0, $i + 1)
          : $self->{message}[0];
    }

    # Truncate to the last word under 72 characters.
    $self->{subject} =~ s/^(.{0,$self->{max_sub_length}})\s+.*$/$1/m
      if $self->{max_sub_length}
      && length $self->{subject} > $self->{max_sub_length};

    $self->_dbpnt( qq{Subject is "$self->{subject}"}) if $self->{verbose};

    # Q-Encoding (RFC 2047)
    if (PERL58) {
        require Encode;
        Encode::from_to($self->{subject}, $self->{charset}, 'MIME-Q');
    }

    return $self;
}

##############################################################################

=head3 execute

  $notifier->execute;

Sends the notification message. This involves opening a file handle to
F<sendmail> or a tied file handle connected to an SMTP server and passing it
to C<output()>. This is the main method used to send notifications or execute
any other actions in response to Subversion activity.

=cut

sub execute {
    my $self = shift;
    $self->_dbpnt( "Sending message") if $self->{verbose};
    return $self unless @{ $self->{to} };

    my $out = $self->{smtp}
        ? SVN::Notify::SMTP->get_handle($self)
        : $self->_pipe(
            '|-', $self->{sendmail}, '-oi', '-t',
            ($self->{set_sender} ? ('-f', $self->{from}) : ())
        );

    # Output the message.
    $self->output($out);

    close $out or warn "Child process exited: $?\n";
    $self->_dbpnt( "Message sent") if $self->{verbose};
    return $self;
}

##############################################################################

=head3 output

  $notifier->output($file_handle);
  $notifier->output($file_handle, $no_headers);

Called internally by C<execute()> to output a complete email message. The file
a file handle, so that C<output()> and its related methods can print directly
to the email message. The optional second argument, if true, will suppress the
output of the email headers.

Really C<output()> is a simple wrapper around a number of other method calls.
It is thus essentially a shortcut for:

    $notifier->output_headers($out) unless $no_headers;
    $notifier->output_content_type($out);
    $notifier->start_body($out);
    $notifier->output_metadata($out);
    $notifier->output_log_message($out);
    $notifier->output_file_lists($out);
    if ($notifier->with_diff) {
        my $diff_handle = $self->diff_handle;
        if ($notifier->attach_diff) {
            $notifier->end_body($out);
            $notifier->output_attached_diff($out, $diff_handle);
        } else {
            $notifier->output_diff($out, $diff_handle);
            $notifier->end_body($out);
        }
    } else {
        $notifier->end_body($out);
    }
    $notifier->end_message($out);

=cut

sub output {
    my ($self, $out, $no_headers) = @_;
    $self->_dbpnt( "Outputting notification message") if $self->{verbose} > 1;
    $self->output_headers($out) unless $no_headers;
    $self->output_content_type($out);
    $self->start_body($out);
    $self->output_metadata($out);
    $self->output_log_message($out);
    $self->output_file_lists($out);
    if ($self->{with_diff}) {
        # Get a handle on the diff output.
        my $diff = $self->diff_handle;
        if ($self->{attach_diff}) {
            $self->end_body($out);
            $self->output_attached_diff($out, $diff);
        } else {
            $self->output_diff($out, $diff);
            $self->end_body($out);
        }
    } else {
        $self->end_body($out);
    }
    $self->end_message($out);

    return $self;
}

##############################################################################

=head3 output_headers

  $notifier->output_headers($file_handle);

Outputs the headers for the notification message headers. Should be called
only once for a single email message.

=cut

sub output_headers {
    my ($self, $out) = @_;
    $self->_dbpnt( "Outputting headers") if $self->{verbose} > 2;
    print $out
      "MIME-Version: 1.0\n",
      "From: $self->{from}\n",
      "Errors-To: $self->{from}\n",
      "To: ", join ( ', ', @{ $self->{to} } ), "\n",
      "Subject: $self->{subject}\n";
    print $out "Reply-To: $self->{reply_to}\n" if $self->{reply_to};
    print $out "X-Mailer: SVN::Notify ", $self->VERSION,
               ": http://search.cpan.org/dist/SVN-Notify/\n";

    return $self;
}

##############################################################################

=head3 output_content_type

  $notifier->output_content_type($file_handle);

Outputs the content type and transfer encoding headers. These demarcate the
body of the message. If the C<attach_diff> parameter was set to true, then a
boundary string will be generated and the Content-Type set to
"multipart/mixed" and stored as the C<boundary> attribute.

Arter that, this method outputs the content type returned by
C<content_type()>, the character set specified by the C<charset> attribute,
and a Content-Transfer-Encoding of "8bit". Subclasses can either rely on this
functionality or override this method to provide their own content type
headers.

=cut

sub output_content_type {
    my ($self, $out) = @_;
    $self->_dbpnt( "Outputting content type") if $self->{verbose} > 2;
    # Output the content type.
    if ($self->{attach_diff}) {
        # We need a boundary string.
        unless ($self->{boundary}) {
            my $salt = join '',
              ('.', '/', 0..9, 'A'..'Z', 'a'..'z')[rand 64, rand 64];
            $self->{boundary} = crypt($self->{subject}, $salt);
        }
        print $out
          qq{Content-Type: multipart/mixed; boundary="$self->{boundary}"\n\n};
    }

    my $ctype = $self->content_type;
    print $out "--$self->{boundary}\n" if $self->{attach_diff};
    print $out "Content-Type: $ctype; charset=$self->{charset}\n",
      ($self->{language} ? "Content-Language: $self->{language}\n" : ()),
      "Content-Transfer-Encoding: 8bit\n\n";
    return $self;
}

##############################################################################

=head3 start_body

  $notifier->start_body($file_handle);

This method starts the body of the notification message, which means that it
outputs the contents of the C<header> attribute, if there are any. Otherwise
it outputs nothing, but see subclasses for other behaviors.

=cut

sub start_body {
    my ($self, $out) = @_;
    print $out "$self->{header}\n\n" if $self->{header};
    return $self;
}

##############################################################################

=head3 output_metadata

  $notifier->output_metadata($file_handle);

This method outputs the metadata of the commit, including the revision number,
author (user), and date of the revision. If the C<author_url>, C<viewcvs_url>,
or C<revision_url> attributes have been set, then the appropriate URL(s) for
the revision will also be output.

=cut

sub output_metadata {
    my ($self, $out) = @_;
    print $out "Revision: $self->{revision}\n";
    if (my $url = $self->{revision_url}) {
        printf $out "          $url\n", $self->{revision};
    }

    # Output the Author any any relevant URL.
    print $out "Author:   $self->{user}\n";
    if (my $url = $self->{author_url}) {
        printf $out "          $url\n", $self->{user};
    }

    print $out "Date:     $self->{date}\n";


    print $out "\n";
    return $self;
}

##############################################################################

=head3 output_log_message

  $notifier->output_log_message($file_handle);

Outputs the commit log message, as well as the label "Log Message".

=cut

sub output_log_message {
    my ($self, $out) = @_;
    $self->_dbpnt( "Outputting log message") if $self->{verbose} > 1;
    my $msg = join "\n", @{$self->{message}};
    print $out "Log Message:\n-----------\n$msg\n";

    # Make Revision links. Mutually exclusive with viewcvs.
    if (my $url = $self->{revision_url}) {
        if (my @matches = $msg =~ /\b(?:rev(?:ision)?\s*#?\s*(\d+))\b/ig) {
            print $out "\nRevision Links:\n--------------\n";
            printf $out "    $url\n", $_ for @matches;
        }
    }

    # Make Bugzilla links.
    if (my $url = $self->bugzilla_url) {
        if (my @matches = $msg =~ /\b(?:bug\s*#?\s*(\d+))\b/ig) {
            print $out "\nBugzilla Links:\n--------------\n";
            printf $out "    $url\n", $_ for @matches;
        }
    }

    # Make RT links.
    if (my $url = $self->rt_url) {
        if (my @matches = $msg =~ /\b(?:(?:rt-)?ticket:?\s*#?\s*(\d+))\b/ig) {
            print $out "\nRT Links:\n--------\n";
            printf $out "    $url\n", $_ for @matches;
        }
    }

    # Make JIRA links.
    if (my $url = $self->jira_url) {
        if (my @matches = $msg =~ /\b([A-Z]+-\d+)\b/g) {
            print $out "\nJIRA Links:\n----------\n";
            printf $out "    $url\n", $_ for @matches;
        }
    }

    # Make GNATS links.
    if (my $url = $self->gnats_url) {
        if (my @matches = $msg =~ /\b(?:PR\s*(\d+))\b/ig) {
            print $out "\nGNATS Links:\n-----------\n";
            printf $out "    $url\n", $_ for @matches;
        }
     }

    # Make custom ticketing system links.
    if (my $url = $self->ticket_url) {
        my $regex = $self->ticket_regex
            or die q{Missing "ticket_regex" parameter to accompany }
            . q{"ticket_url" parameter};
        if (my @matches = $msg =~ /$regex/ig) {
            print $out "\nTicket Links:\n-----------\n";
            printf $out "    $url\n", $_ for @matches;
        }
    }

    else {
        die q{Missing "ticket_url" parameter to accompany }
            . q{"ticket_regex" parameter}
            if $self->ticket_regex;
    }

    return $self;
}

##############################################################################

=head3 output_file_lists

  $notifier->output_log_message($file_handle);

Outputs the lists of modified, added, and deleted files, as well as the list
of files for which properties were changed. The labels used for each group are
pulled in from the C<file_label_map()> class method.

=cut

sub output_file_lists {
    my ($self, $out) = @_;
    my $files = $self->{files} or return $self;
    $self->_dbpnt( "Outputting file lists") if $self->{verbose} > 1;
    my $map = $self->file_label_map;
    # Create the lines that will go underneath the above in the message.
    my %dash = ( map { $_ => '-' x length($map->{$_}) } keys %$map );

    foreach my $type (qw(U A D _)) {
        # Skip it if there's nothing to report.
        next unless $files->{$type};
        $self->_dbpnt( "  Outputting $map->{$type} file list")
          if $self->{verbose} > 2;

        # Identify the action and output each file.
        print $out "\n$map->{$type}:\n$dash{$type}\n";
        print $out "    $_\n" for @{ $files->{$type} };
    }
    print $out "\n";
}

##############################################################################

=head3 end_body

  $notifier->end_body($file_handle);

Closes out the body of the email by outtputing the contents of the C<footer>
attribute, if any, and then a couple of newlines. Designed to be called when
the body of the message is complete, and before any call to
C<output_attached_diff()>.

=cut

sub end_body {
    my ($self, $out) = @_;
    $self->_dbpnt( "Ending body") if $self->{verbose} > 2;
    print $out $self->{footer} ? "\n$self->{footer}\n" : "\n";
    return $self;
}

##############################################################################

=head3 output_diff

  $notifier->output_diff($out_file_handle, $diff_file_handle);

Reads diff data from C<$diff_file_handle> and outputs it to to
C<$out_file_handle>.

=cut

sub output_diff {
    my $self = shift;
    $self->_dbpnt( "Outputting diff") if $self->{verbose} > 1;
    $self->_dump_diff(@_);
}

##############################################################################

=head3 output_attached_diff

  $notifier->output_attached_diff($out_file_handle, $diff_file_handle);

Reads diff data from C<$diff_file_handle> and outputs it to to
C<$out_file_handle> as an attachment.

=cut

sub output_attached_diff {
    my ($self, $out, $diff) = @_;
    $self->_dbpnt( "Attaching diff") if $self->{verbose} > 2;
    print $out "\n--$self->{boundary}\n",
      "Content-Disposition: attachment; filename=",
      "r$self->{revision}-$self->{user}.diff\n",
      "Content-Type: text/plain; charset=$self->{charset}\n",
      ($self->{language} ? "Content-Language: $self->{language}\n" : ()),
      "Content-Transfer-Encoding: 8bit\n\n";
    $self->_dump_diff($out, $diff);
}

##############################################################################

=head3 end_message

  $notifier->end_message($file_handle);

Outputs the final part of the message,. In this case, that means only a
boundary if the C<attach_diff> parameter is true. Designed to be called after
any call to C<output_attached_diff()>.

=cut

sub end_message {
    my ($self, $out) = @_;
    print $out "--$self->{boundary}--\n" if $self->{attach_diff};
    return $self;
}

##############################################################################

=head3 diff_handle

  my $diff = $notifier->diff_handle;
  while (<$diff>) { print }

Returns a file handle reference providing access to the the commit diff. It
will usually be passed as the second argument to C<output_diff()> or
C<output_attached_diff()>.

=cut

sub diff_handle {
    my $self = shift;
    return $self->_pipe(
        '-|'   => $self->{svnlook},
        'diff' => $self->{repos_path},
        '-r'   => $self->{revision},
        ( $self->{diff_switches}
            ? grep { defined && $_ ne '' }
                # Allow quoting of arguments, but strip out the quotes.
                split /(?:'([^']+)'|"([^"]+)")?\s+(?:'([^']+)'|"([^"]+)")?/,
                $self->{diff_switches}
            : ()
        ),
    );
}

##############################################################################
# This method actually dumps the output of C<svnlook diff>. It's a separate
# method because output_attached_diff() and output_diff() do essentially the
# same thing, so they can both call it. The diff output will be truncated at
# max_diff_length, if specified.
##############################################################################

sub _dump_diff {
    my ($self, $out, $diff) = @_;

    if (my $max = $self->{max_diff_length}) {
        my $length = 0;
        while (<$diff>) {
            s/[\n\r]+$//;
            if (($length += length) < $max) {
                print $out "$_\n";
            }
            else {
                print $out
                    "\n\@\@ Diff output truncated at $max characters. \@\@\n";
                last;
            }
        }
    }

    else {
        while (<$diff>) {
            s/[\n\r]+$//;
            print $out "$_\n";
        }
    }
    close $diff or warn "Child process exited: $?\n";
    return $self;
}

##############################################################################

__PACKAGE__->_accessors(qw(
    repos_path
    revision
    to_regex_map
    from
    user_domain
    svnlook
    sendmail
    set_sender
    smtp
    charset
    io_layer
    language
    with_diff
    attach_diff
    diff_switches
    reply_to
    subject_prefix
    subject_cx
    max_sub_length
    max_diff_length
    author_url
    revision_url
    rt_url
    bugzilla_url
    jira_url
    gnats_url
    ticket_url
    ticket_regex
    header
    footer
    verbose
    boundary
    user
    date
    message
    message_size
    subject
    files
));

##############################################################################
# This method is used to create accessors for the list of attributes passed to
# it. It creates them both for SVN::Notify (just above) and for all subclasses
# in register_attributes().
##############################################################################

sub _accessors {
    my $class = shift;
    for my $attr (@_) {
        no strict 'refs';
        *{"$class\::$attr"} = sub {
            my $self = shift;
            return $self->{$attr} unless @_;
            $self->{$attr} = shift;
            return $self;
        };
    }
}

# Aliases for deprecated attributes.
sub svnweb_url  { shift->revision_url(@_) }
sub viewcvs_url { shift->revision_url(@_) }

for my $attr (qw(to strip_cx_regex)) {
    no strict 'refs';
    *{__PACKAGE__ . "::$attr"} = sub {
        my $self = shift;
        return wantarray ? @{ $self->{$attr} } : $self->{$attr}[0] unless @_;
        $self->{$attr}= \@_;
        return $self;
    };
}

=head2 Accessors

=head3 repos_path

  my $repos_path = $notifier->repos_path;
  $notifier = $notifier->repos_path($repos_path);

Gets or sets the value of the C<repos_path> attribute.

=head3 revision

  my $revision = $notifier->revision;
  $notifier = $notifier->revision($revision);

Gets or sets the value of the C<revision> attribute.

=head3 to

  my $to = $notifier->to;
  $notifier = $notifier->to($to);
  my @tos = $notifier->to;
  $notifier = $notifier->to(@tos);

Gets or sets the list of values stored in the C<to> attribute. In a scalar
context, it returns only the first value in the list, for backards
compatibility with older versions of SVN::Notify. In list context, it of
course returns the entire list. Pass in one or more values to set all of the
values for the C<to> attribute.

=head3 to_regex_map

  my $to_regex_map = $notifier->to_regex_map;
  $notifier = $notifier->to_regex_map($to_regex_map);

Gets or sets the value of the C<to_regex_map> attribute, which is a hash
reference of email addresses mapped to regular expressions.

=head3 from

  my $from = $notifier->from;
  $notifier = $notifier->from($from);

Gets or sets the value of the C<from> attribute.

=head3 user_domain

  my $user_domain = $notifier->user_domain;
  $notifier = $notifier->user_domain($user_domain);

Gets or sets the value of the C<user_domain> attribute.

=head3 svnlook

  my $svnlook = $notifier->svnlook;
  $notifier = $notifier->svnlook($svnlook);

Gets or sets the value of the C<svnlook> attribute.

=head3 sendmail

  my $sendmail = $notifier->sendmail;
  $notifier = $notifier->sendmail($sendmail);

Gets or sets the value of the C<sendmail> attribute.

=head3 set_sender

  my $set_sender = $notifier->set_sender;
  $notifier = $notifier->set_sender($set_sender);

Gets or sets the value of the C<set_sender> attribute.

=head3 smtp

  my $smtp = $notifier->smtp;
  $notifier = $notifier->smtp($smtp);

Gets or sets the value of the C<smtp> attribute.

=head3 charset

  my $charset = $notifier->charset;
  $notifier = $notifier->charset($charset);

Gets or sets the value of the C<charset> attribute.

=head3 io_layer

  my $io_layer = $notifier->io_layer;
  $notifier = $notifier->io_layer($io_layer);

Gets or sets the value of the C<io_layer> attribute.

=head3 language

  my $language = $notifier->language;
  $notifier = $notifier->language($language);

Gets or sets the value of the C<language> attribute.

=head3 with_diff

  my $with_diff = $notifier->with_diff;
  $notifier = $notifier->with_diff($with_diff);

Gets or sets the value of the C<with_diff> attribute.

=head3 attach_diff

  my $attach_diff = $notifier->attach_diff;
  $notifier = $notifier->attach_diff($attach_diff);

Gets or sets the value of the C<attach_diff> attribute.

=head3 diff_switches

  my $diff_switches = $notifier->diff_switches;
  $notifier = $notifier->diff_switches($diff_switches);

Gets or sets the value of the C<diff_switches> attribute.

=head3 reply_to

  my $reply_to = $notifier->reply_to;
  $notifier = $notifier->reply_to($reply_to);

Gets or sets the value of the C<reply_to> attribute.

=head3 subject_prefix

  my $subject_prefix = $notifier->subject_prefix;
  $notifier = $notifier->subject_prefix($subject_prefix);

Gets or sets the value of the C<subject_prefix> attribute.

=head3 subject_cx

  my $subject_cx = $notifier->subject_cx;
  $notifier = $notifier->subject_cx($subject_cx);

Gets or sets the value of the C<subject_cx> attribute.

=head3 strip_cx_regex

  my $strip_cx_regex = $notifier->strip_cx_regex;
  $notifier = $notifier->strip_cx_regex($strip_cx_regex);
  my @strip_cx_regexs = $notifier->strip_cx_regex;
  $notifier = $notifier->strip_cx_regex(@strip_cx_regexs);

Gets or sets the list of values stored in the C<strip_cx_regex> attribute. In
a scalar context, it returns only the first value in the list; in list
context, it of course returns the entire list. Pass in one or more values to
set all of the values for the C<strip_cx_regex> attribute.

=head3 max_sub_length

  my $max_sub_length = $notifier->max_sub_length;
  $notifier = $notifier->max_sub_length($max_sub_length);

Gets or sets the value of the C<max_sub_length> attribute.

=head3 max_diff_length

  my $max_diff_length = $notifier->max_diff_length;
  $notifier = $notifier->max_diff_length($max_diff_length);

Gets or set the value of the C<max_diff_length> attribute.

=head3 author_url

  my $author_url = $notifier->author_url;
  $notifier = $notifier->author_url($author_url);

Gets or sets the value of the C<author_url> attribute.

=head3 revision_url

  my $revision_url = $notifier->revision_url;
  $notifier = $notifier->revision_url($revision_url);

Gets or sets the value of the C<revision_url> attribute.

=head3 svnweb_url

Deprecated. Pleas use C<revision_url()>, instead.

=head3 viewcvs_url

Deprecated. Pleas use C<revision_url()>, instead.

=head3 verbose

  my $verbose = $notifier->verbose;
  $notifier = $notifier->verbose($verbose);

Gets or sets the value of the C<verbose> attribute.

=head3 bondary

  my $bondary = $notifier->bondary;
  $notifier = $notifier->bondary($bondary);

Gets or sets the value of the C<bondary> attribute. This string is normally
set by a call to C<output_headers()>, but may be set ahead of time.

=head3 user

  my $user = $notifier->user;
  $notifier = $notifier->user($user);

Gets or sets the value of the C<user> attribute, which is set to the value
pulled in from F<svnlook> by the call to C<prepare_contents()>.

=head3 date

  my $date = $notifier->date;
  $notifier = $notifier->date($date);

Gets or sets the value of the C<date> attribute, which is set to the value
pulled in from F<svnlook> by the call to C<prepare_contents()>.

=head3 message

  my $message = $notifier->message;
  $notifier = $notifier->message($message);

Gets or sets the value of the C<message> attribute, which is set to an array
reference of strings by the call to C<prepare_contents()>.

=head3 message_size

  my $message_size = $notifier->message_size;
  $notifier = $notifier->message_size($message_size);

Gets or sets the value of the C<message_size> attribute, which is set to the
value pulled in from F<svnlook> by the call to C<prepare_contents()>.

=head3 subject

  my $subject = $notifier->subject;
  $notifier = $notifier->subject($subject);

Gets or sets the value of the C<subject> attribute, which is normally set
by a call to C<prepare_subject()>, but may be set explicitly.

=head3 files

  my $files = $notifier->files;
  $notifier = $notifier->files($files);

Gets or sets the value of the C<files> attribute, which is set to a hash
reference of change type mapped to arrays of strings by the call to
C<prepare_files()>.

=head3 header

  my $header = $notifier->header;
  $notifier = $notifier->header($header);

Gets or set the value of the C<header> attribute.

=head3 footer

  my $footer = $notifier->footer;
  $notifier = $notifier->footer($footer);

Gets or set the value of the C<footer> attribute.

=cut

##############################################################################
# This method forks off a process to execute an external program and any
# associated arguments and returns a file handle that can be read from to
# fetch the output of the external program, or written to. Pass "-|" as the
# sole argument to read from another process (such as svnlook), and pass "|-"
# to write to another process (such as sendmail).
##############################################################################

sub _pipe {
    my ($self, $mode) = (shift, shift);
    $self->_dbpnt( q{Piping execution of "} . join(q{" "}, @_) . q{"})
      if $self->{verbose};
    # Safer version of backtick (see perlipc(1)).
    local *PIPE;
    if (WIN32) {
        my $cmd = $mode eq '-|'
            ? q{"}  . join(q{" "}, @_) . q{"|}
            : q{|"} . join(q{" "}, @_) . q{"};
        open PIPE, $cmd or die "Cannot fork: $!\n";
        return *PIPE;
    }
    my $pid = open PIPE, $mode;
    die "Cannot fork: $!\n" unless defined $pid;

    if ($pid) {
        # Parent process. Set the encoing layer and return the file handle.
        binmode PIPE, ":$self->{io_layer}" if PERL58;
        return *PIPE;
    } else {
        # Child process. Execute the commands.
        exec @_ or die "Cannot exec $_[0]: $!\n";
        # Not reached.
    }
}

##############################################################################
# This method passes its arguments to _pipe(), but then fetches each line
# off output from the returned file handle, safely strips out and replaces any
# newlines and carriage returns, and returns an array reference of those
# lines.
##############################################################################

sub _read_pipe {
    my $self = shift;
    my $fh = $self->_pipe('-|', @_);
    local $/; my @lines = split /(?:\r\n|\r|\n)/, <$fh>;
    close $fh or warn "Child process exited: $?\n";
    return \@lines;
}

##############################################################################
# This method is used for debugging output in various verbose modes.
##############################################################################

sub _dbpnt { print __PACKAGE__, ": $_[1]\n" }

package SVN::Notify::SMTP;

sub get_handle {
    my ($class, $notifier) = @_;

    # Load Net::SMTP or the appropriate subclass.
    my $smtp_class = do {
        if ($notifier->{smtp_user}) {
            require Net::SMTP_auth;
            'Net::SMTP_auth';
        } else {
            require Net::SMTP;
            'Net::SMTP';
        }
    };

    my $smtp = $smtp_class->new(
        $notifier->{smtp},
        ( $notifier->{verbose} > 1 ? ( Debug => 1 ) : ())
    ) or die "Unable to create $smtp_class object: $!";

    $smtp->auth( @{ $notifier }{qw(smtp_authtype smtp_user smtp_pass)} )
        if $notifier->{smtp_user};

    binmode tied(*{ $smtp->tied_fh }), ":$notifier->{io_layer}"
        if SVN::Notify::PERL58;
    $smtp->mail($notifier->{from});
    $smtp->to(@{ $notifier->{to} });
    $smtp->data;
    tie local(*SMTP), $class, $smtp;
    return *SMTP;
}

sub TIEHANDLE {
    my ($class, $smtp) = @_;
    bless \$smtp, $class;
}

sub PRINT  { ${+shift}->datasend(@_) }
sub PRINTF { ${+shift}->datasend(sprintf shift, @_) }
sub CLOSE  {
    my $self = shift;
    $$self->dataend;
    $$self->quit;
}

1;
__END__

=head1 See Also

=over

=item L<SVN::Notify::HTML|SVN::Notify::HTML>

=item L<SVN::Notify::HTML::ColorDiff|SVN::Notify::HTML::ColorDiff>

Subclasses SVN::Notify.

=item L<https://sourceforge.net/docs/E09#svn_notify>

SourceForge.net support for SVN::Notify.

=item L<http://svn.haxx.se/users/archive-2006-05/0593.shtml>

Tutorial for installing Apache, Subversion, and SVN::Notify on Windows.

=back

=head1 Bugs

Please send bug reports to <bug-svn-notify@rt.cpan.org>.

=head1 Author

=begin comment

Fake-out Module::Build. Delete if it ever changes to support =head1 headers
other than all uppercase.

=head1 AUTHOR

=end comment

David Wheeler <david@kineticode.com>

=head1 Copyright and License

Copyright (c) 2004-2006 Kineticode, Inc. All Rights Reserved.

This module is free software; you can redistribute it and/or modify it under the
same terms as Perl itself.

=cut
