#!perl -w

use strict;
use Test::More tests => 37;
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
    revision_url => 'http://foo.com/?cs=%s',
    to         => ['test@example.com', 'try@example.com'],
);

my $subj = "Did this, that, and the «other».";
my $qsubj;
if (SVN::Notify::PERL58()) {
    Encode::_utf8_on( $subj );
    $qsubj = quotemeta Encode::encode( 'MIME-Q', $subj );
} else {
    $qsubj = quotemeta $subj;
}

##############################################################################

ok my $notifier = SVN::Notify->new(%args), 'Create new SMTP notifier';
isa_ok $notifier, 'SVN::Notify', 'it';
ok $notifier->prepare, 'Prepare notifier';
do {
    # I can't quite get the file handle stuff right in tied_fh below, so
    # just silence warnings for now.
    local $^W;
    ok $notifier->execute, 'Execute notifier';
};
is_deeply $smtp->{new}, [
    'smtp.example.com',
    'Hello' => Sys::Hostname::hostname(),
    NoTLS => 1,
], 'The SMTP::TLS object should have been instantiated with the SMTP address';
is $smtp->{mail}, 'theory', 'Mail should be initiated by user "theory"';
is_deeply $smtp->{to}, $args{to}, 'Mail should be from the right addresses';
ok $smtp->{data}, 'data() should have been called';
ok $smtp->{dataend}, 'dataend() should have been called';
ok $smtp->{quit}, 'quit() should have been called';

like $smtp->{datasend}, qr/Subject: \[111\] $qsubj\n/, 'Check subject';
like $smtp->{datasend}, qr/From: theory\n/, 'Check From';
like $smtp->{datasend}, qr/To:\s+test\@example\.com,\s+try\@example\.com\n/,
    'Check To';
like $smtp->{datasend}, qr{Content-Type: text/plain; charset=UTF-8\n},
      'Check Content-Type';
like $smtp->{datasend}, qr{Content-Transfer-Encoding: 8bit\n},
      'Check Content-Transfer-Encoding';

# Make sure we have headers for each of the four kinds of changes.
for my $header ('Log Message', 'Modified Paths', 'Added Paths',
                'Removed Paths', 'Property Changed', 'Revision Links') {
    like $smtp->{datasend}, qr/^$header/m, $header;
}

# Check that we have the commit metatdata.
like $smtp->{datasend}, qr/Revision: 111\n/, 'Check Revision';
like $smtp->{datasend}, qr/Author:   theory\n/, 'Check Author';
like $smtp->{datasend}, qr/Date:     2004-04-20 01:33:35 -0700 \(Tue, 20 Apr 2004\)\n/,
      'Check Date';

# Check that the log message is there.
like $smtp->{datasend},
    qr/Did this, that, and the «other»\. And then I did some more\. Some\nit was done on a second line\./,
    'Check for log message, which should be UTF-8, but not utf8.';

# Make sure that the revision URL is there:
like $smtp->{datasend}, qr{^    http://foo[.]com/[?]cs=1234}m,
    'We should have a revision URL';

##############################################################################
# Test port, authentication, and Debug.
$args{smtp_user}     = 'theory';
$args{smtp_pass}     = 'w00t!';
$args{smtp_port}     = 1234;
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

is_deeply $smtp->{new}, [
    'smtp.example.com',
    Hello => Sys::Hostname::hostname(),
    Port  => 1234,
    NoTLS => 1,
    User  => 'theory',
    Password => 'w00t!',
    Debug => 1,
], 'The SMTP::TLSx object should be instantiated with SMTP address and Debug on';
is $smtp->{mail}, 'theory', 'Mail should be initiated by user "theory"';
is_deeply $smtp->{to}, $args{to}, 'Mail should be from the right addresses';
ok $smtp->{data}, 'data() should have been called';
ok $smtp->{dataend}, 'dataend() should have been called';
ok $smtp->{quit}, 'quit() should have been called';

# This class mocks Net::SMTP for testing purposes.
package Net::SMTP::TLS;
BEGIN { $INC{'Net/SMTP/TLS.pm'} = __FILE__; }

sub new {
    my $class = shift;
    $smtp->{new} = \@_;
    bless {}, $class;
}

sub mail     { $smtp->{mail} = $_[1] }
sub to       { shift; $smtp->{to} = \@_ }
sub data     { $smtp->{data} = 1 }
sub datasend { shift; $smtp->{datasend} .= join '', @_ }
sub dataend  { $smtp->{dataend} = 1; }
sub quit     { $smtp->{quit} = 1 }
sub tied_fh {
    $smtp->{tied_fh} = 1;
    return \local *STDOUT;
}
