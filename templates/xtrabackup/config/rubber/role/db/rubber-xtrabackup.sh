<%
  @path = "/mnt/db-backup-tools/rubber-xtrabackup.sh"
	@perms = 0755
	@backup = false
%>#!/bin/bash
# 
# Run innobackupex for databases, ensure it succeeded, and put file in place for S3 upload by Rubber.
# First, set up some variables.
INNOBACKUP="/usr/bin/innobackupex"
LOGFILE="/tmp/rubber-xtrabackup-log"
MEMORY="512M"
MYSQL="/usr/bin/mysql"
MYSQLADMIN="/usr/bin/mysqladmin"
# If you use MyISAM tables, comment this out or Bad Things will happen. Leave as-is if you use InnoDB.
NOLOCK="--no-lock"
# By default, don't use differential backups unless -d command line argument supplied.
DIFFERENTIALS=0
# The number of differential backups to perform before rotating into a new full backup
# NOTE: Ensure you have enough disk space to keep this amount of diffs on the volume
#       you supply via the -t (backup directory) option.
MAXDIFFS=24
# Some folks have empty passwords and won't supply one.
PASSWORD=""
# Have rubber include slave commands if we're on a slave.
<%  dbm_inst = rubber_instances.for_role('db', 'primary' => true).collect { |i| i.name }
 if dbm_inst.include?(rubber_env.host)
%>
# We're on a primary DB instance
SLAVECMD=""
<% else %>
# We're on a slave DB instance.
SLAVECMD="--safe-slave-backup --slave-info"
<% end %>

# Lets get our command line parameters
while getopts ":u:p:t:db:" opt; do
  case $opt in
    u)
      USERNAME="$OPTARG"
      ;;
		p)
			PASSWORD="$OPTARG"
			;;
		t)
			BACKUPDIR="$OPTARG"
			;;
		b)
			BACKUPFILE="$OPTARG"
			;;
		d)
			DIFFERENTIALS=1
			;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done

if [[ -z "$USERNAME" || -z "$BACKUPDIR" || -z "$BACKUPFILE" ]]; then
	echo "Required parameters missing. Please supply -u (database username), -t (backup directory) and -b (backup file)"
	exit 1
fi

differential_backup () {
	# This method will handle differential backups
	BASEDIR="$BACKUPDIR/diffs/base"
	
	if [ ! -d "$BASEDIR" ]; then
		echo "$BASEDIR does not exist. Running full base backup..."
		clean_base_backup
		echo "Success. Exiting."
		exit 0
	else
		if [ -f "$BACKUPDIR/diffs/diff-status" ]; then
			# Check current diff number
			DIFFNUM=`cat $BACKUPDIR/diffs/diff-status`
			# Increase diff number by one
			let "NEWDIFFNUM = $DIFFNUM + 1"
			if [ "$NEWDIFFNUM" -gt "$MAXDIFFS" ]; then
				echo "Exceeded maximum number of differentials. Performing new base backup."
				clean_base_backup
				echo "Success. Exiting."
				exit 0				
			else
				if [ "$NEWDIFFNUM" -eq "1" ]; then
					# First diff, let's set the base for the diff to $BASEDIR
					DIFFBASE=$BASEDIR
				else
					DIFFBASE="$BACKUPDIR/diffs/$DIFFNUM"
				fi
				# Run the backup
				incremental_backup $DIFFBASE "$BACKUPDIR/diffs/$NEWDIFFNUM"
				# Once this is verified we'll merge this incremental into the base folder
				prepare_backup $BASEDIR "$BACKUPDIR/diffs/$NEWDIFFNUM"
				# Then prepare the backup once again
				prepare_backup $BASEDIR
				# Finally, tar it all up.
				tar czf $BACKUPFILE -C $BASEDIR .
				# Update our diff status.
				echo $NEWDIFFNUM > "$BACKUPDIR/diffs/diff-status"
				echo "Success. exiting."
				exit 0
			fi
		else
			echo "Can't get backup status. Performing new base backup."
			clean_base_backup
			echo "Success. Exiting."
			exit 0
		fi
	fi
}			

