#!/usr/bin/env bash

# script to monitor running spot instance

set -o errexit  # make the script exit when a command fails
set -o pipefail # for pipe fails: exit status of the last command that threw a non-zero exit code is returned
set -o nounset # exit when the script tries to use undeclared variables
# for debugging use set -o xtrace
#set -o xtrace

function CheckSpotTermination {
  # check if the spot instance is scheduled for termination (based on instance status codes) and restart after termination
  if [[ ! -z `~/AWS_Setup/tools/bin/aws ec2 describe-spot-instance-requests \
                                         --filters Name=instance-id,Values=${INSTANCE_ID} \
                                         --query 'SpotInstanceRequests[*].{ID:Status}' \
                                          | grep 'Terminat*'` ]] ; then
    echo "Spot instance ${INSTANCE_NAME} is marked for termination (most likely due to a price change)" ;
  fi

}

function CheckProgressFromLog {
  # check the progress of the job
  if [[ `tail -1 ${LOG_FILE}` == *"Timing: finished"* ]]; then # read the last line of a file and see if it contains the important string

    echo "The job has finished. Uploading the bcbio_final contents to ${CLUSTER_UPLOAD_PATH}. Terminating the ${INSTANCE_NAME} instance, deleting its bcbio volume, deleting its analysis volume. Removing monitoring cron job. "
ssh -o StrictHostKeyChecking=no ${CLUSTER_USERNAME}@${DOWNLOAD_METHOD} /bin/bash << EOF
    rsync --exclude="*.bam.*" -avzPe ssh ubuntu@${INSTANCE_PUBLIC_DNS}:/mnt/work/analysis/${PROJECT_NAME}/bcbio_final/ ${CLUSTER_UPLOAD_PATH}/${PROJECT_NAME} # upload data excluding everything with *.bam in name
EOF
    ${BCBIO_TOOLS_PATH}/aws ec2 terminate-instances --instance-ids ${INSTANCE_ID} # terminate the instance
    sleep 30 # wait until the instance is terminated and the volumes are dissatached
    ${BCBIO_TOOLS_PATH}/aws ec2 delete-volume --volume-id ${BCBIO_VOLUME_ID} # delete bcbio volume
    ${BCBIO_TOOLS_PATH}/aws ec2 delete-volume --volume-id ${ANALYSIS_VOLUME_ID} # delete analysis volume
    crontab -l | grep -q '${INSTANCE_NAME}'  | crontab - # remove cron job

  elif [[ `tail -1 ${LOG_FILE}` == *"non-zero exit status"* ]]; then

    echo "Something went wrong, job teminated due to error, see log file. Terminating the ${INSTANCE_NAME} instance, deleting its bcbio volume. Leaving its analysis volume"
    ${BCBIO_TOOLS_PATH}/aws ec2 terminate-instances --instance-ids ${INSTANCE_ID} # terminate the instance
    sleep 30 # wait until the instance is terminated and the volumes are dissatached
    ${BCBIO_TOOLS_PATH}/aws ec2 delete-volume --volume-id ${BCBIO_VOLUME_ID} # delete bcbio volume

  elif [[ `tail -1 ${LOG_FILE}` == *"No such file"* ]]; then

    echo "No log files of instance with the name ${INSTANCE_NAME} exist in the ${LOG_DIR}"

  else
    echo "The ${INSTANCE_NAME}'s log reports `tail -1 ${LOG_FILE}`"

  fi

}

# magic variables
__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__file="${__dir}/$(basename "${BASH_SOURCE[0]}")"
__base="$(basename ${__file})"

BCBIO_AV_ZONE=$1
INSTANCE_NAME=$2
BCBIO_VOLUME_ID=$3
ANALYSIS_VOLUME_ID=$4
SPOT_IN_USE=$5
LOG_DIR=$6
BCBIO_TOOLS_PATH=$7
PROJECT_NAME=$8
CLUSTER_UPLOAD_PATH=$9
CLUSTER_USERNAME=${10}
DOWNLOAD_METHOD=${11}

# get running instance's id
INSTANCE_ID=`${BCBIO_TOOLS_PATH}/aws ec2 describe-instances \
                                                  --region=${BCBIO_AV_ZONE%?} \
                                                  --filters Name=tag-key,Values="Name" Name=tag-value,Values="${INSTANCE_NAME}" \
                                                  --query 'Reservations[*].Instances[*].{ID:InstanceId}'`
# get running instance's public dns
INSTANCE_PUBLIC_DNS=`${BCBIO_TOOLS_PATH}/aws ec2 describe-instances \
                                                  --region=${BCBIO_AV_ZONE%?} \
                                                  --filters Name=tag-key,Values="Name" Name=tag-value,Values="${INSTANCE_NAME}" \
                                                  --query 'Reservations[*].Instances[*].{ID:PublicDnsName}' | \
                                                  tr -d '[:space:]'`
# some optional parameters
OPTS=`getopt -o c --long copy -n "${__base}" -- "$@"`
eval set -- "$OPTS"

while true; do
  case "$1" in
    # use the option if you want to copy the log file from your instance to your local machine
    --copy) mkdir -p ${LOG_DIR} ;
            scp -o StrictHostKeyChecking=no ubuntu@${INSTANCE_PUBLIC_DNS}:/mnt/work/analysis/${PROJECT_NAME}/bcbio.log ${LOG_DIR}/${PROJECT_NAME}_bcbio.log ;
            shift ;;
    --) shift ; break ;;
  esac
done

LOG_FILE="${LOG_DIR}/${PROJECT_NAME}_bcbio.log"

# check for the job progress from the  log file
CheckProgressFromLog

# if we're using spot instance, check if it's scheduled for termination
if [[ ${SPOT_IN_USE} == "True" ]]; then
  CheckSpotTermination
fi
