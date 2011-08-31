package SVN::Notify;

use strict;
require 5.006_000;
use constant WIN32  => $^O eq 'MSWin32';
use constant PERL58 => $] > 5.007_000;
require Encode if PERL58;
$SVN::Notify::VERSION = '2.83';

# Make sure any output (such as from _dbpnt()) triggers no Perl warnings.
if (PERL58) {
    # Dupe them?
    binmode STDOUT, ':utf8';
    binmode STDERR, ':utf8';
}

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
fully subclassable, to add new functionality, and offers L<comprehensive
content filtering|SVN::Notify::Filter> to easily modify the format of its
messages. By default, A list of all the files affected by the commit will be
assembled and listed in a single message. An additional option allows diffs to
be calculated for the changes and either appended to the message or added as
an attachment. See the C<with_diff> and C<attach_diff> options below.

=head1 Usage

To use SVN::Notify, simply add a call to F<svnnotify> to your Subversion
repository's F<post-commit> script. This script lives in the F<hooks>
directory at the root of the repository directory; consult the documentation
in F<post-commit.tmpl> for details. Make sure that you specify the complete
path to F<svnnotify>, as well as to F<svnlook> and F<sendmail> in the options
passed to F<svnnotify> so that everything executes properly. And if you
specify any string options, be sure that they are in the encoding specified by
the C<--encoding> option, or UTF-8 if you have not specified C<--encoding>.

=head2 Windows Usage

To get SVN::Notify to work properly in a F<post-commit> script, you must set
the following environment variables, as they will likely not be present inside
Apache:

=over

=item PATH=C:\perl\bin

=item OS=Windows_NT

=item SystemRoot=C:\WINDOWS

=back

See L<Windows Subversion + Apache + TortoiseSVN + SVN::Notify
HOWTO|http://svn.haxx.se/users/archive-2006-05/0593.shtml> for more detailed
information on getting SVN::Notify running on Windows. If you have issues with
asynchronous execution, try using
L<F<HookStart.exe>|http://www.koders.com/csharp/fidE2724F44EF2D47F1C0FE76C538006435FA20051D.aspx>
to run F<svnnotify>.

=cut

# Map the svnlook changed codes to nice labels.
my %map = (
    U => 'Modified Paths',
    A => 'Added Paths',
    D => 'Removed Paths',
    _ => 'Property Changed',
);

my %filters;

##############################################################################

=head1 Class Interface

=head2 Constructor

=head3 new

  my $notifier = SVN::Notify->new(%params);

Constructs and returns a new SVN::Notify object. This object is a handle on
the whole process of collecting meta data and content for the commit email and
then sending it. As such, it takes a number of parameters to affect that
process.

Each of these parameters has a corresponding command-line option that can be
passed to F<svnnotify>. The options have the same names as these parameters,
but any underscores you see here should be replaced with dashes when passed to
F<svnnotify>. Most also have a corresponding single-character option. On Perl
5.8 and higher, If you pass parameters to C<new()>, they B<must> be L<decoded
into Perl's internal form|Encode/"PERL ENCODING API"> if they have any
non-ASCII characters.

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
unless either C<to_regex_map> or C<to_email_map> is specified.

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
unless C<to> or C<to_email_map> is specified.

The command-line options, C<--to-regex_map> and C<-x>, can be specified any
number of times, once for each entry in the hash to be passed to C<new()>. The
value passed to the option must be in the form of the key and the value
separated by an equal sign. Consult the L<Getopt::Long> documentation for more
information.

Here's an example complements of Matt Doar of how to use C<to_regex_map> to do
per-branch matching:

  author=`svnlook author $REPOS -r $REV`

  # The mail regexes should match all the top-level directories
  /usr/bin/svnnotify --repos-path "$REPOS" --revision "$REV" \
  -x eng-bar@example.com,${EXTRAS}="^Bar" \
  -x eng-foo@example.com,${EXTRAS}="^trunk/Foo|^branches/Foo|^tags/Foo" \
  -x $author@example.com="^users" --subject-cx

=item to_email_map

  svnnotify --to-email-map L18N=translate@example.com \
            --to-email-map License=legal@example.com

The inverse of C<to_regex_map>: The regular expression is the hash key
and the email address or addresses are the value.

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

=item smtp_tls

  svnnotify --smtp-tls

Use TLS authentication and encrypted channels for connecting with the server.
Usually, TLS servers will require user/password authentication.

=item smtp_user

  svnnotify --smtp-user myuser

The user name for SMTP authentication. If this option is specified,
SVN::Notify will use L<Net::SMTP_auth|Net::SMTP_auth> to send the notification
message, and will of course authenticate to the SMTP server.

=item smtp_pass

  svnnotify --smtp-pass mypassword

The password for SMTP authentication. Use in parallel with C<smtp_user>.

=item smtp_port

  svnnotify --smtp-port 465

The port for an SMTP server through which to send the notification email. The
default port is 25.

=item smtp_authtype

  svnnotify --smtp-authtype authtype

Deprecated in SVN::Notify 2.83, where it has become a no-op. The auth type is
determined by the contents returned by the SMTP server's response to the
C<EHLO> command. See L<Net::SMTP::TLS/TLS and AUTHentication> for details.

=item encoding

  svnnotify --encoding UTF-8
  svnnotify -c Big5

The character set typically used on the repository for log messages, file
names, and file contents. Used to specify the character set in the email
Content-Type headers and, when the C<language> parameter is specified, the
C<$LANG> environment variable when launching C<sendmail>. See L</"Character
Encoding Support"> for more information. Defaults to "UTF-8".

=item charset

  svnnotify --charset UTF-8

Deprecated. Use C<encoding> instead.

=item svn_encoding

  svnnotify --svn-encoding euc-jp

The character set used in files and log messages managed in Subversion. It's
useful to set this option if you store files in Subversion using one character
set but want to send notification messages in a different character set.
Therefore C<encoding> would be used for the notification message, and
C<svn_encoding> would be used to read in data from Subversion. See
L</"Character Encoding Support"> for more information. Defaults to the value
stored in C<encoding>.

=item diff_encoding

  svnnotify --diff-encoding iso-2022-jp

