@rem = '--*-Perl-*--
@echo off
if "%OS%" == "Windows_NT" goto WinNT
perl -x -S "%0" %1 %2 %3 %4 %5 %6 %7 %8 %9
goto endofperl
:WinNT
perl -x -S %0 %*
if NOT "%COMSPEC%" == "%SystemRoot%\system32\cmd.exe" goto endofperl
if %errorlevel% == 9009 echo You do not have Perl in your PATH.
if errorlevel 1 goto script_failed_so_exit_with_non_zero_val 2>nul
goto endofperl
@rem ';
#!/usr/bin/perl -w
#line 15

use strict;
use FindBin;
use File::Spec::Functions;

my $file = catfile($FindBin::Bin, updir, 'data', "output.txt");

open F, ">$file" or die "Cannot open '$file': $!\n";
binmode F, ':raw';
binmode STDIN, ':raw';
while (<STDIN>) { print F }
close F;

__END__
:endofperl
