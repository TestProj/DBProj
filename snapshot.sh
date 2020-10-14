export PATH=/home/app/.local/bin:$PATH

# download the aws cred and restore in below file
source ./aws_cred.txt

aws configure set aws_access_key_id ${aws_access_key_id}
aws configure set aws_secret_access_key ${aws_secret_access_key}
aws configure set aws_session_token ${aws_session_token}

rm ./aws_cred.txt

if [ ! "$SNAPSHOT_NAME" ]; then
	SNAPSHOT_NAME=$INSTANCE_NAME-snap-`date '+%Y%m%d'`		
fi

if [ ! "$PREVIOUS_SNAPSHOT_NAME" ]; then
    PREVIOUS_SNAPSHOT_NAME=$INSTANCE_NAME-snap-`date -d '-1 day' '+%Y%m%d'`
fi

# option in case you want to debug
#export DEBUG=' --debug '
export DEBUG=''

echo "Instance Name: " $INSTANCE_NAME
echo "Snapshot Name: " $SNAPSHOT_NAME
echo "Delete Previous Instance: " $DELETE_PREVIOUS_SNAPSHOT
echo "Previous Snapshot Name to Delete: " $PREVIOUS_SNAPSHOT_NAME

echo "Taking snapshot"
aws rds create-db-snapshot --db-instance-identifier $INSTANCE_NAME --db-snapshot-identifier $SNAPSHOT_NAME $DEBUG
echo "Waiting for the snapshot status to complete..."
sleep 90s
while [[ $(/home/app/.local/bin/aws rds describe-db-snapshots --db-snapshot-identifier $SNAPSHOT_NAME  --query DBSnapshots[0].Status $DEBUG) != "\"available\"" ]]
do
    sleep 90s
done


# Deleting the previous instance if option selected and current snapshot successful
if [[ "$DELETE_PREVIOUS_SNAPSHOT" = true && $(/home/app/.local/bin/aws rds describe-db-snapshots --db-snapshot-identifier $SNAPSHOT_NAME  --query DBSnapshots[0].Status $DEBUG) == "\"available\"" ]]; then

	sleep 30
	echo "Snapshot status: " $(/home/app/.local/bin/aws rds describe-db-snapshots --db-snapshot-identifier $SNAPSHOT_NAME  --query DBSnapshots[0].Status $DEBUG)

	sleep 30
	echo "Deleting previous snapshot"
	aws rds delete-db-snapshot --db-snapshot-identifier $PREVIOUS_SNAPSHOT_NAME $DEBUG
fi


set -x
