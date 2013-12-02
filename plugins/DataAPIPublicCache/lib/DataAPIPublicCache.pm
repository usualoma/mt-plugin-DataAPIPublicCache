package DataAPIPublicCache;

use strict;
use warnings;
use utf8;

sub cache_directory {
    my ($app) = @_;
    File::Spec->catdir( $app->support_directory_path,
        'data-api-public-cache' );
}

sub _put_data {
    my ( $app, $fmgr, $data, $file ) = @_;

    my $enc     = $app->charset || 'UTF-8';
    my $dir     = File::Basename::dirname($file);
    my $cur_dir = $dir;

    my @dirs = ();
    for (
        my $parent_dir = File::Basename::dirname($cur_dir);
        $cur_dir && $cur_dir ne $parent_dir;
        $cur_dir    = $parent_dir,
        $parent_dir = File::Basename::dirname($cur_dir)
        )
    {
        if ( my $base = File::Basename::basename($cur_dir) ) {
            unshift @dirs, $base;
        }
    }

    require Cwd;
    my $status = 1;
    my $cwd    = Cwd::getcwd();
    if ( $dir =~ m{^/} ) {
        chdir '/';
    }
    for (@dirs) {
        if ( !$fmgr->exists($_) ) {
            if ( !$fmgr->mkpath($_) ) {
                $status = 0;
                last;
            }
        }
        chdir $_;
    }

    if (!$fmgr->put_data(
            Encode::encode( $enc, $data ),
            File::Basename::basename($file)
        )
        )
    {
        $status = 0;
    }
    chdir $cwd;

    $status;
}

sub write_cache {
    my ( $app, $data ) = @_;

    my $basename = cache_basename()
        or return;

    my $cachefile = File::Spec->catfile( cache_directory($app), $basename );

    my $fmgr = MT::FileMgr->new('Local');
    if ( !_put_data( $app, $fmgr, $data, $cachefile ) ) {
        $app->log( $fmgr->errstr );
        return;
    }

    return 1;
}

sub cache_basename {
    $ENV{HTTP_X_DATA_API_PUBLIC_CACHE_FILENAME};
}

sub init_cache_writer {
    my ($app) = @_;

    no warnings 'redefine';

    require MT::App;
    my $print_encode = \&MT::App::print_encode;
    *MT::App::print_encode = sub {
        my ( $app, $data ) = @_;
        if ( cache_basename()
            && ( $app->response_code || 200 ) == 200 )
        {
            write_cache( $app, $data );
        }
        $print_encode->(@_);
    };

}

sub init_callbacks {
    my ($app) = @_;

    for my $cb (qw(post_save post_remove)) {
        $app->add_callback(
            $cb, 9, $app,
            sub {
                my ( $eh, $obj ) = @_;

                my $obj_type = ref $obj;
                return 1
                    unless grep { $_ eq $obj_type } split ',',
                    $app->config->DataAPIPublicCacheHookObjects;

                my $fmgr = MT::FileMgr->new('Local');
                require File::Find;
                File::Find::find(
                    {   wanted => sub {
                            -d $_ ? rmdir $_ : $fmgr->delete($_);
                        },
                        bydepth  => 1,
                        no_chdir => 1,
                    },
                    cache_directory($app)
                );

                return 1;
            }
        );
    }
}

sub init_app {
    my ( $plugin, $app ) = @_;
    init_cache_writer($app);
    init_callbacks($app);
}

1;
