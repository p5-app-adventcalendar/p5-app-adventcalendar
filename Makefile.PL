use inc::Module::Install;
name 'App-AdventCalendar';
all_from 'lib/App/AdventCalendar.pm';

requires 'Plack';
requires 'Path::Class';
requires 'Router::Simple';
requires 'Text::Xslate' => '0.05';
requires 'Text::Xatena';
requires 'Time::Piece';
requires 'Date::Format';
requires 'Plack';

recommends 'File::Spec::Memoized'; # for performance

tests 't/*.t';
author_tests 'xt';

test_requires 'Test::More';
WriteAll;
