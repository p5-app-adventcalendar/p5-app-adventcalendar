use Plack::Test;
use Test::More;
use HTTP::Request;
use App::AdventCalendar;

my $app = sub { App::AdventCalendar::handler(@_) };

test_psgi $app, sub {
    my $cb = shift;

    my $req = HTTP::Request->new(GET => 'http://localhost/2010/example/');
    my $res = $cb->($req);

    is $res->code, 200;

    $req = HTTP::Request->new(GET => 'http://localhost/200/example/');
    $res = $cb->($req);

    is $res->code, 404;

    $req = HTTP::Request->new(GET => 'http://localhost/2010/example:xx/');
    $res = $cb->($req);

    is $res->code, 404;
};

done_testing;
