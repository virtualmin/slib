#!/usr/bin/env perl
use strict;
use warnings;
use 5.010;

use Test::Simple tests => 3;

my ($err, $res) = `sh t/run.sh 'is_fully_qualified localhost.localdomain'`;
ok( $err != 0 );

($err, $res) = `sh t/run.sh 'is_fully_qualified dootdoot.com'`;
ok( $err == 0 );

($err, $res) = `sh t/run.sh 'is_fully_qualified doot'`;
ok( $err != 0 );
