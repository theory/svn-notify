#!perl -w

# $Id$

use strict;
use Test::More tests => 12;

use File::Spec::Functions;

BEGIN { use_ok('SVN::Notify') }

my %args = (
    svnlook  => catfile(qw(t bin testsvnlook)),
    sendmail => catfile(qw(t bin testsendmail)),
#    svnlook  => "$^X " . catfile(qw(t bin testsvnlook)),
#    sendmail => "$^X " . catfile(qw(t bin testsendmail)),
    path     => 'tmp',
    format   => 'text',
    rev      => '111',
    to       => 'test@example.com',
);


ok( my $notifier = SVN::Notify->new(%args), "Construct new notifier" );
isa_ok($notifier, 'SVN::Notify');
ok( $notifier->prepare_recipients, 'prepare recipients' );
ok( $notifier->prepare_contents, 'prepare contents' );
ok( $notifier->prepare_subject, 'prepare subject');
ok( $notifier->prepare_files, 'prepare files');
#while (my ($k, $v) = each %{$notifier->{files}}) {
#    diag $k;
#    diag "  $_" for @$v;
#}
ok( $notifier->notify, "Notify" );

my $outfile = catfile qw(t data output.txt);
open CAP, "<$outfile" or die "Cannot open '$outfile': $!\n";
my $email = do { local $/;  <CAP>; };
close CAP;

# Check the email headers.
like( $email, qr/Subject: \[111\] Did this, that, and the other\.\n/,
      "Check subject" );
like( $email, qr/From: theory\n/, 'Check From');
like( $email, qr/To: test\@example\.com\n/, 'Check To');
like( $email, qr{Content-Type: text/plain\n}, 'Check Content-Type' );