The character set used by files in Subversion, and thus present in the the
diff. It's useful to set this option if you store files in Subversion using
one character write log messages in a different character set. Therefore
C<svn_encoding> would be used to read the log message and C<diff_encoding>
would be used to read the diff from Subversion. See L</"Character Encoding
Support"> for more information. Defaults to the value stored in
C<svn_encoding>.

=item language

  svnnotify --language fr
  svnnotify -g i-klingon

The language typically used on the repository for log messages, file names,
and file contents. Used to specify the email Content-Language header and to
set the C<$LANG> environment variable to C<< $notify->language . '.' .
$notify->encoding >> before executing C<svnlook> and C<sendmail> (but not for
sending data to Net::SMTP). Undefined by default, meaning that no
Content-Language header is output and the C<$LANG> environment variable will
not be set. See L</"Character Encoding Support"> for more information.

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

=item add_headers

  svnnotify --add-header X-Approve=letMeIn

Add a header to the notification email message. The header name and its value
must be separated by an equals sign. Specify the option multiple times in
order to add multiple headers. Headers with the same names are allowed. Not to
be confused with the C<--header> option, which adds introductory text to the
beginning of the email body.

=item subject_prefix

  svnnotify --subject-prefix [Devlist]
  svnnotify -P [%d (Our-Developers)]

An optional string to prepend to the beginning of the subject line of the
notification email. If it contains '%d', it will be used to place the revision
number; otherwise it will simply be prepended to the subject, which will
contain the revision number in brackets.

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

Adds a specified text to each message as a header at the beginning of the body
of the message. Not to be confused with the C<--add-header> option, which adds
a header to the headers section of the email.

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

=item filters

  svnnotify --filter Trac -F My::Filter

  SVN::Notify->new( %params, filters => ['Markdown', 'My::Filter'] );

Specify a more module to be loaded in the expectation that it defines output
filters. For example, L<SVN::Notify::Filter::Trac|SVN::Notify::Filter::Trac>
loads a filter that converts log messages from Trac's markup format to HTML.
L<SVN::Notify::Filter::Markdown|SVN::Notify::Filter::Markdown>, available on
CPAN, does the same for Markdown format. Check CPAN for other SVN::Notify
filter modules.

