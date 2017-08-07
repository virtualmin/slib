#!/usr/bin/env perl
use strict;
use warnings;
use 5.010;

use Test::Simple tests => 1;

ok( system('shellcheck slib.sh') == 0 );

