#!/usr/bin/env bash

# set of default variables for the system

# LOCAL MACHINE user parameters
BCBIO_TOOLS_PATH="$HOME/AWS_Setup/tools/bin" # path to bcbio tools directory
TMP_DIR="$HOME/AWS_Setup/TMP/" # directory to store launch configs and logs

# CLUSTER (e.g. aquila) parameters
CLUSTER_USERNAME="erevkov" # cluster username
CLUSTER_DOWNLOAD_METHOD="ionode.gis.a-star.edu.sg"

# default launch parameters / user-specified launch parameters
BCBIO_AV_ZONE="ap-southeast-1b" # bcbio availability zone
INSTANCE_TYPE="m4.2xlarge" # ec2 instance type
SPOT_IN_USE="no" # is spot instance used?
NO_ANALYSIS="False" # do not launch the analysis?
NO_MONITOR="False" # do not start the cron job?
SNAPSHOT_NAME="bcbio_clean_install_v.1.0.4" # name tag of the snapshot with bcbio installation
PROJECT_NAME="skandlab_project" # project name
INSTANCE_NAME="${PROJECT_NAME}_instance"
BCBIO_VOLUME_NAME="${PROJECT_NAME}_bcbio" # ebs volume name tag, contains bcbio installation
BCBIO_VOLUME_TYPE="magnetic" # ebs volume type, contains bcbio installation
BCBIO_VOLUME_SIZE="70" # size in GB (minimum=bcbio snapshot size)
ANALYSIS_VOLUME_NAME="${PROJECT_NAME}_analysis" # ebs volume name tag, is used as a working volume (/tmp directory)
ANALYSIS_VOLUME_TYPE="gp2" # ebs volume type, is used as a working volume (/tmp directory)
ANALYSIS_VOLUME_SIZE="150" # size in GB (minimum=bcbio snapshot size)
CRON_OUTPUT="$HOME/AWS_Setup/scripts/logs/cronjob.log" # where to output "echo" commands of the cron job

# optional parameters
SPOT_PRICE="null" # ec2 instance spot price
