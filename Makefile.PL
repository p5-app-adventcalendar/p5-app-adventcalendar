use inc::Module::Install;
name 'App-AdventCalendar';
all_from 'lib/App/AdventCalendar.pm';

requires 'Router::Simple';
requires 'Text::Xslate';
requires 'Text::Xatena';
requires 'Time::Piece';
requires 'Plack';

tests 't/*.t';
author_tests 'xt';

test_requires 'Test::More';
auto_set_repository;
auto_include;
WriteAll;
