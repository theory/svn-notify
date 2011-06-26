#!perl -w

use strict;
use Test::More tests => 244;
use File::Spec::Functions;

use_ok('SVN::Notify');

my $ext = $^O eq 'MSWin32' ? '.bat' : '';

my $dir = catdir curdir, 't', 'scripts';
$dir = catdir curdir, 't', 'bin' unless -d $dir;

my %args = (
    svnlook    => catfile($dir, "testsvnlook$ext"),
    sendmail   => catfile($dir, "testsendmail$ext"),
    repos_path => 'tmp',
    revision   => '111',
    to         => ['test@example.com'],
);

my $subj = "Did this, that, and the «other».";
my $qsubj;
if (SVN::Notify::PERL58()) {
    $subj = Encode::decode_utf8( $subj );
    $qsubj = quotemeta Encode::encode( 'MIME-Q', $subj );
} else {
    $qsubj = quotemeta $subj;
}

##############################################################################
# Basic Functionality.
##############################################################################

ok( my $notifier = SVN::Notify->new(%args), "Construct new notifier" );
isa_ok($notifier, 'SVN::Notify');
ok( $notifier->prepare_recipients, 'prepare recipients' );
ok( $notifier->prepare_contents, 'prepare contents' );
ok( $notifier->prepare_files, 'prepare files');
ok( $notifier->prepare_subject, 'prepare subject');
# Make sure the attributes work.
is($notifier->repos_path, $args{repos_path}, "Check repos_path accessor" );
is($notifier->revision, $args{revision}, "Check revision accessor" );
is_deeply([$notifier->to], $args{to}, "Check to accessor" );
is($notifier->to_regex_map, $args{to_regex_map},
   "Check to_regex_map accessor" );
is($notifier->to_email_map, $args{to_email_map},
   "Check to_email_map accessor" );
is($notifier->from, 'theory', "Check from accessor" );
is($notifier->user_domain, $args{user_domain},
   "Check user_domain accessor" );
is($notifier->svnlook, $args{svnlook}, "Check svnlook accessor" );
is($notifier->sendmail, $args{sendmail}, "Check sendmail accessor" );
is($notifier->encoding, 'UTF-8', "Check encoding accessor" );
is($notifier->svn_encoding, 'UTF-8', "Check svn_encoding accessor" );
is($notifier->diff_encoding, 'UTF-8', "Check diff_encoding accessor" );
is($notifier->language, undef, "Check language accessor" );
is($notifier->env_lang, undef, "Check env_lang accessor" );
is($notifier->svn_env_lang, undef, "Check svn_env_lang accessor" );
is($notifier->with_diff, $args{with_diff}, "Check with_diff accessor" );
is($notifier->attach_diff, $args{attach_diff}, "Check attach_diff accessor" );
is($notifier->diff_switches, $args{diff_switches},
   "Check diff_switches accessor" );
is($notifier->reply_to, $args{reply_to}, "Check reply_to accessor" );
is($notifier->subject_prefix, $args{subject_prefix},
   "Check subject_prefix accessor" );
is($notifier->subject_cx, $args{subject_cx}, "Check subject_cx accessor" );
is($notifier->max_sub_length, $args{max_sub_length},
   "Check max_sub_length accessor" );
is($notifier->viewcvs_url, $args{viewcvs_url}, "Check viewcvs_url accessor" );
is($notifier->svnweb_url, $args{svnweb_url}, "Check svnweb_url accessor" );
is($notifier->author_url, $args{author_url}, "Check author_url accessor" );
is($notifier->verbose, 0, "Check verbose accessor" );
is($notifier->user, 'theory', "Check user accessor" );
is($notifier->date, '2004-04-20 01:33:35 -0700 (Tue, 20 Apr 2004)',
   "Check date accessor" );
is($notifier->message_size, 103, "Check message_size accessor" );
isa_ok($notifier->message, 'ARRAY', "Check message accessor" );
my $msg = 'Did this, that, and the «other». And then I did some more. Some';
Encode::_utf8_on( $msg ) if SVN::Notify::PERL58();
is $notifier->message->[0], $msg, 'Check the message';
isa_ok($notifier->files, 'HASH', "Check files accessor" );
is($notifier->subject, "[111] $subj", "Check subject accessor" );
is($notifier->header, undef, 'Check header accessor');
is($notifier->footer, undef, 'Check footer accessor');
is($notifier->ticket_url, undef, 'Check ticket_url');
is($notifier->ticket_regex, undef, 'Check ticket_regex');
is($notifier->ticket_map, undef, 'Check ticket_map');

