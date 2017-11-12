# Bcbio-AWS automated analysis setup

The system depends heavily on a single-instance [Bcbio AWS Ansible setup], and it is strongly recommended to look through their AWS instruction first.

If neccessary, look for extensive description of this system and its parameters below.
## Launching the analysis
### Installing the tools
Create AWS IAM user (do not forget to save the private key). Install Bcbio, Ansible, Saws, Boto and dependencies into an isolated conda environment and setup with (installs in the current directory). Configure  AWS for your machine ( provide IAM user public and private keys).
```
wget https://repo.continuum.io/miniconda/Miniconda2-latest-Linux-x86_64.sh
bash Miniconda2-latest-Linux-x86_64.sh -b -p tools
./tools/bin/conda install -c conda-forge -c bioconda bcbio-nextgen-vm
./tools/bin/pip install ansible saws boto
./tools/bin/aws configure
```
bcbio-vm has an automated script to setup the AWS infrastructure. We do not need this  as much, but it is useful to create the keypair to allow our local machine to access the instance. To do this, run
```
./tools/bin/bcbio_vm.py aws ansible ap-southeast-1b --keypair
```
This will create *aws_keypairs* directory with the keypair (technically, this can also be done with AWS CLI or via web interface / console). Move the directory to the place where you want to store the keys.

*Important*: edit ~/.ssh/config to enable clean connections to AWS instances (substitute /path/to/aws_keypairs/ in config below)
```
Host *.amazonaws.com
  StrictHostKeyChecking no
  UserKnownHostsFile=/dev/null
  IdentityFile /path/to/aws_keypairs/bcbio
  IdentitiesOnly yes
  ControlPath ~/.ssh/%r@%h:%p
```
Next, make the keys available for a remote server where you store the data: move the keys to the server and *edit the .ssh config file for your user there in the same fashion*.

Pull the scripts and configs from repository, add the directory with the scripts to your $PATH:
```
export PATH=$PATH:/path/to/bcbio/scripts/
```
(or edit ~/.profile).

Edit **bcbio_variables.sh** to set certain default parameters (although almost all of them can be and should be overwritten by flags, see below).

Finally, make sure you have GNU SED and Bash >= 4.0.0 installed on your local machine.
### Starting the analysis
Before you start, think about

