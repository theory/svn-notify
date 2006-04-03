#!perl -w

# $Id$

use strict;
use Test::More;
use File::Spec::Functions;

if ($^O eq 'MSWin32') {
    plan skip_all => "SVN::Notify not yet supported on Win32";
} else {
    plan tests => 182;
}

BEGIN { use_ok('SVN::Notify') }

my $ext = $^O eq 'MSWin32' ? '.bat' : '';

my $dir = catdir curdir, 't', 'scripts';
$dir = catdir curdir, 't', 'bin' unless -d $dir;

my %args = (
    svnlook    => catfile($dir, "testsvnlook$ext"),
    sendmail   => catfile($dir, "testsendmail$ext"),
    repos_path => 'tmp',
    revision   => '111',
    to         => 'test@example.com',
);

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
is($notifier->to, $args{to}, "Check to accessor" );
is($notifier->to_regex_map, $args{to_regex_map},
   "Check to_regex_map accessor" );
is($notifier->from, 'theory', "Check from accessor" );
is($notifier->user_domain, $args{user_domain},
   "Check user_domain accessor" );
is($notifier->svnlook, $args{svnlook}, "Check svnlook accessor" );
is($notifier->sendmail, $args{sendmail}, "Check sendmail accessor" );
is($notifier->charset, 'UTF-8', "Check charset accessor" );
is($notifier->io_layer, 'encoding(UTF-8)', 'Check IO layer');
is($notifier->language, undef, "Check language accessor" );
is($notifier->with_diff, $args{with_diff}, "Check with_diff accessor" );
is($notifier->attach_diff, $args{attach_diff}, "Check attach_diff accessor" );
is($notifier->reply_to, $args{reply_to}, "Check reply_to accessor" );
is($notifier->subject_prefix, $args{subject_prefix},
   "Check subject_prefix accessor" );
is($notifier->subject_cx, $args{subject_cx}, "Check subject_cx accessor" );
is($notifier->max_sub_length, $args{max_sub_length},
   "Check max_sub_length accessor" );
is($notifier->viewcvs_url, $args{viewcvs_url}, "Check viewcvs_url accessor" );
is($notifier->svnweb_url, $args{svnweb_url}, "Check svnweb_url accessor" );
is($notifier->verbose, 0, "Check verbose accessor" );
is($notifier->user, 'theory', "Check user accessor" );
is($notifier->date, '2004-04-20 01:33:35 -0700 (Tue, 20 Apr 2004)',
   "Check date accessor" );
is($notifier->message_size, 103, "Check message_size accessor" );
isa_ok($notifier->message, 'ARRAY', "Check message accessor" );
isa_ok($notifier->files, 'HASH', "Check files accessor" );
is($notifier->subject, '[111] Did this, that, and the other.',
   "Check subject accessor" );
is($notifier->header, undef, 'Check header accessor');
is($notifier->footer, undef, 'Check footer accessor');

# Send the notification.
ok( $notifier->execute, "Notify" );

# Get the output.
my $email = get_output();

# Check the email headers.
like( $email, qr/Subject: \[111\] Did this, that, and the other\.\n/,
      "Check subject" );
like( $email, qr/From: theory\n/, 'Check From');
like( $email, qr/To: test\@example\.com\n/, 'Check To');
like( $email, qr{Content-Type: text/plain; charset=UTF-8\n},
      'Check Content-Type' );
like( $email, qr{Content-Transfer-Encoding: 8bit\n},
      'Check Content-Transfer-Encoding');

# Make sure we have headers for each of the four kinds of changes.
for my $header ('Log Message', 'Modified Paths', 'Added Paths',
                'Removed Paths', 'Property Changed') {
    like( $email, qr/$header/, $header);
}

# Check that we have the commit metatdata.
like( $email, qr/Revision: 111\n/, 'Check Revision');
like( $email, qr/Author:   theory\n/, 'Check Author');
like( $email, qr/Date:     2004-04-20 01:33:35 -0700 \(Tue, 20 Apr 2004\)\n/,
      'Check Date');

# Check that the log message is there.
like( $email, qr/Did this, that, and the other\. And then I did some more\. Some\nit was done on a second line\. “Go figure”\./, 'Check for log message' );

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
ok( $notifier = SVN::Notify->new(
    %args,
    with_diff => 1,
    language  => 'en',
    io_layer  => 'raw',
), 'Construct new diff notifier' );
ok $notifier->with_diff, 'with_diff() should return true';
is $notifier->language, 'en', 'language should be "en"';
is $notifier->io_layer, 'raw', 'IO layer should be "raw"';
isa_ok($notifier, 'SVN::Notify');
ok( $notifier->prepare, "Single method call prepare" );
ok( $notifier->execute, "Diff notify" );

# Get the output.
$email = get_output();

like( $email, qr/Subject: \[111\] Did this, that, and the other\.\n/,
      "Check diff subject" );
like( $email, qr/From: theory\n/, 'Check diff From');
like( $email, qr/To: test\@example\.com\n/, 'Check diff To');
like( $email, qr/Content-Language: en\n/, 'Check diff Content-Language');

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
ok( $notifier = SVN::Notify->new(%args, attach_diff => 1, language => 'en'),
    "Construct new attach diff notifier" );
