#!/bin/bash

# edits the config file automatically created by bcbio_vm.py: project_vars.yaml

set -o errexit  # make the script exit when a command fails
set -o pipefail # for pipe fails: exit status of the last command that threw a non-zero exit code is returned
set -o nounset # exit when the script tries to use undeclared variables
#set -o xtrace

INSTANCE_TYPE=$1
INSTANCE_NAME=$2
SPOT_PRICE=$3
BCBIO_VOLUME_ID=$4
ANALYSIS_VOLUME_ID=$5
PATH_TO_PROJECT_VARS=$6

sed -i '/volume:/d' ${PATH_TO_PROJECT_VARS} # delete "volume" line from the config (if present)

# if they do not exist, add several lines used in launch_aws.yaml later
grep -qF "instance_name: " "${PATH_TO_PROJECT_VARS}" || echo "instance_name: " >> "${PATH_TO_PROJECT_VARS}"
grep -qF "bcbio_volume: " "${PATH_TO_PROJECT_VARS}" || echo "bcbio_volume: " >> "${PATH_TO_PROJECT_VARS}"
grep -qF "analysis_volume: " "${PATH_TO_PROJECT_VARS}" || echo "analysis_volume: "  >> "${PATH_TO_PROJECT_VARS}"

# edit respective parameters
sed -i -e "s/\(instance_type: \).*/\1${INSTANCE_TYPE}/" \
       -e "s/\(instance_name: \).*/\1${INSTANCE_NAME}/" \
       -e "s/\(spot_price: \).*/\1${SPOT_PRICE}/" \
       -e "s/\(bcbio_volume: \).*/\1${BCBIO_VOLUME_ID}/" \
       -e "s/\(analysis_volume: \).*/\1${ANALYSIS_VOLUME_ID}/" ${PATH_TO_PROJECT_VARS}
