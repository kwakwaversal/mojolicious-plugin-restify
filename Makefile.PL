use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
  NAME         => 'Mojolicious::Plugin::Restify',
  VERSION_FROM => 'lib/Mojolicious/Plugin/Restify.pm',
  ABSTRACT     => 'Shortcuts for Mojolicious REST routes',
  AUTHOR       => 'Paul Williams <kwakwa@cpan.org>',
  LICENSE      => 'artistic_2',
  PREREQ_PM    => {'Mojolicious' => '5.00'},
  META_MERGE   => {
    requires  => {perl => '5.010001'},
    resources => {
      license    => 'http://www.opensource.org/licenses/artistic-license-2.0',
      bugtracker => 'https://github.com/kwakwaversal/mojolicious-plugin-restify/issues',
      repository => 'https://github.com/kwakwaversal/mojolicious-plugin-restify.git',
    },
    no_index => {directory => ['t']}
  },
  test         => {TESTS => 't/*.t'}
);
