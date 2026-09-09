#!/usr/bin/env perl
use strict;
use warnings;
use 5.010;
use File::Temp qw(tempdir);
use Test::More;

# These tests use Linux file metadata and utilities, but all paths are redirected
# into a private fixture. No test activates swap or edits the host configuration.
plan skip_all => 'Linux fixture tests (also run on the disposable VM)' if $^O ne 'linux';
open my $src, '<', 'slib.sh' or die $!;
my $source = do { local $/; <$src> };
$source =~ /(# Versioned contract.*?)(?=# serial_ok)/s or die 'Missing swap API';
my $library = $1;

sub write_file {
    my ($path, $text) = @_;
    open my $fh, '>', $path or die "$path: $!";
    print {$fh} $text;
    close $fh;
}
sub read_file {
    my ($path) = @_;
    open my $fh, '<', $path or return '';
    local $/;
    return <$fh> // '';
}
sub run_case {
    my ($scenario, $existing, $fstab) = @_;
    my $dir = tempdir(CLEANUP => 1);
    my $lib = $library;
    # Rewrite fixed system paths before any shell code is run.
    $lib =~ s{/(?:etc|proc|sys|run)(?=[/\s'"])}{$dir$&}g;
    $lib =~ s{/swap\.vm}{$dir/swap.vm}g;
    $lib =~ s{/swap\.virtualmin}{$dir/swap.virtualmin}g;
    mkdir "$dir/$_" for qw(etc proc sys run);
    mkdir "$dir/run/lock";
    write_file("$dir/lib.sh", $lib);
    $fstab //= "/dev/foreign none swap defaults 0 0\n";
    $fstab =~ s/%MANAGED%/$dir\/swap.vm/g;
    write_file("$dir/etc/fstab", $fstab);
    write_file("$dir/proc/meminfo", "MemTotal: 4194304 kB\nMemAvailable: 3145728 kB\nSwapTotal: 1048576 kB\n");
    # Nonzero/invalid offsets and unverified devices conflict; verified partition
    # resume with zero offsets must not prevent an unrelated swapfile resize.
    my %cmdline = (
        resume => 'resume_offset=12345',
        resume_partition => 'resume=UUID=example quiet',
        resume_partition_zero => 'resume=UUID=example resume_offset=0',
        resume_partition_zeroes => 'resume_offset=0000',
        resume_empty_offset => 'resume_offset=',
        resume_bad_offset => 'resume_offset=invalid',
        resume_duplicate_offset => 'resume_offset=12345 resume_offset=0',
    );
    write_file("$dir/proc/cmdline", $cmdline{$scenario} // 'quiet');
    mkdir "$dir/sys/power";
    my %resume = (
        resume_partition => '254:1', resume_partition_zero => '254:1',
        resume_partition_zeroes => '254:1', resume_sysfs => '254:0',
        resume_device => '254:0', resume_unknown_device => '254:2',
        resume_probe_failure => '254:1', resume_bad_device => 'invalid',
    );
    write_file("$dir/sys/power/resume", $resume{$scenario} // '0:0');
    my %offset = (resume_sysfs => '4096', resume_partition_zeroes => '0000',
                  resume_bad_sysfs_offset => 'invalid');
    write_file("$dir/sys/power/resume_offset", $offset{$scenario} // '0');
    write_file("$dir/proc/swaps", "Filename Type Size Used Priority\n$dir/swap.vm file 1020 0 -2\n");
    write_file("$dir/active", "/dev/foreign\n" . ($existing ? "$dir/swap.vm\n" : ''));
    if ($existing) {
        write_file("$dir/swap.vm", 'original');
        truncate "$dir/swap.vm", 1048576;
        chmod 0600, "$dir/swap.vm";
    }
    if ($scenario eq 'hardlink') { link "$dir/swap.vm", "$dir/valuable" or die $!; }
    if ($scenario eq 'symlink') {
        write_file("$dir/valuable", 'preserve me');
        symlink "$dir/valuable", "$dir/swap.vm" or die $!;
    }
    if ($scenario eq 'alias') {
        symlink "$dir/swap.vm", "$dir/alias" or die $!;
        write_file("$dir/etc/fstab", "$dir/alias none swap defaults 0 0\n");
    }
    if ($scenario eq 'native_unit' || $scenario =~ /^ordering/) {
        mkdir "$dir/etc/systemd";
        mkdir "$dir/etc/systemd/system";
        my $unit = "$dir/swap.vm";
        $unit =~ s{^/}{};
        $unit =~ s{/}{-}g;
        if ($scenario eq 'native_unit') {
            write_file("$dir/etc/systemd/system/$unit.swap", "[Swap]\nWhat=$dir/swap.vm\n");
        }
        else {
            mkdir "$dir/run/systemd";
            mkdir "$dir/run/systemd/system";
        }
    }
    my $script = <<'SH';
. "$FIXTURE/lib.sh"
RUN_LOG="$FIXTURE/log"
swapsize=2048
log_info () { printf 'INFO:%s\n' "$1"; }
log_error () { printf 'ERROR:%s\n' "$1"; }
log_warning () { printf 'WARN:%s\n' "$1"; }
log_success () { printf 'OK:%s\n' "$1"; }
id () { echo 0; }
findmnt () {
  if [ "$SCENARIO" = preflight_not_root ]; then printf 'findmnt\n' >> "$FIXTURE/calls"; return 1; fi
  case "$SCENARIO" in legacy_stale|ordering*) echo btrfs ;; *) echo ext4 ;; esac
}
systemctl () { return 0; }
df () { printf 'Filesystem blocks used available capacity mount\nmock 80000000 0 70000000 0%% /\n'; }
blkid () { if [ "$SCENARIO" = unrecognized ]; then echo ext4; else echo swap; fi; }
# Block-device verification is tested with real loop devices on the VM; fixtures
# distinguish a confirmed partition from a filesystem or an unresolved device.
swap_resume_partition () {
  case "$SCENARIO" in
    resume_partition|resume_partition_zero|resume_partition_zeroes) [ "$1" = '254:1' ] ;;
    resume_probe_failure) return 2 ;;
    *) return 1 ;;
  esac
}
# Only owner is mocked, so inode and link-count checks still exercise real files.
stat () {
  if [ "$1" = -c ] && [ "$2" = '%u:%h' ]; then
    printf '0:%s\n' "$(command stat -c %h "$3")"
  else command stat "$@"; fi
}
swap_file_active () { command grep -Fxq -- "$1" "$FIXTURE/active"; }
swapon () {
  for mock_swap_target do :; done
  printf 'swapon %s\n' "$mock_swap_target" >> "$FIXTURE/calls"
  if [ "$SCENARIO" = activation_failure ] && [ "$mock_swap_target" = "$FIXTURE/swap.vm" ] &&
     [ "$(head -c 11 "$mock_swap_target")" = replacement ]; then return 1; fi
  printf '%s\n' "$mock_swap_target" >> "$FIXTURE/active"
}
swapoff () {
  printf 'swapoff %s\n' "$1" >> "$FIXTURE/calls"
  [ "$SCENARIO" != swapoff_failure ] || [ "$1" != "$FIXTURE/swap.vm" ] || return 1
  [ "$SCENARIO" != reuse_rollback_failure ] || return 1
  command grep -Fxv -- "$1" "$FIXTURE/active" > "$FIXTURE/active.new"
  command mv "$FIXTURE/active.new" "$FIXTURE/active"
}
dd () {
  case "$SCENARIO" in allocation_failure|automatic_failure) return 1 ;; esac
  for arg do case "$arg" in of=*) printf replacement > "${arg#of=}" ;; esac; done
}
mkswap () { [ "$SCENARIO" != format_failure ]; }
case "$SCENARIO" in
  fstab_failure|ordering_failure) swap_commit_fstab () { return 1; } ;;
  reuse_fstab_failure|reuse_rollback_failure)
    swapsize=1024
    printf '/dev/foreign\n' > "$FIXTURE/active"
    swap_commit_fstab () { return 1; }
    ;;
  concurrent_fstab) mkswap () { printf '# concurrent edit\n' >> "$FIXTURE/etc/fstab"; } ;;
  no_swap) noswap=1 ;;
  setup) setup_only=1 ;;
  automatic_failure) swapsize= ;;
  remove|remove_failure|legacy_stale|nothing_to_remove) swapsize=0 ;;
  same_size|ordering) swapsize=1024 ;;
  not_root|preflight_not_root) id () { echo 1000; } ;;
  no_memory)
    sed 's/MemAvailable: 3145728/MemAvailable: 1/' "$FIXTURE/proc/meminfo" > "$FIXTURE/mem.new"
    mv "$FIXTURE/mem.new" "$FIXTURE/proc/meminfo"
    ;;
