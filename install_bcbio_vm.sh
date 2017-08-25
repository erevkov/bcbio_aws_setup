#!/usr/bin/env bash

# installs bcbio_vm to an isolated environment in the CURRENT folder and configures aws

set -o errexit
set -o pipefail

wget https://repo.continuum.io/miniconda/Miniconda2-latest-Linux-x86_64.sh
bash Miniconda2-latest-Linux-x86_64.sh -b -p tools
./tools/bin/conda install -c conda-forge -c bioconda bcbio-nextgen-vm
./tools/bin/pip install ansible saws boto
./tools/bin/aws configure

echo "Installation is finished"

exit
