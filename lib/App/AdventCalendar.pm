package App::AdventCalendar;
use strict;
use warnings;
use utf8;
our $VERSION = '0.01';

use Plack::Request;
use Router::Simple;
use Text::Xslate qw/mark_raw/;
use Path::Class;
use Time::Piece ();
use Time::Seconds qw(ONE_DAY);
use Text::Xatena;
use Text::Xatena::Inline;
use Cache::MemoryCache;

eval { require File::Spec::Memoized };

my %xslate;

my $router = Router::Simple->new;

$router->connect(
    '/pull',
    {
        tmpl => 'pull.html',
        act  => sub {
            my ( $root, $vars ) = @_;
            system( $ENV{ADVENT_CALENDAR_PULL_COMMAND} );
            die [ 200, [], ['OK'] ];
        },
    }
);
$router->connect(
    '/help.html',
    {
        tmpl => 'help.html',
        act  => sub {
            my ( $root, $vars ) = @_;
            my $file = dir( $vars->{conf}->{assets_path} )->file('help.txt');
            if ( -e $file ) {
                my $entry = parse_entry($file);
                $vars->{title}     = $entry->{title};
                $vars->{text}      = $entry->{text};
                $vars->{update_at} = $entry->{update_at};
            }
            else {
                die not_found();
            }
        },
    }
);
$router->connect(
    '/{year:\d{4}}/',
    {
        tmpl => 'track_list.html',
        act  => sub {
            my ( $root, $vars ) = @_;
        },
    }
);
$router->connect(
    '/{year:\d{4}}/{name:[a-zA-Z0-9_-]+?}/',
    {
        tmpl => 'index.html',
        act  => sub {
            my ( $root, $vars ) = @_;
            my $t = Time::Piece->strptime( "$vars->{year}/12/01", '%Y/%m/%d' );
            my $now = Time::Piece->localtime;
            my $cache =
              Cache::MemoryCache->new( { namespace => $vars->{name} } );
            my @entries;
            while ( $t->mday <= 25 ) {
                my $title;
                my $exists = ( -e $root->file( $t->ymd . '.txt' ) )
                  && ( $now->year > $vars->{year}
                    || $t->yday <= $now->yday ) ? 1 : 0;

                if ($exists) {
                    my ( $cached_mtime, $cached_title ) = split /\t/,
                      ( $cache->get( $t->mday ) || "0\t" );
                    my $mtime = $root->file( $t->ymd . '.txt' )->stat->mtime;
                    if ( not $cached_title or $mtime > $cached_mtime ) {
                        my $fh = $root->file( $t->ymd . '.txt' )->open;
                        $title = <$fh>;
                        chomp($title);
                        $cache->set( $t->mday => "$mtime\t$title", 'never' );
                    }
                    else {
                        $title = $cached_title;
                    }
                }

                push @entries,
                  {
                    date   => Time::Piece->new($t),
                    exists => $exists,
                    title => $title,
                  };
                $t += ONE_DAY;
            }
            $vars->{entries} = \@entries;
        },
    }
);
$router->connect(
    '/{year:\d{4}}/{name:[a-zA-Z0-9_-]+?}/rss',
    {
        content_type => 'application/xml',
        tmpl         => 'index.xml',
        act          => sub {
            my ( $root, $vars ) = @_;
            my $t = Time::Piece->strptime( "$vars->{year}/12/01", '%Y/%m/%d' );
            my $now = Time::Piece->localtime;
            my @entries;
            while ( $t->mday <= 25 ) {
                my $file = $root->file( $t->ymd . '.txt' );
                if (
                    -e $file
                    && ( $now->year > $vars->{year}
                        || $t->yday <= $now->yday )
                  )
                {
                    my $entry = parse_entry($file);
                    my $uri   = URI->new;
                    $uri->path(
                        $vars->{year} . '/' . $vars->{name} . '/' . $t->mday );
                    $entry->{link} = $uri->as_string;
                    my @tags = split /,\s*/, $entry->{tags} || '';
                    $entry->{categories} = \@tags;
                    push @entries, $entry;
                }
                $t += ONE_DAY;
            }
            $vars->{entries} = \@entries;
        },
    }
);
$router->connect(
    '/{year:\d{4}}/{name:[a-zA-Z0-9_-]+?}/calendar',
    {
        tmpl => 'calendar.html',
        act  => sub {
            my ( $root, $vars ) = @_;
            my $t = Time::Piece->strptime( "$vars->{year}/12/01", '%Y/%m/%d' );
            my $now = Time::Piece->localtime;
            my $cache =
              Cache::MemoryCache->new( { namespace => $vars->{name} } );
            my $startwday = ($t->wday - $t->mday % 7 + 1 + 7) % 7;
            my (@cols, @rows, $i);

            @cols = ();
            for ( 1..($startwday-1) ) {
                push @cols,
                  {
                    date   => undef,
                    exists => 0,
                    title => '',
                  };
            }
            while ( $t->mday <= 25 ) {
                my $title;
                my $exists = ( -e $root->file( $t->ymd . '.txt' ) )
                  && ( $now->year > $vars->{year}
                    || $t->yday <= $now->yday ) ? 1 : 0;

                if ($exists) {
                    my ( $cached_mtime, $cached_title ) = split /\t/,
                      ( $cache->get( $t->mday ) || "0\t" );
                    my $mtime = $root->file( $t->ymd . '.txt' )->stat->mtime;
                    if ( not $cached_title or $mtime > $cached_mtime ) {
                        my $fh = $root->file( $t->ymd . '.txt' )->open;
                        $title = <$fh>;
                        chomp($title);
                        $cache->set( $t->mday => "$mtime\t$title", 'never' );
                    }
                    else {
                        $title = $cached_title;
                    }
                }

                if ( $t->day_of_week == 0 ) {
                    my @tmp = @cols;
                    push @rows, { cols => \@tmp };
                    @cols = ();
                }
                push @cols,
                  {
                    date   => Time::Piece->new($t),
                    exists => $exists,
                    title => $title,
                  };
                $t += ONE_DAY;
            }
            my @tmp = @cols;
            push @rows, { cols => \@tmp };
            $vars->{calendar} = { rows => \@rows };
        },
    }
);
$router->connect(
    '/{year:\d{4}}/{name:[a-zA-Z0-9_-]+?}/{day:\d{1,2}}',
    {
        tmpl => 'entry.html',
        act  => sub {
            my ( $root, $vars ) = @_;
            my $t = Time::Piece->strptime(
                "$vars->{year}/12/@{[sprintf('%02d',$vars->{day})]}",
                '%Y/%m/%d' );
            my $file = $root->file( $t->ymd . '.txt' );

            if ( -e $file ) {
                my $entry = parse_entry($file);
                $vars->{title}     = $entry->{title};
                $vars->{text}      = $entry->{text};
                $vars->{update_at} = $entry->{update_at};
                $vars->{footnotes} = $entry->{footnotes};
            }
            else {
                die not_found();
            }
        },
    }
);

