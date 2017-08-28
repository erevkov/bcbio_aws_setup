#!/bin/bash

# edits the config file: project_vars.yaml

set -o errexit  # make the script exit when a command fails
set -o pipefail # for pipe fails: exit status of the last command that threw a non-zero exit code is returned
set -o nounset # exit when the script tries to use undeclared variables
set -o xtrace

INSTANCE_TYPE=$1
SPOT_PRICE=$2
VOLUME_ID=$3
PATH_TO_PROJECT_VARS=$4

sed -i -e "s/\(instance_type: \).*/\1${INSTANCE_TYPE}/" \
       -e "s/\(spot_price: \).*/\1${SPOT_PRICE}/" \
       -e "s/\(volume: \).*/\1${VOLUME_ID}/" ${PATH_TO_PROJECT_VARS}
