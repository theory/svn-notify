#!perl -w

use strict;
use Test::More tests => 135;
use File::Spec::Functions;
use constant TEST_HTML => eval 'require HTML::Entities';

use_ok('SVN::Notify');
SKIP: {
    skip 'HTML::Entities did not load', 2 unless TEST_HTML;
    use_ok('SVN::Notify::HTML');
    use_ok('SVN::Notify::HTML::ColorDiff');
}

my $ext = $^O eq 'MSWin32' ? '.bat' : '';

my $dir = catdir curdir, 't', 'scripts';
$dir = catdir curdir, 't', 'bin' unless -d $dir;

my %args = (
    svnlook    => catfile($dir, "testsvnlook$ext"),
    sendmail   => catfile($dir, "testsendmail$ext"),
    repos_path => 'tmp',
    revision   => '111',
    to         => ['test@example.com'],
    filters    => ['Uppercase'],
);

my $subj = "DId thIs, thAt, And thE «OthEr».";
my $qsubj;
if (SVN::Notify::PERL58()) {
    Encode::_utf8_on( $subj );
    $qsubj = quotemeta Encode::encode( 'MIME-Q', $subj );
} else {
    $qsubj = quotemeta $subj;
}

##############################################################################
# Basic Functionality.
##############################################################################

ok( my $notifier = SVN::Notify->new(%args), 'Construct new notifier' );
isa_ok($notifier, 'SVN::Notify');
ok $notifier->prepare, 'Prepare log_message filter checking';
ok $notifier->execute, 'Notify log_mesage filter checking';
my $email = get_output();
UTF8: {
    use utf8;
    like $email, qr/DID THIS, THAT, AND THE «OTHER»/,
        'The log message should be uppercase';
}

##############################################################################
# Multiple Filters.
##############################################################################

ok( $notifier = SVN::Notify->new(
    %args,
    filters => [ 'Uppercase', 'LowerVowel' ],
), 'Construct new multi filter notifier' );
isa_ok($notifier, 'SVN::Notify');
ok $notifier->prepare, 'Prepare log_message filter checking';
ok $notifier->execute, 'Notify log_mesage filter checking';
$email = get_output();
UTF8: {
    use utf8;
    like $email, qr/DiD THiS, THaT, aND THe «oTHeR»/,
        'The log message should be uppercase but vowels lowercase';
}

##############################################################################
# Recipients, From, and Subject filter.
##############################################################################

ok( $notifier = SVN::Notify->new(
    %args,
    filters => [ 'LowerVowel' ],
), 'Construct recipients filter notifier' );
isa_ok($notifier, 'SVN::Notify');
ok $notifier->prepare, 'Prepare recipients filter checking';
ok $notifier->execute, 'Notify recipients_mesage filter checking';
like $email, qr/^To: tEst[@]ExAmplE[.]cOm/m, 'The recipient should be modified';
like $email, qr/From: thEOry/m, 'The From header should be modified';
like $email, qr/Subject: \[111\] $qsubj/m, 'The Subject should be modified';

##############################################################################
# Metadata filter.
##############################################################################

ok( $notifier = SVN::Notify->new(
    %args,
    filters => [ 'CapMeta' ],
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
    filters => [ 'AddHeader' ],
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
    filters => [ 'StartEnd' ],
), 'Construct start and end filter notifier' );
isa_ok($notifier, 'SVN::Notify');
ok $notifier->prepare, 'Prepare log_message filter checking';
ok $notifier->execute, 'Notify log_mesage filter checking';
$email = get_output();
like $email, qr/In the beginning[.]{3}/, 'Start text should be present';
like $email, qr/The end[.]/, 'End text should be present';


##############################################################################
# HTML Testing.
##############################################################################

