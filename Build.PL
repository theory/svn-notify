use Module::Build;
use File::Spec::Functions;
use Config;

my $build = Module::Build->new(
    module_name        => 'SVN::Notify',
    license            => 'perl',
    dist_author        => 'David Wheeler <david@kineticode.com>',
    dist_abstract      => 'Subversion activity notification',
    create_makefile_pl => 'passthrough',
    add_to_cleanup     => ['t/data/output.txt'],
    script_files       => [ 'bin/svnnotify' ],
    requires           => { Getopt::Long   => 0 },
    recommends         => { POD::Usage     => 0,
                            HTML::Entities => 0,
                          },
    build_requires     => { Test::Simple => '0.17',
                            HTML::Entities => 0,
                          },
);
$build->create_build_script;

# Set the shebang line in the test scripts and make sure that they're
# executable.
# XXX Replace with $build->fix_shebang_line() once that method is fixed.
for my $script (qw(testsvnlook testsendmail)) {
    for my $suf ('', '.bat') {
        my $file = catfile curdir, 't', 'bin', $script . $suf;
        my $temp = $file . '.tmp';
        open FILE, "<$file" or die "Cannot open '$file': $!\n";
        open TEMP, ">$temp" or die "Cannot open '$temp': $!\n";
        while (<FILE>) {
            s/^#!.*/#!$Config{perlpath} -w/;
            print TEMP;
        }
        close FILE;
        close TEMP;
        rename $temp, $file or die "Cannot rename '$temp' to $file': $!\n";
        chmod 0755, $file;
    }

}