- The [Bcbio config file](http://bcbio-nextgen.readthedocs.io/en/latest/contents/configuration.html) containing your run parameters *on the local machine or cluster*. The script will automatically find the data to download from the cluster and upload it to the instance (e.g. see sample_bcbio_config.yaml in the repository). *Important*: make sure **upload: / dir:** directory path ends with **/bcbio_final**
- Local directory for storing the temporary files: logs, instance launch configs, etc
- Put **launch_aws_extended.yaml** in your **tmp_dir** (the system expects it to be there)
- Have a running **crontab** for your user. If there is no crontab, the monitoring script will fail
- Spot instance price, if running spot instances

Additionally, make sure you understand the arguments you have to provide to the script (see below).

Launch the analysis via *launch_analysis.sh*, for example:
```
bash launch_analysis.sh --config_path /mnt/projects/huangwt/wgs/bcbio_v1.0.4/aws_test/config/test_project.yaml --instance_type m4.2xlarge \
                        --spot_price 0.1  --snapshot_name bcbio_clean_install_v.1.0.4  --bcbio_local_tools $HOME/AWS_Setup/tools/bin/ --availability_zone ap-southeast-1b \
                        --analysis_volume_size 200 --analysis_volume_type gp2 --bcbio_volume_size 70 --bcbio_volume_type magnetic --project_name test_project \
                        --tmp_dir $HOME/AWS_Setup/TMP --cron_output $HOME/AWS_Setup/TMP/cronjob.log --upload_path /mnt/projects/huangwt/wgs/bcbio_v1.0.4/aws_test/bcbio_final
```

##### Starting multiple analyses
To start N new analyses: repeat previous step N times, changing at least **--project_name** flag (best to also change config files to avoid repetition). Probably, this could be done via another small script

### Arguments explanation
##### Notes
- Most arguments have default setting in **bcbio_aws_variables.sh**. Providing flags will overwrite the defaults
- Although technically arguments are divided into mandatory and optional, I recommend to familiarize yourself with most of them for better control and understanding of the process (see sample command above)
- If the argument is of wrong type for some reason, the system will most likely fail. However, practising common sense is still adviced
##### Mandatory flags
| Flag | Description |
| ------ | ------ |
| --av_zone [string] | availability zone to launch the instance in |
| --analysis_volume_size [integer] | analysis volume size in GB |
| --analysis_volume_type [string] | analysis [EBS volume type]. Provide additional --iops [integer] if launching io1 type |
| --iops [string] | analysis volume iops, *only used when the io1 is launched* |
| --bcbio_local_tools [local directory path] | where are bcbio tools installed on your local machine |
| --bcbio_volume_type [integer] | bcbio installation's [EBS volume type] |
| --config_path [cluster file path] | .yaml file containing analysis configuration (with files paths relative to cluster!) |
| --cron_output [local file path] | where to (periodically) write instance's log tails |
| --instance_type [string] | AWS [EC2 instance type] |
| --tmp_dir [local directory path] | where to store temporary files (instance configs, analysis configs, logs) |
| --snapshot_name [string] | snapshot name tag of bcbio installation's EBS volume
| --project_name [string] | name of the current project/analysis. Will be the prefix to instance's and volumes' name tags. *Should be different for each running analysis*
| --upload_path [cluster directory path] | where to upload the data after the analysis is finished


##### Optional flags
| Flag | Description |
| ------ | ------ |
| --bcbio_volume_size [integer] | bcbio installation's volume size in GB. Should be >= bcbio volume's snapshot size. Defaults to bcbio volume's snapshot size|
| --spot_price [float] | [AWS instance spot price] in USD per hour. Should be <= 5 (hardcoded). Defaults to NULL (if not provided, will launch [on-demand instance]). | 
| --noanalysis | do not start the analysis (only launch the instance, volumes and upload the data. For debugging purposes |
| --nomonitor | do not initiate monitoring cron jobs. For  debugging purposes |
| --help | print the help message |




### A quick step-by-step description of the system's internals
1. **launch_analysis.sh** is a wrapper around all other scripts, starts the setup
2. It sources **bcbio_variables.sh** for default variables
3. [AWS CLI] commands are used to create the volumes 
4. **bcbio-vm** creates aws structures if they are not present. Also creates **project_vars.yaml** file
5. **launch_aws_instance.sh** edits **project_vars.yaml** file with **edit_project_vars.sh** (to suit your analysis), moves it to **tmp_dir**. Using variables from **project_vars.yaml**, [Ansible] launches the instance (with the help of its own config, **launch_aws_extended.yaml**, connects the volumes to it and boots the OS
6. The config file is downloaded from the cluster to a local machine
7. **prepare_analysis_from_config.sh**  parses the config file, uploads it and respective files from cluster to the instance
8. **start_bcbio_pipeline.sh** silently starts the bcbio job on the instance (using **nohup ... &**)
9. Finally, **launch_analysis.sh** starts the local cron job with **monitor_instance.sh** (currently running every 2 hours)

The system is created with idempotence in mind: i.e. running the same command several times will not change the result (new instances and volumes will not be created, only missing data will be uploaded, no new cron job will be started, no new configs created, etc)

### Technical restrictions to keep in mind (also useful for debugging)
- Working volume is restored from a saved snapshot with preinstalled bcbio (so to fully update the system you also need to update the snapshot, see below for instruction)
- Snapshot, instance and volumes are *tied to their names*. Having more than 1 object with the same name will lead to fails
- Each system is being launched
- Data copying is done via **rsync** (so, for example, the system could be finetuned to download even hardlinked / broken data)
- The scripts assume the data and the config is located in the GIS cluster. Downloading is done via **ionode**.
- Bcbio is snapshotted with a limited collection of tools (bwa + GRCh37)
- Default limit for the amount of spot instances is 20 (the increase has to be requested from Amazon). There is also a limit on every type of on-demand instance
- If the spot price is too low, the script fails on timeout. If the price is too high, the script currently checks for hardcoded limit (see **launch_analysis.sh**)
- The script currently does not restart terminated instance by itself. Techically, it is only one command to repeat (the same it was launched with).


### Things to be improved further (suggestions)

1. Get profiling metrics to compare perfomance between different instances (e.g. memory usage, CPU usage, etc.)
2. Improve cron job setup. Suggestion: cron jobs should be started and managed based on a log file, that has relative information that can be used to access instances.
3. Automated instances retart in case of failure. Currently, if the instance fails and is terminated, it does not try to restart itself. 
Techical difficulty:  there are certain cituations when we do not want to restart the instance, or want to restart it with different parameters.
4. If possible, improve data transferring part (currently assumes data is on a specified cluster and copies it via rsync).
5. Make use of Toil + CWL in order to have a real cloud cluster setup (master node + worker nodes + distributed workflow). Currently in development by bcbio team.

### Updating the bcbio snapshot
To update the snapshot with bcbio installation you have to

1. Start the instance and attach a clean volume to it.
2. SSH to the instance.
3. Install bcbio like you would normally do on your local machine.
4. Terminate the instance, snapshot the volume (name it), terminate the volume.

This could be done manually, but also with the help of **ansible** and **bcbio-vm**. See [Bcbio AWS Ansible setup], it is a pretty extensive instruction

### Debugging the setup
Common advices:

1. After you install bcbio and its dependencies from the bioconda channels it is useful to update the tools via **bcbio_vm.py install --wrapper** && **bcbio_vm.py upgrade --wrapper**. The github version is sometimes different from what they have in bioconda.
2. Remember that most of bcbio commands are idempotent: they do not change the result when applied several times. For example, if you want to recreate the key pair with **bcbio_vm.py aws --keypair** you actually need to delete the old keys first or they won�t be changed.
3. http://www.yamllint.com/ - for checking yaml files formatting (it will often point to the 1st line - that could mean that something is wrong with syntax anywhere below).
4. During the upgrade it may be useful to upgrade references and tools (e.g. **bwa aligner: bcbio_nextgen.py upgrade --data --aligners bwa**).
5. If something is already launched in your placement group and you want to launch another aws item (e.g. cluster): The fix would be to run **bcbio_vm.py aws vpc --cluster yourotherclustername** so you get a placement group specific to that cluster instead of re-using bcbio_cluster_pg across multiple different clusters. 
6. Various SSH problems - if these are not fixed already, try checking [this github thread].

_Author's note_: I will not provide my full debugging log here for the sake of saving space and assuming that most if not all bugs/shortcomings I had to deal with are now fixed. However, if there still is a need, feel free to contact me.

[//]: # (These are reference links used in the body of this note and get stripped out when the markdown processor does its job. There is no need to format nicely because it shouldn't be seen. Thanks SO - http://stackoverflow.com/questions/4823468/store-comments-in-markdown-syntax)

   [Bcbio AWS Ansible setup]: <https://github.com/chapmanb/bcbio-nextgen/tree/master/scripts/ansible>
   [ebs volume type]: <http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/EBSVolumeTypes.html>
   [EC2 instance type]: <https://aws.amazon.com/ec2/instance-types/>
   [AWS instance spot price]: <https://aws.amazon.com/ec2/spot/pricing/>
   [on-demand instance]: <https://aws.amazon.com/ec2/pricing/on-demand/>
   [AWS CLI]: <https://aws.amazon.com/cli/>
   [Ansible]: <https://www.ansible.com/>
   [this github thread]: <https://github.com/chapmanb/bcbio-nextgen/issues/1929>