SKIP: {
    skip 'HTML::Entities did not load', 12 unless TEST_HTML;

    ##########################################################################
    # Start and End filters with SVN::Notify::HTML.
    ##########################################################################

    ok( $notifier = SVN::Notify::HTML->new(
        %args,
        filters => [ 'StartEnd' ],
    ), 'Construct HTML start and end filter notifier' );
    isa_ok($notifier, 'SVN::Notify');
    ok $notifier->prepare, 'Prepare log_message filter checking';
    ok $notifier->execute, 'Notify log_mesage filter checking';
    $email = get_output();
    like $email, qr/<div id="msg">\nIn the beginning[.]{3}/m,
        'Start text should be present';
    like $email, qr{</html>\nThe end[.]}m, 'End text should be present';

    ##########################################################################
    # StartHTML.
    ##########################################################################

    ok( $notifier = SVN::Notify::HTML->new(
        %args,
        filters => [ 'StartHTML' ],
    ), 'Construct new headers filter notifier' );
    isa_ok($notifier, 'SVN::Notify::HTML');
    isa_ok($notifier, 'SVN::Notify');
    ok $notifier->prepare, 'Prepare log_message filter checking';
    ok $notifier->execute, 'Notify log_mesage filter checking';
    $email = get_output();
    like $email, qr{<meta name="keywords" value="foo" />},
        'New header should be present';
}

##############################################################################
# File Lists filter.
##############################################################################

