package DataAPIPublicCache;

use strict;
use warnings;
use utf8;

sub cache_directory {
    my ($app) = @_;
    File::Spec->catdir( $app->support_directory_path,
        'data-api-public-cache' );
}

sub write_cache {
    my ( $app, $data ) = @_;

    my $basename = cache_basename()
        or return;

    my $fmgr = MT::FileMgr->new('Local');
    my $enc = $app->charset || 'UTF-8';

    my $cachefile = File::Spec->catfile( cache_directory($app), $basename );
    my @mkdirs = ();
    for (
        my $dirname = File::Basename::dirname($cachefile);
        !$fmgr->exists($dirname);
        $dirname = File::Basename::dirname($dirname)
        )
    {
        unshift @mkdirs, $dirname;
    }
    $fmgr->mkpath($_) for @mkdirs;

    $fmgr->put_data( Encode::encode( $enc, $data ), $cachefile );
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

                my $dir  = cache_directory($app);
                my $fmgr = MT::FileMgr->new('Local');

                return 1 unless $fmgr->exists($dir);

                require File::Find;
                File::Find::find(
                    {   wanted => sub {
                            -d $_ ? rmdir $_ : $fmgr->delete($_);
                        },
                        bydepth  => 1,
                        no_chdir => 1,
                    },
                    $dir
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