# Send the notification.
ok( $notifier->execute, "Notify" );

# Get the output.
my $email = get_output();

# Check the email headers.
like( $email, qr/Subject: \[111\] $qsubj\n/, "Check subject" );
like( $email, qr/From: theory\n/, 'Check From');
like( $email, qr/Errors-To: theory\n/, 'Check Errors-To');
like( $email, qr/To: test\@example\.com\n/, 'Check To');
like( $email, qr{Content-Type: text/plain; charset=UTF-8\n},
      'Check Content-Type' );
like( $email, qr{Content-Transfer-Encoding: 8bit\n},
      'Check Content-Transfer-Encoding');

# Make sure we have headers for each of the four kinds of changes.
for my $header ('Log Message', 'Modified Paths', 'Added Paths',
                'Removed Paths', 'Property Changed') {
    like( $email, qr/^$header/m, $header);
}

# Check that we have the commit metatdata.
like( $email, qr/Revision: 111\n/, 'Check Revision');
like( $email, qr/Author:   theory\n/, 'Check Author');
like( $email, qr/Date:     2004-04-20 01:33:35 -0700 \(Tue, 20 Apr 2004\)\n/,
      'Check Date');

# Check that the log message is there.
UTF8: {
    use utf8;
    like( $email, qr/Did this, that, and the «other»\. And then I did some more\. Some\nit was done on a second line\. “Go figure”\./, 'Check for log message' );
}

# Make sure that Class/Meta.pm is listed twice, once for modification and once
# for its attribute being set.
is( scalar @{[$email =~ m{(trunk/Class-Meta/lib/Class/Meta\.pm)}g]}, 2,
    'Check for two Class/Meta.pm');
# For other file names, there should be only one instance.
is( scalar @{[$email =~ m{(trunk/Class-Meta/lib/Class/Meta/Class\.pm)}g]}, 1,
    'Check for one Class/Meta/Class.pm');
is( scalar @{[$email =~ m{(trunk/Class-Meta/lib/Class/Meta/Type\.pm)}g]}, 1,
    'Check for one Class/Meta/Type.pm');

# Make sure that no diff is included.
unlike( $email, qr{Modified: trunk/Params-CallbackRequest/Changes},
        "Check for no diff" );


##############################################################################
# Include diff and language.
##############################################################################
local $ENV{LANG};
ok( $notifier = SVN::Notify->new(
    %args,
    with_diff => 1,
    language  => 'en_US',
), 'Construct new diff notifier' );
ok $notifier->with_diff, 'with_diff() should return true';
is $notifier->language, 'en_US', 'language should be "en_US"';
is($notifier->env_lang, 'en_US.UTF-8', "Check env_lang accessor" );
is($notifier->svn_env_lang, 'en_US.UTF-8', "Check svn_env_lang accessor" );
isa_ok($notifier, 'SVN::Notify');
NO_BADLANG: {
    local $ENV{PERL_BADLANG} = 0;
    ok( $notifier->prepare, "Single method call prepare" );
    ok( $notifier->execute, "Diff notify" );
}

# Get the output.
$email = get_output();

like( $email, qr/Subject: \[111\] $qsubj\n/, "Check diff subject" );
like( $email, qr/From: theory\n/, 'Check diff From');
like( $email, qr/To: test\@example\.com\n/, 'Check diff To');
like( $email, qr/Content-Language: en_US\n/, 'Check diff Content-Language');

# Make sure there are no attachment headers
is( scalar @{[ $email =~ m{Content-Type: text/plain; charset=UTF-8\n} ]}, 1,
    'Check for one Content-Type header' );
is( scalar @{[$email =~ m{Content-Transfer-Encoding: 8bit\n}g]}, 1,
      'Check for one Content-Transfer-Encoding header');

# Make sure that the diff is included.
like( $email, qr{Modified: trunk/Params-CallbackRequest/Changes},
      "Check for diff" );

