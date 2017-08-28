#!/usr/bin/env bash

# set of default variables for the system

# LOCAL MACHINE user parameters
BCBIO_TOOLS_PATH="$HOME/AWS_Setup/tools/bin" # path to bcbio tools directory
AWS_KEYS_PATH="$HOME/AWS_Setup/scripts/aws_keypairs/" # path to aws public/private keys

# CLUSTER (e.g. aquila) parameters
CLUSTER_USERNAME="erevkov" # cluster username
AWS_KEYS_CLUSTER_PATH="$HOME/aws_keypairs/" # path to aws public/private keys

# instance parameters
BCBIO_AV_ZONE="ap-southeast-1b" # bcbio availability zone
INSTANCE_TYPE="m4.2xlarge" # aws instance type
SPOT_PRICE="null" # aws instance spot price
SPOT_IN_USE="no" # is spot instance used?
VOLUME_NAME="skandlab_bcbio" # aws volume name
SNAPSHOT_NAME="bcbio*" # name of the snapshot with bcbio
INSTANCE_NAME="skandlab*" # aws instance name
PROJECT_NAME="skandlab_project" # project name
