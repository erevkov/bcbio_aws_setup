#!/usr/bin/env bash

# script to submit jobs to the aws instance

set -o errexit  # make the script exit when a command fails
set -o pipefail # for pipe fails: exit status of the last command that threw a non-zero exit code is returned
set -o nounset # exit when the script tries to use undeclared variables

INSTANCE_PUBLIC_DNS=$1
AWS_KEYS_PATH=$2


# check for necessary folders
ssh -o StrictHostKeyChecking=no -i ${AWS_KEYS_PATH}/bcbio ubuntu@${INSTANCE_PUBLIC_DNS} << EOF
  source edit_bcbio_system.sh
   # submit job to bcbio and disattach the process from the user
  nohup bcbio_nextgen.py ../config/your-project.yaml -n `nproc` & > bcbio_log.log
EOF
