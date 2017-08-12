#!/usr/bin/env perl
use strict;
use warnings;
use 5.010;

use Test::Simple tests => 3;

my @res = `sh t/run.sh 'is_fully_qualified localhost.localdomain'`;
ok( $res[0] != 0 );

@res = `sh t/run.sh 'is_fully_qualified dootdoot.com'`;
ok( $res[0] == 0 );

@res = `sh t/run.sh 'is_fully_qualified doot'`;
ok( $res[0] != 0 );
