#!/bin/bash

# check if run as root
if [ $(id -u "$(whoami)") -ne 0 ]; then
	echo "SynoShutdownAfterSnapshotReplication needs to run as root!"
	exit 1
fi

# check if git is available
if ! which git > /dev/null; then
	echo "Git not found. Please install the package \"Git Server\"."
	exit 1
fi

# save today's date
today=$(date +'%Y-%m-%d')

# check if there was a boot since 06H00
# this prevents that the machine shuts down if it is booted manually
if grep "^${today}T\\(\\(0[6-9]\\)\\|\\([1-2][0-9]\\)\\).*\\[synoboot\\].*$" /var/log/messages > /dev/null; then
	echo "Terminating script because Synology was manually booted." 
	exit 0
fi

# check for arguments
if [ $# -eq 0 ]; then
	echo "No shared folders passed as arguments to SynoShutdownAfterSnapshotReplication!"
	exit 1
else
	echo "The following shared folders where passed: $*."
	sharedFolders=( "$@" )
fi

# self update run once daily
if [ ! -f /tmp/.synoShutdownAfterSnapshotReplicationUpdate ] || [ "${today}" != "$(date -r /tmp/.synoShutdownAfterSnapshotReplicationUpdate +'%Y-%m-%d')" ]; then
	echo "Checking for updates..."
	# touch file to indicate update has run once
	touch /tmp/.synoShutdownAfterSnapshotReplicationUpdate
	# change dir and update via git
	cd "$(dirname "$0")" || exit 1
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
else
	echo "Already checked for updates today."
fi

# define some vars
finishedReplications=0
nrSharedFolders=${#sharedFolders[@]}

# check logs for success message (apparently twice)
#for (( i=0; i<$nrSharedFolders; i++ )); do
#	matches=$(grep -o "^${today}.*Finish \\[drsite\\]:\\[sync\\] of plan.*\\/target \\[${sharedFolders[$i]}\\]: \\[success\\]\\.$" /var/log/synodr_replica_task.log | wc -l)
#	if [ $matches -ge 2 ]; then
#		((finishedReplications++))
#	fi
#done

# check the op_report if replication finished successfully
readarray replicationJobs <<< "$(find /usr/syno/etc/packages/SnapshotReplication/plan/ -type f -name op_report)"
for (( i=0; i<${#replicationJobs[@]}; i++ )); do
	# check if modification date is today
	modificationDate="$(date -r ${replicationJobs[$i]} +'%Y-%m-%d')"
	if [ "${today}" == "${modificationDate}" ]; then
		# parse report
		report="$(jq -r '.plan.target_id, .plan.role, .op_status, .percentage, .progress, .result.success' ${replicationJobs[$i]} | paste -s -d ',')"	
		# check for shared folders
		for (( j=0; j<nrSharedFolders; j++ )); do
			if [[ "${report}" =~ ^${sharedFolders[$j]}, ]]; then
				# check if job finished
				if [ "${report}" == "${sharedFolders[$j]},2,16,100,2,true" ]; then
					((finishedReplications++))
				fi
				break
			fi
		done
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
	if ps aux | grep -v "grep" | grep "btrfs receive"; then
		echo "There is still a replication ongoing."
		exit 0
	else
		echo "All snapshot replications have finished." 
		shutdown -h +5 "System going down in 5 minutes."
	fi
fi