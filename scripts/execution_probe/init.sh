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
    printf 'CODELIB_RESULT_2|backendError|1||%s|\n' "$(printf '%s' "$1" | base64 | tr -d '\n')"
    exec sleep 3600
}

# Fixture names are re-validated here even though the host already checked them:
# the init trusts only itself for anything it writes into /work.
plain_name() {
    case "$1" in
        ''|.|..|main.cpp|stdin|program|*[!A-Za-z0-9._-]*) return 1 ;;
    esac
    [ "${#1}" -le 64 ]
}

read_fixture() {
    # $1: target directory, $2: names record or empty. Sets fixture_name and
    # writes the decoded content there.
    IFS= read -r fixture_name || fail 'missing fixture name'
    IFS= read -r fixture_data || fail 'missing fixture data'
    fixture_name=$(printf '%s' "$fixture_name" | base64 -d) || fail 'bad fixture name encoding'
    plain_name "$fixture_name" || fail 'invalid fixture name'
    printf '%s' "$fixture_data" | base64 -d > "$1/$fixture_name" || fail 'bad fixture encoding'
    if [ "$1" = /work ]; then
        # Programs run as 65534 and may modify, append to or delete provided files.
        chown 65534:65534 "$1/$fixture_name" 2>/dev/null || true
        chmod 644 "$1/$fixture_name"
    fi
    [ -z "$2" ] || printf '%s\n' "$fixture_name" >>"$2"
}

read_group() {
    # Reads one file group: a decimal count, then name/content pairs.
    IFS= read -r group_count || fail 'missing fixture count'
    case "$group_count" in ''|*[!0-9]*) fail 'invalid fixture count' ;; esac
    [ "$group_count" -le 8 ] || fail 'too many fixtures'
    i=0
    while [ "$i" -lt "$group_count" ]; do
        read_fixture "$1" "$2"
        i=$((i + 1))
    done
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
printf 'CODELIB_READY_2\n'
IFS= read -r standard || fail 'missing standard'
case "$standard" in 17|20) ;; *) fail 'unsupported standard' ;; esac
IFS= read -r source || fail 'missing source'
IFS= read -r input || fail 'missing input'
printf '%s' "$source" | base64 -d >/work/main.cpp || fail 'bad source encoding'
printf '%s' "$input" | base64 -d >/work/stdin || fail 'bad input encoding'
unset source input
chmod 444 /work/main.cpp /work/stdin
read_group /work ''
# Expected files live outside /work with no access for the program user; the
# verdict is computed here, never by code the program could influence. Names
# are recorded during reception so the comparison uses exactly the accepted
# set, including hidden names the shell glob would miss.
mkdir -p /run/expected
chmod 700 /run/expected
read_group /run/expected /run/expected-names

# Expected comparison runs only when no user program is alive any more: a
# detached descendant could otherwise mutate /work during the verdict.
user_alive() {
    for entry in /proc/[0-9]*; do
        [ -r "$entry/status" ] || continue
        state=''
        uid=''
        while IFS= read -r line; do
            case "$line" in
                State:*) set -- $line; state=$2 ;;
                Uid:*) set -- $line; uid=$2 ;;
            esac
        done <"$entry/status"
        [ "$uid" = 65534 ] || continue
        [ "$state" = Z ] || return 0
    done
    return 1
}

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
# Expected file comparison runs in this trusted init after the run is finished
# and no user process remains, so the verdict cannot be influenced by user code.
mismatches=''
if [ "$status" = success ]; then
    if user_alive; then
        # One short grace pass for an exiting descendant; a lingering process
        # means the verdict cannot be trusted and the run fails closed.
        sleep 1
        user_alive && fail 'user program descendants are still alive'
    fi
    if [ -s /run/expected-names ]; then
        while IFS= read -r name; do
            [ -n "$name" ] || continue
            # A symlink is never the produced file: the program must not be able
            # to point the comparison at another path, including the expected file.
            if [ -L "/work/$name" ] || [ ! -f "/work/$name" ] || \
               ! cmp -s "/run/expected/$name" "/work/$name"; then
                mismatches="$mismatches$name\n"
            fi
        done </run/expected-names
        [ -z "$mismatches" ] || status=fileMismatch
    fi
fi
# Bounded base64 framing: child has no descriptor or permissions to the console.
out=$(head -c 65536 /run/out | base64 | tr -d '\n')
err=$(head -c 65536 /run/err | base64 | tr -d '\n')
printf 'CODELIB_RESULT_2|%s|%s|%s|%s|%s\n' "$status" "$code" "$out" "$err" \
    "$(printf '%b' "$mismatches" | base64 | tr -d '\n')"
# The host forcibly tears down the entire VM, including detached descendants.
exec sleep 3600
