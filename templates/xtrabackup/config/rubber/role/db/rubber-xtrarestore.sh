<%
  @path = "/mnt/db-backup-tools/rubber-xtrarestore.sh"
	@perms = 0755
	@backup = false
%>#!/bin/bash
# Variables
LOGFILE="/tmp/rubber-xtrarestore-log"
# Take the file from STDIN, write it into a real file, extract it, service mysql stop,
# then mkdir /mnt/mysql/data & /mnt/mysql/log (move old ones out of the way)
# then innobackupex --copy-back . in the extracted folder, then service mysql start
# Create a temporary folder
rm -rf /mnt/db_restore
mkdir -p /mnt/db_restore
# Write STDIN into file
cat > /mnt/db_restore/current.tar.gz
cd /mnt/db_restore
tar xzvf current.tar.gz
echo 'Stopping MySQL'
if [ -z "`service mysql stop | grep 'done'`" ] ; then
	echo "ERROR: Couldn't stop mysql daemon."
	exit 1
fi
rm -rf /mnt/mysql/old
mkdir -p /mnt/mysql/old
echo 'Moving Data/Log Directories to /old'
mv /mnt/mysql/data /mnt/mysql/log /mnt/mysql/old
mkdir /mnt/mysql/data /mnt/mysql/log
echo 'Copying back'
innobackupex --copy-back . 2> $LOGFILE
if [ -z "`tail -1 $LOGFILE | grep 'completed OK!'`" ] ; then
	echo "ERROR: Innobackupex couldn't copy back."
	exit 1
fi
chown -R mysql.mysql /mnt/mysql/data
chown -R mysql.mysql /mnt/mysql/log
echo 'Starting MySQL'
if [ -z "`service mysql start | grep 'done'`" ] ; then
	echo "ERROR: Couldn't start mysql daemon."
	exit 1
fi
echo 'Cleaning up'
rm -rf /mnt/mysql/old
rm -rf /mnt/db_restore
echo "Success."
exit 0