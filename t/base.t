#!perl -w

# $Id$

use strict;
use Test::More;
use File::Spec::Functions;

if ($^O eq 'MSWin32') {
    plan skip_all => "SVN::Notify not yet supported on Win32";
} else {
    plan tests => 150;
}

BEGIN { use_ok('SVN::Notify') }

my $ext = $^O eq 'MSWin32' ? '.bat' : '';

my %args = (
    svnlook    => catfile(curdir, 't', 'bin', "testsvnlook$ext"),
    sendmail   => catfile(curdir, 't', 'bin', "testsendmail$ext"),
    repos_path => 'tmp',
    format     => 'text',
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
ok( $notifier->send, "Notify" );

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
for my $header ('Log Message', 'Modified Files', 'Added Files',
                'Removed Files', 'Property Changed') {
    like( $email, qr/$header/, $header);
}

# Check that the log message is there.
like( $email, qr/Did this, that, and the other\. And then I did some more\. Some\nit was done on a second line\. Go figure\./, 'Check for log message' );

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
# HTML Email.
##############################################################################
ok( $notifier = SVN::Notify->new(%args, format => 'html'),
    "Construct new HTML notifier" );
isa_ok($notifier, 'SVN::Notify');
ok( $notifier->prepare, "Single method call prepare" );
ok( $notifier->send, "HTML notify" );

# Get the output.
$email = get_output();

# Check the email headers.
like( $email, qr/Subject: \[111\] Did this, that, and the other\.\n/,
      "Check HTML subject" );
like( $email, qr/From: theory\n/, 'Check HTML From');
like( $email, qr/To: test\@example\.com\n/, 'Check HTML To');
like( $email, qr{Content-Type: text/html; charset=UTF-8\n},
      'Check HTML Content-Type' );
like( $email, qr{Content-Transfer-Encoding: 8bit\n},
      'Check HTML Content-Transfer-Encoding');

# Make sure we have headers for each of the four kinds of changes.
for my $header ('Log Message', 'Modified Files', 'Added Files',
                'Removed Files', 'Property Changed') {
    like( $email, qr{<h3>$header</h3>}, "HTML $header" );
}

# Check that the log message is there.
like( $email, qr{<pre>Did this, that, and the other\. And then I did some more\. Some\nit was done on a second line\. Go figure\.</pre>}, 'Check for HTML log message' );

# Make sure that Class/Meta.pm is listed twice, once for modification and once
# for its attribute being set.
is( scalar @{[$email =~ m{(<li>trunk/Class-Meta/lib/Class/Meta\.pm</li>)}g]}, 2,
    'Check for two HTML Class/Meta.pm');
# For other file names, there should be only one instance.
is( scalar @{[$email =~ m{(<li>trunk/Class-Meta/lib/Class/Meta/Class\.pm</li>)}g]}, 1,
    'Check for one HTML Class/Meta/Class.pm');
is( scalar @{[$email =~ m{(<li>trunk/Class-Meta/lib/Class/Meta/Type\.pm</li>)}g]}, 1,
    'Check for one HTML Class/Meta/Type.pm');

# Make sure that no diff is included.
unlike( $email, qr{Modified: trunk/Params-CallbackRequest/Changes},
        "Check for html diff" );

##############################################################################
# Include diff.
##############################################################################
ok( $notifier = SVN::Notify->new(%args, with_diff => 1),
    "Construct new diff notifier" );
isa_ok($notifier, 'SVN::Notify');
ok( $notifier->prepare, "Single method call prepare" );
ok( $notifier->send, "Diff notify" );

# Get the output.
$email = get_output();

like( $email, qr/Subject: \[111\] Did this, that, and the other\.\n/,
      "Check diff subject" );
like( $email, qr/From: theory\n/, 'Check diff From');
like( $email, qr/To: test\@example\.com\n/, 'Check diff To');

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
# Attach diff.
##############################################################################
ok( $notifier = SVN::Notify->new(%args, attach_diff => 1),
    "Construct new attach diff notifier" );
isa_ok($notifier, 'SVN::Notify');
ok( $notifier->prepare, "Single method call prepare" );
ok( $notifier->send, "Attach diff notify" );

# Get the output.
$email = get_output();

like( $email, qr/Subject: \[111\] Did this, that, and the other\.\n/,
      "Check attach diff subject" );
like( $email, qr/From: theory\n/, 'Check attach diff From');
like( $email, qr/To: test\@example\.com\n/, 'Check attach diff To');

# Make sure we have two sets of headers for attachments.
is( scalar @{[ $email =~ m{Content-Type: text/plain; charset=UTF-8\n}g ]}, 2,
    'Check for two Content-Type headers' );
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

##############################################################################
# Include HTML diff.
##############################################################################
ok( $notifier = SVN::Notify->new(%args, format => 'html', with_diff => 1),
    "Construct new HTML diff notifier" );
isa_ok($notifier, 'SVN::Notify');
ok( $notifier->prepare, "Single method call prepare" );
ok( $notifier->send, "HTML diff notify" );

# Get the output.
$email = get_output();

like( $email, qr/Subject: \[111\] Did this, that, and the other\.\n/,
      "Check HTML diff subject" );
like( $email, qr/From: theory\n/, 'Check HTML diff From');
like( $email, qr/To: test\@example\.com\n/, 'Check HTML diff To');

# Make sure there are no attachment headers
is( scalar @{[ $email =~ m{Content-Type: text/(plain|html); charset=UTF-8\n} ]}, 1,
    'Check for one HTML Content-Type header' );
is( scalar @{[$email =~ m{Content-Transfer-Encoding: 8bit\n}g]}, 1,
      'Check for one HTML Content-Transfer-Encoding header');

# Make sure that the diff is included.
like( $email, qr{Modified: trunk/Params-CallbackRequest/Changes},
      "Check for diff" );

# Make sure that it's not attached.
unlike( $email, qr{Content-Type: multipart/mixed; boundary=},
        "Check for no html diff attachment" );
unlike( $email, qr{Content-Disposition: attachment; filename=},
        "Check for no html diff filename" );
like( $email, qr{<pre>\nModified}, "Check for pre tag" );

##############################################################################
# Attach diff.
##############################################################################
ok( $notifier = SVN::Notify->new(%args, format => 'html', attach_diff => 1),
    "Construct new HTML attach diff notifier" );
isa_ok($notifier, 'SVN::Notify');
ok( $notifier->prepare, "Single method call prepare" );
ok( $notifier->send, "Attach HTML attach diff notify" );

# Get the output.
$email = get_output();

like( $email, qr/Subject: \[111\] Did this, that, and the other\.\n/,
      "Check HTML attach diff subject" );
like( $email, qr/From: theory\n/, 'Check HTML attach diff From');
like( $email, qr/To: test\@example\.com\n/, 'Check HTML attach diff To');

# Make sure we have two sets of headers for attachments.
is( scalar @{[ $email =~ m{Content-Type: text/(plain|html); charset=UTF-8\n}g ]}, 2,
    'Check for two Content-Type headers' );
is( scalar @{[$email =~ m{Content-Transfer-Encoding: 8bit\n}g]}, 2,
      'Check for two Content-Transfer-Encoding headers');

# Make sure that the diff is included.
like( $email, qr{Modified: trunk/Params-CallbackRequest/Changes},
      "Check for diff" );

# Make sure that it's attached.
like( $email, qr{Content-Type: multipart/mixed; boundary=},
        "Check for html diff attachment" );
like( $email,
      qr{Content-Disposition: attachment; filename=r111-theory.diff\n},
      "Check for html diff filename" );
unlike( $email, qr{<pre>\nModified}, "Check for no pre tag" );


##############################################################################
# Try to_regex_map.
##############################################################################
ok( $notifier = SVN::Notify->new(%args, to_regex_map => {
    'one@example.com'  => 'AccessorBuilder',
    'two@example.com'  => '^/trunk',
    'none@example.com' => '/branches',
}), "Construct new regex_map notifier" );
isa_ok($notifier, 'SVN::Notify');
ok( $notifier->prepare, "Prepare to_regex_map" );
ok( $notifier->send, "Notify to_regex_map" );

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
ok( $notifier->send, "Notify reply_to" );

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
ok( $notifier->send, "Notify subject_prefix" );

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
ok( $notifier->send, "Notify subject_cx" );

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
ok( $notifier->send, "Notify subject_cx file" );

# Check the output.
$email = get_output();
like( $email, qr{Subject: \[222\] trunk/App-Info/META.yml: Hrm hrm\.\n},
      "Check subject header for file CX" );

##############################################################################
# Try html format with a single file changed.
##############################################################################
ok( $notifier = SVN::Notify->new(%args, revision => '222', format => 'html'),
    "Construct new subject_cx file notifier" );
isa_ok($notifier, 'SVN::Notify');
ok( $notifier->prepare, "Prepare HTML file" );
ok( $notifier->send, "Notify HTML file" );

# Check the output.
$email = get_output();
like( $email, qr{Subject: \[222\] Hrm hrm\.\n},
      "Check subject header for HTML file" );
like( $email, qr/From: theory\n/, 'Check HTML file From');
like( $email, qr/To: test\@example\.com\n/, 'Check HTML file To');
like( $email, qr{Content-Type: text/html; charset=UTF-8\n},
      'Check HTML file Content-Type' );
like( $email, qr{Content-Transfer-Encoding: 8bit\n},
      'Check HTML file Content-Transfer-Encoding');

##############################################################################
# Try max_sub_length.
##############################################################################
ok( $notifier = SVN::Notify->new(%args, max_sub_length => 10),
    "Construct new max_sub_length notifier" );
isa_ok($notifier, 'SVN::Notify');
ok( $notifier->prepare, "Prepare max_sub_length" );
ok( $notifier->send, "Notify max_sub_length" );

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
ok( $notifier->send, "Notify user_domain" );

# Check the output.
$email = get_output();
like( $email, qr/From: theory\@example\.net\n/, 'Check From for user domain');

##############################################################################
# Try view_cvs_url.
##############################################################################
ok( $notifier = SVN::Notify->new(%args, viewcvs_url => 'http://svn.example.com/'),
    "Construct new view_cvs_url notifier" );
isa_ok($notifier, 'SVN::Notify');
ok( $notifier->prepare, "Prepare view_cvs_url" );
ok( $notifier->send, "Notify view_cvs_url" );

# Check the output.
$email = get_output();
like( $email,
      qr{    trunk/Class-Meta/lib/Class/Meta\.pm\n       http://svn\.example\.com/trunk/Class-Meta/lib/Class/Meta\.pm\?r1=110\&r2=111\n},
  "Check for URL" );

##############################################################################
# Try view_cvs_url + HTML.
##############################################################################
ok( $notifier = SVN::Notify->new(%args,
     viewcvs_url => 'http://svn.example.com/',
     format      => 'html',
),
    "Construct new HTML view_cvs_url notifier" );
isa_ok($notifier, 'SVN::Notify');
ok( $notifier->prepare, "Prepare HTML view_cvs_url" );
ok( $notifier->send, "Notify HTML view_cvs_url" );

# Check the output.
$email = get_output();
like( $email,
      qr{  \<li\>\<a href="http://svn\.example\.com/trunk/Class-Meta/lib/Class/Meta\.pm"\>trunk/Class-Meta/lib/Class/Meta\.pm\</a\> \(\<a href="http://svn\.example\.com/trunk/Class-Meta/lib/Class/Meta\.pm\?r1=110\&amp;r2=111"\>Diff\</a\>\)\</li\>\n},
  "Check for HTML URL" );

##############################################################################
# Try charset.
##############################################################################
ok( $notifier = SVN::Notify->new(%args, charset => 'ISO-8859-1'),
    "Construct new charset notifier" );
isa_ok($notifier, 'SVN::Notify');
ok( $notifier->prepare, "Prepare charset" );
ok( $notifier->send, "Notify charset" );

# Check the output.
$email = get_output();
like( $email, qr{Content-Type: text/plain; charset=ISO-8859-1\n},
      'Check Content-Type charset' );

##############################################################################
# Functions.
##############################################################################

sub get_output {
    my $outfile = catfile qw(t data output.txt);
    open CAP, "<$outfile" or die "Cannot open '$outfile': $!\n";
    my $email = do { local $/;  <CAP>; };
    close CAP;
    return $email;
}
