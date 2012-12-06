use inc::Module::Install;
name 'App-AdventCalendar';
all_from 'lib/App/AdventCalendar.pm';

requires 'Plack';
requires 'Path::Class';
requires 'Router::Simple';
requires 'Text::Xslate' => '0.3001';
requires 'Text::Xatena' => '0.08';
requires 'Time::Piece'  => '1.20';
requires 'Date::Format';
requires 'Cache::MemoryCache';
requires 'Text::Markdown';
requires 'Pod::Simple';
requires 'Plack::Middleware::ReverseProxy';
requires 'Log::Minimal';
requires 'Plack::Middleware::Log::Minimal';
requires 'Pod::Simple::XHTML';
requires 'Text::VisualWidth::PP';

requires 'File::Spec::Memoized'; # for performance

tests 't/*.t';
author_tests 'xt';

test_requires 'Test::More';
WriteAll;
