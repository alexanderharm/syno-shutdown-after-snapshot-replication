#!/bin/bash

today=$(date +'%Y-%m-%d')

# check if there was a boot since 06H00
# this prevents that the machine shuts down if it is booted manually
grep "^${today}T\(\(0[6-9]\)\|\([1-2][0-9]\)\).*\\[synoboot\\].*$" /var/log/messages > /dev/null
if [ $? -eq 0 ]; then
	exit 0
fi

# check for arguments
if [ $# -eq 0 ]; then
	echo "No shared folders passed as arguments to SynoShutdownAfterSnapshotReplication!"
	exit 1
else
  sharedFolders=( "$@" )
fi

# check if run as root
if [ $(id -u "$(whoami)") -ne 0 ]; then
	echo "SynoShutdownAfterSnapshotReplication needs to run as root!"
	exit 1
fi

# self update run once daily
if [ ! -f /tmp/.SynoShutdownAfterSnapshotReplicationUpdate ] || [ ${today} -ne $(date -r /tmp/.SynoShutdownAfterSnapshotReplicationUpdate +'%Y-%m-%d') ]; then
	# touch file to indicate update has run once
	touch /tmp/.SynoShutdownAfterSnapshotReplicationUpdate
	# change dir and update via git
	cd "$(dirname "$0")"
	git fetch
	commits=$(git rev-list HEAD...origin/master --count)
	if [ $commits -gt 0 ]; then
		echo "Found a new version, updating..."
		git pull --force
		echo "Executing new version..."
		exec "$0" "$@"
		# In case executing new fails
		echo "Executing new version failed."
		exit 1
	fi
fi

# define some vars
finishedReplications=0
nrSharedFolders=${#sharedFolders[@]}

# check logs for success message
for (( i=0; i<$nrSharedFolders; i++ )); do
	grep "^${today}.*\\/target \\[${sharedFolders[$i]}\\]: \\[success\\]\\.$" /var/log/synodr_replica_task.log > /dev/null
	if [ $? -eq 0 ]; then
		((finishedReplications++))
	fi
done

# test if replications have finished
if [ ${finishedReplications} -ne ${nrSharedFolders} ]; then
	# produce error message if not finished by 23H00
	if [ $(date +%H) -eq 23 ]; then
		echo "Only ${finishedReplications} of ${nrSharedFolders} snapshot replications have finished by $(date +%H:%M)."
		exit 2
	else
		echo "${finishedReplications} of ${nrSharedFolders} snapshot replications have finished."
		exit 0
	fi
else
	echo "All snapshot replications have finished." 
	shutdown -h +5 "System going down in 5 minutes."
fi