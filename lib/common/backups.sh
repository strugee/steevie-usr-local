#!/bin/sh

umask 6

now() {
	date +%s | tr -d '\n'
}

OLDVER=$1
NEWVER=$2
NOW=$(date +%s)

usage() {
	exec 1>&2
        echo "Usage: $0 OLD_VERSION NEW_VERSION"
	exit 1
}

check_startup()
	if [ $(id -u) -ne 0 ]; then
		echo "$0: not invoked as root; bailing"
	        exit 1
	fi

	# ${param:-} expands to empty string if unset

	if [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
		usage
	fi
}

call_mysqldump() {
	DBNAME=$1
	echo 'You will be prompted for the MySQL password.'
	mysqldump -u root -p $DBNAME | pv -W > /var/backups/$DBNAME/pre-$DBNAME-$OLDVER-to-$NEWVER-$NOW.sql
}

take_zfs_snapshot() {
	ZFS_SVC_DATASET=$1
	ZFS_DB_DATASET=$2
	SNAPNAME=pre-nextcloud-$OLDVER-to-$NEWVER-$NOW

	echo 'Taking ZFS snapshot.'
	zfs snapshot -r $ZFS_SVC_DATASET@$SNAPNAME $ZFS_DB_DATASET@$SNAPNAME
}

finalize() {
	echo 'Ready.'
}