sub parse_entry {
    my $file = shift;

    my $text = $file->slurp( iomode => '<:utf8' );
    my ( $title, $body ) = split( "\n\n", $text, 2 );

    my ( $tmp, %meta ) = ( '', () );
    for ( split /\n/, $title ) {
        if ($tmp) {
            my ( $key, $value ) = m{^meta-(\w+):\s*(.+)$};
            if ($key) {
                $meta{$key} = $value;
            }
        } else {
            $tmp = $_;
        }
    }
    $title = $tmp;

    my $xatena = Text::Xatena->new( hatena_compatible => 1 );
    my $inline = Text::Xatena::Inline->new;
    $text = mark_raw( $xatena->format( $body, inline => $inline ) );
    my $ftime = Time::Piece->localtime( $file->stat->mtime );
    my @footnotes = $inline->can('footnotes') ? @{$inline->footnotes} : ();
    return {
        title     => $title,
        text      => $text,
        update_at => $ftime->strftime( '%c' ),
        pubdate   => $ftime->strftime( '%Y-%m-%dT%H:%M:%S' ),
        footnotes => \@footnotes,
        %meta,
    };
}

sub handler {
    my ( $env, $conf ) = @_;
    if ( my $p = $router->match($env) ) {
        my $root = dir( $conf->{assets_path}, $p->{year}, $p->{name} );
        return not_found() unless -d $root;

        my $req = Plack::Request->new($env);
        my $vars = { req => $req, %$p };
        $vars->{conf} = $conf;
        $vars->{tracks} =
          [ map { $_->dir_list(-1) }
              grep { $_->is_dir and !$p->{year} ? $_->stringify !~ /tmpl/ : 1 }
              dir( $conf->{assets_path}, $p->{year} )
              ->children( no_hidden => 1 ) ];

        eval { $p->{act}->( $root, $vars ) };
        if ($@) {
            if ( ref($@) eq 'ARRAY' ) {
                return $@;
            }
            else {
                die $@;
            }
        }

        my $tx = $xslate{$root} ||= do {
            my $base = $req->base;
            Text::Xslate->new(
                syntax => 'TTerse',
                path   => [
                    $root->subdir('tmpl'), dir( $conf->{assets_path}, 'tmpl' )
                ],
                cache_dir => '/tmp/app-adventcalendar',
                cache     => 1,
                function  => {
                    uri_for => sub {
                        my ( $path, $args ) = @_;
                        my $uri = $base->clone;
                        $path =~ s|^/||;
                        $uri->path( $conf->{base_path} . $uri->path . $path );
                        $uri->query_form(@$args) if $args;
                        $uri;
                    },
                    format_date => sub {
                        my ( $tp, $args ) = @_;
                        my $r = $tp->strftime('%Y-%m-%d(%a)');
                        if ($^O eq 'MSWin32') {
                            require Encode;
                            $r = Encode::decode('cp932', $r);
                        }
                        $r;
                    },
                },
            );
        };
        my $content_type = $p->{content_type} || 'text/html';
        my $body         = $tx->render($p->{tmpl}, $vars);
        utf8::encode($body);
        return [
            200,
            [
              'Content-Type'   => $content_type,
              'Content-Length' => length($body),
            ],
            [ $body ]
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
