#!perl -w

# $Id: base.t 2771 2006-04-03 23:10:02Z theory $

use strict;
use Test::More;
use File::Spec::Functions;

if (eval { require HTML::Entities }) {
    plan tests => 77;
} else {
    plan skip_all => "SVN::Notify::Alternative requires HTML::Entities";
}

use_ok 'SVN::Notify::Alternative' or die;

my $ext = $^O eq 'MSWin32' ? '.bat' : '';

my $dir = catdir curdir, 't', 'scripts';
$dir = catdir curdir, 't', 'bin' unless -d $dir;

my %args = (
    svnlook    => catfile($dir, "testsvnlook$ext"),
    sendmail   => catfile($dir, "testsendmail$ext"),
    repos_path => 'tmp',
    revision   => '111',
    to         => 'test@example.com',
    handler    => 'Alternative',
);

##############################################################################
# Basic Functionality.
##############################################################################

ok my $notifier = SVN::Notify->new(%args), 'Construct new alt notifier';
isa_ok $notifier, 'SVN::Notify::Alternative';
isa_ok $notifier, 'SVN::Notify';
ok $notifier->prepare, 'Prepare alt notifier';
ok $notifier->execute, 'Execute the alt notifier';

my $email = get_output();
my $mime_count = ($email =~ s/MIME-Version/MIME-Version/g);
is $mime_count, 1, 'There should be only one MIME-Version header';

my ($bound) = $email
    =~ m{Content-Type: multipart/alternative; boundary="([^"]+)"};
ok $bound, 'There should be a multiplart/alternative header';

my $bound_count = ($email =~ s/--$bound/--$bound/g);
is $bound_count, 3, 'There should be three instances of the boundary';
like $email, qr{--$bound--\s+$},
    'The message should end with the final boundary';

like $email, qr{Content-Type: text/plain; charset=UTF-8},
    'There should be a plain text content-type';

like $email, qr{Content-Type: text/html; charset=UTF-8},
    'There should be an HTML content-type';

# Make sure we have headers for each of the four kinds of changes.
for my $header (
    'Log Message',
    'Modified Paths',
    'Added Paths',
    'Removed Paths',
    'Property Changed',
) {
    like $email, qr/^$header/m, $header;
    like $email, qr{^<h3>$header</h3>}m, "HTML $header";
}

##############################################################################
# Try with diff.
##############################################################################
ok $notifier = SVN::Notify->new(
    %args,
    with_diff => 1,
), 'Construct new colordiff alt notifier';
isa_ok $notifier, 'SVN::Notify::Alternative';
isa_ok $notifier, 'SVN::Notify';
ok $notifier->prepare, 'Prepare alt notifier';
ok $notifier->execute, 'Execute the alt notifier';

$email = get_output();

($bound) = $email
    =~ m{Content-Type: multipart/alternative; boundary="([^"]+)"};
ok $bound, 'There should be a multiplart/alternative header';

$bound_count = ($email =~ s/--$bound/--$bound/g);
is $bound_count, 3, 'There should be three instances of the boundary';
like $email, qr{--$bound--\s+$},
    'The message should end with the final boundary';

like $email, qr{Content-Type: text/plain; charset=UTF-8},
    'There should be a plain text content-type';

like $email, qr{Content-Type: text/html; charset=UTF-8},
    'There should be an HTML content-type';

like $email, qr{^Modified: trunk/Params-CallbackRequest/Changes}m,
    'The diff should be embedded in the plain text mesage';

like $email,
    qr{^<a id="trunkParamsCallbackRequestChanges">Modified: trunk/Params-CallbackRequest/Changes}m,
    'The diff should be embedded in the HTML message';

##############################################################################
# Try with ColorDiff.
##############################################################################
ok $notifier = SVN::Notify->new(
    %args,
    alternatives => ['HTML::ColorDiff'],
    with_diff    => 1,
), 'Construct new colordiff alt notifier';
isa_ok $notifier, 'SVN::Notify::Alternative';
isa_ok $notifier, 'SVN::Notify';
ok $notifier->prepare, 'Prepare alt notifier';
ok $notifier->execute, 'Execute the alt notifier';

$email = get_output();

($bound) = $email
    =~ m{Content-Type: multipart/alternative; boundary="([^"]+)"};
ok $bound, 'There should be a multiplart/alternative header';

$bound_count = ($email =~ s/--$bound/--$bound/g);
is $bound_count, 3, 'There should be three instances of the boundary';
like $email, qr{--$bound--\s+$},
    'The message should end with the final boundary';

