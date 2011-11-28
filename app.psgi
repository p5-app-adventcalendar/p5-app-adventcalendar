use strict;
use warnings;
use utf8;
use lib 'lib';

use Plack::Builder;
use App::AdventCalendar;
use Time::HiRes;

my $conf = do 'config.pl' or
            die "please run 'cp config.pl.sample config.pl' and edit config.pl";

my $app = sub { App::AdventCalendar::handler($_[0], $conf) };

builder {
    enable 'Static', path => qr{^/(?:img|css|js)/}, root => "$conf->{assets_path}/htdocs/";
    enable 'ReverseProxy';
    enable 'Log::Minimal';
    enable sub {
        my $app = shift;
        sub {
            local $SIG{ALRM} = sub {
                die "TIMEOUT";
            };
            my $last = alarm(20);
            my $ret = $app->(@_);
            alarm $last;
            return $ret;
        };
    };

    $app;
};
