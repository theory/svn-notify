#!perl -w

# $Id$

use strict;
use Test::More;
use File::Spec::Functions;

if ($^O eq 'MSWin32') {
    plan skip_all => "SVN::Notify::HTML not yet supported on Win32";
} elsif (eval { require HTML::Entities }) {
    plan tests => 97;
} else {
    plan skip_all => "SVN::Notify::HTML requires HTML::Entities";
}

BEGIN { use_ok('SVN::Notify::HTML') }

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
ok( my $notifier = SVN::Notify::HTML->new(%args),
    "Construct new HTML notifier" );
isa_ok($notifier, 'SVN::Notify::HTML');
isa_ok($notifier, 'SVN::Notify');
ok( $notifier->prepare, "Single method call prepare" );
ok( $notifier->execute, "HTML notify" );

# Get the output.
my $email = get_output();

# Check the email headers.
like( $email, qr/Subject: \[111\] Did this, that, and the other\.\n/,
      "Check HTML subject" );
like( $email, qr/From: theory\n/, 'Check HTML From');
like( $email, qr/To: test\@example\.com\n/, 'Check HTML To');
like( $email, qr{Content-Type: text/html; charset=UTF-8\n},
      'Check HTML Content-Type' );
like( $email, qr{Content-Transfer-Encoding: 8bit\n},
      'Check HTML Content-Transfer-Encoding');

# Make sure that the <html>, <head>, <body>, and <dl> headers tags
# are included.
for my $tag (qw(html head body dl)) {
    like( $email, qr/<$tag>/, "Check for <$tag> tag" );
    like( $email, qr/<\/$tag>/, "Check for </$tag> tag" );
}

# Make sure we have styles.
like( $email, qr|<style type="text/css">|, "Check for <style> tag" );
like( $email, qr/<\/style>/, "Check for </style> tag" );
like( $email, qr/pre {font-size:125%;}/, "Check for style" );

# Make sure we have headers for each of the four kinds of changes.
for my $header ('Log Message', 'Modified Files', 'Added Files',
                'Removed Files', 'Property Changed') {
    like( $email, qr{<h3>$header</h3>}, "HTML $header" );
}

# Check that we have the commit metatdata.
like( $email, qr|<dt>Revision</dt> <dd>111</dd>\n|, 'Check Revision');
like( $email, qr|<dt>Author</dt> <dd>theory</dd>\n|, 'Check Author');
like( $email,
      qr|<dt>Date</dt> <dd>2004-04-20 01:33:35 -0700 \(Tue, 20 Apr 2004\)</dd>\n|,
      'Check Date');

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
# Make sure that handler delegation works.
##############################################################################
ok( $notifier = SVN::Notify->new(%args, handler => 'HTML'),
    "Construct new HTML notifier" );
isa_ok($notifier, 'SVN::Notify::HTML');
isa_ok($notifier, 'SVN::Notify');
ok( $notifier->prepare, "Single method call prepare" );
ok( $notifier->execute, "HTML notify" );

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

##############################################################################
# Include HTML diff.
##############################################################################
ok( $notifier = SVN::Notify::HTML->new(%args, with_diff => 1),
    "Construct new HTML diff notifier" );
isa_ok($notifier, 'SVN::Notify::HTML');
isa_ok($notifier, 'SVN::Notify');
ok( $notifier->prepare, "Single method call prepare" );
ok( $notifier->execute, "HTML diff notify" );

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

# Make sure that the diff is included and escaped.
like( $email, qr{Modified: trunk/Params-CallbackRequest/Changes},
      "Check for diff" );

# Make sure that it's not attached.
unlike( $email, qr{Content-Type: multipart/mixed; boundary=},
        "Check for no html diff attachment" );
unlike( $email, qr{Content-Disposition: attachment; filename=},
        "Check for no html diff filename" );
like( $email, qr{<pre>\nModified}, "Check for pre tag" );
like( $email, qr{isa        =\&gt; 'Apache',}, "Check for HTML escaping" );

##############################################################################
# Attach diff.
##############################################################################
ok( $notifier = SVN::Notify::HTML->new(%args, attach_diff => 1),
    "Construct new HTML attach diff notifier" );
isa_ok($notifier, 'SVN::Notify::HTML');
isa_ok($notifier, 'SVN::Notify');
ok( $notifier->prepare, "Single method call prepare" );
ok( $notifier->execute, "Attach HTML attach diff notify" );

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
like( $email, qr{Content-Type: multipart/mixed; boundary="(.*)"\n},
        "Check for html diff attachment" );
like( $email,
      qr{Content-Disposition: attachment; filename=r111-theory.diff\n},
      "Check for html diff filename" );
unlike( $email, qr{<pre>\nModified}, "Check for no pre tag" );

# Check for boundaries.
is( scalar @{[$email =~ m{(--[^-\s]+\n)}g]}, 2,
    'Check for two boundaries');
is( scalar @{[$email =~ m{(--[^-\s]+--)}g]}, 1,
    'Check for one final boundary');

##############################################################################
# Try html format with a single file changed.
##############################################################################
ok( $notifier = SVN::Notify::HTML->new(%args, revision => '222'),
    "Construct new subject_cx file notifier" );
isa_ok($notifier, 'SVN::Notify::HTML');
isa_ok($notifier, 'SVN::Notify');
ok( $notifier->prepare, "Prepare HTML file" );
ok( $notifier->execute, "Notify HTML file" );

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
# Try view_cvs_url + HTML.
##############################################################################
ok( $notifier = SVN::Notify::HTML->new(%args,
     viewcvs_url => 'http://svn.example.com/',
),
    "Construct new HTML view_cvs_url notifier" );
isa_ok($notifier, 'SVN::Notify::HTML');
isa_ok($notifier, 'SVN::Notify');
ok( $notifier->prepare, "Prepare HTML view_cvs_url" );
ok( $notifier->execute, "Notify HTML view_cvs_url" );

# Check the output.
$email = get_output();
like( $email,
      qr|<dt>Revision</dt>\s+<dd><a href="http://svn\.example\.com/\?rev=111\&amp;view=rev">111</a></dd>\n|,
      'Check for HTML URL');

##############################################################################
# Try charset.
##############################################################################
ok( $notifier = SVN::Notify::HTML->new(%args, charset => 'ISO-8859-1'),
    "Construct new charset notifier" );
isa_ok($notifier, 'SVN::Notify::HTML');
isa_ok($notifier, 'SVN::Notify');
ok( $notifier->prepare, "Prepare charset" );
ok( $notifier->execute, "Notify charset" );

# Check the output.
$email = get_output();
like( $email, qr{Content-Type: text/html; charset=ISO-8859-1\n},
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
