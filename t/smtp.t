#!perl -w

# $Id: base.t 2771 2006-04-03 23:10:02Z theory $

use strict;
use Test::More tests => 36;
use File::Spec::Functions;

use_ok 'SVN::Notify' or die;

my $ext = $^O eq 'MSWin32' ? '.bat' : '';

my $dir = catdir curdir, 't', 'scripts';
$dir = catdir curdir, 't', 'bin' unless -d $dir;
my $smtp = {};

my %args = (
    svnlook    => catfile($dir, "testsvnlook$ext"),
    smtp       => 'smtp.example.com',
    repos_path => 'tmp',
    revision   => '111',
    to         => 'test@example.com',
);

ok my $notifier = SVN::Notify->new(%args), 'Create new SMTP notifier';
isa_ok $notifier, 'SVN::Notify', 'it';
ok $notifier->prepare, 'Prepare notifier';
do {
    # I can't quite get the file handle stuff right in tied_fh below, so
    # just silence warnings for now.
    local $^W;
    ok $notifier->execute, 'Execute notifier';
};
is_deeply $smtp->{new}, ['smtp.example.com'],
    'The SMTP object should have been instantiated with the SMTP address';
is $smtp->{mail}, 'theory', 'Mail should be initiated by user "theory"';
is $smtp->{to}, 'test@example.com', 'Mail should be from the right address';
ok $smtp->{data}, 'data() should have been called';
ok $smtp->{dataend}, 'dataend() should have been called';
ok $smtp->{quit}, 'quit() should have been called';

like $smtp->{datasend}, qr/Subject: \[111\] Did this, that, and the other\.\n/,
      "Check subject";
like $smtp->{datasend}, qr/From: theory\n/, 'Check From';
like $smtp->{datasend}, qr/To: test\@example\.com\n/, 'Check To';
like $smtp->{datasend}, qr{Content-Type: text/plain; charset=UTF-8\n},
      'Check Content-Type';
like $smtp->{datasend}, qr{Content-Transfer-Encoding: 8bit\n},
      'Check Content-Transfer-Encoding';

# Make sure we have headers for each of the four kinds of changes.
for my $header ('Log Message', 'Modified Paths', 'Added Paths',
                'Removed Paths', 'Property Changed') {
    like $smtp->{datasend}, qr/^$header/m, $header;
}

# Check that we have the commit metatdata.
like $smtp->{datasend}, qr/Revision: 111\n/, 'Check Revision';
like $smtp->{datasend}, qr/Author:   theory\n/, 'Check Author';
like $smtp->{datasend}, qr/Date:     2004-04-20 01:33:35 -0700 \(Tue, 20 Apr 2004\)\n/,
      'Check Date';

# Check that the log message is there.
like $smtp->{datasend},
    qr/Did this, that, and the other\. And then I did some more\. Some\nit was done on a second line\./,
    'Check for log message';

##############################################################################
# Test authentication and Debug.
$args{smtp_user}     = 'theory';
$args{smtp_pass}     = 'w00t!';
$args{smtp_authtype} = 'NTLM';
$args{verbose}       = 2;
$smtp = {};

do {
    # Silence debugging.
    local $^W;
    *SVN::Notify::_dbpnt = sub {};
};

ok $notifier = SVN::Notify->new(%args),
    'Create new authenticating SMTP notifier';
isa_ok $notifier, 'SVN::Notify', 'it';
ok $notifier->prepare, 'Prepare notifier';
do {
    # I can't quite get the file handle stuff right in tied_fh below, so
    # just silence warnings for now.
    local $^W;
    ok $notifier->execute, 'Execute notifier';
};

is_deeply $smtp->{new}, ['smtp.example.com', Debug => 1],
    'The SMTP object should be instantiated with SMTP address and Debug on';
is $smtp->{mail}, 'theory', 'Mail should be initiated by user "theory"';
is $smtp->{to}, 'test@example.com', 'Mail should be from the right address';
ok $smtp->{data}, 'data() should have been called';
ok $smtp->{dataend}, 'dataend() should have been called';
ok $smtp->{quit}, 'quit() should have been called';
is $smtp->{auth}, 'NTLM,theory,w00t!', 'auth() should have been called';

# This class mocks Net::SMTP for testing purposes.
package Net::SMTP;
BEGIN { $INC{'Net/SMTP.pm'} = __FILE__; }

sub new {
    my $class = shift;
    $smtp->{new} = \@_;
    bless {}, $class;
}

sub mail     { $smtp->{mail} = $_[1] }
sub to       { $smtp->{to} = $_[1] }
sub data     { $smtp->{data} = 1 }
sub datasend { shift; $smtp->{datasend} .= join '', @_ }
sub dataend  { $smtp->{dataend} = 1; }
sub quit     { $smtp->{quit} = 1 }
sub tied_fh {
    $smtp->{tied_fh} = 1;
    return \local *STDOUT;
}

package Net::SMTP_auth;
use base 'Net::SMTP';
BEGIN { $INC{'Net/SMTP_auth.pm'} = __FILE__; }
sub auth { shift; $smtp->{auth} = join ',', @_ }
