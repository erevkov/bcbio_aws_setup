#!/usr/bin/env bash

# script to launch the bcbio analysis using aws instance

### launch command example (run in one line, division below is for readability)
#  bash launch_analysis.sh --config_path /mnt/projects/huangwt/wgs/bcbio_v1.0.4/aws_test/config/test_project.yaml --instance_type m4.2xlarge --spot_price 0.1  \
# --snapshot_name bcbio_clean_install_v.1.0.4  --bcbio_local_tools $HOME/AWS_Setup/tools/bin/ --availability_zone ap-southeast-1b --analysis_volume_size 200 --analysis_volume_type gp2 \
# --bcbio_volume_size 70 --bcbio_volume_type magnetic --project_name test_project --tmp_dir $HOME/AWS_Setup/TMP --cron_output $HOME/AWS_Setup/TMP/cronjob.log \
# --upload_path /mnt/projects/huangwt/wgs/bcbio_v1.0.4/aws_test/bcbio_final
###

set -o errexit  # make the script exit when a command fails
set -o pipefail # for pipe fails: exit status of the last command that threw a non-zero exit code is returned
set -o nounset # exit when the script tries to use undeclared variables
# for debugging use set -o xtrace
# set -o xtrace

# magic variables
__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__file="${__dir}/$(basename "${BASH_SOURCE[0]}")"
__base="$(basename ${__file})"

# some default parameters
USAGE="$(basename "$0") - script to launch a single aws instance using bcbio tools

##### Mandatory flags
| Flag | Description |
| ------ | ------ |
| --av_zone | string, availability zone to launch the instance in |
| --analysis_volume_size | integer, analysis volume size in GB |
| --analysis_volume_type | string, analysis [EBS volume type]. Provide additional --iops [integer] if launching io1 type |
| --iops | integer, analysis volume iops, *only used when the io1 is launched* |
| --bcbio_local_tools | local directory path, where are bcbio tools installed on your local machine |
| --bcbio_volume_type | integer, bcbio installation's [EBS volume type] |
| --config_path | cluster file path, .yaml file containing analysis configuration (with files paths relative to cluster!) |
| --cron_output | local file path, where to (periodically) write instance's log tails |
| --instance_type | string, AWS [EC2 instance type] |
| --tmp_dir | local directory path, where to store temporary files (instance configs, analysis configs, logs) |
| --snapshot_name | string, snapshot name tag of bcbio installation's EBS volume
| --project_name | string, name of the current project/analysis. Will be the prefix to instance's and volumes' name tags. *Should be different for each running analysis*
| --upload_path | cluster directory path, where to upload the data after the analysis is finished


##### Optional flags
| Flag | Description |
| ------ | ------ |
| --bcbio_volume_size | integer, bcbio installation's volume size in GB. Should be >= bcbio volume's snapshot size. Defaults to bcbio volume's snapshot size|
| --spot_price | integer, [AWS instance spot price]. Defaults to NULL (if not provided, will launch [on-demand instance]). |
| --noanalysis | do not start the analysis (only launch the instance, volumes and upload the data. For debugging purposes |
| --nomonitor | do not initiate monitoring cron jobs. For  debugging purposes |
| --help | print the help message |" # help message

source bcbio_aws_variables.sh # default variables declaration

# arguments for specifying the launch parameters (getopt because wanted to provide full-word flags)
OPTS=`getopt -o a:b:c:i:n:s:v:h --long analysis_volume_type:,analysis_volume_size:,availability_zone:,bcbio_local_tools:,bcbio_volume_type:,bcbio_volume_size:,config_path:,cron_output:,iops:,instance_type:,tmp_dir:,project_name:,spot_price:,snapshot_name:,upload_path:,nomonitor,noanalysis,help -n "${__base}" -- "$@"`
eval set -- "$OPTS"

while true; do
  case "$1" in
    --availability_zone) BCBIO_AV_ZONE=$2 ; shift 2 ;;
    --analysis_volume_size) ANALYSIS_VOLUME_SIZE=$2 ; shift 2 ;;
    --analysis_volume_type) ANALYSIS_VOLUME_TYPE=$2 ; shift 2 ;;
    --bcbio_local_tools) BCBIO_TOOLS_PATH=$2 ; shift 2 ;;
    --bcbio_volume_type) BCBIO_VOLUME_TYPE=$2 ; shift 2 ;;
    --bcbio_volume_size) BCBIO_VOLUME_SIZE=$2 ; shift 2 ;;
    --config_path) CLUSTER_CONFIG_PATH=$2 ; shift 2 ;;
    --cron_output) CRON_OUTPUT=$2 ; shift 2 ;;
    --iops) ANALYSIS_VOLUME_IOPS=$2 ; IOPS_IN_USE="True" ; shift 2 ;;
    --instance_type) INSTANCE_TYPE=$2 ; shift 2 ;;
    --tmp_dir) TMP_DIR=$2 ; shift 2 ;;
    --spot_price) SPOT_PRICE=$2 ; SPOT_IN_USE="True" ; shift 2 ;;
    --snapshot_name) SNAPSHOT_NAME=$2 ; shift 2 ;;
    --project_name) PROJECT_NAME=$2 ; INSTANCE_NAME="${PROJECT_NAME}_instance" ; BCBIO_VOLUME_NAME="${PROJECT_NAME}_bcbio" ; ANALYSIS_VOLUME_NAME="${PROJECT_NAME}_analysis" ; shift 2 ;;
    --noanalysis) NO_ANALYSIS="True" ; shift ;;
    --nomonitor) NO_MONITOR="True" ; shift ;;
    --upload_path) CLUSTER_UPLOAD_PATH=$2 ; shift 2 ;;
    --help) echo "${USAGE}" >&2 ; exit 1 ;;
    --) shift ; break ;;
  esac