like $email, qr{Content-Type: text/plain; charset=UTF-8},
    'There should be a plain text content-type';

like $email, qr{Content-Type: text/html; charset=UTF-8},
    'There should be an HTML content-type';

like $email, qr{^Modified: trunk/Params-CallbackRequest/Changes}m,
    'The diff should be embedded in the HTML mesage';

like $email,
    qr{^<div class="modfile"><h4>Modified: trunk/Params-CallbackRequest/Changes}m,
    'The diff should be embedded in the HTML message';

##############################################################################
# Try with multiple alternatives.
##############################################################################
ok $notifier = SVN::Notify->new(
    %args,
    alternatives => ['HTML', 'HTML::ColorDiff'],
    with_diff    => 1,
), 'Construct new colordiff alt notifier';
isa_ok $notifier, 'SVN::Notify::Alternative';
isa_ok $notifier, 'SVN::Notify';
ok $notifier->prepare, 'Prepare alt notifier';
ok $notifier->execute, 'Execute the alt notifier';

$email = get_output();

($bound) = $email
    =~ m{Content-Type: multipart/alternative; boundary="([^"]+)"};
ok $bound, 'There should be a multiplart/alternative header';

$bound_count = ($email =~ s/--$bound/--$bound/g);
is $bound_count, 4, 'There should be four instances of the boundary';
like $email, qr{--$bound--\s+$},
    'The message should end with the final boundary';

like $email, qr{Content-Type: text/plain; charset=UTF-8},
    'There should be a plain text content-type';

like $email, qr{Content-Type: text/html; charset=UTF-8},
    'There should be an HTML content-type';

like $email, qr{^Modified: trunk/Params-CallbackRequest/Changes}m,
    'The diff should be embedded in the HTML mesage';

like $email,
    qr{^<div class="modfile"><h4>Modified: trunk/Params-CallbackRequest/Changes}m,
    'The diff should be embedded in the HTML message';

like $email,
    qr{^<div class="modfile"><h4>Modified: trunk/Params-CallbackRequest/Changes}m,
    'The diff should be embedded in the HTML::ColorDiff message';

##############################################################################
# Try with attach_diff.
##############################################################################
ok $notifier = SVN::Notify->new(
    %args,
    attach_diff => 1,
), 'Construct new colordiff alt notifier';
isa_ok $notifier, 'SVN::Notify::Alternative';
isa_ok $notifier, 'SVN::Notify';
ok $notifier->prepare, 'Prepare alt notifier';
ok $notifier->execute, 'Execute the alt notifier';

$email = get_output();

($bound) = $email
    =~ m{Content-Type: multipart/alternative; boundary="([^"]+)"};
ok $bound, 'There should be a multiplart/alternative header';

$bound_count = ($email =~ s/--$bound/--$bound/g);
is $bound_count, 3, 'There should be three instances of the alt boundary';
like $email, qr{--$bound--\s+$},
    'The message should end with the final alt boundary';

my ($mbound) = $email
    =~ m{Content-Type: multipart/mixed; boundary="([^"]+)"};
ok $mbound, 'There should be a multipart/mixed header';
$bound_count = ($email =~ s/--$mbound/--$mbound/g);
is $bound_count, 3, 'There should be three instances of the mixed boundary';
like $email, qr{--$mbound--\n--$bound--\s+$},
    'The message should end with the final mixed and alt boundaries';

like $email, qr{Content-Type: text/plain; charset=UTF-8},
    'There should be a plain text content-type';

like $email, qr{Content-Type: text/html; charset=UTF-8},
    'There should be an HTML content-type';

like $email, qr{^Modified: trunk/Params-CallbackRequest/Changes}m,
    'The diff should be embedded in the plain text mesage';

like $email, qr{--$bound\nContent-Type: multipart/mixed; boundary="$mbound"},
    'The multipart/mixed header should come after an alt boundary';

like $email, qr{--$mbound\nContent-Type: text/html; charset=UTF-8},
    'The multipart message should be the HTML format';

like $email,
    qr{--$mbound\nContent-Disposition: attachment; filename=r111-theory\.diff},
    'The diff should be attached to the message';

my $attach_count = ( $email
        =~ s/Content-Disposition: attachment/Content-Disposition: attachment/g
    )
;

is $attach_count, 1, 'The attachment should be attached only once';

sub get_output {
    my $outfile = catfile qw(t data output.txt);
    open CAP, "<$outfile" or die "Cannot open '$outfile': $!\n";
    return join '', <CAP>;
}