full_backup () {
	# This method will handle full backups for further processing. 
	# This function requires a single argument, the destination folder of the backup.
	if [ -z "$1" ]; then
		echo "ERROR: full_backup() called without destination parameter. Exiting."
		exit 1
	fi
	echo "Running full backup into $1"
	$INNOBACKUP --no-timestamp --user=$USERNAME $PASSCMD $SLAVECMD $NOLOCK $1 2> $LOGFILE
	echo "Checking backup result..."
	check_backup_result
}

prepare_backup () {
	# This prepares the backups for immediate restore.
	# This function supports two arguments:
	# 1) The base folder (required)
	# 2) The incremental folder (optional)
	if [ -z "$1" ]; then
		echo "ERROR: prepare_backup() called without base folder. Exiting."
		exit 1
	fi
	if [ -z "$2" ]; then
		$INNOBACKUP --apply-log --redo-only $1 2> $LOGFILE
	else
		$INNOBACKUP --apply-log --redo-only $1 --incremental-dir=$2 2> $LOGFILE
	fi
	check_backup_result
}

clean_base_backup () {
	echo "Removing $BACKUPDIR/diffs to ensure clean start..."
	rm -rf "$BACKUPDIR/diffs"
	mkdir -p "$BACKUPDIR/diffs"
	ensure_destination_exists
	full_backup $BASEDIR
	prepare_backup $BASEDIR
	echo "Backup OK. Compressing backup..."
	tar czf $BACKUPFILE -C $BASEDIR .
	echo "Creating backup-status"
	echo 0 > "$BACKUPDIR/diffs/diff-status"
}

incremental_backup () {
	# This function requires two arguments:
	# 1) The base folder for the incremental
	# 2) The destination folder for the incremental
	if [[ -z "$1" || -z "$2" ]]; then
		echo "ERROR: incremental_backup() called without base or destination parameter. Exiting."
		exit 1
	fi
	echo "Running incremental backup with base at $1 into $2"
	$INNOBACKUP --no-timestamp --user=$USERNAME $PASSCMD $SLAVECMD $NOLOCK --incremental $2 --incremental-basedir=$1 2> $LOGFILE
	echo "Checking backup result..."
	check_backup_result
}

full_compressed_backup () {
	# This method will create a full backup and compress it into $BACKUPFILE in one step.
	# First remove the existing full backup, if any.
	rm -rf "$BACKUPDIR/full"
	ensure_destination_exists
	full_backup "$BACKUPDIR/full"
	echo "Checking backup result..."
	check_backup_result
	echo "Backup OK. Compressing backup..."
	tar czf $BACKUPFILE -C "$BACKUPDIR/full" .
	echo "Cleaning up"
	rm -rf "$BACKUPDIR/full"	
}

check_backup_result () {
	if [ -z "`tail -1 $LOGFILE | grep 'completed OK!'`" ] ; then
	 echo "ERROR: $INNOBACKUPEX failed:"
	 echo "----------------------------"
	 cat $LOGFILE
	 rm -f $LOGFILE
	 rm -f $BACKUPFILE
	 exit 1
	fi
}

ensure_destination_exists () {
	mkdir -p `dirname $BACKUPFILE`
}

echo "----------------------------------"
echo "Started innobackupex backup script"
echo "Start: `date`"
echo "----------------------------------"

if [ ! -x "$INNOBACKUP" ]; then
 echo "$INNOBACKUP does not exist. Ensure you have bootstrapped this instance and that the xtrabackup package is installed."
 exit 1
fi

# Only supply --password if password supplied.
if [ -z "$PASSWORD" ]; then
	PASSCMD=""
else
	PASSCMD="--password=$PASSWORD"
fi

if [ -z "`$MYSQLADMIN --user=$USERNAME $PASSCMD status | grep 'Uptime'`" ] ; then
 echo "ERROR: MySQL not running."
 exit 1
fi

if ! `echo 'exit' | $MYSQL -s --user=$USERNAME $PASSCMD` ; then
 echo "ERROR: Mysql username or password is incorrect"
 exit 1
fi

if [ ! -d "$BACKUPDIR" ]; then
	echo "$BACKUPDIR did not exist. Creating..."
	mkdir -p $BACKUPDIR
fi

if [ "$DIFFERENTIALS" -eq "1" ]; then
	echo "Running differential backup..."
	differential_backup
	echo "Success. Exiting."
	exit 0
else
	echo "Running full compressed backup..."
	full_compressed_backup
	echo "Success. Exiting."
	exit 0
fi