done

# checking if the spot price is unreasonably high
if [[ "${SPOT_PRICE}" -gt "5" ]]; then
  echo "SPOT_PRICE is too high, not sure you want to bid that, exiting..."
  exit 1
fi

# checking if the config path is present: no sense in trying to start the analysis without it
if [[ -z ${CLUSTER_CONFIG_PATH+x} ]]; then
  echo "CLUSTER_CONFIG_PATH is unset, no analysis description, exiting"
  exit 1
else
  echo "CLUSTER_CONFIG_PATH is set to '${CLUSTER_CONFIG_PATH}'"
fi

# check if bcbio volume WITH THIS NAME is already present
BCBIO_VOLUME_ID=`${BCBIO_TOOLS_PATH}/aws ec2 describe-volumes \
                                      --region ${BCBIO_AV_ZONE%?} \
                                      --filters Name=tag-key,Values="Name" Name=tag-value,Values="${BCBIO_VOLUME_NAME}" \
                                      --query 'Volumes[*].{ID:VolumeId}'`
if [[ -z ${BCBIO_VOLUME_ID} ]]; then # if not present then
  # creating bcbio volume from snapshot with preinstalled bcbio
  # get the bcbio volume snapshot id
  echo "Bcbio volume with name ${BCBIO_VOLUME_NAME} is not present, creating a new one from snapshot..."
  SNAPSHOT_ID=`${BCBIO_TOOLS_PATH}/aws ec2 describe-snapshots \
                                        --region ${BCBIO_AV_ZONE%?} \
                                        --filters Name=tag-key,Values="Name" Name=tag-value,Values=${SNAPSHOT_NAME} \
                                        --query 'Snapshots[*].{ID:SnapshotId}'`

  # create working volume from the snapshot id
  ${BCBIO_TOOLS_PATH}/aws ec2 create-volume \
                              --snapshot-id ${SNAPSHOT_ID} \
                              --volume-type ${BCBIO_VOLUME_TYPE} \
                              --size ${BCBIO_VOLUME_SIZE} \
                              --availability-zone ${BCBIO_AV_ZONE} \
                              --tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value='${BCBIO_VOLUME_NAME}'}]'
  echo "Waiting until the bcbio volume is created..."
  sleep 20 # wait until the volume is initialized
  echo "Waiting until the bcbio volume is created... Done"
  BCBIO_VOLUME_ID=`${BCBIO_TOOLS_PATH}/aws ec2 describe-volumes \
                                        --region ${BCBIO_AV_ZONE%?} \
                                        --filters Name=tag-key,Values="Name" Name=tag-value,Values="${BCBIO_VOLUME_NAME}" \
                                        --query 'Volumes[*].{ID:VolumeId}'`

  echo "Bcbio volume with name ${BCBIO_VOLUME_NAME} is not present, creating a new one from snapshot... Done"
