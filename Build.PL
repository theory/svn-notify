use Module::Build;
use File::Spec::Functions;

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

for (qw(testsvnlook testsendmail)) {
    my $f = catfile curdir, 't', 'bin', $_;
    chmod 0755, $f;
}