esac
if [ "$SCENARIO" = remove_failure ]; then swap_commit_fstab () { return 1; }; fi
if [ "$SCENARIO" = ordering_failure ]; then swapsize=1024; fi
if [ "$SCENARIO" = preflight_not_root ]; then
  swap_plan 0
  result=$?
  printf 'PREFLIGHT:%s\n' "$swap_error"
  exit "$result"
fi
if [ "$SCENARIO" = automatic_failure ]; then
  memory_ok 1048576 0
  exit "$?"
fi
swap_setup 0
SH
    write_file("$dir/test.sh", $script);
    local %ENV = (%ENV, FIXTURE => $dir, SCENARIO => $scenario);
    open my $pipe, '-|', 'dash', "$dir/test.sh" or die $!;
    my $out = do { local $/; <$pipe> // '' };
    close $pipe;
    my $status = $? >> 8;
    my $unit = "$dir/swap.vm";
    $unit =~ s{^/}{};
    $unit =~ s{/}{-}g;
    my $ordering = read_file("$dir/etc/systemd/system/$unit.swap.d/50-virtualmin-swap.conf");
    return ($status, $out, read_file("$dir/swap.vm"), read_file("$dir/etc/fstab"),
            read_file("$dir/active"), read_file("$dir/calls"), read_file("$dir/valuable"), $ordering);
}

