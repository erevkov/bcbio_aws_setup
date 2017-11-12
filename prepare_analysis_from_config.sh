#!/usr/bin/env bash

# script to parse the supplied config file and prepare the respective analysis on aws instance (make the config file, upload it to instance)
# Note: uploading data here to avoid passing FILES_TO_DOWLOAD array to the main script

set -o errexit  # make the script exit when a command fails
set -o pipefail # for pipe fails: exit status of the last command that threw a non-zero exit code is returned
set -o nounset # exit when the script tries to use undeclared variables
# for debugging use set -o xtrace
# set -o xtrace

CONFIG_FILE=$1
INSTANCE_DATA_PATH=$2
INSTANCE_UPLOAD_PATH=$3
# arguments for data uploading
PROJECT_NAME=$4
TMP_DIR=$5
INSTANCE_PUBLIC_DNS=$6
CLUSTER_USERNAME=$7
CLUSTER_DOWNLOAD_METHOD=$8

FILES_TO_DOWNLOAD=()

function SubstituteFilesPaths() {
  # function to substitute local files directories for new directories (aws in our case). Also writes all local files paths into an array (so they could be downloaded later)

  # count the number of times "pattern" line is present (1 yaml block = 1 occurrence of a "pattern" line)
  BLOCK_AMOUNT="$(awk "/$1/ {count++} END{print count}" ${CONFIG_FILE})"

  for (( block=1; block<=${BLOCK_AMOUNT}; block++ )); do

    # get "pattern" line for each block
    FILES_LINE=`awk "/$1/ {print}" ${CONFIG_FILE} | sed "s/.*$1//" | sed "${block}q;d"`
    # number of files in a csv-line
    FILES_AMOUNT=`echo "${FILES_LINE}" | awk '{FS=",|, "; print NF}'`
    # parse each "pattern" line
    for (( pos=1; pos<=${FILES_AMOUNT}; pos++ )); do
     FILE=`echo "${FILES_LINE}" | awk -F ',|, ' -v POSITION=${pos} '{print $POSITION}'`
     # grow array with all the files to download
     if [[ ! "${FILE}" == *"/mnt/work/analysis"* ]]; then # only add file if it doesn't look like aws instance path (i.e. doesn't contain /mnt/work/analysis path)
       FILES_TO_DOWNLOAD+=("${FILE}")
     fi
     # new path to file
     NEW_FILE=`echo "${FILE}" | sed "s|$(dirname "${FILE}")|$2|"`
     # substitute old path with new path in config file
     sed -i -e "s|"${FILE}"|${NEW_FILE}|" ${CONFIG_FILE}

    done

  done

}
# edit the config file (locally)
SubstituteFilesPaths "files: " ${INSTANCE_DATA_PATH}
SubstituteFilesPaths "variant_regions: " ${INSTANCE_DATA_PATH}
SubstituteFilesPaths "dir: " ${INSTANCE_UPLOAD_PATH}
printf "%s\n" "${FILES_TO_DOWNLOAD[@]}" > ${TMP_DIR}/analysis_configs/${PROJECT_NAME}_files.txt # save the files that we need to download (for later, just in case)

# upload the config to instance (if not uploaded already)
if [[ ! `head -1 ${TMP_DIR}/analysis_configs/${PROJECT_NAME}_config.yaml` == *"config edited and uploaded"* ]]; then
  rsync -avzPe ssh ${TMP_DIR}/analysis_configs/${PROJECT_NAME}_config.yaml ubuntu@${INSTANCE_PUBLIC_DNS}:/mnt/work/analysis/${PROJECT_NAME}/config/
  sed -i '1s|^|# config edited and uploaded to instance\!\n|' ${TMP_DIR}/analysis_configs/${PROJECT_NAME}_config.yaml
fi

# upload data to the instance (if not uploaded already)
if [[ ! `head -1 ${TMP_DIR}/analysis_configs/${PROJECT_NAME}_config.yaml` == *"data uploaded"* ]]; then
  # login to the cluster, transfer the data to ebs volume attached to the instance
  echo "Uploading data using ${CLUSTER_DOWNLOAD_METHOD} via ssh (if it is not already uploaded, rsync will check first) (may take some time)..."

  if [ ! ${#FILES_TO_DOWNLOAD[@]} -eq 0 ]; then # if array is empty then populate it
    readarray -t FILES_TO_DOWNLOAD < "${TMP_DIR}/analysis_configs/${PROJECT_NAME}_files.txt" # populate array with files to download
  fi

for DATA_PATH in "${FILES_TO_DOWNLOAD[@]}"; do
ssh -o StrictHostKeyChecking=no ${CLUSTER_USERNAME}@${CLUSTER_DOWNLOAD_METHOD} /bin/bash << EOF
  rsync --update -avzPe ssh ${DATA_PATH} ubuntu@${INSTANCE_PUBLIC_DNS}:/mnt/work/analysis/${PROJECT_NAME}/data/ # copies only new files to the data directory
EOF
done


else
  echo "Data seem to be already uploaded (as indicated in the ${PROJECT_NAME}_config.yaml)"

fi