isa_ok($notifier, 'SVN::Notify');
ok( $notifier->prepare, "Single method call prepare" );
ok( $notifier->execute, "Attach diff notify" );

# Get the output.
$email = get_output();

like( $email, qr/Subject: \[111\] Did this, that, and the other\.\n/,
      "Check attach diff subject" );
like( $email, qr/From: theory\n/, 'Check attach diff From');
like( $email, qr/To: test\@example\.com\n/, 'Check attach diff To');

# Make sure we have two sets of headers for attachments.
is( scalar @{[ $email =~ m{Content-Type: text/plain; charset=UTF-8\n}g ]}, 2,
    'Check for two Content-Type headers' );
is( scalar @{[ $email =~ m{Content-Language: en\n}g ]}, 2,
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
# Try reply_to.
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
ok( $notifier = SVN::Notify->new(%args, subject_prefix => '[Commits]'),
    "Construct new subject_prefix notifier" );
isa_ok($notifier, 'SVN::Notify');
ok( $notifier->prepare, "Prepare subject_prefix" );
ok( $notifier->execute, "Notify subject_prefix" );

# Check the output.
$email = get_output();
like( $email, qr/Subject: \[Commits\] \[111\] Did this, that, and the other\.\n/,
      "Check subject header for prefix" );

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
like( $email, qr{Subject: \[111\] trunk/Class-Meta: Did this, that, and the other\.\n},
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
like( $email, qr{Subject: \[222\] trunk/App-Info/META.yml: Hrm hrm\.\n},
      "Check subject header for file CX" );

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
like( $email, qr|ViewCVS:\s+http://svn\.example\.com/\?rev=111\&view=rev\n|,
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
like( $email, qr|SVNWeb:\s+http://svn\.example\.com/\?rev=111\&view=rev\n|,
      'Check for URL');

##############################################################################
# Try charset.
##############################################################################
ok( $notifier = SVN::Notify->new(%args, charset => 'ISO-8859-1'),
    "Construct new charset notifier" );
isa_ok($notifier, 'SVN::Notify');
ok( $notifier->prepare, "Prepare charset" );
ok( $notifier->execute, "Notify charset" );

# Check the output.
$email = get_output();
like( $email, qr{Content-Type: text/plain; charset=ISO-8859-1\n},
      'Check Content-Type charset' );

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
),
    "Construct new URL notifier" );
isa_ok($notifier, 'SVN::Notify');
ok( $notifier->prepare, "Prepare URL" );
ok( $notifier->execute, "Notify URL" );

$email = get_output();

# Check for application URLs.
like( $email, qr|ViewCVS:\s+http://viewsvn\.bricolage\.cc/\?rev=222\&view=rev\n|,
      'Check for main ViewCVS URL');
like($email, qr/ViewCVS Links:\n/, 'Check for ViewCVS Links label' );
like($email,
     qr{    http://viewsvn\.bricolage\.cc/\?rev=606&view=rev\n},
     "Check for log mesage ViewCVS URL");
like($email, qr/RT Links:\n/, 'Check for ViewCVS Links label' );
like($email,
     qr{    http://rt\.cpan\.org/NoAuth/Bugs\.html\?id=4321\n},
     "Check for RT URL");
like($email, qr/Bugzilla Links:\n/, 'Check for Bugzilla Links label' );
like( $email,
      qr{   http://bugzilla\.mozilla\.org/show_bug\.cgi\?id=709\n},
      "Check for Bugzilla URL" );
like($email, qr/JIRA Links:\n/, 'Check for JIRA Links label' );
like( $email,
      qr{    http://jira\.atlassian\.com/secure/ViewIssue\.jspa\?key=TST-1608\n},
      "Check for Jira URL" );
like($email, qr/GNATS Links:\n/, 'Check for GNATS Links label' );
like($email,
     qr{    http://gnats\.example\.com/gnatsweb\.pl\?cmd=view&pr=12345\n},
     "Check for GNATS URL");
like($email, qr/Ticket Links:\n/, 'Check for Ticket Links label' );
like($email,
     qr{    http://ticket\.example\.com/id=4321\n},
     "Check for custom ticket URL");

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
ok( $notifier->prepare, "Prepare subject checking" );
ok( $notifier->execute, "Notify subject checking" );
is( $notifier->subject, '[111] Class-Meta',
    "Check subject for stripped cx and no log message line");

# Check the output.
$email = get_output();
like( $email, qr{Subject: \[111\] Class-Meta\n},
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
is( $notifier->subject, '[111] Class',
    "Check subject for stripped cx and no log message line");

# Check the output.
$email = get_output();
like( $email, qr{Subject: \[111\] Class\n},
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
# Test file_exe
##############################################################################
is +SVN::Notify->find_exe('testsvnlook'),  catfile($dir, "testsvnlook$ext"),
    'find_exe should find the test script';

##############################################################################
# Functions.
##############################################################################

sub get_output {
    my $outfile = catfile qw(t data output.txt);
    open CAP, "<$outfile" or die "Cannot open '$outfile': $!\n";
    return join '', <CAP>;
}

# This is so that we know where _find_exe() will search.
MOCKFILESPEC: {
    package File::Spec;
    sub path { 'foo', 'bar', $dir }
}
