#!/bin/bash

# check if run as root
if [ $(id -u "$(whoami)") -ne 0 ]; then
	echo "SynoShutdownAfterSnapshotReplication needs to run as root!"
	exit 1
fi

# check if git is available
which git > /dev/null
if [ $? -ne 0 ]; then
	echo "Git not found. Please install the package \"Git Server\"."
	exit 1
fi

# save today's date
today=$(date +'%Y-%m-%d')

# check if there was a boot since 06H00
# this prevents that the machine shuts down if it is booted manually
grep "^${today}T\(\(0[6-9]\)\|\([1-2][0-9]\)\).*\\[synoboot\\].*$" /var/log/messages > /dev/null
if [ $? -eq 0 ]; then
	echo "Terminating script because Synology was manually booted." 
	exit 0
fi

# check for arguments
if [ $# -eq 0 ]; then
	echo "No shared folders passed as arguments to SynoShutdownAfterSnapshotReplication!"
	exit 1
else
	echo "The following shared folders where passed: "$@"."
	sharedFolders=( "$@" )
fi

# self update run once daily
if [ ! -f /tmp/.synoShutdownAfterSnapshotReplicationUpdate ] || [ "${today}" != "$(date -r /tmp/.synoShutdownAfterSnapshotReplicationUpdate +'%Y-%m-%d')" ]; then
	echo "Running self update..."
	# touch file to indicate update has run once
	touch /tmp/.synoShutdownAfterSnapshotReplicationUpdate
	# change dir and update via git
	cd "$(dirname "$0")"
	git fetch
	commits=$(git rev-list HEAD...origin/master --count)
	if [ $commits -gt 0 ]; then
		echo "Found a new version, updating..."
		git pull --force
		echo "Executing new version..."
		exec "$(pwd -P)/synoShutdownAfterSnapshotReplication.sh" "$@"
		# In case executing new fails
		echo "Executing new version failed."
		exit 1
	fi
	echo "No updates available."
fi

# define some vars
finishedReplications=0
nrSharedFolders=${#sharedFolders[@]}

# check logs for success message (apparently twice)
for (( i=0; i<$nrSharedFolders; i++ )); do
	matches=$(grep -o "^${today}.*Finish \\[drsite\\]:\\[sync\\] of plan.*\\/target \\[${sharedFolders[$i]}\\]: \\[success\\]\\.$" /var/log/synodr_replica_task.log | wc -l)
	if [ $matches -ge 2 ]; then
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
	# double check if btrfs receive is still running
	ps aux | grep -v "grep" | grep "btrfs receive"
	if [ $? -eq 0 ]; then
		echo "There is still a replication ongoing."
	else
		echo "All snapshot replications have finished." 
		shutdown -h +5 "System going down in 5 minutes."
	fi
fi