for my $failure (qw(allocation_failure format_failure activation_failure swapoff_failure fstab_failure no_memory resume resume_sysfs resume_device resume_unknown_device resume_probe_failure resume_empty_offset resume_bad_offset resume_duplicate_offset resume_bad_sysfs_offset resume_bad_device not_root)) {
    my ($status, $out, $file, $fstab, $active) = run_case($failure, 1);
    isnt($status, 0, "$failure is reported");
    like($file, qr/^original\0+$/, "$failure preserves the original inode contents");
    is($fstab, "/dev/foreign none swap defaults 0 0\n", "$failure leaves fstab intact");
    like($active, qr{/swap\.vm\n}, "$failure leaves original swap active");
}
for my $conflict (qw(resume resume_sysfs resume_device)) {
    my ($status, $out) = run_case($conflict, 1);
    like($out, qr/Hibernation into a swapfile/, "$conflict names the hibernation conflict");
}
{
    my ($status, $out, $file, $fstab, $active, $calls) = run_case('not_root', 1);
    like($out, qr/requires root/, 'unprivileged execution is diagnosed');
    is($calls, '', 'unprivileged run never touches live swap');
    ($status, $out, $file, $fstab, $active, $calls) = run_case('preflight_not_root', 1);
    isnt($status, 0, 'direct unprivileged preflight fails');
    like($out, qr/PREFLIGHT:Swap management requires root/, 'swap_plan reports its own root check');
    is($calls, '', 'swap_plan checks root before probing the system');
    for my $partition (qw(resume_partition resume_partition_zero resume_partition_zeroes)) {
        ($status, $out, $file) = run_case($partition, 1);
        is($status, 0, "$partition does not block an unrelated resize");
        is($file, 'replacement', "$partition still installs the replacement");
    }
    ($status, $out, $file, $fstab, $active, $calls) = run_case('nothing_to_remove', 0);
    is($status, 0, 'removing absent managed swap succeeds');
    is($calls, '', 'absent managed swap needs no live changes');
    is($fstab, "/dev/foreign none swap defaults 0 0\n", 'absent managed swap leaves fstab untouched');
    unlike($out, qr/The swap space previously configured by this installer will be removed\./, 'absent managed swap announces no removal');
}
for my $guard (qw(no_swap setup)) {
    my ($status, $out, $file, $fstab, $active, $calls) = run_case($guard, 1);
    is($status, 0, "$guard succeeds");
    is($calls, '', "$guard never calls swapon or swapoff");
    is($fstab, "/dev/foreign none swap defaults 0 0\n", "$guard leaves fstab intact");
    like($file, qr/^original\0+$/, "$guard leaves the swapfile intact");
}
my ($status, $out, $file, $fstab, $active, $calls, $valuable) = run_case('symlink', 0);
isnt($status, 0, 'rejects a symlink at the managed pathname');
is($valuable, 'preserve me', 'symlink target is untouched');
is($calls, '', 'unsafe pathname is rejected before activation');

($status, $out, $file, $fstab, $active) = run_case('create', 0);
is($status, 0, 'creation succeeds');
is($out, '', 'successful execution does not repeat the preview or print a success message');
is($file, 'replacement', 'installs the prepared replacement');
like($fstab, qr{/swap\.vm none swap defaults,nofail 0 0}, 'persists with nofail');
like($active, qr{^/dev/foreign\n}, 'preserves foreign swap');