# Make sure that it's not attached.
unlike( $email, qr{Content-Type: multipart/mixed; boundary=},
        "Check for no attachment" );
unlike( $email, qr{Content-Disposition: attachment; filename=},
        "Check for no filename" );

##############################################################################
# Attach diff with language.
##############################################################################
ok( $notifier = SVN::Notify->new(%args, attach_diff => 1, language => 'en_US'),
    "Construct new attach diff notifier" );
isa_ok($notifier, 'SVN::Notify');
NO_BADLANG: {
    local $ENV{PERL_BADLANG} = 0;
    ok( $notifier->prepare, "Single method call prepare" );
    ok( $notifier->execute, "Attach diff notify" );
}

# Get the output.
$email = get_output();

like( $email, qr/Subject: \[111\] $qsubj\n/, 'Check attach diff subject' );
like( $email, qr/From: theory\n/, 'Check attach diff From');
like( $email, qr/To: test\@example\.com\n/, 'Check attach diff To');

# Make sure we have two sets of headers for attachments.
is( scalar @{[ $email =~ m{Content-Type: text/plain; charset=UTF-8\n}g ]}, 2,
    'Check for two Content-Type headers' );
is( scalar @{[ $email =~ m{Content-Language: en_US\n}g ]}, 2,
    'Check for two Content-Language headers' );
is( scalar @{[$email =~ m{Content-Transfer-Encoding: 8bit\n}g]}, 2,
      'Check for two Content-Transfer-Encoding headers');

# Make sure that the diff is included.
like( $email, qr{Modified: trunk/Params-CallbackRequest/Changes},
      "Check for diff" );

# Make sure that it's attached.
like( $email, qr{Content-Type: multipart/mixed; boundary=},
      "Check for attachment" );
like( $email,
      qr{Content-Disposition: attachment; filename=r111-theory.diff\n},
      "Check for filename" );

# Check for boundaries.
is( scalar @{[$email =~ m{(--[^-\s]+\n)}g]}, 2,
    'Check for two boundaries');
is( scalar @{[$email =~ m{(--[^-\s]+--)}g]}, 1,
    'Check for one final boundary');

##############################################################################
# Try to_regex_map.
##############################################################################
my $regex_map = {
    'one@example.com'  => 'AccessorBuilder',
    'two@example.com'  => '^/trunk',
    'none@example.com' => '/branches',
};
ok( $notifier = SVN::Notify->new(%args, to_regex_map => $regex_map),
    "Construct new regex_map notifier" );
isa_ok($notifier, 'SVN::Notify');
ok( $notifier->prepare, "Prepare to_regex_map" );
ok( $notifier->execute, "Notify to_regex_map" );
is keys %$regex_map, 3, 'The regex map hash should be unchanged';

# Check the output.
$email = get_output();
like( $email,
      qr/To: (test|one|two)\@example\.com, (test|one|two)\@example\.com, (test|one|two)\@example\.com\n/,
      'Check regex_map To');

##############################################################################
# Try to_email_map.
##############################################################################
my $email_map = {
    'AccessorBuilder' => 'one@example.com',
    '^/trunk',        => 'two@example.com',
    '/branches'       => 'hone@example.com',
};
ok( $notifier = SVN::Notify->new(%args, to_email_map => $email_map),
    "Construct new email_map notifier" );
isa_ok($notifier, 'SVN::Notify');
is_deeply $notifier->to_email_map, $email_map, 'email_map should be set';
ok( $notifier->prepare, "Prepare to_email_map" );
ok( $notifier->execute, "Notify to_email_map" );
is keys %$email_map, 3, 'The email map hash should be unchanged';

# Check the output.
$email = get_output();
like( $email,
      qr/To: (test|one|two)\@example\.com, (test|one|two)\@example\.com, (test|one|two)\@example\.com\n/,
      'Check email_map To');

##############################################################################
ok( $notifier = SVN::Notify->new(%args, reply_to => 'me@example.com'),
    "Construct new reply_to notifier" );
isa_ok($notifier, 'SVN::Notify');
ok( $notifier->prepare, "Prepare reply_to" );
ok( $notifier->execute, "Notify reply_to" );

# Check the output.
$email = get_output();
like( $email, qr/Reply-To: me\@example\.com\n/, 'Check Reply-To Header');

