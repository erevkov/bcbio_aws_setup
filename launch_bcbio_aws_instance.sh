#!/usr/bin/env bash

# script to launch a single instance with selected parameters

set -o errexit  # make the script exit when a command fails
set -o pipefail # for pipe fails: exit status of the last command that threw a non-zero exit code is returned
set -o nounset # exit when the script tries to use undeclared variables
# for debugging use set -o xtrace
#set -o xtrace

BCBIO_TOOLS_PATH=$1
BCBIO_AV_ZONE=$2
VOLUME_NAME=$3
INSTANCE_TYPE=$4
SPOT_PRICE=$5

# preparing the system
${BCBIO_TOOLS_PATH}/bcbio_vm.py aws ansible ${BCBIO_AV_ZONE} --keypair # creating vpc, keypair

VOLUME_ID=`${BCBIO_TOOLS_PATH}/aws ec2 describe-volumes \
                                      --region ${BCBIO_AV_ZONE%?} \
                                      --filters Name=tag-key,Values="Name" Name=tag-value,Values="${VOLUME_NAME}" \
                                      --query 'Volumes[*].{ID:VolumeId}'` # get the volume id

. edit_launch_config.sh ${INSTANCE_TYPE} ${SPOT_PRICE} ${VOLUME_ID} # editing the config file
${BCBIO_TOOLS_PATH}/ansible-playbook -i 'localhost,' -vvv launch_aws.yaml # launch the instance

if [ $? -eq 0 ]; then
    echo "Done"
else
    echo "Something went wrong during the preparation/launch"
fi
