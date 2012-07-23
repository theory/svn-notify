#!perl -w

use strict;
use Test::More tests => 11;

BEGIN { use_ok 'SVN::Notify' };

my %testopts = (
    '--repos-path'     => 'foo',
    '--revision'       => '2',
    '--svnlook'        => 'svnlook',
    '--sendmail'       => 'sendmail',
    '--to'             => 'test@example.com',
    '--strip-cx-regex' => '^trunk',
    '--add-header'     => 'foo=bar',
    '--header'         => '«header»',
    '--footer'         => '«footer»',
);

my %params = (
    set_sender        => undef,
    smtp              => undef,
    smtp_user         => undef,
    smtp_pass         => undef,
    smtp_port         => undef,
    smtp_tls          => undef,
    smtp_authtype     => undef,
    to_regex_map      => undef,
    to_email_map      => undef,
    from              => undef,
    user_domain       => undef,
    encoding          => undef,
    svn_encoding      => undef,
    diff_encoding     => undef,
    language          => undef,
    with_diff         => undef,
    attach_diff       => undef,
    diff_switches     => undef,
    diff_content_type => undef,
    reply_to          => undef,
    subject_prefix    => undef,
    subject_cx        => undef,
    no_first_line     => undef,
    max_sub_length    => undef,
    max_diff_length   => undef,
    handler           => undef,
    filters           => undef,
    author_url        => undef,
    revision_url      => undef,
    ticket_map        => undef,
    ticket_url        => undef,
    ticket_regex      => undef,
    verbose           => undef,
    help              => undef,
    man               => undef,
    version           => undef,
);

while (my ($k, $v) = each %testopts) {
    $k =~ s/^--//;
    $k =~ s/-/_/g;
    $params{$k} = $v;
    Encode::_utf8_on( $params{$k} ) if SVN::Notify::PERL58();
}
$params{to} = [ $params{to} ];
delete $params{add_header};
$params{add_headers} = { foo => [qw(bar baz)] };

# Make sure that the default options work.
local @ARGV = (%testopts, '--add-header', 'foo=baz');
ok my $opts = SVN::Notify->get_options, "Get SVN::Notify options";

# Make sure that this is an array.
$params{strip_cx_regex} = ['^trunk'] if $Getopt::Long::VERSION >= 2.34;

is_deeply($opts, \%params, "Check results");

$params{ticket_url} = 'url';
$params{handler}  = 'HTML';
$params{linkize}  = undef;
$params{css_url}  = undef;
$params{wrap_log} = undef;

# Use the --handler option to load the HTML subclass and make sure that
# its options are properly parsed out of @ARGV.
@ARGV = (%testopts, '--bugzilla-url' => 'url', '--handler' => 'HTML', '--add-header', 'foo=baz');
ok $opts = SVN::Notify->get_options, "Get SVN::Notify + HTML options";
is_deeply($opts, \%params, "Check new results");

SKIP: {
    # Use the --filter option to load the Trac filter and make sure that its
    # options are properly parsed out of @ARGV.
    eval 'require Text::Trac';
    skip 'Text::Trac did not load', 4 if $@;
    local @ARGV = (%testopts, '--filter', 'Trac', '--trac-url', 'http://trac.example.com/');
    ok my $opts = SVN::Notify->get_options, "Get SVN::Notify options";
    is $opts->{trac_url}, 'http://trac.example.com/', 'trac_url should be set';
    ok my $notifier = SVN::Notify->new(%$opts), 'Construct SVN::Notify';
    is $notifier->trac_url, 'http://trac.example.com/', 'trac_url attribute should be set';
}

# Test --to-regex-map.
local @ARGV = (
    %testopts,
    '--to-regex-map', 'f@example.com=^this/',
    '--to-regex-map', 'b@example.com=^that/',
    '--to-regex-map', 'z@example.com=^that/',
);

ok $opts = SVN::Notify->get_options, "Get SVN::Notify + HTML options";
delete $params{$_} for qw(linkize css_url wrap_log);
$params{add_headers} = { foo => ['bar']};
$params{handler} = $params{ticket_url} = undef;
$params{to_regex_map} = {
    'f@example.com' => '^this/',
    'b@example.com' => '^that/',
    'z@example.com' => '^that/',
};

is_deeply $opts, \%params, 'Should have to_regex_map hash';

BEGIN {
    package HTML::Entities;
    $INC{'HTML/Entities.pm'} = __FILE__;
}
