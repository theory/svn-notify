#!/usr/bin/perl -w

# $Id $

use strict;
use File::Spec::Functions;

print "1..1\n";
# Silence "Syntax OK".
close STDERR;
my $ret = system $^X, '-cw', '-I' . catdir(curdir, qw(blib lib)),
  '-I' . catdir(curdir, qw(lib)), catfile(curdir, 'bin', 'svnnotify');
print +($ret ? 'not ' : ''), "ok 1\n"
