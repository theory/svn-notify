#!perl -w

# $Id: colordiff.t 726 2004-10-09 19:28:09Z theory $

use strict;
use Test::More;
use File::Spec::Functions;

if ($^O eq 'MSWin32') {
    plan skip_all => "SVN::Notify::HTML::ColorDiff not yet supported on Win32";
} elsif (eval { require HTML::Entities }) {
    plan tests => 120;
} else {
    plan skip_all => "SVN::Notify::HTML::ColorDiff requires HTML::Entities";
}

BEGIN { use_ok('SVN::Notify::HTML::ColorDiff') }

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
ok( my $notifier = SVN::Notify::HTML::ColorDiff->new(%args),
    "Construct new HTML::ColorDiff notifier" );
isa_ok($notifier, 'SVN::Notify::HTML::ColorDiff');
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
    like( $email, qr/<$tag/, "Check for <$tag> tag" );
    like( $email, qr/<\/$tag>/, "Check for </$tag> tag" );
}

# Make sure we have styles and the appropriate div.
like( $email, qr|<style type="text/css">|, "Check for <style> tag" );
like( $email, qr/<\/style>/, "Check for </style> tag" );
like( $email, qr/#patch .add {background:#ddffdd;}/, "Check for style" );
like( $email, qr/<div id="msg">/, "Check for msg div" );

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
ok( $notifier = SVN::Notify->new(%args, handler => 'HTML::ColorDiff'),
    "Construct new HTML notifier" );
isa_ok($notifier, 'SVN::Notify::HTML::ColorDiff');
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
ok( $notifier = SVN::Notify::HTML::ColorDiff->new(%args, with_diff => 1),
    "Construct new HTML diff notifier" );
isa_ok($notifier, 'SVN::Notify::HTML::ColorDiff');
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
like( $email, qr/<div id="patch">/, "Check for patch div" );
like( $email, qr{<a id="trunkParamsCallbackRequestChanges"></a>\n},
      "Check for file div ID");
like( $email, qr{<div class="modfile"><h4>trunk/Params-CallbackRequest/Changes \(600 => 601\)</h4>},
      "Check for diff file header" );
like( $email, qr{<a id="trunkParamsCallbackRequestlibParamsCallbackpm"></a>\n},
      "Check for added file div ID");
like( $email, qr{<div class="addfile"><h4>trunk/Params-CallbackRequest/lib/Params/Callback.pm \(600 => 601\)</h4>},
      "Check for added diff file header" );

# Make sure that it's not attached.
unlike( $email, qr{Content-Type: multipart/mixed; boundary=},
        "Check for no html diff attachment" );
unlike( $email, qr{Content-Disposition: attachment; filename=},
        "Check for no html diff filename" );
like( $email, qr{isa        =\&gt; 'Apache',}, "Check for HTML escaping" );

# Make sure that the file names have links into the diff.
like( $email,
      qr|<li><a href="#trunkParamsCallbackRequestChanges">trunk/Params-CallbackRequest/Changes</a></li>\n|,
      "Check for file name link." );

# Make sure that the file names are linked.
like( $email,
      qr|<li><a href="#trunkClassMetaChanges">trunk/Class-Meta/Changes</a></li>|,
      "Check for linked file name" );
like( $email,
      qr|<li><a href="#trunkClassMetalibClassMetaTypepm">trunk/Class-Meta/lib/Class/Meta/Type\.pm</a></li>|,
      "Check for linked property change file");

##############################################################################
# Attach diff.
##############################################################################
ok( $notifier = SVN::Notify::HTML::ColorDiff->new(%args, attach_diff => 1,
                                       boundary => 'frank'),
    "Construct new HTML attach diff notifier" );
isa_ok($notifier, 'SVN::Notify::HTML::ColorDiff');
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
is( scalar @{[$email =~ m{(--frank\n)}g]}, 2,
    'Check for two boundaries');
is( scalar @{[$email =~ m{(--frank--)}g]}, 1,
    'Check for one final boundary');

##############################################################################
# Try html format with a single file changed.
##############################################################################
ok( $notifier = SVN::Notify::HTML::ColorDiff->new(%args, revision => '222'),
    "Construct new subject_cx file notifier" );
isa_ok($notifier, 'SVN::Notify::HTML::ColorDiff');
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
ok( $notifier = SVN::Notify::HTML::ColorDiff->new(%args,
     viewcvs_url => 'http://svn.example.com/',
),
    "Construct new HTML view_cvs_url notifier" );
isa_ok($notifier, 'SVN::Notify::HTML::ColorDiff');
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
ok( $notifier = SVN::Notify::HTML::ColorDiff->new(%args, charset => 'ISO-8859-1'),
    "Construct new charset notifier" );
isa_ok($notifier, 'SVN::Notify::HTML::ColorDiff');
isa_ok($notifier, 'SVN::Notify');
ok( $notifier->prepare, "Prepare charset" );
ok( $notifier->execute, "Notify charset" );

# Check the output.
$email = get_output();
like( $email, qr{Content-Type: text/html; charset=ISO-8859-1\n},
      'Check Content-Type charset' );

##############################################################################
# Try html format with propsets.
##############################################################################
ok( $notifier = SVN::Notify::HTML::ColorDiff->new(%args, with_diff => 1,
                                                  revision => '333'),
    "Construct new propset notifier" );
isa_ok($notifier, 'SVN::Notify::HTML::ColorDiff');
isa_ok($notifier, 'SVN::Notify::HTML');
isa_ok($notifier, 'SVN::Notify');
ok( $notifier->prepare, "Prepare propset HTML file" );
ok( $notifier->execute, "Notify propset HTML file" );

# Check the output.
$email = get_output();
like( $email, qr{Subject: \[333\] Property modification\.\n},
      "Check subject header for propset HTML" );
like( $email, qr/From: theory\n/, 'Check propset HTML From');
like( $email, qr/To: test\@example\.com\n/, 'Check propset HTML To');
like( $email, qr{Content-Type: text/html; charset=UTF-8\n},
      'Check propset HTML Content-Type' );
like( $email, qr{Content-Transfer-Encoding: 8bit\n},
      'Check propset HTML Content-Transfer-Encoding');

# Check for a header for the modified file.
like( $email, qr{<a id="trunkactivitymailbinactivitymail"></a>\n},
      "Check for modified file div ID");
like( $email, qr{<div class="modfile"><h4>trunk/activitymail/bin/activitymail \(681 => 682\)</h4>},
      "Check for modified file header" );

# Check for propset file.
like( $email, qr{<a id="trunkactivitymailbinactivitymail"></a>\n},
      "Check for modified file div ID");
like( $email, qr{<div class="propset"><h4>trunk/activitymail/t/activitymail\.t</h4>},
      "Check for modified file header" );

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