##############################################################################
# Try subject_prefix.
##############################################################################
ok( $notifier = SVN::Notify->new(%args, subject_prefix => '[C] '),
    "Construct new subject_prefix notifier" );
isa_ok($notifier, 'SVN::Notify');
ok( $notifier->prepare, "Prepare subject_prefix" );
ok( $notifier->execute, "Notify subject_prefix" );

# Check the output.
$email = get_output();
like( $email, qr/Subject: \[C\] \[111\] $qsubj\n/, 'Check subject header for prefix' );

##############################################################################
# Try subject_prefix with %n.
##############################################################################
ok( $notifier = SVN::Notify->new(%args, subject_prefix => '[Commit r%d] '),
    "Construct new subject_prefix with %d notifier" );
isa_ok($notifier, 'SVN::Notify');
ok( $notifier->prepare, "Prepare subject_prefix" );
ok( $notifier->execute, "Notify subject_prefix" );

# Check the output.
$email = get_output();
if (SVN::Notify::PERL58()) {
    $qsubj = quotemeta Encode::encode( 'MIME-Q', "[Commit r111] $subj" );
} else {
    $qsubj = quotemeta "[Commit r111] $subj";
}

like( $email, qr/Subject: $qsubj\n/,
      "Check subject header for prefix with %d" );

##############################################################################
# Try subject_cx.
##############################################################################
ok( $notifier = SVN::Notify->new(%args, subject_cx => 1),
    "Construct new subject_cx notifier" );
isa_ok($notifier, 'SVN::Notify');
ok( $notifier->prepare, "Prepare subject_cx" );
ok( $notifier->execute, "Notify subject_cx" );

# Check the output.
$email = get_output();
if (SVN::Notify::PERL58()) {
    $qsubj = quotemeta Encode::encode( 'MIME-Q', "[111] trunk: $subj" );
} else {
    $qsubj = quotemeta "[111] trunk: $subj";
}
like( $email, qr{Subject: $qsubj\n},
      "Check subject header for CX" );

##############################################################################
# Try subject_cx with a single file changed.
##############################################################################
ok( $notifier = SVN::Notify->new(%args, revision => '222', subject_cx => 1),
    "Construct new subject_cx file notifier" );