ok( $notifier = SVN::Notify->new(
    %args,
    filters => [ 'StripTrunk' ],
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
    filters => [ 'StripTrunkDiff' ],
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
        filters => [ 'SimpleStripTrunkDiff' ],
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
    skip 'HTML::Entities did not load', 12 unless TEST_HTML;
    eval 'require Text::Trac';
    skip 'Text::Trac did not load', 12 if $@;

    ok( $notifier = SVN::Notify->new(
        %args,
        filters => [ 'Trac' ],
    ), 'Construct Trac filter notifier' );
    isa_ok($notifier, 'SVN::Notify');
    ok $notifier->prepare, 'Prepare log_message filter checking';
    ok $notifier->execute, 'Notify log_mesage filter checking';
    $email = get_output();
    UTF8: {
        use utf8;
        like $email,
            qr{^Did this, that, and the «other»[.] And then I did some more[.] Some\nit was done on a second line[.] “Go figure”[.] r1234\n}ms,
            'The text output should not be HTML formatted';
    }

    # Try it with SVN::Notify::HTML.
    ok $notifier = SVN::Notify::HTML->new(
        %args,
        filters => [ 'Trac' ],
        trac_url => 'http://trac.example.com/'
    ), 'Construct Trac filtered log notifier';
    isa_ok($notifier, 'SVN::Notify::HTML');
    isa_ok $notifier, 'SVN::Notify';
    ok $notifier->prepare, 'Prepare HTML header and footer checking';
    ok $notifier->execute, 'Notify HTML header and footer checking';
    # Check the output.
    $email = get_output();
    UTF8: {
        use utf8;
        like $email,
            qr{<p>\s*Did this, that, and the «other»[.] And then I did some more[.] Some\nit was done on a second line[.] “Go figure”[.] <a class="changeset" href="http://trac[.]example[.]com/changeset/1234">r1234</a>\s*</p>}ms,
            'HTML output should have Track wiki conveted to HTML';
    }
    like $email, qr{^#logmsg blockquote[.]citation}ms,
        'CSS should be modified, too';
}

##############################################################################
# More HTML testing.
##############################################################################

SKIP: {
    skip 'HTML::Entities did not load', 43 unless TEST_HTML;

    ##########################################################################
    # Try the metadata filter on SVN::Notify::HTML.
    ##########################################################################
    ok( $notifier = SVN::Notify::HTML->new(
        %args,
        filters => [ 'CapMeta' ],
    ), 'Construct new metadata filter notifier' );
    isa_ok($notifier, 'SVN::Notify::HTML');
    isa_ok($notifier, 'SVN::Notify');
    ok $notifier->prepare, 'Prepare log_message filter checking';
    ok $notifier->execute, 'Notify log_mesage filter checking';
    $email = get_output();
    like $email, qr{Content-Type: text/html; charset=UTF-8}, 'Should be HTML';
    like $email, qr/REVISION: 111/, 'Revision header should be uppercase';
    like $email, qr/AUTHOR:   theory/, 'Author header should be uppercase';

    ##########################################################################
    # Try the file Lists filter with SVN::Notify::HTML.
    ##########################################################################

    ok( $notifier = SVN::Notify::HTML->new(
        %args,
        filters => [ 'StripTrunk' ],
    ), 'Construct new file lists filter notifier' );
    isa_ok($notifier, 'SVN::Notify::HTML');
    isa_ok($notifier, 'SVN::Notify');
    ok $notifier->prepare, 'Prepare log_message filter checking';
    ok $notifier->execute, 'Notify log_mesage filter checking';
    $email = get_output();
    like $email, qr{Content-Type: text/html; charset=UTF-8}, 'Should be HTML';
    like $email, qr{^\s+Class-Meta/Changes}m, 'trunk/ should be stripped out';

    ##########################################################################
    # Try the diff filter with SVN::Notify::HTML.
    ##########################################################################

    ok( $notifier = SVN::Notify::HTML->new(
        %args,
        with_diff => 1,
        filters => [ 'StripTrunkDiff' ],
    ), 'Construct new diff filter notifier' );
    isa_ok($notifier, 'SVN::Notify::HTML');
    isa_ok($notifier, 'SVN::Notify');
    ok $notifier->prepare, 'Prepare log_message filter checking';
    ok $notifier->execute, 'Notify log_mesage filter checking';
    $email = get_output();
    like $email, qr{^-{3}\s+Params-CallbackRequest/Changes}m, 'leading trunk should be stripped';
    like $email, qr{^[+]{3}\s+Params-CallbackRequest/Changes}m, 'leading trunk should be stripped';

    ##########################################################################
    # Try the diff filter with SVN::Notify::HTML::ColorDiff.
    ##########################################################################

    ok( $notifier = SVN::Notify::HTML::ColorDiff->new(
        %args,
        with_diff => 1,
        filters => [ 'StripTrunkDiff' ],
    ), 'Construct new diff filter notifier' );
    isa_ok($notifier, 'SVN::Notify::HTML::ColorDiff');
    isa_ok($notifier, 'SVN::Notify::HTML');
    isa_ok($notifier, 'SVN::Notify');
    ok $notifier->prepare, 'Prepare log_message filter checking';
    ok $notifier->execute, 'Notify log_mesage filter checking';
    $email = get_output();
    like $email, qr{^-{3}\s+Params-CallbackRequest/Changes}m, 'leading trunk should be stripped';
    like $email, qr{^[+]{3}\s+Params-CallbackRequest/Changes}m, 'leading trunk should be stripped';

    ##########################################################################
    # Try a CSS filter.
    ##########################################################################

    ok( $notifier = SVN::Notify::HTML->new(
        %args,
        filters => [ 'CSS' ],
    ), 'Construct CSS filter notifier' );
    isa_ok($notifier, 'SVN::Notify::HTML');
    isa_ok($notifier, 'SVN::Notify');
    ok $notifier->prepare, 'Prepare log_message filter checking';
    ok $notifier->execute, 'Notify log_mesage filter checking';
    $email = get_output();
    like $email, qr/^#patch { width: 90%; }/m, 'Should have modified the CSS';

    ##########################################################################
    # Try a CSS filter with ColofDiff.
    ##########################################################################

    ok( $notifier = SVN::Notify::HTML::ColorDiff->new(
        %args,
        filters => [ 'CSS' ],
    ), 'Construct CSS filter notifier' );
    isa_ok($notifier, 'SVN::Notify::HTML::ColorDiff');
    isa_ok($notifier, 'SVN::Notify::HTML');
    isa_ok($notifier, 'SVN::Notify');
    ok $notifier->prepare, 'Prepare log_message filter checking';
    ok $notifier->execute, 'Notify log_mesage filter checking';
    $email = get_output();
    like $email, qr/^#patch .lines, .info {color:#999;background:#fff;}/m,
        'Should have modified the CSS';
}

##############################################################################
# Try the special callback filters.
##############################################################################
ok( $notifier = SVN::Notify->new(
    %args,
    filters => [ 'Callback' ],
), 'Construct new callback notifier' );
isa_ok($notifier, 'SVN::Notify');
ok $notifier->prepare, 'Prepare callback filter checking';
ok $notifier->execute, 'Notify callback filter checking';

if (SVN::Notify::PERL58()) {
    # Newer Perls should read this as utf8.
    use utf8;
    is $notifier->subject,
        'prep [111] Did this, that, and the «other». postp pree poste',
        'The subject should have been modified';
} else {
    # Perl 5.6 has to read this as bytes.
    is $notifier->subject,
        'prep [111] Did this, that, and the «other». postp pree poste',
        'The subject should have been modified';
}

##############################################################################
# This is mainly just to generate the Trac demo message.
##############################################################################
SKIP: {
    skip 'HTML::Entities did not load', 9 unless TEST_HTML;
    eval 'require Text::Trac';
    skip 'Text::Trac did not load', 9 if $@;

    $ENV{FOO} = 1;
    ok( $notifier = SVN::Notify::HTML::ColorDiff->new(
        %args,
        to         => ['test@example.com'],
        revision   => '555',
        trac_url   => 'http://trac.edgewall.org/',
        with_diff  => 1,
        filters    => [ 'Trac' ],
    ), 'Construct Trac filter notifier' );
    isa_ok($notifier, 'SVN::Notify::HTML::ColorDiff');
    isa_ok($notifier, 'SVN::Notify::HTML');
    isa_ok($notifier, 'SVN::Notify');
    ok $notifier->filters_for( 'log_message' ),
        'There should be log_message filters';
    ok !$notifier->filters_for( 'recipients' ),
        'There should not be recipients filters';
    ok $notifier->prepare, 'Prepare Trac filter checking';
    ok $notifier->execute, 'Notify Trac filter checking';
    $email = get_output();
    unlike $email, qr/^To: tEst[@]ExAmplE[.]cOm/m,
        'The recipient should not be modified';
}

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
    sub recipients {
        my ($notifier, $recip) = @_;
        tr/aeiou/AEIOU/ for @$recip;
        return $recip;
    }
    sub from {
        my ($notifier, $from) = @_;
        $from =~ tr/aeiou/AEIOU/;
        return $from;
    }
    sub subject { from(@_) }

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
        my ($notifier, $lines) = @_;
        s{^(\s*)trunk/}{$1} for @$lines;
        return $lines;
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
            close shift->{fh} or die $! ? "Error closing diff pipe: $!"
                                        : "Exit status $? from diff pipe"; # "
        }

        sub READLINE {
            my $fh = shift->{fh};
            defined( my $line = <$fh> ) or return;
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
        $lines->[-1] =~ s/100/90/ || $lines->[-1] =~ s/888/999/;
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

    package SVN::Notify::Filter::Callback;
    $INC{'SVN/Notify/Filter/Callback.pm'} = __FILE__;
    sub pre_prepare {
        my $notifier = shift;
        $notifier->subject_prefix('prep ');
        $notifier->subject( 'prep ');
    }
    sub post_prepare {
        my $notifier = shift;
        $notifier->subject( $notifier->subject . ' postp');
    }
    sub pre_execute {
        my $notifier = shift;
        $notifier->subject( $notifier->subject . ' pree');
    }
    sub post_execute {
        my $notifier = shift;
        $notifier->subject( $notifier->subject . ' poste');
    }
}