This command-line option can be specified more than once to load multiple
filters. The C<filters> parameter to C<new()> should be an array reference of
modules names. If a value contains "::", it is assumed to be a complete module
name. Otherwise, it is assumed to be in the SVN::Notify::Filter name space.
See L<SVN::Notify::Filter|SVN::Notify::Filter> for details on writing your own
output filters (it's really easy, I promise!).

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

=item ticket_map

  svnnotify --ticket-map '\[?#\s*(\d+)\s*\]?=http://example.com/ticket?id=%s' \
            --ticket-map 'rt=http://rt.cpan.org/NoAuth/Bugs.html?id=%s' \
            --ticket-map '\b([A-Z0-9]+-\d+)\b=http://jira/browse/%s'

Specifies a mapping between a regular expression and a URL. The regular
expression should return a single match to be interpolated into the URL, which
should be a C<sprintf> format using "%s" to place the match (usually the
ticket identifier) from the regex. The command-line option may be specified
any number of times for different ticketing systems. To the API, it must be
passed as a hash reference.

The first example matches "[#1234]" or "#1234" or "[# 1234]". This regex
should be as specific as possible, preferably wrapped in "\b" to match word
boundaries. If you're using L<SVN::Notify::HTML|SVN::Notify::HTML>, be sure to
read its documentation for a different regular expression requirement!

Optionally, the key value can be a placeholder for a regular expression used
internally by SVN::Notify to match strings typically used for well-known
ticketing systems. Those keys are:

=over

=item rt

Matches Request Tracker (RT) ticket references of the form "Ticket # 12",
"ticket 6", "RT # 52", "rt 52", "RT-Ticket # 213" or even "Ticket#1066".

=item bugzilla

Matches Bugzilla bug references of the form "Bug # 12" or "bug 6" or even
"Bug#1066".

=item jira

Matches JIRA references of the form "JRA-1234".

=item gnats

Matches GnatsWeb references of the form "PR 1234".

=back

=item rt_url

  svnnotify --rt-url 'http://rt.cpan.org/NoAuth/Bugs.html?id=%s'
  svnnotify -T 'http://rt.perl.org/NoAuth/Bugs.html?id=%s'

A shortcut for C<--ticket-map 'rt=$url'> provided for backwards compatibility.

=item bugzilla_url

  svnnotify --bugzilla-url 'http://bugzilla.mozilla.org/show_bug.cgi?id=%s'
  svnnotify -B 'http://bugs.bricolage.cc/show_bug.cgi?id=%s'

A shortcut for C<--ticket-map 'bugzilla=$url'> provided for backwards
compatibility.

=item jira_url

  svnnotify --jira-url 'http://jira.atlassian.com/secure/ViewIssue.jspa?key=%s'
  svnnotify -J 'http://nagoya.apache.org/jira/secure/ViewIssue.jspa?key=%s'

A shortcut for C<--ticket-map 'jira=$url'> provided for backwards
compatibility.

=item gnats_url

  svnnotify --gnats-url 'http://gnatsweb.example.com/cgi-bin/gnatsweb.pl?cmd=view&pr=%s'
  svnnotify -G 'http://gnatsweb.example.com/cgi-bin/gnatsweb.pl?cmd=view&pr=%s'

A shortcut for C<--ticket-map 'gnats=$url'> provided for backwards
compatibility.

=item ticket_url

  svnnotify --ticket-url 'http://ticket.example.com/showticket.html?id=%s'

Deprecated. Use C<ticket_map>, instead.

=item ticket_regex

  svnnotify --ticket-regex '\[?#\s*(\d+)\s*\]?'

Deprecated. Use C<ticket_map>, instead.

=item verbose

  svnnotify --verbose -V

A value between 0 and 3 specifying how verbose SVN::Notify should be. The
default is 0, meaning that SVN::Notify will be silent. A value of 1 causes
SVN::Notify to output some information about what it's doing, while 2 and 3
each cause greater verbosity. To set the verbosity on the command line, simply
pass the C<--verbose> or C<-V> option once for each level of verbosity, up to
three times. Output from SVN::Notify is sent to C<STDOUT>.

=item boundary

The boundary to use between email body text and attachments. This is normally
generated by SVN::Notify.

=item subject

The subject of the email to be sent. This attribute is normally generated by
C<prepare_subject()>.

=back

=cut

# XXX Sneakily used by SVN::Notify::HTML. Change to use class methods?
our %_ticket_regexen = (
    rt       => '\b((?:rt|(?:rt-)?ticket:?)\s*#?\s*(\d+))\b',
    bugzilla => '\b(bug\s*#?\s*(\d+))\b',
    jira     => '\b([A-Z0-9]+-\d+)\b',
    gnats    => '\b(PR\s*(\d+))\b',
);

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

    # Load any filters.
    $params{filters} ||= {};
    if (ref $params{filters} eq 'ARRAY') {
        my $filts = {};
        for my $pkg ( @{ $params{filters} } ) {
            $pkg = "SVN::Notify::Filter::$pkg" if $pkg !~ /::/;
            if ($filters{$pkg}) {
                while (my ($k, $v) = each %{ $filters{$pkg} }) {
                    $filts->{$k} ||= [];
                    push @{ $filts->{$k} }, $v;
                }
            } else {
                eval "require $pkg" or die $@;
                $filters{$pkg} = {};
                no strict 'refs';
                while ( my ($k, $v) = each %{ "$pkg\::" } ) {
                    my $code = *{$v}{CODE} or next;
                    $filters{$pkg}->{$k} = $code;
                    $filts->{$k} ||= [];
                    push @{ $filts->{$k} }, $code;
                }
            }
        }
        $params{filters} = $filts;
    }

    # Make sure that the tos are an arrayref.
    $params{to} = [ $params{to} || () ] unless ref $params{to};

    # Check for required parameters.
    $class->_dbpnt( "Checking required parameters to new()")
      if $params{verbose};
    _usage( qq{Missing required "repos_path" parameter} )
      unless $params{repos_path};
    _usage( qq{Missing required "revision" parameter} )
      unless $params{revision};

    # Set up default values.
    $params{svnlook}        ||= $ENV{SVNLOOK}  || $class->find_exe('svnlook');
    $params{with_diff}      ||= $params{attach_diff};
    $params{verbose}        ||= 0;
    $params{encoding}       ||= $params{charset} || 'UTF-8';
    $params{svn_encoding}   ||= $params{encoding};
    $params{diff_encoding}  ||= $params{svn_encoding};
    $params{sendmail}       ||= $ENV{SENDMAIL} || $class->find_exe('sendmail')
        unless $params{smtp};

    _usage( qq{Cannot find sendmail and no "smtp" parameter specified} )
        unless $params{sendmail} || $params{smtp};

    # Set up the environment locale.
    if ( $params{language} && !$ENV{LANG} ) {
        ( my $lang_country = $params{language} ) =~ s/-/_/g;
        for my $p (qw(encoding svn_encoding)) {
            my $encoding = $params{$p};
            $encoding =~ s/-//g if uc($encoding) ne 'UTF-8';
            (my $label = $p ) =~ s/(_?)encoding/$1/;
            $params{"${label}env_lang"} = "$lang_country.$encoding";
        }
    }

    # Set up the revision URL.
    $params{revision_url} ||= delete $params{svnweb_url}
                          ||  delete $params{viewcvs_url};
    if ($params{revision_url} && $params{revision_url} !~ /%s/) {
        warn "--revision-url must have '%s' format\n";
        $params{revision_url} .= '/revision/?rev=%s&view=rev'
    }

    # Set up the issue tracking links.
    my $track = $params{ticket_map};
    if ($params{ticket_regex}) {
        $track->{ delete $params{ticket_regex} } = delete $params{ticket_url};
    }

    for my $system (qw(rt bugzilla jira gnats)) {
        my $param = $system . '_url';
        if ($params{ $param }) {
            $track->{ $system } = delete $params{ $param };
            warn "--$system-url must have '%s' format\n"
                unless $track->{ $system } =~ /%s/;
        }
    }
    $params{ticket_map} = $track if $track;

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

This method use Getopt::Long to parse C<@ARGV>. It then looks for any
C<handler> and C<filter> options and, if it finds any, loads the appropriate
classes and parses any options they requires from C<@ARGV>. Subclasses and
filter classes should use C<register_attributes()> to register any attributes
and options they require.

After that, on Perl 5.8 and later, it decodes all of the string option from
the encoding specified by the C<encoding> option or UTF-8. This allows options
to be passed to SVN::Notify in that encoding and end up being displayed
properly in the resulting notification message.

=cut

sub get_options {
    my $class = shift;
    my $opts = {};
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
        'to-email-map=s%'     => \$opts->{to_email_map},
        'from|f=s'            => \$opts->{from},
        'user-domain|D=s'     => \$opts->{user_domain},
        'svnlook|l=s'         => \$opts->{svnlook},
        'sendmail|s=s'        => \$opts->{sendmail},
        'set-sender|E'        => \$opts->{set_sender},
        'smtp=s'              => \$opts->{smtp},
        'smtp-port=i'         => \$opts->{smtp_port},
        'smtp-tls!'           => \$opts->{smtp_tls},
        'encoding|charset|c=s'=> \$opts->{encoding},
        'diff-encoding=s'     => \$opts->{diff_encoding},
        'svn-encoding=s'      => \$opts->{svn_encoding},
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
        'filter|F=s@'         => \$opts->{filters},
        'author-url|A=s'      => \$opts->{author_url},
        'ticket-regex=s'      => \$opts->{ticket_regex},
        'ticket-map=s%'       => \$opts->{ticket_map},
        'verbose|V+'          => \$opts->{verbose},
        'help|h'              => \$opts->{help},
        'man|m'               => \$opts->{man},
        'version|v'           => \$opts->{version},
        'header=s'            => \$opts->{header},
        'footer=s'            => \$opts->{footer},
        'smtp-user=s'         => \$opts->{smtp_user},
        'smtp-pass=s'         => \$opts->{smtp_pass},
        'smtp-authtype=s'     => \$opts->{smtp_authtype},
        'add-header=s%'       => sub {
            shift; push @{ $opts->{add_headers}{+shift} }, shift
        },
        'revision-url|U|svnweb-url|S|viewcvs-url=s' => \$opts->{revision_url},
        'rt-url|T|bugzilla-url|B|jira-url|J|gnats-url|G|ticket-url=s'
            => \$opts->{ticket_url},
    ) or return;

    # Load a subclass if one has been specified.
    if (my $hand = $opts->{handler}) {
        eval "require " . __PACKAGE__ . "::$hand" or die $@;
        if ($hand eq 'Alternative') {
            # Load the alternative subclasses.
            Getopt::Long::GetOptions(
                map { delete $OPTS{$_} => \$opts->{$_} } keys %OPTS
            );
            for my $alt (@{ $opts->{alternatives} || ['HTML']}) {
                eval "require " . __PACKAGE__ . "::$alt" or die $@;
            }
        }
    }

    # Load any filters.
    if ($opts->{filters}) {
        for my $pkg ( @{ $opts->{filters} } ) {
            $pkg = "SVN::Notify::Filter::$pkg" if $pkg !~ /::/;
            eval "require $pkg" or die $@;
        }
    }

    # Disallow pass-through so that any invalid options will now fail.
    Getopt::Long::Configure (qw(no_pass_through));
    my @to_decode;
    if (%OPTS) {
        # Get a list of string options we'll need to decode.
        @to_decode = map { $OPTS{$_} } grep { /=s$/ } keys %OPTS
            if PERL58;

        # Load any other options.
        Getopt::Long::GetOptions(
            map { delete $OPTS{$_} => \$opts->{$_} } keys %OPTS
        );
    } else {
        # Call GetOptions() again so that invalid options will be properly
        # caught.
        Getopt::Long::GetOptions();
    }

    if (PERL58) {
        # Decode all string options.
        my $encoding = $opts->{encoding} || 'UTF-8';
        for my $opt ( qw(
            repos_path
            revision
            from
            user_domain
            svnlook
            sendmail
            smtp
            smtp_tls
            smtp_port
            diff_switches
            reply_to
            subject_prefix
            handler
            author_url
            ticket_regex
            header
            footer
            smtp_user
            smtp_pass
            revision_url
            ticket_url
        ), @to_decode ) {
            $opts->{$opt} = Encode::decode( $encoding, $opts->{$opt} )
                if $opts->{$opt};
        }
    }

    # Clear the extra options specifications and return.
    %OPTS = ();
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
    require Config;
    for my $path (
        File::Spec->path,
        qw(/usr/local/bin /usr/bin /usr/sbin),
        'C:\\program files\\subversion\\bin',
        $Config::Config{installbin},
        $Config::Config{installscript},
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
C<to_regex_map> or C<to_email_map> parameter and none of the regular
expressions match any of the affected directories).

=cut

sub prepare {
    my $self = shift;
    $self->run_filters('pre_prepare');
    _usage(
        qq{Missing required "to", "to_regex_map", or "to_email_map" parameter}
    ) unless @{$self->{to}} || $self->{to_regex_map} || $self->{to_email_map};
    $self->prepare_recipients;
    return $self unless @{ $self->{to} };
    $self->prepare_contents;
    $self->prepare_files;
    $self->prepare_subject;
    $self->run_filters('post_prepare');
    return $self;
}

##############################################################################

=head3 prepare_recipients

  $notifier->prepare_recipients;

Collects and prepares a list of the notification recipients. The recipients
are a combination of the value passed to the C<to> parameter as well as any
email addresses specified as keys in the hash reference passed C<to_regex_map>
parameter or values passed to the C<to_email_map> parameter, where the
corresponding regular expressions stored in the hash matches one or more of
the names of the directories affected by the commit.

If the F<subject_cx> parameter to C<new()> has a true value,
C<prepare_recipients()> also determines the directory name to use for the
context.

=cut

sub prepare_recipients {
    my $self = shift;
    $self->_dbpnt( "Preparing recipients list") if $self->{verbose};
    unless (
        $self->{to_regex_map}
     || $self->{subject_cx}
     || $self->{to_email_map}
    ) {
        $self->{to} = $self->run_filters( recipients => $self->{to} );
        return $self;
    }

    # Prevent duplication.
    my $tos = $self->{to} = [ @{ $self->{to} } ];

    my $regexen = $self->{to_regex_map} && $self->{to_email_map}
        ? [ %{ $self->{to_regex_map} }, reverse %{ $self->{to_email_map } } ]
        : $self->{to_regex_map} ? [ %{ $self->{to_regex_map} } ]
        : $self->{to_email_map} ? [ reverse %{ $self->{to_email_map } } ]
        :                         undef;

    if ($regexen) {
        $self->_dbpnt( "Compiling regex_map regular expressions")
            if $self->{verbose} > 1;
        for (my $i = 1; $i < @$regexen; $i += 2) {
            $self->_dbpnt( qq{Compiling "$_"}) if $self->{verbose} > 2;
            # Remove initial slash and compile.
            $regexen->[$i] =~ s|^\^[/\\]|^|;
            $regexen->[$i] = qr/$regexen->[$i]/;
        }
    } else {
        $regexen = [];
    }

    local $ENV{LANG} = "$self->{svn_env_lang}" if $self->{svn_env_lang};
    my $fh = $self->_pipe(
        $self->{svn_encoding},
        '-|', $self->{svnlook},
        'dirs-changed',
        $self->{repos_path},
        '-r', $self->{revision},
    );

    # Read in a list of the directories changed.
    my ($cx, %seen);
    while (<$fh>) {
        s/[\n\r\/\\]+$//;
        for (my $i = 0; $i < @$regexen; $i += 2) {
            my ($email, $rx) = @{$regexen}[$i, $i + 1];
            # If the directory matches the regex, save the email.
            if (/$rx/) {
                $self->_dbpnt( qq{"$_" matched $rx}) if $self->{verbose} > 2;
                push @$tos, $email unless $seen{$email}++;
            }
        }
        # Grab the context if it's needed for the subject.
        if ($self->{subject_cx}) {
            # XXX Do we need to set utf8 here?
            my $l = length;
            $cx ||= $_;
            $cx =~ s{[/\\]?[^/\\]+$}{} until !$cx || m{^\Q$cx\E(?:$|/|\\)};
        }
    }
    $self->_dbpnt( qq{Context is "$cx"})
        if $self->{subject_cx} && $self->{verbose} > 1;
    close $fh or warn "Child process exited: $?\n";
    $self->{cx} = $cx;
    $tos = $self->run_filters( recipients => $tos );
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
    local $ENV{LANG} = "$self->{svn_env_lang}" if $self->{svn_env_lang};
    my $lines = $self->_read_pipe($self->{svnlook}, 'info', $self->{repos_path},
                                  '-r', $self->{revision});
    $self->{user} = shift @$lines;
    $self->{date} = shift @$lines;
    $self->{message_size} = shift @$lines;
    $self->{message} = $lines;

    # Set up the from address.
    unless ($self->{from}) {
        $self->{from} = $self->{user}
            . ( $self->{user_domain} ? "\@$self->{user_domain}" : '' );
    }
    $self->{from} = $self->run_filters( from => $self->{from} );

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
    local $ENV{LANG} = "$self->{svn_env_lang}" if $self->{svn_env_lang};
    my $fh = $self->_pipe(
        $self->{svn_encoding},
        '-|', $self->{svnlook},
        'changed',
        $self->{repos_path},
        '-r', $self->{revision},
    );

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

    $self->{subject} = '';

    # Start with the optional message and revision number..
    if ( defined $self->{subject_prefix} ) {
        if ( index($self->{subject_prefix}, '%d') > 0 ) {
            $self->{subject} .=
                sprintf $self->{subject_prefix}, $self->{revision};
        } else {
            $self->{subject} .=
                $self->{subject_prefix} . "[$self->{revision}] ";
        }
    } else {
        $self->{subject} .= "[$self->{revision}] ";
    }

    # Add the context if there is one.
    if ($self->{cx}) {
        if (my $rx = $self->{strip_cx_regex}) {
            $self->{cx} =~ s/$_// for @$rx;
        }
        my $space = $self->{no_first_line} ? '' : ': ';
        $self->{subject} .= $self->{cx} . $space if $self->{cx};
    }

    # Add the first sentence/line from the log message.
    unless ($self->{no_first_line}) {
        # Truncate to first period after a minimum of 10 characters.
        my $i = index substr($self->{message}[0], 10), '. ';
        $self->{subject} .= $i > 0
            ? substr($self->{message}[0], 0, $i + 11)
            : $self->{message}[0];
    }

    # Truncate to the last word under 72 characters.
    $self->{subject} =~ s/^(.{0,$self->{max_sub_length}})\s+.*$/$1/m
      if $self->{max_sub_length}
      && length $self->{subject} > $self->{max_sub_length};

    # Now filter it.
    $self->{subject} = $self->run_filters( subject => $self->{subject} );
    $self->_dbpnt( qq{Subject is "$self->{subject}"}) if $self->{verbose};

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
    $self->run_filters('pre_execute');
    return $self unless @{ $self->{to} };

    my $out = $self->{smtp} ? SVN::Notify::SMTP->get_handle($self) : do {
        local $ENV{LANG} = $self->{env_lang} if $self->{env_lang};
        $self->_pipe(
            $self->{encoding},
            '|-', $self->{sendmail},
            '-oi', '-t',
            ($self->{set_sender} ? ('-f', $self->{from}) : ())
        );
    };

    # Output the message.
    $self->output($out);

    close $out or warn "Child process exited: $?\n";
    $self->_dbpnt( 'Message sent' ) if $self->{verbose};
    $self->run_filters('post_execute');
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

    # Q-Encoding (RFC 2047)
    my $subj = PERL58
        ? Encode::encode( 'MIME-Q', $self->{subject} )
        : $self->{subject};
    my @headers = (
        "MIME-Version: 1.0\n",
        "X-Mailer: SVN::Notify " . $self->VERSION
            . ": http://search.cpan.org/dist/SVN-Notify/\n",
        "From: $self->{from}\n",
        "Errors-To: $self->{from}\n",
        "To: " . join ( ', ', @{ $self->{to} } ) . "\n",
        "Subject: $subj\n"
    );

    push @headers, "Reply-To: $self->{reply_to}\n" if $self->{reply_to};

    if (my $heads = $self->{add_headers}) {
        while (my ($k, $v) = each %{ $heads }) {
            push @headers, "$k: $_\n" for ref $v ? @{ $v } : $v;
        }
    }

    print $out @{ $self->run_filters( headers => \@headers ) };
    return $self;
}

##############################################################################

=head3 output_content_type

  $notifier->output_content_type($file_handle);

Outputs the content type and transfer encoding headers. These demarcate the
body of the message. If the C<attach_diff> parameter was set to true, then a
boundary string will be generated and the Content-Type set to
"multipart/mixed" and stored as the C<boundary> attribute.

After that, this method outputs the content type returned by
C<content_type()>, the character set specified by the C<encoding> attribute,
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
        $self->{boundary} ||= join '', ('a'..'z', 'A'..'Z', 0..9)[ map { rand 62 } 0..10];
        print $out
          qq{Content-Type: multipart/mixed; boundary="$self->{boundary}"\n\n};
    }

    my $ctype = $self->content_type;
    print $out "--$self->{boundary}\n" if $self->{attach_diff};
    print $out "Content-Type: $ctype; charset=$self->{encoding}\n",
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
    my $start = [ $self->{header} ? ("$self->{header}\n") : () ];
    $start = $self->run_filters( start_body => $start );
    print $out @$start, "\n" if $start && @$start;
    return $self;
}

