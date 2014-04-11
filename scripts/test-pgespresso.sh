#!/bin/bash
# Basic test script for concurrent backup from a standby
# using pgespresso and rsync. By default, it creates a
# test directory (within the current directory) containing
# the required Postgres clusters.
#
# Requirements: PostgreSQL 9.2 or 9.3
# Recommended:  pgbench
#
# Usage:   ./test-pgespresso.sh
# Cleanup: ./test-pgespresso.sh destroy
#
# Copyright (c) 2014, 2ndQuadrant Limited <www.2ndquadrant.com>
#
# Author: Marco Nenciarini <marco.nenciarini@2ndQuadrant.it>
#
# See COPYING for licensing information
#

set -e

# in case of error print a red error message
trap "echo -e '\033[1;31mERROR!\033[0m'" ERR

destdir=$(mkdir -p test && cd test && pwd)
waldir="$destdir/archive"

masterdir="$destdir/master"
masterlog="/tmp/master.log"
masterport="6432"

standbydir="$destdir/standby"
standbylog="/tmp/standby.log"
standbyport="6433"

backupdir="$destdir/backup"
backuplog="/tmp/backup.log"
backupport="6434"

# reset the postgres environment
unset PGDATA PGHOST PGPORT PGPASSWORD
export PGUSER=postgres
export PGHOST=/tmp

# print a green progress message
progress() {
    echo -e "\033[1;32m$*\033[0m"
}

# if the first argument is "destroy" dispose the test environment
if [ "$1" = "destroy" ]
then
    progress "Destroying the test environment"
    pg_ctl -D "$masterdir" -w stop || :
    pg_ctl -D "$standbydir" -w stop || :
    pg_ctl -D "$backupdir" -w stop || :
    rm -fr "$destdir"
    echo
    progress "Done. Test environment destroyed."
    echo
    exit 0
fi

# initialize the wal archive
mkdir -p "$waldir"

# initdb the master if not exists
if [ ! -e "$masterdir/PG_VERSION" ]
then
    progress "Creating the master instance"
    mkdir -p "$masterdir"

    # if postgres 9.3 or greater enable checksum
    version=($(initdb --version | sed -e 's/.* //; s/\./ /g'))
    if [ "${version[0]}" -gt "9" ] || ([ "${version[0]}" = "9" ] && [ "${version[1]}" -ge "3" ])
    then
	initdb -k -D "$masterdir" -U "$PGUSER"
    else
	initdb -D "$masterdir" -U "$PGUSER"
    fi
    cat >> "$masterdir/postgresql.conf" <<EOF
wal_level = hot_standby
hot_standby = on
max_wal_senders = 10
archive_mode = on
archive_command = 'cp -i %p $waldir/%f'
log_min_messages = debug1
port = $masterport
EOF
    cat >> "$masterdir/pg_hba.conf" <<EOF
local   replication     postgres                                trust
EOF
    :> "$masterlog"
    echo
fi
# start the master if not nunning
if [ ! -e "$masterdir/postmaster.pid" ]
then
    progress "Starting the master instance"
    pg_ctl -D "$masterdir" -w -l "$masterlog" start
    echo
fi

# clone the standby using pg_basebackup if not exists
if [ ! -e "$standbydir/PG_VERSION" ]
then
    progress "Creating the standby instance"
    mkdir -p "$standbydir"
    pg_basebackup -p "$masterport" -X stream -D "$standbydir"
    chmod 700 "$standbydir"
    cat >> "$standbydir/postgresql.conf" <<EOF
port = $standbyport
EOF
    cat > "$standbydir/recovery.conf" <<EOF
standby_mode = 'on'
primary_conninfo = 'port=$masterport user=postgres'
restore_command = 'cp -f $waldir/%f %p </dev/null'
EOF
    :> "$standbylog"
    echo
fi
# start the standby if not running
if [ ! -e "$standbydir/postmaster.pid" ]
then
    progress "Starting the standby instance"
    pg_ctl -D "$standbydir" -w -l "$standbylog" start
    echo
fi

# stop the backup instance if running
if [ -e "$backupdir/postmaster.pid" ]
then
    progress "Stopping esisting backup instance"
    pg_ctl -D "$backupdir" -w stop
    echo
fi

######################################################
### test the backup using the pgespresso extension ###
######################################################

if [ -n "$(which pgbench)" ]
then
    progress "Starting pgbench to generate some traffic"
    pgbench -i -p "$masterport" &> /dev/null
    pgbench -p "$masterport" -T 60 &> /dev/null &
    pgbenchpid=$!
    # on exit kill background pgbench
    trap '([ -n "$pgbenchpid" ] && kill "$pgbenchpid" && wait "$pgbenchpid") &> /dev/null || :' EXIT
    echo
else
    pgbenchpid=
fi

progress "Create the pgespresso extension (if not exists)"
psql -p "$masterport" -tAc "CREATE EXTENSION IF NOT EXISTS pgespresso;"
echo

# from now on we access only the standby
export PGPORT=$standbyport

# wait the pgespresso extension to be available on standby
while ! psql -tAc "\dx" | grep -q pgespresso
do
    sleep 1
done

progress "Starting pgespresso backup"
LABEL=$(psql -tAc "SELECT pgespresso_start_backup('test backup', true);")
echo

progress "Copy data"
rsync -a --delete-excluded \
      --exclude="postmaster.*" \
      --exclude="recovery.*" \
      --exclude="pg_xlog/*" \
      "$standbydir/" "$backupdir" \
|| [ $? -eq 24 ] # avoid failing if rsync reports vanished files

# always sync controldata as last file
rsync -a "$standbydir/global/pg_control" "$backupdir/global/pg_control"

echo

progress "Stop backup"
stop_segment=$(psql -tAc "SELECT pgespresso_stop_backup('$LABEL
');")
echo

progress "Generating the backup label"
cat > "$backupdir/backup_label" <<EOF
$LABEL
EOF
echo

progress "The backup label content is:"
echo
cat "$backupdir/backup_label" | sed 's/^/	/'
echo

# read the start segment from the backup_label
start_segment=$(awk -F '[ ()]+' '/START WAL/{print $6}' "$backupdir/backup_label")

progress "Wal file info:"
echo
echo "First required segment: $start_segment"
echo "Last required segment: $stop_segment"
echo

if [ -z "$pgbenchpid" ]
then
    # Avoid waiting for the current XLOG to be filled (no pgbench)
    psql -p "$masterport" -c 'SELECT pg_switch_xlog()';
fi

progress "Wait for the the required segment to be closed (on master)"
while [ ! -e "$waldir/$stop_segment" ]
do
    sleep 1
done
echo

if [ -n "$pgbenchpid" ]
then
    progress "Terminate background pgbench"
    kill $pgbenchpid
    wait $pgbenchpid &> /dev/null || :
    pgbenchpid=
    echo
fi

# change the port and enable full debug logging on the backup
cat >> "$backupdir/postgresql.conf" <<EOF
port = $backupport
log_min_messages = debug5
EOF

# create a srecovery.conf suitable for retrieving WAL segments
cat > "$backupdir/recovery.conf" <<EOF
restore_command = 'cp -f $waldir/%f %p </dev/null'
EOF

progress "Done. You can start the new backup using the following command:"
echo
progress "    pg_ctl -D '$backupdir' -l '$backuplog' start"
echo
progress "Once finished you can dispose the test environment calling:"
echo
progress "    $0 destroy"
echo