else
  echo "Bcbio volume with name ${BCBIO_VOLUME_NAME} is present, skipping creation"
fi

# check if analysis volume WITH THIS NAME is already present
ANALYSIS_VOLUME_ID=`${BCBIO_TOOLS_PATH}/aws ec2 describe-volumes \
                                      --region ${BCBIO_AV_ZONE%?} \
                                      --filters Name=tag-key,Values="Name" Name=tag-value,Values="${ANALYSIS_VOLUME_NAME}" \
                                      --query 'Volumes[*].{ID:VolumeId}'`

if [[ -z ${ANALYSIS_VOLUME_ID} ]]; then # if not present then
  # create analysis volume with user parameters
  echo "Analysis volume with name ${ANALYSIS_VOLUME_NAME} is not present, creating a new one with user specifications..."
  if [[ IOPS_IN_USE == "True" ]]; then
    echo "IOPS flag provided, creating volume with non-standard iops"
    ${BCBIO_TOOLS_PATH}/aws ec2 create-volume \
                                --volume-type ${ANALYSIS_VOLUME_TYPE} \
                                --iops ${IOPS} \
                                --size ${ANALYSIS_VOLUME_SIZE} \
                                --availability-zone ${BCBIO_AV_ZONE} \
                                --tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value='${ANALYSIS_VOLUME_NAME}'}]'
  else
    echo "IOPS flag not provided, creating volume with standard iops"
    ${BCBIO_TOOLS_PATH}/aws ec2 create-volume \
                                --volume-type ${ANALYSIS_VOLUME_TYPE} \
                                --size ${ANALYSIS_VOLUME_SIZE} \
                                --availability-zone ${BCBIO_AV_ZONE} \
                                --tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value='${ANALYSIS_VOLUME_NAME}'}]'
  fi
  echo "Waiting until the analysis volume is created..."
  sleep 20 # wait until the volume is initialized in the aws system, takes around 10-15 seconds
  echo "Waiting until the analysis volume is created... Done"
  ANALYSIS_VOLUME_ID=`${BCBIO_TOOLS_PATH}/aws ec2 describe-volumes \
                                        --region ${BCBIO_AV_ZONE%?} \
                                        --filters Name=tag-key,Values="Name" Name=tag-value,Values="${ANALYSIS_VOLUME_NAME}" \
                                        --query 'Volumes[*].{ID:VolumeId}'`
  echo "Analysis volume with name ${ANALYSIS_VOLUME_NAME} is not present, creating a new one with user specifications... Done"

else
  echo "Analysis volume with name ${ANALYSIS_VOLUME_NAME} is present, skipping creation"
fi

# creating aws structures: VPC, instance private/public keys, allowing port 22 access (doesn't create anything if the structures are already present). Creates project_vars.yaml in current dir
${BCBIO_TOOLS_PATH}/bcbio_vm.py aws ansible ${BCBIO_AV_ZONE} --keypair
mkdir -p ${TMP_DIR}/instances_configs/
mv project_vars.yaml ${TMP_DIR}/instances_configs/${PROJECT_NAME}_project_vars.yaml

# check if the instance with the same name is already present
INSTANCE_ID=`${BCBIO_TOOLS_PATH}/aws ec2 describe-instances \
                                                  --region=${BCBIO_AV_ZONE%?} \
                                                  --filters Name=tag-key,Values="Name" Name=tag-value,Values="${INSTANCE_NAME}" \
                                                            Name=instance-state-name,Values=running \
                                                  --query 'Reservations[*].Instances[*].{ID:InstanceId}'`
if [[ -z "${INSTANCE_ID}" ]]; then # if not present then
  # launch aws instance
  echo "Launching instance..."
  source launch_aws_instance.sh ${BCBIO_TOOLS_PATH} ${BCBIO_AV_ZONE} ${INSTANCE_TYPE} \
                                ${INSTANCE_NAME} ${SPOT_PRICE} ${BCBIO_VOLUME_ID} \
                                ${ANALYSIS_VOLUME_ID} ${TMP_DIR} ${PROJECT_NAME}
  echo "Launching instance...Done"
else
  echo "Instance named ${INSTANCE_NAME} already created, skipping creation"
fi

