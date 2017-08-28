#!/usr/bin/env bash

# script to start the job on the AWS instance

set -o errexit  # make the script exit when a command fails
set -o pipefail # for pipe fails: exit status of the last command that threw a non-zero exit code is returned
set -o nounset # exit when the script tries to use undeclared variables

INSTANCE_PUBLIC_DNS=$1
AWS_KEYS_PATH=$2


# check for necessary folders
ssh -o StrictHostKeyChecking=no -i ${AWS_KEYS_PATH}/bcbio ubuntu@${INSTANCE_PUBLIC_DNS} << EOF

  # edit bcbio config for better perfomance
  CORES=`nproc` # amount of CPUs in instance
  MEMORY=`free -lm | grep Mem | awk '{print int($2/1024 + 0.5)}'` # amount of instance's RAM in GiB
  BCBIO_SYSTEM_FILE="/mnt/work/bcbio/galaxy/bcbio_system.yaml"
  source edit_bcbio_system.sh ${MEMORY} ${CORES} ${BCBIO_SYSTEM_FILE}

   # submit job to bcbio and disattach the process from the user
  nohup bcbio_nextgen.py ../config/your-project.yaml -n ${CORES} & > bcbio_log.log

EOF
