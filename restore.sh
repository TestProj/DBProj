

export PATH=/home/app/.local/bin:$PATH

set +x

#export DEBUG=' --debug '
export DEBUG=''
export WAIT=90s

source ./aws_cred.txt

aws configure set aws_access_key_id ${aws_access_key_id}
aws configure set aws_secret_access_key ${aws_secret_access_key}
aws configure set aws_session_token ${aws_session_token}

rm ./aws_cred.txt


if [ ! "$SNAPSHOT_NAME" ]; then
    SNAPSHOT_NAME=$INSTANCE_NAME-snap-`date -d '-1 day' '+%Y%m%d'`
fi

if [ ! "$INSTANCE_BACKUP_NAME" ]; then
	INSTANCE_BACKUP_NAME=b-`date '+%Y%m%d'`		
fi

echo "Instance Name: " $INSTANCE_NAME
echo "Instance Backup: " $INSTANCE_BACKUP_NAME
echo "Delete Backup Instance: " $DELETE_BACKUP_INSTANCE
echo "Snapshot Name: " $SNAPSHOT_NAME


# Verify snapshot is available to restore, else exit with error
if [[ $(/home/app/.local/bin/aws rds describe-db-snapshots --db-snapshot-identifier $SNAPSHOT_NAME  --query DBSnapshots[0].Status $DEBUG) != "\"available\"" ]]; then
    echo "Snapshot NOT in available status to restore. Job will exit with error"
    exit 1
fi



# Rename Instance
echo "Renaming instance to backup"
aws rds modify-db-instance --db-instance-identifier $INSTANCE_NAME --new-db-instance-identifier $INSTANCE_BACKUP_NAME --apply-immediately $DEBUG
echo "Waiting for new instance to appear and available"
sleep 90s
while [[ $(aws rds describe-db-instances --db-instance-identifier $INSTANCE_BACKUP_NAME --query DBInstances[0].DBInstanceStatus $DEBUG) != "\"available\"" ]]
do
    sleep $WAIT
done


# Stop the renamed instance
echo "Stopping the instance"
aws rds stop-db-instance --db-instance-identifier $INSTANCE_BACKUP_NAME $DEBUG
sleep 60s


# Restore Snapshot
echo "Restoring snapshot"
aws rds restore-db-instance-from-db-snapshot --db-snapshot-identifier $SNAPSHOT_NAME --db-instance-identifier $INSTANCE_NAME --db-name $INSTANCE_NAME --db-subnet-group-name $DB_SUBNET_GROUP_NAME $DEBUG
echo "Waiting for instance to be available"
while [[ $(aws rds describe-db-instances --db-instance-identifier $INSTANCE_NAME --query DBInstances[0].DBInstanceStatus $DEBUG) != "\"available\"" ]]
do
    sleep $WAIT
done


# Changing DB Parameter Group Name and Security Group
echo "Changing DB Parameter Group Name and Security Group"
aws rds modify-db-instance --db-instance-identifier $INSTANCE_NAME --db-parameter-group-name $DB_PARAMETER_GROUP_NAME --vpc-security-group-ids $VPC_SECURITY_GROUP_IDS --apply-immediately $DEBUG
sleep 60
echo "Waiting for instance to be available again"
while [[ $(aws rds describe-db-instances --db-instance-identifier $INSTANCE_NAME --query DBInstances[0].DBInstanceStatus $DEBUG) != "\"available\"" ]]
do
    sleep $WAIT
done


# Rebooting the instance
echo "Rebooting the instance"
aws rds reboot-db-instance --db-instance-identifier $INSTANCE_NAME $DEBUG
sleep 60
echo "Waiting for instance to be available"
while [[ $(aws rds describe-db-instances --db-instance-identifier $INSTANCE_NAME --query DBInstances[0].DBInstanceStatus $DEBUG) != "\"available\"" ]]
do
    sleep $WAIT
done


# Deleting the backup if option selected and restored instance status is in available status
if [[ "$DELETE_BACKUP_INSTANCE" = true && $(aws rds describe-db-instances --db-instance-identifier $INSTANCE_NAME --query DBInstances[0].DBInstanceStatus $DEBUG) == "\"available\"" ]]; then

	sleep 30
	echo "Restored instance status: " $(aws rds describe-db-instances --db-instance-identifier $INSTANCE_NAME --query DBInstances[0].DBInstanceStatus $DEBUG)
    
    sleep 30s
    echo "Waiting for the backup instance to stop"
    while [[ $(aws rds describe-db-instances --db-instance-identifier $INSTANCE_BACKUP_NAME --query DBInstances[0].DBInstanceStatus $DEBUG) != "\"stopped\"" ]]
    do
        sleep $WAIT
    done

	sleep 30
	echo "Deleting backup instance"
	aws rds delete-db-instance --skip-final-snapshot --db-instance-identifier $INSTANCE_BACKUP_NAME $DEBUG
fi


set -x
