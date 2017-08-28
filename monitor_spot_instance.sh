#!/usr/bin/env bash

# script to monitor running spot instance

set -o errexit  # make the script exit when a command fails
set -o pipefail # for pipe fails: exit status of the last command that threw a non-zero exit code is returned
set -o nounset # exit when the script tries to use undeclared variables
# for debugging use set -o xtrace
#set -o xtrace

source bcbio_aws_variables.sh # user-set variables

# get running instance's ip
INSTANCE_IP=`${BCBIO_TOOLS_PATH}/aws ec2 describe-instances \
                                                  --region=${BCBIO_AV_ZONE%?} \
                                                  --filters Name=tag-key,Values="Name" Name=tag-value,Values="${INSTANCE_NAME}" \
                                                  --query 'Reservations[*].Instances[*].{ID:PublicIpAddress}'`

watch -n5 CheckTermination ${INSTANCE_IP} # check if the instance is scheduled for termination and restart after termination

function CheckTermination {

  if curl -s http://$1/latest/meta-data/spot/termination-time | grep -q .*T.*Z ; then
    echo "Terminated, restarting..." ;
    sleep 2m
    sh launch_bcbio_aws_instance.sh ${BCBIO_TOOLS_PATH} ${BCBIO_AV_ZONE} ${VOLUME_NAME} ${INSTANCE_TYPE} ${SPOT_PRICE}
    echo "Instance restarted"
  fi

}