# Automatic setup must not swallow failures merely because RAM is sufficient.
($status, $out, $file, $fstab, $active) = run_case('automatic_failure', 0);
isnt($status, 0, 'automatic allocation failure is fatal despite sufficient memory');
like($out, qr/Swap operation failed/, 'automatic failure reports the error');
is($fstab, "/dev/foreign none swap defaults 0 0\n", 'automatic failure preserves fstab');
is($active, "/dev/foreign\n", 'automatic failure preserves existing swap');

($status, $out, $file, $fstab, $active, $calls) = run_case('same_size', 1);
is($status, 0, 'same-size repair succeeds');
is($calls, '', 'same-size active swap is never cycled');
like($fstab, qr{defaults,nofail}, 'repairs missing persistence');

# Reusing an inactive file must roll back activation when persistence fails.
for my $failure (qw(reuse_fstab_failure reuse_rollback_failure)) {
    ($status, $out, $file, $fstab, $active) = run_case($failure, 1);
    isnt($status, 0, "$failure is reported");
    like($file, qr/^original\0+$/, "$failure retains the original file");
    is($fstab, "/dev/foreign none swap defaults 0 0\n", "$failure preserves fstab");
    if ($failure eq 'reuse_fstab_failure') {
        is($active, "/dev/foreign\n", 'failed repair restores the original inactive state');
    }
    else {
        like($active, qr{/swap\.vm\n}, 'failed deactivation keeps the original file active');
        like($out, qr/Could not undo activation/, 'failed deactivation explains the retained state');
    }
}

($status, $out, $file, $fstab, $active) = run_case('remove', 1);
is($status, 0, 'removal succeeds');
is($file, '', 'managed file is removed');
is($active, "/dev/foreign\n", 'removal preserves foreign swap');

($status, $out, $file, $fstab, $active) = run_case('remove_failure', 1);
isnt($status, 0, 'failed persistence update aborts removal');
like($file, qr/^original\0+$/, 'failed removal retains original contents');
like($active, qr{/swap\.vm\n}, 'failed removal reactivates original swap');

($status, $out, $file, $fstab, $active) = run_case('concurrent_fstab', 1);
isnt($status, 0, 'concurrent fstab edit aborts replacement');
like($fstab, qr/# concurrent edit/, 'preserves concurrent edit');
like($file, qr/^original\0+$/, 'concurrent edit restores original swap');

for my $unsafe (qw(hardlink unrecognized alias native_unit)) {
    ($status, $out, $file, $fstab, $active, $calls) = run_case($unsafe, 1);
    isnt($status, 0, "rejects $unsafe managed files");
    is($calls, '', "$unsafe rejection precedes any live swap change");
    like($file, qr/^original\0+$/, "$unsafe contents are retained");
}
for my $record (
    "%MANAGED% none swap noauto 0 0\n",
    "%MANAGED% none ext4 defaults 0 0\n",
    "%MANAGED% none swap defaults 0 0\n%MANAGED% none swap defaults 0 0\n"
) {
    ($status, $out, $file, $fstab, $active, $calls) = run_case('conflict', 1, $record);
    isnt($status, 0, 'rejects conflicting persistence');
    is($calls, '', 'fstab conflict is rejected before live changes');
    like($file, qr/^original\0+$/, 'conflicting persistence retains original contents');
}

($status, $out, $file, $fstab, $active) = run_case('legacy_stale', 0,
    "%MANAGED% none swap defaults 0 0\n");
is($status, 0, 'removes a missing legacy swapfile entry on Btrfs');
unlike($fstab, qr{swap\.vm}, 'does not leave the stale legacy boot entry behind');
is($active, "/dev/foreign\n", 'stale-entry removal preserves other active swap');

my @ordered = run_case('ordering', 1);
is($ordered[0], 0, 'repairs Btrfs boot ordering with systemd');
like($ordered[7], qr/^After=swap.target systemd-remount-fs.service$/m, 'serializes activation after ordinary swap');
like($ordered[7], qr/^DefaultDependencies=no$/m, 'avoids a cycle with swap.target');
like($ordered[7], qr/^Before=umount.target$/m, 'retains shutdown ordering');
@ordered = run_case('ordering_failure', 1);
isnt($ordered[0], 0, 'reports failure after ordering preparation');
is($ordered[7], '', 'failed persistence update removes the newly created drop-in');

done_testing();
