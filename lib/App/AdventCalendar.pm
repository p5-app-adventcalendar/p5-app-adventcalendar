package App::AdventCalendar;
use strict;
use warnings;
our $VERSION = '0.01';

use Plack::Request;
use Text::Xslate;
use Path::Class;

sub handler {
    my $env = shift;

    my $req = Plack::Request->new($env);
    if ( $req->path_info =~ qr{^/(\d{4})/([a-zA-Z0-9_-]+?)/$} ) {
        my $year = $1;
        my $name = $2;
        my $root = dir( 'assets', $year, $name, 'tmpl' );
        return not_found() unless -d $root;

        my $tx = Text::Xslate->new(
            syntax    => 'TTerse',
            path      => [ $root ],
            cache_dir => '/tmp/app-adventecalendar',
            cache     => 1,
        );
        return [
            200,
            [ 'Content-Type' => 'text/html' ],
            [ $tx->render( 'index.html', { year => $year, name => $name } ) ]
        ];
    }

    return not_found();
}

sub not_found {
    return [ 404, [ 'Content-Type' => 'text/html' ], [ 'Not Found' ] ];
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
