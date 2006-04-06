#!perl -w

# $Id$

use strict;
use Test::More tests => 5;

BEGIN {use_ok 'SVN::Notify' };

my %testopts = (
    '--repos-path'     => 'foo',
    '--revision'       => '2',
    '--svnlook'        => 'svnlook',
    '--sendmail'       => 'sendmail',
    '--to'             => 'test@example.com',
    '--strip-cx-regex' => '^trunk',
);

my %params = (
    smtp            => undef,
    to_regex_map    => undef,
    from            => undef,
    user_domain     => undef,
    charset         => undef,
    io_layer        => undef,
    language        => undef,
    with_diff       => undef,
    attach_diff     => undef,
    reply_to        => undef,
    subject_prefix  => undef,
    subject_cx      => undef,
    no_first_line   => undef,
    max_sub_length  => undef,
    max_diff_length => undef,
    handler         => undef,
    viewcvs_url     => undef,
    svnweb_url      => undef,
    rt_url          => undef,
    bugzilla_url    => undef,
    gnats_url       => undef,
    jira_url        => undef,
    ticket_url      => undef,
    ticket_regex    => undef,
    verbose         => undef,
    help            => undef,
    man             => undef,
    version         => undef,
    header          => undef,
    footer          => undef,
);

while (my ($k, $v) = each %testopts) {
    $k =~ s/^--//;
    $k =~ s/-/_/g;
    $params{$k} = $v;
}


# Make sure that the default options work.
local @ARGV = %testopts;
ok my $opts = SVN::Notify->get_options, "Get SVN::Notify options";

# Make sure that this is an array.
$params{strip_cx_regex} = ['^trunk'] if $Getopt::Long::VERSION >= 2.34;

is_deeply($opts, \%params, "Check results");

$params{bugzilla_url} = 'url';
$params{handler} = 'HTML';
$params{linkize} = undef;
$params{css_url} = undef;

# Use the --handler option to load the HTML subclass and make sure that
# its options are properly parsed out of @ARGV.
@ARGV = (%testopts, '--bugzilla-url' => 'url', '--handler' => 'HTML');
ok $opts = SVN::Notify->get_options, "Get SVN::Notify + HTML options";
is_deeply($opts, \%params, "Check new results");
