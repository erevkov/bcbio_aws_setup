#!/usr/bin/env bash

# script to edit the bcbio_system.yaml on the instance

MEMORY=$1
CORES=$2
BCBIO_SYSTEM_FILE=$3

sed -i -e "s/\<memory: 3G\>/memory: ${MEMORY}/g" \
       -e "s/\<cores: 16\>/cores: ${CORES}/g" ${BCBIO_SYSTEM_FILE}
