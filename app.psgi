use strict;
use warnings;
use utf8;
use lib 'lib';

use App::AdventCalendar;

my $app = sub { App::AdventCalendar::handler(@_) };

$app;
