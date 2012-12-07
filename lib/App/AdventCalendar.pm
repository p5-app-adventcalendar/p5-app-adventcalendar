package App::AdventCalendar;
use 5.010_000;
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
use Date::Format;
use Text::Xatena;
use Text::Xatena::Inline;
use Cache::MemoryCache;
use Text::Markdown ();
use Encode qw(encode_utf8 decode_utf8 find_encoding);
use Log::Minimal;
use Pod::Simple::XHTML;
use Text::VisualWidth::PP;

eval { require File::Spec::Memoized };

my $strftime_encoding = find_encoding($^O eq 'MSWin32' ? 'cp932' : 'utf8')
    or die 'Oops!';

my %xslate;

my $router = Router::Simple->new;

$router->connect(
    '/',
    {
        tmpl => 'top.html',
        act  => sub {
            my ( $root, $vars ) = @_;
            my $file = dir( $vars->{conf}->{assets_path} )->file('top.txt');
            if ( -e $file ) {
                my $entry = parse_entry($file);
                $vars->{title}     = $entry->{title};
                $vars->{text}      = $entry->{text};
                $vars->{update_at} = $entry->{update_at};
            }
            else {
                die not_found();
            }
            $vars->{year} = '';
            $vars->{name} = '';
        },
    }
);
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
              Cache::MemoryCache->new( { namespace => "$vars->{year}/$vars->{name}" } );
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
                        $title //= '';
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
                    title  => $title,
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
                    && (   $now->year > $vars->{year}
                        || $t->yday <= $now->yday )
                  )
                {
                    my $entry = parse_entry($file);
                    if ($entry->{title}) {
                        my $uri   = URI->new;
                        $uri->path(
                            $vars->{year} . '/' . $vars->{name} . '/' . $t->mday );
                        $entry->{link} = $uri->as_string;
                        my @tags = split /,\s*/, $entry->{tags} || '';
                        $entry->{categories} = \@tags;
                        push @entries, $entry;
                    }
                }
                $t += ONE_DAY;
            }
            @entries = reverse @entries;
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
              Cache::MemoryCache->new( { namespace => "$vars->{year}/$vars->{name}" } );
            my ( @cols, @rows, $i );

            @cols = ();
            push @cols,
              {
                date   => undef,
                exists => 0,
                title  => '',
              }
              for 1 .. $t->day_of_week;

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
                    title  => trim_text(decode_utf8($title), 50),
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
                debugf("rendering $file");
                my $entry = parse_entry($file);
                $vars->{title}     = $entry->{title};
                $vars->{text}      = $entry->{text};
                $vars->{update_at} = $entry->{update_at};
                $vars->{footnotes} = $entry->{footnotes};
                $vars->{author}    = $entry->{author} || '';
            }
            else {
                debugf("file '$file' is not found.");
                die not_found();
            }
        },
    }
);

sub format_text {
    my($text, $meta) = @_;

    given (lc($meta->{format} || '')) {
        when ('markdown') {
            return (Text::Markdown::markdown($text));
        }
        when ('html') {
            return $text;
        }
        when ('pod') {
            my $parser = Pod::Simple::XHTML->new();
            $parser->output_string(\my $out);
            $parser->html_header('');
            $parser->html_footer('');
            $parser->parse_string_document("=pod\n\n$text");
            return ($out);
        }
        default {
            state $xatena = Text::Xatena->new( hatena_compatible => 1 );
            my $inline    = Text::Xatena::Inline->new;

            return( $xatena->format( $text, inline => $inline ),
                    @{ $inline->footnotes } );
        }
    }
}

sub trim_text {
    my ($text, $width) = @_;
    my $trim = Text::VisualWidth::PP::trim($text, $width);
    return $text eq $trim ? $text : "$trim ...";
}

sub parse_entry {
    my $file = shift;

    my $raw_text = $file->slurp( iomode => '<:utf8' );
    my ( $title, $body ) = split( "\n\n", $raw_text, 2 );

    my ( $tmp, %meta ) = ( '', () );
    for ( split /\n/, $title ) {
        if ($tmp) {
            my ( $key, $value ) = m{^meta-(\w+):\s*(.+)\s*$};
            if ($key) {
                $meta{$key} = $value;
            }
        }
        else {
            $tmp = $_;
        }
    }
    $title = $tmp;

    my($text, @footnotes) = format_text($body, \%meta);
    foreach my $note(@footnotes) {
        $note->{note} = mark_raw($note->{note});
    }
    return {
        title     => $title,
        text      => mark_raw($text),
        update_at => time2str('%c', $file->stat->mtime),
        pubdate   => time2str('%a, %d %b %Y %H:%M:%S %z', $file->stat->mtime),
        footnotes => \@footnotes,
        %meta,
    };
}

sub handler {
    my ( $env, $global_conf ) = @_;
    if ( my $p = $router->match($env) ) {
        my $conf = $global_conf->{global};
        my $root = dir( $conf->{assets_path} );
 
        if ($p->{year}) {
            unless ($global_conf->{years}{$p->{year}}) {
                return not_found();
            }
            $conf = +{ %{ $conf }, %{ $global_conf->{years}{$p->{year}} } };
            $root = dir( $conf->{assets_path}, $p->{year}, $p->{name} );
        }
        return not_found() unless -d $root;

        my $req = Plack::Request->new($env);
        my $vars = { req => $req, %$p };
        $vars->{conf}   = $conf;
        $vars->{tracks} = [
            sort(map { $_->dir_list(-1) }
              grep { $_->is_dir and !$p->{year} ? $_->stringify !~ /(tmpl|htdocs)/ : 1 }
              dir( $conf->{assets_path}, $p->{year} )
              ->children( no_hidden => 1 ))
        ];

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
                        return $strftime_encoding->decode(
                            $tp->strftime('%Y-%m-%d(%a)')
                        );
                    },
                    html_escape_hex => sub {
                        my ( $str, $args ) = @_;
                        $str //= '';
                        $str =~ s{([^A-Za-z0-9\-_.!~*'()@ ])}
                                 { sprintf('&#x%X;', ord($1)) }ge;
                        return mark_raw($str);
                    },
                    ucfirst => sub {
                        my $str = shift;
                        ucfirst $str;
                    },
                },
            );
        };
        my $content_type = $p->{content_type} || 'text/html';
        my $body         = encode_utf8( $tx->render( $p->{tmpl}, $vars ) );
        return [
            200,
            [
                'Content-Type'   => $content_type,
                'Content-Length' => length($body),
            ],
            [$body]
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
