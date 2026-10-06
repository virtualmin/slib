#!/usr/bin/env perl
use strict;
use warnings;
use 5.010;
use File::Temp qw(tempdir);
use Test::More;

# All hosts-file edits go to a private fixture instead of /etc/hosts.
open my $src, '<', 'slib.sh' or die $!;
my $source = do { local $/; <$src> };
$source =~ /^(set_hosts_entry \(\) \{.*?^\})/ms or die 'Missing set_hosts_entry';
my $function = $1;
$source =~ /^(set_hostname \(\) \{.*?^\})/ms or die 'Missing set_hostname';
my $hostname_function = $1;

# write_file(path, text) writes a private fixture.
sub write_file {
    my ($path, $text) = @_;
    open my $fh, '>', $path or die "$path: $!";
    print {$fh} $text;
    close $fh;
}
# read_file(path) returns fixture contents, or empty text if missing.
sub read_file {
    my ($path) = @_;
    open my $fh, '<', $path or return '';
    local $/;
    return <$fh> // '';
}
# run_case(hosts, name, [address], [shell], [status]) uses a private hosts file.
# An undefined hosts value leaves the input file missing. Status defaults to 0.
sub run_case {
    my ($hosts, $name, $address, $shell, $expected_status) = @_;
    $address //= '192.0.2.5';
    $shell //= 'sh';
    $expected_status //= 0;
    my $dir = tempdir(CLEANUP => 1);
    (my $lib = $function) =~ s{/etc/hosts}{$dir/hosts}g;
    write_file("$dir/hosts", $hosts) if defined $hosts;
    write_file("$dir/lib.sh",
        "detect_ip () { address=$address; }\nlog_debug () { :; }\n"
        . "log_warning () { :; }\n$lib\n");
    my $status = system($shell, '-c', '. "$1/lib.sh" && set_hosts_entry "$2"',
        $shell, $dir, $name);
    $status == ($expected_status << 8)
        or die "set_hosts_entry $name returned unexpected status $status";
    return read_file("$dir/hosts");
}

my @shells = qw(sh bash);
push @shells, 'dash' if grep { -x "$_/dash" } split /:/, $ENV{PATH};
for my $shell (@shells) {
    my $base = "127.0.0.1 localhost\n";
    my @cases = (
        [$base, 'host.example.com', undef,
         "${base}192.0.2.5\thost.example.com\thost\n",
         'adds a fully qualified hostname with its short name'],
        [$base, 'host', undef,
         "${base}192.0.2.5\thost\n",
         'adds a short hostname once'],
        ["${base}192.0.2.5 old.example.com old\n", 'host.example.com', undef,
         "${base}192.0.2.5 host.example.com host old.example.com old\n",
         'sets a fully qualified hostname and keeps existing names'],
        ["${base}192.0.2.5 old.example.com old\n", 'host', undef,
         "${base}192.0.2.5 host old.example.com old\n",
         'sets a short hostname and keeps existing names'],
        ["${base}192.0.2.50 other.example.com other\n", 'host', undef,
         "${base}192.0.2.50 other.example.com other\n192.0.2.5\thost\n",
         'does not replace an IPv4 address with the same prefix'],
        ["${base}192.0.205 other.example.com other\n", 'host', undef,
         "${base}192.0.205 other.example.com other\n192.0.2.5\thost\n",
         'treats IPv4 dots literally'],
        ["${base}2001:db8::10 other.example.com other\n", 'host', '2001:db8::1',
         "${base}2001:db8::10 other.example.com other\n2001:db8::1\thost\n",
         'does not replace an IPv6 address with the same prefix'],
        ["${base}\t 192.0.2.5\told.example.com old\n", 'host', undef,
         "${base}192.0.2.5 host old.example.com old\n",
         'matches an indented address field'],
        ["${base}192.0.2.5 old.example.com host service.example.com host.example.com # keep service\n",
         'host.example.com', undef,
         "${base}192.0.2.5 host.example.com host old.example.com service.example.com # keep service\n",
         'keeps unrelated aliases and comments without repeating requested names'],
        ["${base}192.0.2.5 old# keep comment\n", 'host', undef,
         "${base}192.0.2.5 host old # keep comment\n",
         'keeps a comment attached to the last name'],
        ["${base}2001:db8::1 old.example.com old\n", 'host.example.com', '2001:db8::1',
         "${base}2001:db8::1 host.example.com host old.example.com old\n",
         'updates an exact IPv6 address'],
        ["${base}# 192.0.2.5 commented.example.com\n\n192.0.2.50 other\n192.0.2.5 old\n",
         'host', undef,
         "${base}# 192.0.2.5 commented.example.com\n\n192.0.2.50 other\n192.0.2.5 host old\n",
         'leaves other addresses, comments, and blank lines unchanged'],
        ["${base}192.0.2.5 vm.internal vm # Added by Google\n", 'host', undef,
         "${base}192.0.2.5 vm.internal vm # Added by Google\n192.0.2.5\thost\n",
         'adds a separate mapping without changing a Google-managed entry'],
        ["${base}192.0.2.5 vm.internal vm # Added by Google\n192.0.2.5 old\n",
         'host', undef,
         "${base}192.0.2.5 vm.internal vm # Added by Google\n192.0.2.5 host old\n",
         'updates an ordinary entry and keeps the Google-managed entry'],
        [undef, 'host.example.com', undef,
         "192.0.2.5\thost.example.com\thost\n",
         'creates a missing hosts file'],
    );
    for my $case (@cases) {
        my ($hosts, $name, $address, $expected, $label) = @{$case};
        is(run_case($hosts, $name, $address, $shell), $expected, "$shell $label");
    }
    # Repeated installer runs must not grow the alias list
    my $hosts = run_case("${base}192.0.2.5 old service # keep\n",
                         'host.example.com', undef, $shell);
    is(run_case($hosts, 'host.example.com', undef, $shell), $hosts,
       "$shell repeated updates keep the same names and comments");
    # Incomplete mappings must leave the original contents intact
    is(run_case($base, 'host', '', $shell, 1), $base,
       "$shell rejects an empty address without changing the hosts file");
    is(run_case($base, '', undef, $shell, 1), $base,
       "$shell rejects an empty hostname without changing the hosts file");

    # The hostname setter must preserve a failed hosts update's return status.
    my $dir = tempdir(CLEANUP => 1);
    (my $setter = $hostname_function) =~ s{/etc/hostname}{$dir/hostname}g;
    write_file("$dir/setter.sh", <<'SH');
hostname () { :; }
hostnamectl () { :; }
set_hostname_cloud () { :; }
log_debug () { :; }
is_fully_qualified () { return 0; }
set_hosts_entry () { return 7; }
SH
    open my $fixture, '>>', "$dir/setter.sh" or die $!;
    print {$fixture} "$setter\nset_hostname host.example.com\n";
    close $fixture or die $!;
    is(system($shell, "$dir/setter.sh") >> 8, 7,
       "$shell set_hostname propagates a failed hosts update");
}

done_testing();
