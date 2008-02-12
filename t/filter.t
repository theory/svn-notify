#!perl -w

# $Id $

use strict;
use Test::More tests => 96;
use File::Spec::Functions;

use_ok('SVN::Notify');
use_ok('SVN::Notify::HTML');

my $ext = $^O eq 'MSWin32' ? '.bat' : '';

my $dir = catdir curdir, 't', 'scripts';
$dir = catdir curdir, 't', 'bin' unless -d $dir;

my %args = (
    svnlook    => catfile($dir, "testsvnlook$ext"),
    sendmail   => catfile($dir, "testsendmail$ext"),
    repos_path => 'tmp',
    revision   => '111',
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
like $email, qr/DID THIS, THAT, AND THE OTHER/,
    'The log message should be uppercase';

##############################################################################
# Multiple Filters.
##############################################################################

ok( $notifier = SVN::Notify->new(
    %args,
    filter => [ 'Uppercase', 'LowerVowel' ],
), 'Construct new multi filter notifier' );
isa_ok($notifier, 'SVN::Notify');
ok $notifier->prepare, 'Prepare log_message filter checking';
ok $notifier->execute, 'Notify log_mesage filter checking';
$email = get_output();
like $email, qr/DiD THiS, THaT, aND THe oTHeR/,
    'The log message should be uppercase but vowels lowercase';

##############################################################################
# Metadata filter.
##############################################################################

ok( $notifier = SVN::Notify->new(
    %args,
    filter => [ 'CapMeta' ],
), 'Construct new metadata filter notifier' );
isa_ok($notifier, 'SVN::Notify');
ok $notifier->prepare, 'Prepare log_message filter checking';
ok $notifier->execute, 'Notify log_mesage filter checking';
$email = get_output();
like $email, qr/REVISION: 111/, 'Revision header should be uppercase';
like $email, qr/AUTHOR:   theory/, 'Author header should be uppercase';

##############################################################################
# Headers filter.
##############################################################################

ok( $notifier = SVN::Notify->new(
    %args,
    filter => [ 'AddHeader' ],
), 'Construct new headers filter notifier' );
isa_ok($notifier, 'SVN::Notify');
ok $notifier->prepare, 'Prepare log_message filter checking';
ok $notifier->execute, 'Notify log_mesage filter checking';
$email = get_output();
like $email, qr/X-Foo: Bar\nContent-Type:/, 'New header should be included';

##############################################################################
# Start and End filters.
##############################################################################

ok( $notifier = SVN::Notify->new(
    %args,
    filter => [ 'StartEnd' ],
), 'Construct start and end filter notifier' );
isa_ok($notifier, 'SVN::Notify');
ok $notifier->prepare, 'Prepare log_message filter checking';
ok $notifier->execute, 'Notify log_mesage filter checking';
$email = get_output();
like $email, qr/In the beginning[.]{3}/, 'Start text should be present';
like $email, qr/The end[.]/, 'End text should be present';

##############################################################################
# Start and End filters with SVN::Notify::HTML.
##############################################################################

ok( $notifier = SVN::Notify::HTML->new(
    %args,
    filter => [ 'StartEnd' ],
), 'Construct HTML start and end filter notifier' );
isa_ok($notifier, 'SVN::Notify');
ok $notifier->prepare, 'Prepare log_message filter checking';
ok $notifier->execute, 'Notify log_mesage filter checking';
$email = get_output();
like $email, qr/<div id="msg">\nIn the beginning[.]{3}/m,
    'Start text should be present';
like $email, qr{</html>\nThe end[.]}m, 'End text should be present';

##############################################################################
# StartHTML.
##############################################################################

ok( $notifier = SVN::Notify::HTML->new(
    %args,
    filter => [ 'StartHTML' ],
), 'Construct new headers filter notifier' );
isa_ok($notifier, 'SVN::Notify::HTML');
isa_ok($notifier, 'SVN::Notify');
ok $notifier->prepare, 'Prepare log_message filter checking';
ok $notifier->execute, 'Notify log_mesage filter checking';
$email = get_output();
like $email, qr{<meta name="keywords" value="foo" />},
    'New header should be present';

##############################################################################
# File Lists filter.
##############################################################################

ok( $notifier = SVN::Notify->new(
    %args,
    filter => [ 'StripTrunk' ],
), 'Construct new file lists filter notifier' );
isa_ok($notifier, 'SVN::Notify');
ok $notifier->prepare, 'Prepare log_message filter checking';
ok $notifier->execute, 'Notify log_mesage filter checking';
$email = get_output();
like $email, qr{^\s+Class-Meta/Changes}m, 'trunk/ should be stripped out';

##############################################################################
# Diff filters.
##############################################################################

ok( $notifier = SVN::Notify->new(
    %args,
    with_diff => 1,
    filter => [ 'StripTrunkDiff' ],
), 'Construct new diff filter notifier' );
isa_ok($notifier, 'SVN::Notify');
ok $notifier->prepare, 'Prepare log_message filter checking';
ok $notifier->execute, 'Notify log_mesage filter checking';
$email = get_output();
like $email, qr{^-{3}\s+Params-CallbackRequest/Changes}m, 'leading trunk should be stripped';
like $email, qr{^[+]{3}\s+Params-CallbackRequest/Changes}m, 'leading trunk should be stripped';

##############################################################################
# Non-stream Diff filter.
##############################################################################

SKIP: {
    eval 'require IO::ScalarArray';
    skip 'IO::ScalarArray did not load', 6 if $@;

    ok( $notifier = SVN::Notify->new(
        %args,
        with_diff => 1,
        filter => [ 'SimpleStripTrunkDiff' ],
    ), 'Construct new diff filter notifier' );
    isa_ok($notifier, 'SVN::Notify');
    ok $notifier->prepare, 'Prepare log_message filter checking';
    ok $notifier->execute, 'Notify log_mesage filter checking';
    $email = get_output();
    like $email, qr{^-{3}\s+Params-CallbackRequest/Changes}m, 'leading trunk should be stripped';
    like $email, qr{^[+]{3}\s+Params-CallbackRequest/Changes}m, 'leading trunk should be stripped';
}

##############################################################################
# The included Trac filter.
##############################################################################

SKIP: {
    eval 'require Text::Trac';
    skip 'Text::Trac did not load', 11 if $@;

    ok( $notifier = SVN::Notify->new(
        %args,
        filter => [ 'Trac' ],
    ), 'Construct Trac filter notifier' );
    isa_ok($notifier, 'SVN::Notify');
    ok $notifier->prepare, 'Prepare log_message filter checking';
    ok $notifier->execute, 'Notify log_mesage filter checking';
    $email = get_output();
    like $email, qr{<p>\s*Did this, that, and the other[.] And then I did some more[.] Some\nit was done on a second line[.] “Go figure”[.] <a class="changeset" href="/changeset/1234">r1234</a>\s*</p>}ms;

    # Try it with SVN::Notify::HTML.
    ok $notifier = SVN::Notify::HTML->new(
        %args,
        filter => [ 'Trac' ],
        trac_url => 'http://trac.example.com/'
    ), 'Construct Trac filtered log notifier';
    isa_ok($notifier, 'SVN::Notify::HTML');
    isa_ok $notifier, 'SVN::Notify';
    ok $notifier->prepare, 'Prepare HTML header and footer checking';
    ok $notifier->execute, 'Notify HTML header and footer checking';
    # Check the output.
    $email = get_output();
    like $email, qr{<p>\s*Did this, that, and the other[.] And then I did some more[.] Some\nit was done on a second line[.] “Go figure”[.] <a class="changeset" href="http://trac[.]example[.]com/changeset/1234">r1234</a>\s*</p>}ms;
}

##############################################################################
# Try the metadata filter on SVN::Notify::HTML.
##############################################################################
ok( $notifier = SVN::Notify::HTML->new(
    %args,
    filter => [ 'CapMeta' ],
), 'Construct new metadata filter notifier' );
isa_ok($notifier, 'SVN::Notify::HTML');
isa_ok($notifier, 'SVN::Notify');
ok $notifier->prepare, 'Prepare log_message filter checking';
ok $notifier->execute, 'Notify log_mesage filter checking';
$email = get_output();
like $email, qr{Content-Type: text/html; charset=UTF-8}, 'Should be HTML';
like $email, qr/REVISION: 111/, 'Revision header should be uppercase';
like $email, qr/AUTHOR:   theory/, 'Author header should be uppercase';

##############################################################################
# Try the file Lists filter with SVN::Notify::HTML.
##############################################################################

ok( $notifier = SVN::Notify::HTML->new(
    %args,
    filter => [ 'StripTrunk' ],
), 'Construct new file lists filter notifier' );
isa_ok($notifier, 'SVN::Notify::HTML');
isa_ok($notifier, 'SVN::Notify');
ok $notifier->prepare, 'Prepare log_message filter checking';
ok $notifier->execute, 'Notify log_mesage filter checking';
$email = get_output();
like $email, qr{Content-Type: text/html; charset=UTF-8}, 'Should be HTML';
like $email, qr{^\s+Class-Meta/Changes}m, 'trunk/ should be stripped out';

##############################################################################
# Try the diff filter with SVN::Notify::HTML.
##############################################################################

ok( $notifier = SVN::Notify::HTML->new(
    %args,
    with_diff => 1,
    filter => [ 'StripTrunkDiff' ],
), 'Construct new diff filter notifier' );
isa_ok($notifier, 'SVN::Notify');
ok $notifier->prepare, 'Prepare log_message filter checking';
ok $notifier->execute, 'Notify log_mesage filter checking';
$email = get_output();
like $email, qr{^-{3}\s+Params-CallbackRequest/Changes}m, 'leading trunk should be stripped';
like $email, qr{^[+]{3}\s+Params-CallbackRequest/Changes}m, 'leading trunk should be stripped';

##############################################################################
# Try a CSS filter.
##############################################################################

ok( $notifier = SVN::Notify::HTML->new(
    %args,
    filter => [ 'CSS' ],
), 'Construct CSS filter notifier' );
isa_ok($notifier, 'SVN::Notify::HTML');
isa_ok($notifier, 'SVN::Notify');
ok $notifier->prepare, 'Prepare log_message filter checking';
ok $notifier->execute, 'Notify log_mesage filter checking';
$email = get_output();
like $email, qr/^#patch { width: 90%; }/m, 'Should have modified the CSS';

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

    package SVN::Notify::Filter::LowerVowel;
    $INC{'SVN/Notify/Filter/LowerVowel.pm'} = __FILE__;
    sub log_message {
        my ($notifier, $lines) = @_;
        tr/AEIOU/aeiou/ for @$lines;
        return $lines;
    }

    package SVN::Notify::Filter::CapMeta;
    $INC{'SVN/Notify/Filter/CapMeta.pm'} = __FILE__;
    sub metadata {
        my ($notifier, $lines) = @_;
        s/([^:]+:)/uc $1/eg for @$lines;
        return $lines;
    }

    package SVN::Notify::Filter::AddHeader;
    $INC{'SVN/Notify/Filter/AddHeader.pm'} = __FILE__;
    sub headers {
        my ($notifier, $headers) = @_;
        push @$headers, "X-Foo: Bar\n";
        return $headers;
    }

    package SVN::Notify::Filter::StripTrunk;
    $INC{'SVN/Notify/Filter/StripTrunk.pm'} = __FILE__;
    sub file_lists {
        my ($notifier, $lists) = @_;
        for my $list ( values %$lists ) {
            s{^trunk/}{} for @$list;
        }
        return $lists;
    }

    package SVN::Notify::Filter::StripTrunkDiff;
    $INC{'SVN/Notify/Filter/StripTrunkDiff.pm'} = __FILE__;
    use Symbol ();

    IO: {
        package My::IO::TrunkStripper;
        sub TIEHANDLE {
            my ($class, $fh) = @_;
            bless { fh => $fh }, $class;
        }

        sub CLOSE {
            close shift->{fh};
        }

        sub READLINE {
            my $fh = shift->{fh};
            my $line = <$fh> or return;
            $line =~ s{^((?:-{3}|[+]{3})\s+)trunk/}{$1};
            return $line;
        }
    }

    sub diff {
        my ($notifier, $fh) = @_;
        my $filter = Symbol::gensym;
        tie *{ $filter }, 'My::IO::TrunkStripper', $fh;
        return $filter;
    }

    package SVN::Notify::Filter::SimpleStripTrunkDiff;
    $INC{'SVN/Notify/Filter/SimpleStripTrunkDiff.pm'} = __FILE__;
    sub diff {
        my ($notifier, $fh) = @_;
        my @lines;
        while (<$fh>) {
            s{^((?:-{3}|[+]{3})\s+)trunk/}{$1};
            push @lines, $_;
        }
        return IO::ScalarArray->new(\@lines);
    }

    package SVN::Notify::Filter::CSS;
    $INC{'SVN/Notify/Filter/CSS.pm'} = __FILE__;
    sub css {
        my ($notifier, $lines) = @_;
        $lines->[-1] =~ s/100/90/;
        return $lines;
    }

    package SVN::Notify::Filter::StartEnd;
    $INC{'SVN/Notify/Filter/StartEnd.pm'} = __FILE__;
    sub start_body {
        my ($notifier, $lines) = @_;
        push @$lines, "In the beginning...\n";
        return $lines;
    }
    sub end_body {
        my ($notifier, $lines) = @_;
        push @$lines, "The end.\n";
        return $lines;
    }

    package SVN::Notify::Filter::StartHTML;
    $INC{'SVN/Notify/Filter/StartHTML.pm'} = __FILE__;
    sub start_html {
        my ($notifier, $lines) = @_;
        push @$lines, qq{<meta name="keywords" value="foo" />\n};
        return $lines;
    }
}
