# Intended to be sourced for library functions, not run directly

# Automatically sets up the following variables:
#  * $CHRONIC
#  * $SOFTERR_STREAM
#  * $SOFTERR_EXITCODE

CHRONIC=false
test $(ps -o comm= $PPID) = chronic && CHRONIC=true

SOFTERR_STREAM=2
$CHRONIC && SOFTERR_STREAM=1
SOFTERR_EXITCODE=1
$CHRONIC && SOFTERR_EXITCODE=0

logging_cleanup() {
	rm -f $STDOUT_FIFO $STDERR_FIFO
}

logging_init() {
	# Note well: since we are sending stdout and stderr to different systemd-cat processes to get
	# differing priorities for those, the output is not strictly ordered, though it will tend to be
	# approximately ordered. See the description of --stderr-priority= in systemd-cat(1).

	# IMPORTANT: also, the caller is expected to add logging_cleanup() to the EXIT trap.

	STDOUT_FIFO=$(mktemp -u)
	mkfifo -m 0600 $STDOUT_FIFO
	trap "rm -f $STDOUT_FIFO" EXIT

	STDERR_FIFO=$(mktemp -u)
	mkfifo -m 0600 $STDERR_FIFO
	trap "rm -f $STDOUT_FIFO; rm -f $STDERR_FIFO" EXIT

	# Start the background output/log processing pipeline
	# Can't use /dev/stdout for tee because | overwrites the inherited stdout, so we set up an
	# fd 3 instead
	exec 3<&1 # Duplicate our original stdout to fd 3
	<$STDOUT_FIFO sh -c "tee /dev/fd/3 | systemd-cat -t $(basename $0)" &
	exec 4<&2 # Use fd 4 for the original stderr
	<$STDERR_FIFO sh -c "tee /dev/fd/4 | systemd-cat -t $(basename $0) -p warning" &

	# Send stdout to it
	exec 1>$STDOUT_FIFO
	# Ditto stderr
	exec 2>$STDERR_FIFO
}

ensure_args() {
	ARGSTR="$1"
	shift
	if [ $# = 0 ]; then
		echo usage: $(basename $0) $ARGSTR 1>&2
		exit 1
	fi
}

test_is_root() {
	if [ $(id -u) != 0 ]; then
		echo $(basename $0): need to be root >&2
		exit 1
	fi
}

lockfile_acquire() {
	if ! dotlockfile -pr0 $DOTLOCK_ARGS /var/lock/run-borg.lock; then
		echo $(basename $0): failed to acquire lockfile >&$SOFTERR_STREAM
		exit $SOFTERR_EXITCODE
	fi
}

lockfile_release() {
	dotlockfile -u /var/lock/run-borg.lock
}

gc() {
	# Need to not be in /media/borg-stage so that it can be unmounted
	# gc() may be called on startup to clean up from last time, so we only mutate $PWD if necessary
	case $PWD/ in
		/media/borg-stage) cd - >/dev/null;;
	esac

	mountpoint -q /media/borg-stage && umount -R /media/borg-stage
	# For some reason there's a weird alternate empty dataset mount underneath everything that doesn't unmount the first time around
	mountpoint -q /media/borg-stage && umount -R /media/borg-stage
	zfs destroy -r rpool@borg-stage
}

gc_if_needed() {
	# Garbage-collect old staging snapshots in case we crashed last time
	# Need `|| true` because otherwise the command failure crashes the program due to `set -e`
	zfs list -d1 rpool@borg-stage >/dev/null 2>&1 && gc || true
}

freeze_fs() {
	# Freeze a view of the filesystem so Borg backups are atomic
	zfs snapshot -r rpool@borg-stage
	zfs list -t snapshot -o name,net.strugee:borgignore -s name -H | grep 'on$' | cut -f1 | grep '@borg-stage' | xargs -n 1 zfs destroy
	mkdir -p /media/borg-stage
	zfs-mount-snapshots borg-stage /media/borg-stage
}

invoke_borg() {
	borg create --progress --stats --compression auto,lzma,6 \
	--exclude root/.gdfuse/default/cache \
	--exclude root/.cache \
	--exclude home/*/.cache \
	--exclude var/cache \
	--exclude var/backups \
	--exclude var/tmp \
	--exclude var/log \
	/media/gdrive/borg::steevie-$(date +%F-%H:%M-%a-%s)-$BORG_TAG \
	$@
}