# get running instance's public dns
INSTANCE_PUBLIC_DNS=`${BCBIO_TOOLS_PATH}/aws ec2 describe-instances \
                                                  --region=${BCBIO_AV_ZONE%?} \
                                                  --filters Name=tag-key,Values="Name" Name=tag-value,Values="${INSTANCE_NAME}" \
                                                  --query 'Reservations[*].Instances[*].{ID:PublicDnsName}' | \
                                                  tr -d '[:space:]'`

# quickly check for necessary directories and create them if they're not present
echo "Creating necessary directories at the working volume..."
ssh -o StrictHostKeyChecking=no ubuntu@${INSTANCE_PUBLIC_DNS} /bin/bash << EOF
  if [[ ! -d /mnt/work/analysis/${PROJECT_NAME} ]]; then
    mkdir -p /mnt/work/analysis/${PROJECT_NAME}/tmp
    mkdir -p /mnt/work/analysis/${PROJECT_NAME}/bcbio_final
  fi
EOF
echo "Creating necessary directories at the working volume...Done"

# if config file doesn't exist, download it
mkdir -p ${TMP_DIR}/analysis_configs
if [[ ! -e ${TMP_DIR}/analysis_configs/${PROJECT_NAME}_config.yaml ]]; then
  rsync --update -chavzP --stats ${CLUSTER_USERNAME}@${CLUSTER_DOWNLOAD_METHOD}:/${CLUSTER_CONFIG_PATH} ${TMP_DIR}/analysis_configs/${PROJECT_NAME}_config.yaml
fi

# if data not uploaded, check config and the upload (see prepare_analysis_from_config.sh)
if [[ ! `head -1 ${TMP_DIR}/analysis_configs/${PROJECT_NAME}_config.yaml` == *"data_uploaded"* ]]; then
  # locally edit the the bcbio config for aws-bcbio + upload the data (in the same script)
  source prepare_analysis_from_config.sh ${TMP_DIR}/analysis_configs/${PROJECT_NAME}_config.yaml /mnt/work/analysis/${PROJECT_NAME}/data /mnt/work/analysis/${PROJECT_NAME}/ \
                                         ${PROJECT_NAME} ${TMP_DIR} ${INSTANCE_PUBLIC_DNS} ${CLUSTER_USERNAME} ${CLUSTER_DOWNLOAD_METHOD}
  if [[ $? -eq 0 ]]; then
      echo "Uploading data using ${CLUSTER_DOWNLOAD_METHOD} via ssh (if it is not already uploaded) (may take some time)... Done"
      sed -i '1s|^|# data uploaded to instance + config edited and uploaded to instance\!\n|' ${TMP_DIR}/analysis_configs/${PROJECT_NAME}_config.yaml # mark the data upload in the config (prepends 1st line)
  else
      echo "Something went wrong during the upload, data not uploaded, EXITING"
      exit 1
  fi
fi

# launch the analysis
if [[ ! "${NO_ANALYSIS}" == "True" ]]; then
  echo "Starting bcbio analysis..."
  source start_bcbio_pipeline.sh ${INSTANCE_PUBLIC_DNS} ${PROJECT_NAME}
else
  echo "--noanalysis flag provided, no analysis started"
fi

# setting up cron job to monitor the instance (if it doesn't exist already)
if [[ (-z `crontab -l | grep -q '${INSTANCE_NAME}'`) && (! "${NO_MONITOR}" == "True") ]]; then
  echo "Adding monitoring cron job for ${INSTANCE_NAME}..."
  mkdir -p ${TMP_DIR}/logs
  LOG_DIR=${TMP_DIR}/logs # store the instance logs here
  # launch the monitoring job running every 2 hours
  (crontab -l 2>/dev/null; echo "0 */2 * * * bash ${__dir}/monitor_instance.sh ${BCBIO_AV_ZONE} ${INSTANCE_NAME} ${BCBIO_VOLUME_ID} \
                                                                               ${ANALYSIS_VOLUME_ID} ${SPOT_IN_USE} ${LOG_DIR} \
                                                                               ${BCBIO_TOOLS_PATH} ${PROJECT_NAME} ${CLUSTER_UPLOAD_PATH} \
                                                                               ${CLUSTER_USERNAME} ${CLUSTER_DOWNLOAD_METHOD} --copy >> ${CRON_OUTPUT}") | crontab
  echo "Adding monitoring cron job for the ${INSTANCE_NAME}... Done"
else
  echo "Not adding monitoring cron job for ${INSTANCE_NAME}"
fi
