# Intended to be sourced for library functions, not run directly

# Automatically sets up the following variables:
#  * $CHRONIC
#  * $SOFTERR_STREAM
#  * $SOFTERR_EXITCODE

# Gotta hardcode this, unfortunately, because this is POSIX sh and POSIX doesn't let us determine where we're being sourced from
. /usr/local/lib/common/functions.sh

CHRONIC=false
test $(ps -o comm= $PPID) = chronic && CHRONIC=true

SOFTERR_STREAM=2
$CHRONIC && SOFTERR_STREAM=1
SOFTERR_EXITCODE=1
$CHRONIC && SOFTERR_EXITCODE=0

# Just a constant
BORG_STD_FLAGS='--compression auto,lzma,6 --lock-wait 10'

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
		/media/borg-stage/) cd - >/dev/null;;
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
	borg create $BORG_FLAGS --progress --stats $BORG_STD_FLAGS \
	--exclude root/.gdfuse/default/cache \
	--exclude root/.cache \
	--exclude home/*/.cache \
	--exclude var/cache \
	--exclude var/backups \
	--exclude var/tmp \
	--exclude var/log \
	/media/gdrive/borg-2021::steevie-$(date +%F-%H:%M-%a-%s)$BORG_TAG \
	$@
}
