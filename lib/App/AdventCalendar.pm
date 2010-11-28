package App::AdventCalendar;
use strict;
use warnings;
our $VERSION = '0.01';

use Router::Simple;
use Text::Xslate;
use Path::Class;
use Time::Piece;
use Time::Seconds;

sub handler {
    my $env = shift;

    my $router = Router::Simple->new();
    $router->connect(
        '/{year:\d{4}}/{name:[a-zA-Z0-9_-]+?}/',
        { controller => 'Calendar', action => 'list' }
    );

    if ( my $p = $router->match($env) ) {
        my $root = dir( 'assets', $p->{year}, $p->{name} );
        return not_found() unless -d $root;

        my $t = Time::Piece->strptime( "$p->{year}/12/01", '%Y/%m/%d' );
        my @entries;
        while ( $t->year <= $p->{year} ) {
            push @entries, {
                date   => Time::Piece->new($t),
                exists => -e $root->file( $t->ymd . '.txt' ) ? 1 : 0,
            };
            $t += ONE_DAY;
        }

        my $tx = Text::Xslate->new(
            syntax    => 'TTerse',
            path      => [$root->subdir('tmpl')],
            cache_dir => '/tmp/app-adventecalendar',
            cache     => 1,
        );
        return [
            200,
            [ 'Content-Type' => 'text/html' ],
            [ $tx->render( 'index.html', { entries => \@entries, %$p } ) ]
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
