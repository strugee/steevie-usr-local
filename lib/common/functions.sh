# Intended to be sourced for library functions, not run directly

logging_init_channels() {
	# Note well: since we are sending stdout and stderr to different systemd-cat processes to get
	# differing priorities for those, the output is not strictly ordered, though it will tend to be
	# approximately ordered. See the description of --stderr-priority= in systemd-cat(1).

	# Abort if we've already done setup
	if ! [ -z ${INFO_DIRECTWRITE_FIFO+x} ]; then
		echo 'warning: called logging_init_channels more than once; this may produce unexpected and untested results'
		return
	fi

	STDOUT_FIFO=$(mktemp -u)
	mkfifo -m 0600 $STDOUT_FIFO

	STDERR_FIFO=$(mktemp -u)
	mkfifo -m 0600 $STDERR_FIFO

	INFO_DIRECTWRITE_FIFO=$(mktemp -u)
	mkfifo -m 0600 $INFO_DIRECTWRITE_FIFO

	WARN_DIRECTWRITE_FIFO=$(mktemp -u)
	mkfifo -m 0600 $WARN_DIRECTWRITE_FIFO

	# Start the background output/log processing pipeline

	# The trap is in the subshell to prevent a subtle race condition. If the subprocess was
	# scheduled by the kernel before the parent process was, all was well because it would be
	# able to open the FIFO. However, if the parent reached EOF, ran the cleanup code in the EXIT
	# trap, and exited before the subprocess was scheduled, then by the time the subprocess
	# opened the FIFO to be file descriptor 0, the FIFO would already have been cleaned up.
	#
	# Thus, we simply run the trap in the subprocess so that cleanup is tied to the logging channel
	# itself, not the parent process. This is (arguably) a more logically consistent place to put
	# this cleanup *and*, as a bonus, it means we do not need to require calling code to register
	# a cleanup function as a part of their EXIT traps.
	(trap "rm $INFO_DIRECTWRITE_FIFO" EXIT && <$INFO_DIRECTWRITE_FIFO systemd-cat -t $(basename $0)) &
	(trap "rm $WARN_DIRECTWRITE_FIFO" EXIT && <$WARN_DIRECTWRITE_FIFO systemd-cat -t $(basename $0) -p warning) &

	# Can't use /dev/stdout for tee because | overwrites the inherited stdout, so we set up an
	# fd 3 instead. Same for stderr and fd 4.
	exec 3<&1 # Duplicate our original stdout to fd 3
	(trap "rm $STDOUT_FIFO" EXIT && <$STDOUT_FIFO tee /dev/fd/3 > $INFO_DIRECTWRITE_FIFO) &
	exec 4<&2 # Use fd 4 for the original stderr
	(trap "rm $STDERR_FIFO" EXIT && <$STDERR_FIFO tee /dev/fd/4 > $WARN_DIRECTWRITE_FIFO) &
}

logging_init() {
	# IMPORTANT: you should read the comments for logging_init_channels()
	logging_init_channels

	# Send stdout to the logging channel
	exec 1>$STDOUT_FIFO
	# Ditto stderr
	exec 2>$STDERR_FIFO
}

log_channel_info() {
	cat > $INFO_DIRECTWRITE_FIFO
}

log_channel_warn() {
	cat > $WARN_DIRECTWRITE_FIFO
}

log_info() {
	echo "$@" | log_channel_info
}

log_warn() {
	echo "$@" | log_channel_warn
}

ensure_args() {
	ARGSTR="$1"
	shift
	if [ $# = 0 ]; then
		echo usage: $(basename $0) $ARGSTR 1>&2
		exit 1
	fi
}

die() {
	echo $(basename $0): "$@" >&2
	exit 1
}

test_is_root() {
	if [ $(id -u) != 0 ]; then
		die need to be root >&2
	fi
}
