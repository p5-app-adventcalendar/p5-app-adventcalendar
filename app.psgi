use strict;
use warnings;
use utf8;
use lib 'lib';

use Plack::Builder;
use App::AdventCalendar;

my $app = sub { App::AdventCalendar::handler(@_) };

builder {
    enable 'Static', path => qr{^/(img|css|js)/}, root => 'assets/htdocs/';
    enable 'ContentLength';
    enable 'Lint';
    $app;
};
