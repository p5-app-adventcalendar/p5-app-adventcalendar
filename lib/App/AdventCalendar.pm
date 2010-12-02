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

my $router = Router::Simple->new();
$router->connect(
    '/pull',
    { controller => 'Calendar', action => 'pull' }
);
$router->connect(
    '/help.html',
    { controller => 'Calendar', action => 'help' }
);
$router->connect(
    '/{year:\d{4}}/',
    { controller => 'Calendar', action => 'track_list' }
);
$router->connect(
    '/{year:\d{4}}/{name:[a-zA-Z0-9_-]+?}/',
    { controller => 'Calendar', action => 'index' }
);
$router->connect(
    '/{year:\d{4}}/{name:[a-zA-Z0-9_-]+?}/rss',
    { controller => 'Calendar', action => 'feed' }
);
$router->connect(
    '/{year:\d{4}}/{name:[a-zA-Z0-9_-]+?}/{day:\d{1,2}}',
    { controller => 'Calendar', action => 'entry' }
);

my %xslate;

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

        if ( $p->{action} eq 'index' ) {
            my $t = Time::Piece->strptime( "$p->{year}/12/01", '%Y/%m/%d' );
            my @entries;
            while ( $t->mday <= 25 ) {
                push @entries,
                  {
                    date   => Time::Piece->new($t),
                    exists => ( -e $root->file( $t->ymd . '.txt' ) )
                      && ( localtime->year > $p->{year}
                        || $t->yday <= localtime->yday ) ? 1 : 0,
                  };
                $t += ONE_DAY;
            }
            $vars->{entries} = \@entries;
        }
        elsif ( $p->{action} eq 'feed' ) {
            my $t = Time::Piece->strptime( "$p->{year}/12/01", '%Y/%m/%d' );
            my @entries;
            while ( $t->mday <= 25 ) {
                my $file = $root->file( $t->ymd . '.txt' );
                if ( -e $file && ( localtime->year > $p->{year}
                        || $t->yday <= localtime->yday )) {
                    my $entry = parse_entry($file);
                    my $uri = URI->new;
                    $uri->path($p->{name} . '/' . $t->mday);
                    $entry->{link} = $uri->as_string;
                    push @entries, $entry;
                }
                $t += ONE_DAY;
            }
            $vars->{entries} = \@entries;
        }
        elsif ( $p->{action} eq 'entry' ) {
            my $t = Time::Piece->strptime(
                    "$p->{year}/12/@{[sprintf('%02d',$p->{day})]}", '%Y/%m/%d' );
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
        }
        elsif ( $p->{action} eq 'help' ) {
            my $file = dir( $conf->{assets_path} )->file( 'help.txt' );
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
        }
        elsif ( $p->{action} eq 'track_list' ) {
        }
        elsif ( $p->{action} eq 'pull' && $ENV{ADVENT_CALENDAR_PULL_COMMAND} ) {
            system($ENV{ADVENT_CALENDAR_PULL_COMMAND});
            return [200, [], ['OK']];
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
        my $content_type = 'text/html';
        my $tmpl = "$p->{action}.html";

        if ($p->{action} eq 'feed') {
           $content_type = 'application/xml';
           $tmpl = 'index.xml';
        }
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
