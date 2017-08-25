#!/usr/bin/env bash

# script to run the whole analysis

set -o errexit  # make the script exit when a command fails
set -o pipefail # for pipe fails: exit status of the last command that threw a non-zero exit code is returned
set -o nounset # exit when the script tries to use undeclared variables
# for debugging use set -o xtrace
#set -o xtrace

# magic variables
__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__file="${__dir}/$(basename "${BASH_SOURCE[0]}")"
__base="$(basename ${__file})"

# some default parameters
USAGE="$(basename "$0") --script to launch a single aws instance with bcbio
Possible arguments (pass with no parameters to see the default option):
[--help] - help, print this message and exit
[--path] - specify path to bcbio/tools/bin
[--av_zone] - specify availability zone to launch the instance
[--instance_type] - specify aws instance type
[--volume] - specify volume NAME
[--data] - specify directory where to get the data from" # help message

source bcbio_aws_variables.sh # user-set variables

# arguments for specifying the run parameters
OPTS=`getopt --long path:,av_zone:,instance_type:,spot_price:,volume:,data:,help -n "${__base}" -- "$@"`
eval set -- "$OPTS"

while true; do
  case "$1" in
    --path)
      case "$2" in
        "") echo "path is ${BCBIO_TOOLS_PATH}, left default" >&2; shift 2 ;;
         *) BCBIO_TOOLS_PATH=$2 ; shift 2 ;;
      esac ;;
    --av_zone)
      case "$2" in
        "") echo "availability zone is ${BCBIO_AV_ZONE}, left default" >&2; shift 2 ;;
         *) BCBIO_AV_ZONE=$2 ; shift 2 ;;
      esac ;;
    --instance_type)
      case "$2" in
        "") echo "instance type is ${INSTANCE_TYPE}, left default" >&2; shift 2 ;;
         *) INSTANCE_TYPE=$2 ; shift 2 ;;
      esac ;;
    --spot_price)
      case "$2" in
        "") echo "spot price is ${SPOT_PRICE}, left default " >&2; shift 2 ;;
         *) SPOT_PRICE=$2 ; SPOT_IN_USE="yes"; shift 2 ;;
      esac ;;
    --volume)
      case "$2" in
        "") echo "volume is ${VOLUME_NAME}, left default " >&2; shift 2 ;;
         *) VOLUME=$2 ; shift 2 ;;
      esac ;;
    --data)
      case "$2" in
        "") echo "No path to data provided / nowhere to download the data from; exiting"; exit 1 ;;
         *) DATA_PATH=$2 ; shift 2 ;;
      esac ;;
    --help) echo "${USAGE}" >&2 ; exit 1 ;;
    --) shift; break ;;
  esac
done

# creating volume for the analysis from snapshot with preinstalled bcbio
# get the volume snapshot id
SNAPSHOT_ID=`${BCBIO_TOOLS_PATH}/aws ec2 describe-snapshots \
                                      --region ${BCBIO_AV_ZONE%?} \
                                      --filters Name=tag-key,Values="Name" Name=tag-value,Values="${SNAPSHOT_NAME}" \
                                      --query 'Snapshots[*].{ID:SnapshotId}'`

# create working volume from the snapshot id
${BCBIO_TOOLS_PATH}/aws ec2 create-volume \
                            --snapshot-id ${SNAPSHOT_ID} \
                            --size 300 \
                            --availability-zone ${BCBIO_AV_ZONE}

# launch the aws instance
echo "Launching instance..."
source launch_bcbio_aws_instance.sh ${BCBIO_TOOLS_PATH} ${BCBIO_AV_ZONE} ${VOLUME_NAME} ${INSTANCE_TYPE} ${SPOT_PRICE}
if [ $? -eq 0 ]; then
    echo "Launching instance... Done"
else
    echo "Something went wrong during the launch, instance not launched"
fi

# get running instance's public dns
INSTANCE_PUBLIC_DNS=`${BCBIO_TOOLS_PATH}/aws ec2 describe-instances \
                                                  --region=${BCBIO_AV_ZONE%?} \
                                                  --filters Name=tag-key,Values="Name" Name=tag-value,Values="${INSTANCE_NAME}" \
                                                  --query 'Reservations[*].Instances[*].{ID:PublicDnsName}'`

# check for necessary folders and create them if they're not present
echo "Creating necessary folders in the working volume"
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

# upload (copying) the data to the working volume
echo "Uploading data..."
scp -o StrictHostKeyChecking=no -i ${AWS_KEYS_PATH}/bcbio ${DATA_PATH} ubuntu@${INSTANCE_PUBLIC_DNS}:/mnt/work/
if [ $? -eq 0 ]; then
    echo echo "Uploading data... Done"
else
    echo "Something went wrong during the upload, data not uploaded"
fi

# launching the analysis
source submit_bcbio_job.sh ${INSTANCE_PUBLIC_DNS} ${AWS_KEYS_PATH}

# enable monitoring if the spot instance is in use
if [ ${SPOT_IN_USE} -eq "yes" ]; then
  # script to enable monitoring on the instance
  source monitor_spot_instance.sh
fi

# terminate instance after the job ia finished

#TODO
# 1) Finish the submitting script
