#!/usr/bin/env bash

# script to run the whole analysis

set -o errexit  # make the script exit when a command fails
set -o pipefail # for pipe fails: exit status of the last command that threw a non-zero exit code is returned
set -o nounset # exit when the script tries to use undeclared variables
# for debugging use set -o xtrace
set -o xtrace

# magic variables
__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__file="${__dir}/$(basename "${BASH_SOURCE[0]}")"
__base="$(basename ${__file})"

# some default parameters
USAGE="$(basename "$0") --script to launch a single aws instance with bcbio
Possible arguments (pass with no parameters to see the default option):
[--help] - help, print this message and exit
[--bcbio_tools] - specify path to bcbio/tools/bin
[--av_zone] - specify availability zone to launch the instance
[--instance_type] - specify aws instance type
[--snap_name] - specify volume NAME
[--data] - specify directory where to get the data from" # help message

source bcbio_aws_variables.sh # user-set variables

# arguments for specifying the run parameters (getopt because wanted to provide full-word flags)
OPTS=`getopt -o b:a:i:s:n:d:h --long bcbio_tools:,av_zone:,instance_type:,spot_price:,snap_name:,data:,help -n "${__base}" -- "$@"`
eval set -- "$OPTS"

while true; do
  case "$1" in
    --bcbio_tools) BCBIO_TOOLS_PATH=$2 ; shift 2 ;;
    --av_zone) BCBIO_AV_ZONE=$2 ; shift 2 ;;
    --instance_type) INSTANCE_TYPE=$2 ; shift 2 ;;
    --spot_price) SPOT_PRICE=$2 ; SPOT_IN_USE="yes"; shift 2 ;;
    --snap_name) SNAPSHOT_NAME=$2 ; shift 2 ;;
    --data) DATA_PATH=$2 ; shift 2 ;;
    --help) echo "${USAGE}" >&2 ; exit 1 ;;
    --) shift; break ;;
  esac
done

# checking if the data path argument is present
if [ -z ${DATA_PATH+x} ]; then
  echo "DATA_PATH is unset, no input data, exiting"; exit 1
else
  echo "DATA_PATH is set to '${DATA_PATH}'"
fi

# check if the volume is already present
VOLUME_ID=`${BCBIO_TOOLS_PATH}/aws ec2 describe-volumes \
                                      --region ${BCBIO_AV_ZONE%?} \
                                      --filters Name=tag-key,Values="Name" Name=tag-value,Values="${VOLUME_NAME}" \
                                      --query 'Volumes[*].{ID:VolumeId}'`
if [ -z "${VOLUME_ID}" ]; then
  # creating volume for the analysis from snapshot with preinstalled bcbio
  # get the volume snapshot id
  echo "Volume is not present, creating from snapshot..."
  SNAPSHOT_ID=`${BCBIO_TOOLS_PATH}/aws ec2 describe-snapshots \
                                        --region ${BCBIO_AV_ZONE%?} \
                                        --filters Name=tag-key,Values="Name" Name=tag-value,Values="${SNAPSHOT_NAME}" \
                                        --query 'Snapshots[*].{ID:SnapshotId}'`

  # create working volume from the snapshot id
  ${BCBIO_TOOLS_PATH}/aws ec2 create-volume \
                              --snapshot-id ${SNAPSHOT_ID} \
                              --volume-type gp2 \
                              --size 300 \
                              --availability-zone ${BCBIO_AV_ZONE} \
                              --tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value='${VOLUME_NAME}'}]'
  sleep 30 # wait until the volume is intialized
  VOLUME_ID=`${BCBIO_TOOLS_PATH}/aws ec2 describe-volumes \
                                        --region ${BCBIO_AV_ZONE%?} \
                                        --filters Name=tag-key,Values="Name" Name=tag-value,Values="${VOLUME_NAME}" \
                                        --query 'Volumes[*].{ID:VolumeId}'`

  echo "Volume is not present, creating from snapshot... Done"

else
  echo "Volume is present, skipping creation"
fi

# launch the aws instance
${BCBIO_TOOLS_PATH}/bcbio_vm.py aws ansible ${BCBIO_AV_ZONE} --keypair # creating vpc, keypair
echo "Launching instance..."
sh launch_bcbio_aws_instance.sh ${BCBIO_TOOLS_PATH} ${BCBIO_AV_ZONE} ${VOLUME_NAME} ${INSTANCE_TYPE} ${SPOT_PRICE} ${VOLUME_ID}

# get running instance's public dns
sleep 60 # wait until the instance is intialized
INSTANCE_PUBLIC_DNS=`${BCBIO_TOOLS_PATH}/aws ec2 describe-instances \
                                                  --region=${BCBIO_AV_ZONE%?} \
                                                  --filters Name=tag-key,Values="Name" Name=tag-value,Values="${INSTANCE_NAME}" \
                                                  --query 'Reservations[*].Instances[*].{ID:PublicDnsName}'`
# check for necessary folders and create them if they're not present
echo "Creating necessary folders at the working volume..."
ssh -o StrictHostKeyChecking=no -i ${AWS_KEYS_PATH}/bcbio ubuntu@${INSTANCE_PUBLIC_DNS} << EOF
  if [ ! -d /mnt/work/${PROJECT_NAME} ]; then
    mkdir -p ${PROJECT_NAME}
    mkdir -p ${PROJECT_NAME}/tmp
    mkdir -p ${PROJECT_NAME}/data
    mkdir -p ${PROJECT_NAME}/config
    mkdir -p ${PROJECT_NAME}/bcbio_final
  fi
  cd
EOF
echo "Creating necessary folders at the working volume...Done"

exit

# upload (copying) the data to the working volume
echo "Uploading data...May take some time..."
scp -o StrictHostKeyChecking=no -i ${AWS_KEYS_PATH}/bcbio ${DATA_PATH} ubuntu@${INSTANCE_PUBLIC_DNS}:/mnt/work/${PROJECT_NAME}/data/
if [ $? -eq 0 ]; then
    echo "Uploading data... Done"
else
    echo "Something went wrong during the upload, data not uploaded"
fi

# launching the analysis
source submit_bcbio_job.sh ${INSTANCE_PUBLIC_DNS} ${AWS_KEYS_PATH}

# enable monitoring if the spot instance is in use
if [ ${SPOT_IN_USE} -eq "yes" ]; then
  # script to enable monitoring on the instance
  sh monitor_spot_instance.sh
fi

# terminate instance after the job is finished


#TODO
# 1) Rewrite getting instance_public_dns part
