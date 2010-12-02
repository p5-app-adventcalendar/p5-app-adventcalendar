package App::AdventCalendar;
use strict;
use warnings;
use utf8;
our $VERSION = '0.01';

use Plack::Request;
use Router::Simple;
use Text::Xslate qw/mark_raw/;
use Path::Class;
use Time::Piece;
use Time::Seconds;
use Text::Xatena;
use Text::Xatena::Inline::Aggressive;
use Cache::MemoryCache;
use Encode;
use POSIX 'strftime';

eval { require File::Spec::Memoized };

my %xslate;

my $router = Router::Simple->new;

$router->connect('/pull', {
    tmpl => 'pull.html',
    act  => sub {
        my ($root, $vars) = @_;
        system($ENV{ADVENT_CALENDAR_PULL_COMMAND});
        return [200, [], ['OK']];
    },
});
$router->connect('/help.html', {
    tmpl => 'help.html',
    act  => sub {
        my ($root, $vars) = @_;
        my $file = dir( $vars->{conf}->{assets_path} )->file( 'help.txt' );
        if ( -e $file ) {
            my $xatena = Text::Xatena->new( hatena_compatible => 1 );
            my $entry = parse_entry($file);
            $vars->{title}     = $entry->{title};
            $vars->{text}      = $entry->{text};
            $vars->{update_at} = $entry->{update_at};
        }
        else {
            return not_found();
        }
    },
});
$router->connect('/{year:\d{4}}/', {
    tmpl => 'track_list.html',
    act  => sub {
        my ($root, $vars) = @_;
    },
});
$router->connect('/{year:\d{4}}/{name:[a-zA-Z0-9_-]+?}/', {
    tmpl => 'index.html',
    act  => sub {
        my ($root, $vars) = @_;
        my $t = Time::Piece->strptime( "$vars->{year}/12/01", '%Y/%m/%d' );
        my $cache = Cache::MemoryCache->new( { namespace => $vars->{name} } );
        my @entries;
        while ( $t->mday <= 25 ) {
            my $title;
            my $exists = ( -e $root->file( $t->ymd . '.txt' ) )
                  && ( localtime->year > $vars->{year}
                    || $t->yday <= localtime->yday ) ? 1 : 0;

            if ( $exists ) {
                my ( $cached_mtime, $cached_title ) = split/\t/, ( $cache->get( $t->mday ) || "0\t" );
                my $mtime = $root->file( $t->ymd . '.txt' )->stat->[9];
                if ( not $cached_title or $mtime > $cached_mtime ) {
                    my $fh    = $root->file( $t->ymd . '.txt' )->open;
                    $title = <$fh>; chomp($title);
                    $cache->set( $t->mday => "$mtime\t$title", 'never' );
                }
                else {
                    $title = $cached_title;
                }
            }

            push @entries,
              {
                date   => Time::Piece->new($t),
                exists => $exists,,
                title  => $title,
              };
            $t += ONE_DAY;
        }
        $vars->{entries} = \@entries;
    },
});
$router->connect('/{year:\d{4}}/{name:[a-zA-Z0-9_-]+?}/rss', {
    content_type => 'application/xml',
    tmpl => 'feed.xml',
    act  => sub {
        my ($root, $vars) = @_;
        my $t = Time::Piece->strptime( "$vars->{year}/12/01", '%Y/%m/%d' );
        my @entries;
        while ( $t->mday <= 25 ) {
            my $file = $root->file( $t->ymd . '.txt' );
            if ( -e $file && ( localtime->year > $vars->{year}
                    || $t->yday <= localtime->yday )) {
                my $entry = parse_entry($file);
                my $uri = URI->new;
                $uri->path($vars->{year} . '/' . $vars->{name} . '/' . $t->mday);
                $entry->{link} = $uri->as_string;
                push @entries, $entry;
            }
            $t += ONE_DAY;
        }
        $vars->{entries} = \@entries;
    },
});
$router->connect('/{year:\d{4}}/{name:[a-zA-Z0-9_-]+?}/{day:\d{1,2}}', {
    tmpl => 'entry.html',
    act  => sub {
        my ($root, $vars) = @_;
        my $t = Time::Piece->strptime(
                "$vars->{year}/12/@{[sprintf('%02d',$vars->{day})]}", '%Y/%m/%d' );
        my $file = $root->file($t->ymd . '.txt');

        if ( -e $file ) {
            my $entry = parse_entry($file);
            $vars->{title}     = $entry->{title};
            $vars->{text}      = $entry->{text};
            $vars->{update_at} = $entry->{update_at};
        }
        else {
            return not_found();
        }
    },
});


sub parse_entry {
    my $file = shift;

    my $text = $file->slurp( iomode => '<:utf8' );
    my ( $title, $body ) = split( "\n\n", $text, 2 );
    my $xatena = Text::Xatena->new( hatena_compatible => 1 );
    $text = mark_raw(
        $xatena->format(
            $body,
            Text::Xatena::Inline::Aggressive->new(
                cache => Cache::MemoryCache->new
            )
        )
    );
    my @ftime = localtime((stat($file))[9]);
    return {
        title     => $title,
        text      => $text,
        update_at => strftime('%c', @ftime),
        pubdate   => strftime('%Y-%m-%dT%H:%M:%S', @ftime),
    }
}

sub handler {
    my ($env, $conf) = @_;
    if ( my $p = $router->match($env) ) {
        my $root = dir( $conf->{assets_path}, $p->{year}, $p->{name} );
        return not_found() unless -d $root;

        my $req  = Plack::Request->new($env);
        my $vars = { req => $req, %$p };
        $vars->{conf} = $conf;
        $vars->{tracks} = [ map { $_->dir_list(-1) } grep {
            $_->is_dir and !$p->{year} ? $_->stringify !~ /tmpl/ : 1
        } dir( $conf->{assets_path}, $p->{year} )->children( no_hidden => 1 ) ];
        
        eval { $p->{act}->($root, $vars) };
        if ($@) {
            if (ref($@) eq 'ARRAY') {
                return $@;
            } else {
                die $@;
            }
        }

        my $tx = $xslate{$root} ||= do {
            my $base = $req->base;
            Text::Xslate->new(
                syntax    => 'TTerse',
                path      => [$root->subdir('tmpl'), dir($conf->{assets_path},'tmpl')],
                cache_dir => '/tmp/app-adventcalendar',
                cache     => 1,
                function  => {
                    uri_for => sub {
                        my($path, $args) = @_;
                        my $uri = $base->clone;
                        $path =~ s|^/||;
                        $uri->path($conf->{base_path} . $uri->path . $path);
                        $uri->query_form(@$args) if $args;
                        $uri;
                    },
                },
            );
        };
        my $content_type = $p->{content_type} || 'text/html';
        my $tmpl         = $p->{tmpl};

        return [
            200,
            [ 'Content-Type' => $content_type ],
            [ encode_utf8($tx->render( $tmpl, $vars )) ]
        ];
    }
    else {
        return not_found();
    }
}

sub not_found {
    return [ 404, [ 'Content-Type' => 'text/html' ], ['Not Found'] ];
}

1;
__END__

=head1 NAME

App::AdventCalendar -

=head1 SYNOPSIS

  use App::AdventCalendar;

=head1 DESCRIPTION

App::AdventCalendar is

=head1 AUTHOR

Kan Fushihara E<lt>kan@mfac.jpE<gt>

=head1 SEE ALSO

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
