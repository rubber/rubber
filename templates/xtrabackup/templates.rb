if FileTest.exist?("config/rubber/rubber-percona.yml")
  gsub_file "config/rubber/rubber-percona.yml", /^db_backup_cmd.*$/, \
  "# Replaced by xtrabackup vulcanizer.\n# \\0\n" + \
  "# ** If you'd like to run differential backups, add '-d' to the command line below.\n" + \
  "db_backup_cmd: \"/mnt/db-backup-tools/rubber-xtrabackup.sh -u %user% -p %pass% -t /mnt/db_backups -b %backup_file%\"\n"
  gsub_file "config/rubber/rubber-percona.yml", /^db_restore_cmd.*$/, \
  "# Replaced by xtrabackup vulcanizer.\n# \\0\n" + \
  "db_restore_cmd: \"/mnt/db-backup-tools/rubber-xtrarestore.sh\"\n"
elsif FileTest.exist?("config/rubber/rubber-mysql.yml")
  gsub_file "config/rubber/rubber-mysql.yml", /^db_backup_cmd.*$/, \
  "# Replaced by xtrabackup vulcanizer.\n# \\0\n" + \
  "# ** If you'd like to run differential backups, add '-d' to the command line below.\n" + \
  "db_backup_cmd: \"/mnt/db-backup-tools/rubber-xtrabackup.sh -u %user% -p %pass% -t /mnt/db_backups -b %backup_file%\"\n"
  gsub_file "config/rubber/rubber-mysql.yml", /^db_restore_cmd.*$/, \
  "# Replaced by xtrabackup vulcanizer.\n# \\0\n" + \
  "db_restore_cmd: \"/mnt/db-backup-tools/rubber-xtrarestore.sh\"\n"
end