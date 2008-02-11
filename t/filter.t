#!perl -w

# $Id $

use strict;
use Test::More tests => 6;
use File::Spec::Functions;

use_ok('SVN::Notify');

my $ext = $^O eq 'MSWin32' ? '.bat' : '';

my $dir = catdir curdir, 't', 'scripts';
$dir = catdir curdir, 't', 'bin' unless -d $dir;

my %args = (
    svnlook    => catfile($dir, "testsvnlook$ext"),
    sendmail   => catfile($dir, "testsendmail$ext"),
    repos_path => 'tmp',
    revision   => '222',
    to         => ['test@example.com'],
    filter     => ['Uppercase'],
);

##############################################################################
# Basic Functionality.
##############################################################################

ok( my $notifier = SVN::Notify->new(%args), 'Construct new notifier' );
isa_ok($notifier, 'SVN::Notify');
ok $notifier->prepare, 'Prepare log_message filter checking';
ok $notifier->execute, 'Notify log_mesage filter checking';
my $email = get_output();
like $email, qr/HRM HRM[.] LET'S TRY A FEW LINKS/,
    'The log message should be uppercase';

##############################################################################
# Functions.
##############################################################################

sub get_output {
    my $outfile = catfile qw(t data output.txt);
    open CAP, "<$outfile" or die "Cannot open '$outfile': $!\n";
    binmode CAP, 'utf8' if SVN::Notify::PERL58();
    return join '', <CAP>;
}

BEGIN {
    package SVN::Notify::Filter::Uppercase;
    $INC{'SVN/Notify/Filter/Uppercase.pm'} = __FILE__;
    sub log_message {
        my ($notifier, $lines) = @_;
        $_ = uc $_ for @$lines;
        return $lines;
    }
    1;
}
