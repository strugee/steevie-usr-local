# Intended to be sourced for library functions, not run directly

# Automatically sets up the following variables:
#  * $CHRONIC
#  * $SOFTERR_STREAM
#  * $SOFTERR_EXITCODE

#############################################################
# COMMON LIBRARY INITIALIZATION
#############################################################

# Gotta hardcode this, unfortunately, because this is POSIX sh and POSIX doesn't let us determine where we're being sourced from
. /usr/local/lib/common/functions.sh

logging_init

#############################################################
# VARIABLE INITIALIZATION
#############################################################

CHRONIC=false
test $(ps -o comm= $PPID) = chronic && CHRONIC=true

SOFTERR_STREAM=2
$CHRONIC && SOFTERR_STREAM=1
SOFTERR_EXITCODE=1
$CHRONIC && SOFTERR_EXITCODE=0

# Just a constant
BORG_STD_FLAGS='--compression auto,zstd,15 --lock-wait 10'

#############################################################
# FUNCTION LIBRARY
#############################################################

lockfile_acquire() {
	if ! dotlockfile -pr0 $DOTLOCK_ARGS /var/lock/run-borg.lock; then
		echo $(basename $0): failed to acquire lockfile >&$SOFTERR_STREAM
		exit $SOFTERR_EXITCODE
	fi

	log_info 'acquired lockfile'
}

lockfile_release() {
	dotlockfile -u /var/lock/run-borg.lock
	log_info 'released lockfile'
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
	log_info 'ran garbage collection'

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
	log_info 'froze filesystem'
}

get_existing_homedirs() {
	for i in $(getent passwd | cut -d: -f6); do
		test -d $i && echo $i
	done
}

get_homedir_caches() {
	for i in $(get_existing_homedirs); do
		test -d $i/.cache && echo $i/.cache
	done
}

invoke_borg() {
	log_info 'invoking borg'
	borg create $BORG_FLAGS --progress --stats $BORG_STD_FLAGS \
	--exclude root/.gdfuse/default/cache \
	$(for i in $(get_homedir_caches | sed 's;^/;;'); do printf -- "--exclude $i "; done) \
	--exclude var/cache \
	--exclude var/backups \
	--exclude var/tmp \
	--exclude var/log \
	ssh://fgl4136d@fgl4136d.repo.borgbase.com/./repo::steevie-$(date +%F-%H:%M-%a-%s)$BORG_TAG \
	$@
	log_info 'borg-create complete'
}
