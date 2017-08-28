#!/usr/bin/env bash

# script to launch a single instance with selected parameters

set -o errexit  # make the script exit when a command fails
set -o pipefail # for pipe fails: exit status of the last command that threw a non-zero exit code is returned
set -o nounset # exit when the script tries to use undeclared variables
# for debugging use set -o xtrace
set -o xtrace

BCBIO_TOOLS_PATH=$1
BCBIO_AV_ZONE=$2
VOLUME_NAME=$3
INSTANCE_TYPE=$4
SPOT_PRICE=$5
VOLUME_ID=$6

sh edit_launch_config.sh ${INSTANCE_TYPE} ${SPOT_PRICE} ${VOLUME_ID} project_vars.yaml # editing the config file
${BCBIO_TOOLS_PATH}/ansible-playbook -i 'localhost,' -vvv launch_aws.yaml # launch the instance

#aws ec2 create-tags --resources vol-00df42a6 --tags Key=Name,Value=exome-validation
