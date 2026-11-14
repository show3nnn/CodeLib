#!/bin/busybox sh
# Trusted PID 1, developer prototype. All compiler inputs and outputs stay in RAM.
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
export LC_ALL=C
export HOME=/tmp
umask 077
mount -t devtmpfs devtmpfs /dev
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mkdir -p /dev/pts /run /work
chmod 1777 /tmp
mount -t devpts devpts /dev/pts
# No virtual NIC, disks, shared directories, guest agent socket or host mounts.
exec </dev/hvc0 >/dev/hvc0 2>/dev/hvc0
stty -F /dev/hvc0 raw -echo
chmod 600 /dev/hvc0

fail() {
    printf 'CODELIB_RESULT_1|backendError|1||%s\n' "$(printf '%s' "$1" | base64 | tr -d '\n')"
    exec sleep 3600
}

# APK verifies signatures using the Alpine keys in the pinned official rootfs.
# No --allow-untrusted, network access, repositories or package scripts.
apk verify /packages/linux-virt-*.apk >/run/apk.log 2>&1 || fail 'kernel signature verification failed'
rm /packages/linux-virt-*.apk
apk add --no-network --no-scripts --force-non-repository --repositories-file /dev/null /packages/*.apk >/run/apk.log 2>&1 ||
    fail "$(tail -c 4096 /run/apk.log)"
rm -f /packages/*.apk
# Build only our pinned trusted supervisor before receiving any user source.
gcc -std=c11 -Os -Wall -Wextra -Werror -o /run/supervise /supervisor.c >/run/supervisor-build.log 2>&1 ||
    fail "$(tail -c 4096 /run/supervisor-build.log)"
chmod 755 /work
chown 65534:65534 /work
printf 'CODELIB_READY_1\n'
IFS= read -r standard || fail 'missing standard'
case "$standard" in 17|20) ;; *) fail 'unsupported standard' ;; esac
IFS= read -r source || fail 'missing source'
IFS= read -r input || fail 'missing input'
printf '%s' "$source" | base64 -d >/work/main.cpp || fail 'bad source encoding'
printf '%s' "$input" | base64 -d >/work/stdin || fail 'bad input encoding'
unset source input
chmod 444 /work/main.cpp /work/stdin

# Supervisor drops groups/UID and applies hard limits before exec. wait4
# distinguishes an actual signal from a normal exit(128 + signal).
status=success
printf 'CODELIB_PHASE_1|compiling\n'
/run/supervise compile "$standard" </dev/null >/run/out 2>/run/err || fail 'compiler supervisor failed'
read -r code signal </run/termination || fail 'missing compiler status'
if [ "$code" -ne 0 ]; then
    status=compileError
else
    printf 'CODELIB_PHASE_1|running\n'
    /run/supervise run </work/stdin >/run/out 2>/run/err || fail 'runtime supervisor failed'
    read -r code signal </run/termination || fail 'missing program status'
    [ "$code" -eq 0 ] || status=runtimeError
    [ "$signal" -ne 24 ] || status=cpuLimit
    [ "$signal" -ne 25 ] || status=outputLimit
fi
out_size=$(wc -c </run/out)
err_size=$(wc -c </run/err)
if [ "$out_size" -gt 65536 ] || [ "$err_size" -gt 65536 ]; then status=outputLimit; fi
# Bounded base64 framing: child has no descriptor or permissions to the console.
out=$(head -c 65536 /run/out | base64 | tr -d '\n')
err=$(head -c 65536 /run/err | base64 | tr -d '\n')
printf 'CODELIB_RESULT_1|%s|%s|%s|%s\n' "$status" "$code" "$out" "$err"
# The host forcibly tears down the entire VM, including detached descendants.
exec sleep 3600
