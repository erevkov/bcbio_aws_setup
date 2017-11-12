#!/usr/bin/env bash

# script to start the job on the AWS instance

set -o errexit  # make the script exit when a command fails
set -o pipefail # for pipe fails: exit status of the last command that threw a non-zero exit code is returned
set -o nounset # exit when the script tries to use undeclared variables
#set -o xtrace

INSTANCE_PUBLIC_DNS=$1
PROJECT_NAME=$2

# ssh to instance and check for necessary folders
ssh -o StrictHostKeyChecking=no ubuntu@${INSTANCE_PUBLIC_DNS} << EOF
  set -o xtrace
  # determine the instance parameters and edit bcbio config for better perfomance
  CORES="\$(nproc)" # amount of CPUs in instance
  MEMORY="\$(free -lm | grep Mem | awk '{print \$2}')" # amount of instance's RAM in MB
  MEMORY_PER_CORE="\$(echo | awk -v mem="\$MEMORY" -v cores="\$CORES" '{print int(mem/(cores*1024)+0.5)}')" # amount of instance's RAM in GB per core
  BCBIO_SYSTEM_FILE="/mnt/work/bcbio/galaxy/bcbio_system.yaml" # fixed location of bcbio system file

  # quickly (sed) edit the config file (assuming the standard confiuration)
  sed -i -e "s/\<memory: 3G\>/memory: \${MEMORY_PER_CORE}G/g" \
         -e "s/\<cores: 16\>/cores: \${CORES}/g" \${BCBIO_SYSTEM_FILE}

  cd /mnt/work/analysis/${PROJECT_NAME}/
  # launch bcbio_nextgen.py, redirect output and disattach the process from the user
  export PATH=/mnt/work/bcbio/bin:$PATH
  nohup /mnt/work/bcbio/bin/bcbio_nextgen.py /mnt/work/analysis/${PROJECT_NAME}/config/${PROJECT_NAME}_config.yaml -n \${CORES} --workdir /mnt/work/analysis/${PROJECT_NAME}/tmp &> bcbio.log & # redirect both stdout and stderr

EOF