isa_ok($notifier, 'SVN::Notify');
ok( $notifier->prepare, "Prepare subject_cx file" );
ok( $notifier->execute, "Notify subject_cx file" );
# Check the output.
$email = get_output();
like( $email, qr{Subject: \[222\] trunk/App-Info/META.yml: Hrm hrm\. Let's try a few links\.\n},
      "Check subject header for file CX" );

##############################################################################
# Make sure sub is at least 10 chars long.
##############################################################################
ok( $notifier = SVN::Notify->new(%args, revision => '222'),
    "Construct new subject length notifier" );
isa_ok($notifier, 'SVN::Notify');
ok( $notifier->prepare, 'Prepare subject length' );
ok( $notifier->execute, 'Notify subject length' );

# Check the output.
$email = get_output();
like( $email, qr{Subject: \[222\] Hrm hrm\. Let's try a few links\.\n},
      "Check subject header for subject length" );

##############################################################################
# Try max_sub_length.
##############################################################################
ok( $notifier = SVN::Notify->new(%args, max_sub_length => 10),
    "Construct new max_sub_length notifier" );
isa_ok($notifier, 'SVN::Notify');
ok( $notifier->prepare, "Prepare max_sub_length" );
ok( $notifier->execute, "Notify max_sub_length" );

# Check the output.
$email = get_output();
like( $email, qr{Subject: \[111\] Did\n},
      "Check subject header for 10 characters." );

##############################################################################
# Try user_domain.
##############################################################################
ok( $notifier = SVN::Notify->new(%args, user_domain => 'example.net'),
    "Construct new user_domain notifier" );
isa_ok($notifier, 'SVN::Notify');
ok( $notifier->prepare, "Prepare user_domain" );
ok( $notifier->execute, "Notify user_domain" );

# Check the output.
$email = get_output();
like( $email, qr/From: theory\@example\.net\n/, 'Check From for user domain');

##############################################################################
# Try viewcvs_url.
##############################################################################
ok( $notifier = SVN::Notify->new(
    %args,
    viewcvs_url => 'http://svn.example.com/?rev=%s&view=rev'
   ), "Construct new viewcvs_url notifier" );
isa_ok($notifier, 'SVN::Notify');
ok( $notifier->prepare, "Prepare viewcvs_url" );
ok( $notifier->execute, "Notify viewcvs_url" );

# Check the output.
$email = get_output();
like( $email, qr|Revision:\s+111\n\s+http://svn\.example\.com/\?rev=111\&view=rev\n|,
      'Check for URL');

##############################################################################
# Try svnweb_url.
##############################################################################
ok( $notifier = SVN::Notify->new(
    %args,
    svnweb_url => 'http://svn.example.com/?rev=%s&view=rev'
   ), "Construct new svnweb_url notifier" );
isa_ok($notifier, 'SVN::Notify');
ok( $notifier->prepare, "Prepare svnweb_url" );
ok( $notifier->execute, "Notify svnweb_url" );

# Check the output.
$email = get_output();
like( $email, qr|Revision:\s+111\n\s+http://svn\.example\.com/\?rev=111\&view=rev\n|,
      'Check for URL');

##############################################################################
# Try author_url.
##############################################################################
ok( $notifier = SVN::Notify->new(
    %args,
    author_url => 'http://svn.example.com/~%s/',
   ), "Construct new author_url notifier" );
isa_ok($notifier, 'SVN::Notify');
ok( $notifier->prepare, "Prepare author_url" );
ok( $notifier->execute, "Notify author_url" );

# Check the output.
$email = get_output();
like( $email, qr|Author:\s+theory\n\s+http://svn\.example\.com/~theory/\n|,
      'Check for author URL');

##############################################################################
# Try encoding.
##############################################################################
ok( $notifier = SVN::Notify->new(%args, encoding => 'ISO-8859-1'),
    "Construct new encoding notifier" );
isa_ok($notifier, 'SVN::Notify');
is( $notifier->encoding, 'ISO-8859-1', 'Check encoding');
is( $notifier->svn_encoding, 'ISO-8859-1', 'Check encoding');
is( $notifier->diff_encoding, 'ISO-8859-1', 'Check encoding');
ok( $notifier->prepare, "Prepare encoding" );
ok( $notifier->execute, "Notify encoding" );

# Check the output.
$email = get_output();
like( $email, qr{Content-Type: text/plain; charset=ISO-8859-1\n},
      'Check Content-Type charset' );

ok( $notifier = SVN::Notify->new(
    %args,
    svn_encoding => 'ISO-8859-1',
    diff_encoding => 'US-ASCII',
), 'Constrcut new multi-encoding notifier' );
is( $notifier->encoding, 'UTF-8', 'Check encoding');
is( $notifier->svn_encoding, 'ISO-8859-1', 'Check encoding');
is( $notifier->diff_encoding, 'US-ASCII', 'Check encoding');

##############################################################################
# Try Bug tracking URLs.
##############################################################################
ok( $notifier = SVN::Notify->new(
    %args,
    revision => 222,
    viewcvs_url  => 'http://viewsvn.bricolage.cc/?rev=%s&view=rev',
    rt_url       => 'http://rt.cpan.org/NoAuth/Bugs.html?id=%s',
    bugzilla_url => 'http://bugzilla.mozilla.org/show_bug.cgi?id=%s',
    jira_url     => 'http://jira.atlassian.com/secure/ViewIssue.jspa?key=%s',
    gnats_url    => 'http://gnats.example.com/gnatsweb.pl?cmd=view&pr=%s',
    ticket_url   => 'http://ticket.example.com/id=%s',
    ticket_regex => '\[?\s*Custom\s*#\s*(\d+)\s*\]?',
    ticket_map   => { '\b[Mm]antis-(\d+)\b' => 'http://server/mantisbt/view.php?id=%s' },
),
    "Construct new URL notifier" );
isa_ok($notifier, 'SVN::Notify');

is_deeply( $notifier->ticket_map, {
    rt       => 'http://rt.cpan.org/NoAuth/Bugs.html?id=%s',
    bugzilla => 'http://bugzilla.mozilla.org/show_bug.cgi?id=%s',
    jira     => 'http://jira.atlassian.com/secure/ViewIssue.jspa?key=%s',
    gnats    => 'http://gnats.example.com/gnatsweb.pl?cmd=view&pr=%s',
    '\[?\s*Custom\s*#\s*(\d+)\s*\]?' => 'http://ticket.example.com/id=%s',
    '\b[Mm]antis-(\d+)\b' => 'http://server/mantisbt/view.php?id=%s',
}, 'Check ticket_map accessor' );

ok( $notifier->prepare, "Prepare URL" );
ok( $notifier->execute, "Notify URL" );

$email = get_output();

# Check for application URLs.
like( $email, qr|Revision:\s+222\n\s+http://viewsvn\.bricolage\.cc/\?rev=222\&view=rev\n|,
      'Check for main ViewCVS URL');
like($email, qr/Revision Links:\n/, 'Check for ViewCVS Links label' );
like($email, qr/Ticket Links:\n/, 'Check for Ticket Links label' );
like($email,
     qr{    http://viewsvn\.bricolage\.cc/\?rev=606&view=rev\n},
     "Check for log mesage ViewCVS URL");
like($email,
     qr{    http://rt\.cpan\.org/NoAuth/Bugs\.html\?id=4321\n},
     "Check for RT URL");
like($email,
     qr{    http://rt\.cpan\.org/NoAuth/Bugs\.html\?id=123\n},
     "Check for Jesse's RT URL");
like($email,
     qr{    http://rt\.cpan\.org/NoAuth/Bugs\.html\?id=445\n},
     "Check for Ask's RT URL");
like( $email,
      qr{   http://bugzilla\.mozilla\.org/show_bug\.cgi\?id=709\n},
      "Check for Bugzilla URL" );
like( $email,
      qr{    http://jira\.atlassian\.com/secure/ViewIssue\.jspa\?key=PRJ1234-111\n},
      "Check for Jira URL" );
like($email,
     qr{    http://gnats\.example\.com/gnatsweb\.pl\?cmd=view&pr=12345\n},
     "Check for GNATS URL");
like($email,
     qr{    http://ticket\.example\.com/id=4321\n},
     "Check for custom ticket URL");
like($email,
     qr{    http://server/mantisbt/view\.php\?id=161\n},
     "Check for Mantis ticket URL");

##############################################################################
# Try leaving out the first line from the subject and removing part of the
# context file name.
##############################################################################
ok( $notifier = SVN::Notify->new(
    %args,
    subject_cx => 1,
    strip_cx_regex => ['^trunk/'],
    no_first_line => 1,
),
    "Construct new subject checking notifier" );
isa_ok($notifier, 'SVN::Notify');
is_deeply( [ $notifier->strip_cx_regex ], ['^trunk/'],
           'Check the strip_cx_regex accessor' );
ok( $notifier->prepare, "Prepare subject checking" );
ok( $notifier->execute, "Notify subject checking" );
is( $notifier->subject, '[111] trunk',
    "Check subject for stripped cx and no log message line");

# Check the output.
$email = get_output();
like( $email, qr{Subject: \[111\] trunk\n},
      "Check subject header for stripped cx and no log message line" );

##############################################################################
# Try two cx stripping regular expressions.
##############################################################################
ok( $notifier = SVN::Notify->new(
    %args,
    subject_cx => 1,
    strip_cx_regex => ['^trunk/', '-Meta$'],
    no_first_line => 1,
),
    "Construct new subject checking notifier" );
isa_ok($notifier, 'SVN::Notify');
ok( $notifier->prepare, "Prepare subject checking" );
ok( $notifier->execute, "Notify subject checking" );
is( $notifier->subject, '[111] trunk',
    "Check subject for stripped cx and no log message line");

# Check the output.
$email = get_output();
like( $email, qr{Subject: \[111\] trunk\n},
      "Check subject header for stripped cx and no log message line" );

##############################################################################
# Try header and footer.
##############################################################################
ok( $notifier = SVN::Notify->new(
    %args,
    header => 'This is the header',
    footer => 'This is the footer',
), 'Construct new header and foot notifier' );

isa_ok $notifier, 'SVN::Notify';
is $notifier->header, 'This is the header', 'Check the header';
is $notifier->footer, 'This is the footer', 'Check the footer';
ok $notifier->prepare, 'Prepare header and footer checking';
ok $notifier->execute, 'Notify header and footer checking';

# Check the output.
$email = get_output();
like $email, qr{This is the header\n\nRevision: 111},
      'Check for the header';

like $email, qr/This is the footer\s+\Z/, 'Check for the footer';

##############################################################################
# Try diff-switches
##############################################################################
ok( $notifier = SVN::Notify->new(
    %args,
    revision      => '111',
    with_diff     => 1,
    diff_switches => '--no-diff-added',
), 'Construct new diff_switches notifier' );

isa_ok $notifier, 'SVN::Notify';
is $notifier->diff_switches, '--no-diff-added', 'Check diff_switches()';
ok $notifier->prepare, 'Prepare header and footer checking';
ok $notifier->execute, 'Notify header and footer checking';

# Check the output.
$email = get_output();
like $email,
    qr{Added:\s+trunk/Params-CallbackRequest/lib/Params/Callback\.pm\s+\Z},
    'Make sure the added file is omitted from the diff';

##############################################################################
# Try max_diff_size
##############################################################################
ok $notifier = SVN::Notify->new(
    %args,
    max_diff_length => 1024,
    with_diff       => 1,
), 'Construct new max_diff_length notifier';

isa_ok $notifier, 'SVN::Notify';
is $notifier->max_diff_length, 1024, 'max_diff_hlength should be set';
ok $notifier->with_diff, 'with_diff should be set';
ok $notifier->prepare, 'Prepare max_diff_length checking';
ok $notifier->execute, 'Notify max_diff_length checking';

# Check the output.
$email = get_output();
like $email, qr{mod_perl::VERSION < 1.99 \? 'Apache' : 'Apache::RequestRec';},
    'Check for the last diff line';
unlike $email, qr{ BEGIN }, 'Check for missing extra line';
like $email, qr{Diff output truncated at 1024 characters.},
    'Check for truncation message';

##############################################################################
# Try multiple recipients.
##############################################################################
my $tos = ['test@example.com', 'try@example.com'];
ok $notifier = SVN::Notify->new(
    %args,
    to => $tos,
), 'Construct new "multiple to" notifier';
isa_ok $notifier, 'SVN::Notify';
is_deeply [$notifier->to], $tos, 'Should be arrayref of recipients';
ok $notifier->prepare, 'Prepare "multiple to" checking';
ok $notifier->execute, 'Notify "multiple to" checking';
$email = get_output();
like $email, qr{To:\s+test\@example\.com,\s+try\@example\.com\n},
    'Check for both address in the To header';

##############################################################################
# Try add_headers.
##############################################################################
my $headers = {
    Approve    => 'secrit',
    'X-Flavor' => [qw(vegemite marmite)],
};
ok $notifier = SVN::Notify->new(
    %args,
    add_headers => $headers,
), 'Construct new "add headers" notifier';
isa_ok $notifier, 'SVN::Notify';
is_deeply $notifier->add_headers, $headers, 'Should be hashref of headers';
ok $notifier->prepare, 'Prepare "add headers" checking';
ok $notifier->execute, 'Notify "add headers" checking';
$email = get_output();
like $email, qr/Approve:\s+secrit\n/, 'Check for single header';
like $email, qr{X-Flavor:\s+vegemite\nX-Flavor:\s+marmite\n},
    'Check for multiple additional headers';

##############################################################################
# Test file_exe
##############################################################################
my $look = catfile($dir, 'testsvnlook');

if (SVN::Notify::WIN32()) {
    require File::Copy;
    $ext = '.exe';
    File::Copy::copy("$look.bat", "$look.exe");
}
is +SVN::Notify->find_exe('testsvnlook'),  catfile($dir, "testsvnlook$ext"),
    'find_exe should find the test script';

unlink "$look.exe" if SVN::Notify::WIN32();

##############################################################################
# Functions.
##############################################################################

sub get_output {
    my $outfile = catfile qw(t data output.txt);
    open CAP, "<$outfile" or die "Cannot open '$outfile': $!\n";
    binmode CAP, 'utf8' if SVN::Notify::PERL58();
    return join '', <CAP>;
}

# This is so that we know where _find_exe() will search.
MOCKFILESPEC: {
    package File::Spec;
    sub path { 'foo', 'bar', $dir }
}
