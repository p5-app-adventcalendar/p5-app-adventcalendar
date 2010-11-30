#!perl -d:NYTProf
use 5.12.0;
use lib 'lib';
use App::AdventCalendar;

my $request_uri = shift(@ARGV) || '/2010/sample/';
my $env = {
    REQUEST_URI     => $request_uri,
    PATH_INFO       => $request_uri,
    REQUEST_METHOD  => 'GET',
    QUERY_STRING    => '',
    SERVER_PROTOCOL => 'HTTP/1.1',
};

for(1 ... 100) {
    my $res = App::AdventCalendar::handler($env);
    $res->[0] == 200 or die @{$res->[3]};
}
