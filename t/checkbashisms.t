#!/usr/bin/env perl
use strict;
use warnings;
use 5.010;

use Test::Simple tests => 1;

ok( system('checkbashisms slib.sh') == 0 );

