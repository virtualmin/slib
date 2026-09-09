#!/usr/bin/env perl
use strict;
use warnings;
use 5.010;

use Test::Simple tests => 14;

my $G = 1048576;

sub wanted {
    my ( $cmd, $env ) = @_;
    $env //= '';
    my ( $err, $res ) = `$env sh t/run.sh '$cmd'`;
    $res //= '';
    chomp($res);
    return $res;
}

# Automatic sizing: fill the gap to the 8 GiB target, with a
# 2x RAM ceiling, and disk ladder caps of 6/3/2/1 GB at 40/20/10/5 GB usable

# 1 GB RAM, huge disk: the 7 GB gap is capped at 2x RAM
ok( wanted( "swap_size_wanted @{[1*$G]} @{[1*$G]} @{[55*$G]}" ) == 2 * $G );

# 4 GB RAM, huge disk: plain gap to the target
ok( wanted( "swap_size_wanted @{[4*$G]} @{[4*$G]} @{[55*$G]}" ) == 4 * $G );

# 7 GiB RAM, huge disk: only fill the remaining 1 GiB gap
ok( wanted( "swap_size_wanted @{[7*$G]} @{[7*$G]} @{[55*$G]}" ) == 1 * $G );

# 512 MB RAM: 2x RAM ceiling, rounded up to a whole GB
ok( wanted( "swap_size_wanted 524288 524288 @{[55*$G]}" ) == 1 * $G );

# 2 GB RAM with 11 GB usable: disk ladder caps at 2 GB
ok( wanted( "swap_size_wanted @{[2*$G]} @{[2*$G]} @{[11*$G]}" ) == 2 * $G );

# 2 GB RAM with 25 GB usable: disk ladder caps at 3 GB
ok( wanted( "swap_size_wanted @{[2*$G]} @{[2*$G]} @{[25*$G]}" ) == 3 * $G );

# Under 5 GB usable: no swap can be afforded
ok( wanted( "swap_size_wanted @{[1*$G]} @{[1*$G]} @{[4*$G]}" ) == 0 );

# Existing swap counts toward the total: 2 GB RAM + 1 GB swap tops up
ok( wanted( "swap_size_wanted @{[3*$G]} @{[2*$G]} @{[55*$G]}" ) == 4 * $G );

# An explicit size is honored exactly when it fits
ok( wanted( "swap_size_wanted @{[2*$G]} @{[2*$G]} @{[55*$G]}", "swapsize=524288" ) ==
      524288 );

# An explicit size that does not fit yields 0
ok( wanted( "swap_size_wanted @{[2*$G]} @{[2*$G]} @{[11*$G]}", "swapsize=@{[50*$G]}" ) ==
      0 );

# The library API uses validated, whole-MiB values
ok( wanted( "swap_size_wanted @{[2*$G]} @{[2*$G]} @{[55*$G]}", "swapsize=2048" ) ==
      2048 );

# Human readable sizes report GB for whole GB and MB otherwise
ok( wanted("kb_size_h 3145728") eq '3 GiB' );
ok( wanted("kb_size_h 524288") eq '512 MiB' );

# No addition when the combined target is already met.
ok( wanted( "swap_size_wanted @{[8*$G]} @{[4*$G]} @{[55*$G]}" ) == 0 );