##############################################################################

=head3 output_metadata

  $notifier->output_metadata($file_handle);

This method outputs the metadata of the commit, including the revision number,
author (user), and date of the revision. If the C<author_url> or
C<revision_url> attributes have been set, then the appropriate URL(s) for the
revision will also be output.

=cut

sub output_metadata {
    my ($self, $out) = @_;
    my @lines = ("Revision: $self->{revision}\n");
    if (my $url = $self->{revision_url}) {
        push @lines, sprintf "          $url\n", $self->{revision};
    }

    # Output the Author any any relevant URL.
    push @lines, "Author:   $self->{user}\n";
    if (my $url = $self->{author_url}) {
        push @lines, sprintf "          $url\n", $self->{user};
    }

    push @lines, "Date:     $self->{date}\n";

    print $out @{ $self->run_filters( metadata => \@lines ) };
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
    my $msg = join "\n", @{
        $self->run_filters( log_message => $self->{message} )
    };

    print $out "Log Message:\n-----------\n$msg\n";

    # Make Revision links.
    if (my $url = $self->{revision_url}) {
        if (my @matches = $msg =~ /\b(?:(?:rev(?:ision)?\s*#?\s*|r)(\d+))\b/ig) {
            print $out "\nRevision Links:\n--------------\n";
            printf $out "    $url\n", $_ for @matches;
        }
    }

    # Make ticketing system links.
    if (my $map = $self->ticket_map) {
        my $has_header = 0;
        $self->run_ticket_map( sub {
            my ($regex, $url) = @_;
            while ($msg =~ /$regex/ig) {
                unless ($has_header) {
                    print $out "\nTicket Links:\n------------\n";
                    $has_header = 1;
                }
                printf $out "    $url\n",  $2 || $1;
            }
        } );
    }

    return $self;
}

##############################################################################

=head3 output_file_lists

  $notifier->output_file_lists($file_handle);

Outputs the lists of modified, added, and deleted files, as well as the list
of files for which properties were changed. The labels used for each group are
pulled in from the C<file_label_map()> class method.

=cut

sub output_file_lists {
    my ($self, $out) = @_;
    my $files = $self->{files} or return $self;
    $self->_dbpnt( "Outputting file lists") if $self->{verbose} > 1;
    my $map = $self->file_label_map;
    # Create the underlines.
    my %dash = ( map { $_ => '-' x length($map->{$_}) } keys %$map );

    foreach my $type (qw(U A D _)) {
        # Skip it if there's nothing to report.
        next unless $files->{$type};
        $self->_dbpnt( "  Outputting $map->{$type} file list")
          if $self->{verbose} > 2;

        # Identify the action and output each file.
        print $out "\n", @{ $self->run_filters(
            file_lists => [
                "$map->{$type}:\n",
                "$dash{$type}\n",
                map { "    $_\n" } @{ $files->{$type} }
            ]
        ) };
    }
    print $out "\n";
    return $self;
}

##############################################################################

=head3 end_body

  $notifier->end_body($file_handle);

Closes out the body of the email by outputting the contents of the C<footer>
attribute, if any, and then a couple of newlines. Designed to be called when
the body of the message is complete, and before any call to
C<output_attached_diff()>.

=cut

sub end_body {
    my ($self, $out) = @_;
    $self->_dbpnt( "Ending body") if $self->{verbose} > 2;
    my $end = [ $self->{footer} ? ("$self->{footer}\n") : () ];
    $end = $self->run_filters( end_body => $end );
    print $out @$end, "\n" if $end && @$end;
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
      "Content-Type: text/plain; charset=$self->{encoding}\n",
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

=head3 run_ticket_map

  $notifier->run_ticket_map( \&callback, @params );

Loops over the ticket systems you have defined, calling the C<$callback>
function for each one, passing to it the regex, url and @params specified as
its parameters.

=cut

sub run_ticket_map {
    my ($self, $callback, @params) = @_;

    # Make ticketing system links.
    my $map = $self->ticket_map or return;
    my $has_header = 0;
    while (my ($regex, $url) = each %$map) {
        $regex = $_ticket_regexen{ $regex } || $regex;
        $callback->( $regex, $url, @params );
    }
}

##############################################################################

=head3 run_filters

  $data = $notifier->run_filters( $output_type => $data );

Runs the filters for C<$output_type> on $data. Used internally by SVN::Notify
and by subclasses.

=cut

sub run_filters {
    my ($self, $type, $data) = @_;
    my $filters = $self->{filters}{$type} or return $data;
    $data = $_->($self, $data) for @$filters;
    return $data;
}

##############################################################################

=head3 filters_for

  my $filters = $notifier->filters_for( $output_type );

Returns an array reference of of the filters loaded for C<$output_type>.
Returns C<undef> if there are no filters have been loaded for C<$output_type>.

=cut

sub filters_for {
    shift->{filters}{+shift};
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
    # To avoid svnlook output except for diff contents, such as "Modified"
    # etc., to be output in the localized string encoded with another encoding
    # from diff contents. HTML and HTML::ColorDiff also expect the terms
    # printed in English.
    local $ENV{LANG} = 'C';

    return $self->_pipe(
        $self->{diff_encoding},
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
    $diff = $self->run_filters( diff => $diff );

    if (my $max = $self->{max_diff_length}) {
        my $length = 0;
        while (<$diff>) {
            s/[\n\r]+$//;
            if (($length += length) < $max) {
                print $out $_, "\n";
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
            print $out $_, "\n";
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
    to_email_map
    from
    user_domain
    svnlook
    sendmail
    set_sender
    add_headers
    smtp
    encoding
    diff_encoding
    svn_encoding
    env_lang
    svn_env_lang
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
    ticket_url
    ticket_regex
    ticket_map
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
sub svnweb_url   { shift->revision_url(@_) }
sub viewcvs_url  { shift->revision_url(@_) }
sub charset      { shift->encoding(@_)     }

# Deprecated ticket URL systems.
for my $tick (qw(rt bugzilla jira gnats)) {
    no strict 'refs';
    *{$tick . '_url'} = sub {
        my $self = shift;
        my $map = $self->{ticket_map} || {};
        return $map->{$tick} unless @_;
        if (my $url = shift) {
            $map->{$tick} = $url;
        } else {
            delete $map->{$tick};
        }
        $self->{ticket_map} = $map;
        return $self;
    };
}

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
context, it returns only the first value in the list, for backwards
compatibility with older versions of SVN::Notify. In list context, it of
course returns the entire list. Pass in one or more values to set all of the
values for the C<to> attribute.

=head3 to_regex_map

  my $to_regex_map = $notifier->to_regex_map;
  $notifier = $notifier->to_regex_map($to_regex_map);

Gets or sets the value of the C<to_regex_map> attribute, which is a hash
reference of email addresses mapped to regular expressions.

=head3 to_email_map

  my $to_email_map = $notifier->to_email_map;
  $notifier = $notifier->to_email_map($to_email_map);

Gets or sets the value of the C<to_email_map> attribute, which is a hash
reference of regular expressions mapped to email addresses.

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

=head3 encoding

  my $encoding = $notifier->encoding;
  $notifier = $notifier->encoding($encoding);

Gets or sets the value of the C<encoding> attribute. C<charset> is an alias
preserved for backward compatibility.

=head3 svn_encoding

  my $svn_encoding = $notifier->svn_encoding;
  $notifier = $notifier->svn_encoding($svn_encoding);

Gets or sets the value of the C<svn_encoding> attribute.

=head3 diff_encoding

  my $diff_encoding = $notifier->diff_encoding;
  $notifier = $notifier->diff_encoding($diff_encoding);

Gets or sets the value of the C<diff_encoding> attribute.

=head3 language

  my $language = $notifier->language;
  $notifier = $notifier->language($language);

Gets or sets the value of the C<language> attribute.

=head3 env_lang

  my $env_lang = $notifier->env_lang;
  $notifier = $notifier->env_lang($env_lang);

Gets or sets the value of the C<env_lang> attribute, which is set to C<<
$notify->language . '.' . $notify->encoding >> when C<language> is set, and
otherwise is C<undef>. This attribute is used to set the C<$LANG> environment
variable, if it is not already set by the environment, before executing
C<sendmail>.

=head3 svn_env_lang

  my $svn_env_lang = $notifier->svn_env_lang;
  $notifier = $notifier->svn_env_lang($svn_env_lang);

Gets or sets the value of the C<svn_env_lang> attribute, which is set to C<<
$notify->language . '.' . $notify->svn_encoding >> when C<language> is set,
and otherwise is C<undef>. This attribute is used to set the C<$LANG>
environment variable, if it is not already set by the environment, before
executing C<svnlook>. It is not used for C<svnlook diff>, however, as the diff
itself will be emitted in raw octets except for headers such as "Modified",
which need to be in English so that subclasses can parse them. Thus, C<$LANG>
is always set to "C" for the execution of C<svnlook diff>.

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

=head3 add_headers

  my $add_headers = $notifier->add_headers;
  $notifier = $notifier->add_headers({
      'X-Accept' => [qw(This That)],
      'X-Reject' => 'Me!',
  });

Gets or sets the value of the C<add_headers> attribute, which is a hash
reference of the headers to be added to the email message. If one header needs
to appear multiple times, simply pass the corresponding hash value as an array
reference of each value for the header. Not to be confused with the C<header>
accessor, which gets and sets text to be included at the beginning of the body
of the email message.

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

=head3 boundary

  my $boundary = $notifier->boundary;
  $notifier = $notifier->boundary($boundary);

Gets or sets the value of the C<boundary> attribute. This string is normally
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

Gets or set the value of the C<header> attribute. Not to be confused with the
C<add_headers> attribute, which manages headers to be inserted into the
notification email message headers.

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
    my ($self, $encode, $mode) = (shift, shift, shift);
    $self->_dbpnt( q{Piping execution of "} . join(q{" "}, @_) . q{"})
      if $self->{verbose};
    # Safer version of backtick (see perlipc(1)).
    local *PIPE;
    if (WIN32) {
        my $cmd = $mode eq '-|'
            ? q{"}  . join(q{" "}, @_) . q{"|}
            : q{|"} . join(q{" "}, @_) . q{"};
        open PIPE, $cmd or die "Cannot fork: $!\n";
        binmode PIPE, ":encoding($encode)" if PERL58 && $encode;
        return *PIPE;
    }

    my $pid = open PIPE, $mode;
    die "Cannot fork: $!\n" unless defined $pid;

    if ($pid) {
        # Parent process. Set the encoding layer and return the file handle.
        binmode PIPE, ":encoding($encode)" if PERL58 && $encode;
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
    my $fh = $self->_pipe( $self->{svn_encoding}, '-|', @_ );
    local $/; my @lines = split /(?:\r\n|\r|\n)/, <$fh>;
    close $fh or warn "Child process exited: $?\n";
    return \@lines;
}

##############################################################################
# This method is used for debugging output in various verbose modes.
##############################################################################

sub _dbpnt { print ref(shift), ': ', join ' ', @_; }

##############################################################################
# This function is used to exit the program with an error if a parameter is
# missing.
##############################################################################

sub _usage {
    my ($msg) = @_;

    # Just die if the API is used.
    die $msg if $0 !~ /\bsvnnotify(?:[.]bat)?$/;

    # Otherwise, tell 'em how to use it.
    $msg =~ s/_/-/g;
    $msg =~ s/(\s+")/$1--/g;
    $msg =~ s/\bparameter\b/option/g;
    require Pod::Usage;
    Pod::Usage::pod2usage(
        '-message'  => $msg,
        '-verbose'  => 99,
        '-sections' => '(?i:(Usage|Options))',
        '-exitval'  => 1,
    );
}

package SVN::Notify::SMTP;

sub get_handle {
    my ($class, $notifier) = @_;

    # Load Net::SMTP::TLS.
    require Net::SMTP::TLS;
    require Sys::Hostname;
    my $smtp = Net::SMTP::TLS->new(
        $notifier->{smtp},
        Hello => Sys::Hostname::hostname(),
        ( $notifier->{smtp_port} ? ( Port => $notifier->{smtp_port} ) : () ),
        ( $notifier->{smtp_tls}  ? () : (NoTLS => 1) ),
        ( $notifier->{smtp_user} ? ( User => $notifier->{smtp_user} ) : () ),
        ( $notifier->{smtp_pass} ? ( Password => $notifier->{smtp_pass} ) : () ),
        ( $notifier->{verbose}   ? ( Debug => 1 ) : () )
    ) or die "Unable to create SMTP object: $!";

    $smtp->mail($notifier->{from});
    $smtp->to(map { split /\s*,\s*/ } @{ $notifier->{to} });
    $smtp->data;
    tie local(*SMTP), $class, $smtp, $notifier;
    # Perl 5.6 requires the escape.
    return SVN::Notify::PERL58 ? *SMTP : \*SMTP;
}

sub TIEHANDLE {
    my ($class, $smtp, $notifier) = @_;
    bless { smtp => $smtp, notifier => $notifier }, $class;
}

sub PRINT {
    my $self = shift;
    if (SVN::Notify::PERL58) {
        my $encode = $self->{notifier}->encoding;
        return $self->{smtp}->datasend( map {
            Encode::encode( $encode, $_ )
        } @_ )
    }
    return $self->{smtp}->datasend(@_);
}

sub PRINTF {
    my $self = shift;
    $self->PRINT( sprintf(shift, @_) );
}

sub CLOSE  {
    my $self = shift;
    $self->{smtp}->dataend;
    $self->{smtp}->quit;
}

1;
__END__

##############################################################################

=head2 Character Encoding Support

SVN::Notify has comprehensive support for character encodings, but since it
cannot always know what encodings your system supports or in which your data
is stored in Subversion, it needs your help. In plain English, here's what you
need to know to make non-ASCII characters look right in SVN::Notify's
messages:

=over

=item * The encoding for messages

To tell SVN::Notify what character encoding to use when it sends messages, use
the C<--encoding> option. It defaults to "UTF-8", which should cover the vast
majority of needs. You're using it in your code already, right?

=item * The character set you use in your log messages

To tell SVN::Notify the character encoding that you use in Subversion commit
log messages, as well as the names of the files in Subversion, use the
C<--svn-encoding> option, which defaults to the same value as C<--encoding>.
If, for example, you write log messages in Big5, pass C<--svn-encoding Big5>.

=item * The character set you use in your code

To tell SVN::Notify the character encoding that you use in the files stored in
Subversion, and therefore that will be output in diffs, use the
C<--diff-encoding> option, which defaults to the same value as
C<--svn-encoding>. If, for example, you write code in euc-jp but write your
commit log messages in some other encoding, pass C<--diff-encoding euc-jp>.

=item * The locales supported by your OS

SVN::Notify uses the values passed to C<--encoding>, C<--svn-encoding>, and
C<--diff-encoding> to read in data from F<svnlook>, convert it to Perl's
internal encoding, and to output messages in the proper encoding. Most of the
time, if you write code in UTF-8 and want messages delivered in UTF-8, you can
ignore these options.

Sometimes, however, F<svnlook> converts its output to some other encoding.
That encoding is controlled by the C<$LANG> environment variable, which
corresponds to a locale supported by your OS. (See
L<perllocale|perllocale/"Finding locales"> for instructions for finding the
locales supported by your system.) If your system supports UTF-8 locales but
defaults to using some other locale (causing F<svnlook> to output log messages
in the wrong encoding), then all you have to do is pass the C<--language>
option to get SVN::Notify to tell F<svnlook> to use it. For example, if all of
your data is in UTF-8, pass C<--language en_US> to get SVN::Notify to use the
F<en_US.UTF-8> locale. Likewise, pass C<--language sv_SE> to force the use of
the F<sv_SE.UTF-8> locale.

Sometimes, however, the system does not support UTF-8 locales. Or perhaps you
use something other than UTF-8 in your log messages or source code. This
should be no problem, as SVN::Notify uses the encoding options to determine
the locales to use. For example, if your OS offers the F<en_US.ISO88591>
locale, pass both C<--svn-encoding> and C<--language>, like so:

  --svn-encoding ISO-8859-1 --language en_US

SVN::Notify will set the C<$LANG> environment variable to "en_US.ISO88591",
which F<svnlook> will use to convert log messages from its internal form to
ISO-8859-1. SVN::Notify will convert the output from F<svnlook> to UTF-8 (or
whatever C<--encoding> you've specified) before sending the message. Of
course, if you have characters that don't correspond to ISO-8859-1, you'll
still get some garbage characters. It is ideal when the OS locale supports the
same encodings as you use in your source code and log messages, though that's
not always the case.

And finally, because the names and spellings that OS vendors use for locales
can vary widely, SVN::Notify will occasionally get the name of the encoding
wrong, in which case you'll see warnings such as this:

  svnlook: warning: cannot set LC_CTYPE locale
  svnlook: warning: environment variable LANG is en_US.ISO88591
  svnlook: warning: please check that your locale name is correct

In such a case, if all of your data and your log messages are stored in the
same encoding, you can set the C<$LANG> environment variable directly in your
F<post-commit> script before running F<svnnotify>:

  LANG=en_US.ISO-88591 svnnotify -p "$1" -r "$2"

If the C<$LANG> environment variable is already set in this way, SVN::Notify
will not set it before shelling out to F<svnlook>.

=back

This looks like a lot of information, and it is. But in most cases, if you
exclusively use UTF-8 (or ASCII!) in your source code and log messages, and
your OS defaults to a UTF-8 locale, things should just work.

=head1 See Also

=over

=item L<SVN::Notify::HTML|SVN::Notify::HTML>

HTML notification.

=item L<SVN::Notify::HTML::ColorDiff|SVN::Notify::HTML::ColorDiff>

HTML notification with colorized diff.

=item L<SVN::Notify::Filter|SVN::Notify::Filter>

How to write output filters for SVN::Notify.

=item L<SourceForge Hook Scripts|http://sourceforge.net/apps/trac/sourceforge/wiki/Subversion%20hook%20scripts>

SourceForge.net support for SVN::Notify.

=item L<Windows Subversion + Apache + TortoiseSVN + SVN::Notify HOWTO|http://svn.haxx.se/users/archive-2006-05/0593.shtml>

Essential for Windows Subversion users.

=back

=head1 Support

This module is stored in an open L<GitHub
repository|http://github.com/theory/svn-notify/>. Yes, I'm aware of the irony.
Nevertheless, feel free to fork and contribute!

Please file bug reports via L<GitHub
Issues|http://github.com/theory/svn-notify/issues/> or by sending mail to
L<bug-SVN-Notify@rt.cpan.org|mailto:bug-SVN-Notify@rt.cpan.org>.

=head1 Author

David E. Wheeler <david@justatheory.com>

=head1 Copyright and License

Copyright (c) 2004-2011 David E. Wheeler. Some Rights Reserved.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
