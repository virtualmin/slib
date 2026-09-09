#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

# Force the interactive exit trap, but replace terminal cleanup before exiting.
# This proves errors survive the trap without running cleanup's host operations.
local $ENV{PS1} = 'test> ';
local $ENV{TERM} = 'dumb';
for my $shell (qw(sh dash)) {
    my $status = system($shell, '-c', '. ./slib.sh >/dev/null 2>&1; cleanup () { exit "$1"; }; exit 7');
    is($status >> 8, 7, "$shell preserves an error through the exit trap");
}
done_testing();
