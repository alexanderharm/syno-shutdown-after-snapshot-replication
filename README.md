# SynoShutdownAfterSnapshotReplication

This scripts automatically shuts down a Synology NAS after a list of snapshot replication jobs have successfully completed.

#### 1. Notes

- All snapshot replications jobs need to start after midnight on the same day.
- The script will send warning messages if the tasks are not completed by 23:00.
- If the NAS is booted manually after 06:00 the script will ***not*** shut it down to allow for maintenance/administration/other tasks.
- The script will automatically update itself using `git`.

#### 2. Installation:

- install the package `Git Server` on your Synology NAS
- create a shared folder called e. g. `sysadmin` (you want to restrict access to administrators and hide it in the network)
- connect via `ssh` to the NAS and execute the following commands

```bash
# navigate to the shared folder
cd /volume1/sysadmin
# clone the following repo
git clone https://github.com/alexanderharm/syno-shutdown-after-snapshot-replication
```

- create a new task in the `Task Scheduler`

```
# Type
Scheduled task > User-defined script

# General
Task:    SynoShutdownAfterSnapshotReplication
User:    root
Enabled: yes

# Schedule
Run on the following days: Daily
First run time:            (00:00 or the full hour after the replication jobs start)
Frequency:                 Every 15 minute(s)
Last run time:				23:45

# Task Settings
Send run details by email:      yes
Email:                          (enter the appropriate address)
Send run details only when
  script terminates abnormally: yes
  
User-defined script: /volume1/sysadmin/syno-shutdown-after-snapshot-replication/synoShutdownAfterSnapshotReplication.sh "sharedFolder1" "sharedFolder2"
```
