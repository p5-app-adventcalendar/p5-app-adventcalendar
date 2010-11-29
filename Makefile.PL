use inc::Module::Install;
name 'App-AdventCalendar';
all_from 'lib/App/AdventCalendar.pm';

requires 'Plack';
requires 'Path::Class';
requires 'Router::Simple';
requires 'Text::Xslate';
requires 'Text::Xatena';
requires 'Time::Piece';

recommends 'File::Spec::Memoized'; # for performance

tests 't/*.t';
author_tests 'xt';

test_requires 'Test::More';
auto_set_repository;
auto_include;
WriteAll;
