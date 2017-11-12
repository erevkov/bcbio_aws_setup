#!/usr/bin/env bash

# script to launch a single instance with defined parameters

set -o errexit  # make the script exit when a command fails
set -o pipefail # for pipe fails: exit status of the last command that threw a non-zero exit code is returned
set -o nounset # exit when the script tries to use undeclared variables
# for debugging use set -o xtrace
# set -o xtrace

BCBIO_TOOLS_PATH=$1
BCBIO_AV_ZONE=$2
INSTANCE_TYPE=$3
INSTANCE_NAME=$4
SPOT_PRICE=$5
BCBIO_VOLUME_ID=$6
ANALYSIS_VOLUME_ID=$7
TMP_DIR=$8
PROJECT_NAME=$9

bash edit_project_vars.sh ${INSTANCE_TYPE} ${INSTANCE_NAME} ${SPOT_PRICE} ${BCBIO_VOLUME_ID} ${ANALYSIS_VOLUME_ID} ${TMP_DIR}/instances_configs/${PROJECT_NAME}_project_vars.yaml # editing the launching config file
${BCBIO_TOOLS_PATH}/ansible-playbook -i 'localhost,' -vvv ${TMP_DIR}/launch_aws_extended.yaml --extra-vars="varfile=${TMP_DIR}/instances_configs/${PROJECT_NAME}_project_vars.yaml" # launch the instance using ansible
