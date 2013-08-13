use Module::Build;
use Config;
use strict;

my $class = Module::Build->subclass(
    class => 'My::Builder',
    code => q{
             sub ACTION_code {
                 my $self = shift;
                 $self->SUPER::ACTION_code(@_);
                 # Copy the test scripts and then set the shebang line and make
                 # sure that they're executable.
                 my @scripts;
                 my $to_dir = $self->localize_file_path("t/scripts");
                 for my $base (qw(testsvnlook testsendmail)) {
                     my $script = "$to_dir/$base";
                     push @scripts, $self->localize_file_path($script);
                     my $orig = $self->localize_file_path("t/bin/$base");
                     $self->copy_if_modified(
                         from    => $orig,
                         to_dir  => $to_dir,
                         flatten => 1,
                     );
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
    add_to_cleanup     => [qw(t/data/output.txt t/scripts)],
    script_files       => ['bin/svnnotify'],
    configure_requires => { 'Module::Build' => '0.2701' },
    requires           => {
        'Getopt::Long' => '2.34',
        'perl'         => 5.006,
    },
    build_requires     => {
        'Test::More'    => '0.17',
        'Module::Build' => '0.2701',
        'File::Spec'    => 0,
    },
    recommends => {
        'Pod::Usage'          => '1.33',
        'HTML::Entities'      => 0,
        'Net::SMTP::TLS'      => 0,
        'Test::Pod'           => 1.41,
        'Test::Pod::Coverage' => 1.06,
        'File::Spec'          => 0,
        'Text::Trac'          => '0.10',
    },
    meta_merge => {
        resources => {
            homepage   => 'http://search.cpan.org/dist/SVN-Notify/',
            bugtracker => 'http://github.com/theory/svn-notify/issues/',
            repository => 'http://github.com/theory/svn-notify/',
        }
    },
);
$build->create_build_script;

