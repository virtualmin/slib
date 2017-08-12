#!/usr/bin/env perl
use strict;
use warnings;
use 5.010;

my $file = $ARGV[0];
my $testdir = 't';

open my $handle, '<', $file;
chomp(my @lines = <$handle>);
close $handle;

use Data::Dumper;
#print Dumper(@lines);

# Get a list of functions that ideally would be tested
my @funcs;
for( @lines ) {
	my $func = $1 if m/^([a-zA-Z0-9\_]+)\W*\(\)\W*{/;
	push @funcs, $func if $func;
}

#print Dumper(@funcs);

# Get a list of functions that have a test that calls them
my @tests = <./t/*>;
my @tested;
for my $test (@tests) {
	open my $handle, '<', $test;
	chomp(my @lines = <$handle>);
	close $handle;
	for ( @lines ) {
		my $func = $1 if m/run\.sh\W'([a-zA-Z0-9\_]+)\W.*/;
		push @tested, $func if $func;
	}
}

# Figure out what's missing
my @missing;
for my $f (@funcs) {
	push @missing, $f unless grep( /$f/, @tested );
}

my $coverage = sprintf '%.2f', $#tested / $#funcs * 100;
say "Test Coverage: $coverage%";
say "Untested functions:";
for my $f (@missing) {
	say $f;
}

