use Module::Build;
use Config;

my $class = Module::Build->subclass(
    class => 'My::Builder',
    code => q{
             sub ACTION_build {
                 use File::Spec::Functions;
                 my $self = shift;
                 $self->SUPER::ACTION_build(@_);
                 # Copy the test scripts and then set the shebang line and make
                 # sure that they're executable.
                 my @scripts;
                 my $to_dir = $self->localize_file_path("t/scripts");
                 for my $base (qw(testsvnlook testsendmail)) {
                     for my $suf ('', '.bat') {
                         my $script = "$to_dir/$base$suf";
                         push @scripts, $self->localize_file_path($script);
                         my $orig = $self->localize_file_path("t/bin/$base$suf");
                         $self->copy_if_modified(
                             from    => $orig,
                             to_dir  => $to_dir,
                             flatten => 1,
                         );
                     }
                 }
                 $self->fix_shebang_line(@scripts);
                 $self->make_executable(@scripts);
                 $self->add_to_cleanup($to_dir);
             }
         },
);

my $build = $class->new(
    module_name        => 'SVN::Notify',
    license            => 'perl',
    create_makefile_pl => 'passthrough',
    add_to_cleanup     => ['t/data/output.txt'],
    script_files       => [ 'bin/svnnotify' ],
    requires           => { Getopt::Long        => '2.34' },
    build_requires     => { Test::Simple        => '0.17',
                            Module::Build       => '0.26',
                          },
    recommends         => { Pod::Usage          => 0,
                            HTML::Entities      => 0,
                            Test::Pod           => 1.20,
                            Test::Pod::Coverage => 1.06,
                          },
);
$build->create_build_script;

