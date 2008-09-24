#!perl -w

use strict;
use Test::More tests => 7;
use File::Spec::Functions;

BEGIN { use_ok('SVN::Notify') }

eval { SVN::Notify->new };
ok my $err = $@, 'Caught exception';
like $err, qr/Missing required "repos_path" parameter/,
  'Matches missing repos_path';

eval { SVN::Notify->new(repos_path => 'foo') };
ok $err = $@, 'Caught exception';
like $err, qr/Missing required "revision" parameter/,
  'Matches missing revision';

my $dir = catdir curdir, 't', 'scripts';
$dir = catdir curdir, 't', 'bin' unless -d $dir;
my $ext = $^O eq 'MSWin32' ? '.bat' : '';

eval {
    SVN::Notify->new(
        repos_path => 'foo',
        revision   => 1,
        svnlook    => catfile($dir, "testsvnlook$ext"),
        sendmail   => catfile($dir, "testsendmail$ext"),
    )->prepare
};
ok $err = $@, 'Caught exception';
like $err,
    qr/Missing required "to", "to_regex_map", or "to_email_map" parameter/,
    'Matches missing to or to_regex_map';
