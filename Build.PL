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
    requires           => { Getopt::Long        => 0 },
    build_requires     => { Test::Simple        => '0.17' },
    recommends         => { Pod::Usage          => 0,
                            HTML::Entities      => 0,
                            Test::Pod           => 1.20,
                            Test::Pod::Coverage => 1.06,
                          },
);
$build->create_build_script;

# Set the shebang line in the test scripts and make sure that they're
# executable.
for my $script (qw(testsvnlook testsendmail)) {
    for my $suf ('', '.bat') {
        my $file = catfile curdir, 't', 'bin', $script . $suf;
        $build->fix_shebang_line($file);
        chmod 0755, $file;
    }
}
