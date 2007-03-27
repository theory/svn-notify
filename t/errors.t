#!perl -w

use strict;
use Test::More tests => 7;

BEGIN { use_ok('SVN::Notify') }

eval { SVN::Notify->new };
ok my $err = $@, 'Caught exception';
like $err, qr/Missing required "repos_path" parameter/,
  'Matches missing repos_path';

eval { SVN::Notify->new(repos_path => 'foo') };
ok $err = $@, 'Caught exception';
like $err, qr/Missing required "revision" parameter/,
  'Matches missing revision';

eval { SVN::Notify->new(repos_path => 'foo', revision => 1) };
ok $err = $@, 'Caught exception';
like $err, qr/Missing required "to", "to_regex_map", or "to_email_map" parameter/,
  'Matches missing to or to_regex_map';
