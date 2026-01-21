#!/bin/sh

umask 6

now() {
	date +%s | tr -d '\n'
}

backups_init() {
	OLDVER=$1
	NEWVER=$2
	NOW=$(now)
}

usage() {
	exec 1>&2
	if ! [ -z ${BACKUPS_USAGE_OLDVER_OPTIONAL+x} ]; then
		oldver_string='[OLD_VERSION]'
	else
		oldver_string='OLD_VERSION'
	fi

	echo "Usage: $(basename $0) $oldver_string NEW_VERSION"
	exit 1
}

check_root() {
	if [ $(id -u) -ne 0 ]; then
		echo "$(basename $0): not invoked as root; bailing"
	        exit 1
	fi
}

check_startup() {
	check_root

	# ${param:-} expands to empty string if unset

	if [ -z "${1:-}" ]; then
		usage $@
	fi

	if [ -z "${BACKUPS_USAGE_OLDVER_OPTIONAL+x}" ] && [ -z "${2:-}" ]; then
		usage $@
	fi
}

call_mysqldump() {
	DBNAME=$1
	echo 'You will be prompted for the MySQL password.'
	mysqldump -u root -p $DBNAME | pv -W > /var/backups/$DBNAME/pre-$DBNAME-$OLDVER-to-$NEWVER-$NOW.sql
}

call_pgdump() {
	UNIX_USER=$1
	DBNAME=$2
	mkdir -p /var/backups/$DBNAME
	sudo -u $UNIX_USER pg_dump $DBNAME | pv -W > /var/backups/$DBNAME/pre-$DBNAME-$OLDVER-to-$NEWVER-$NOW.sql
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
