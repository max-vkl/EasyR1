#!/bin/bash

# Usage: bash ./scripts/run-in-docker.sh [OPTIONS] [COMMAND]
# ---------------------
# Example for opening a console without GPUs: bash ./scripts/run-in-docker.sh bash
# Example for opening a console with GPUs 0,1,5,7: bash ./scripts/run-in-docker.sh -g 0,1,5,7 bash
# Example with GPUs a custom docker image and training script: bash ./scripts/run-in-docker.sh -g 0,1,2,3 -i my-cool/docker-image:latest python train.py ...
# Example running sweeps: bash scripts/run-in-docker.sh -g 2 "python src/gorillawatch/model/video_models/train_and_eval.py --sweep_run"
# ---------------------
# The current directory is mounted to /workspace in the docker container.
# We automatically detect W&B login credentials in the ~/.netrc file and pass them to the docker container. To store them, do wandb login once on the host machine.

# Default values
image="hiyouga/verl:ngc-th2.6.0-cu126-vllm0.8.4-flashinfer0.2.2-cxx11abi0"
command="bash"
gpus="none"

# set e <- why is this here? -> https://stackoverflow.com/questions/3474526/stop-on-first-error
set -e

# Check if the current directory is named "scripts"
current_directory=$(basename "$PWD")

if [ "$current_directory" == "scripts" ]; then
    echo "Error: This script should be called from the root of the project."
    echo "Example: bash ./scripts/run-in-docker.sh"
    exit 1
fi

# Function to parse the command line arguments
parse_arguments() {
    local in_command=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
        -g)
            shift
            gpus="$1"
            ;;
        -i)
            shift
            image="$1"
            ;;
        *)
            if [ "$in_command" = false ]; then
                command="$1"
            else
                command="${command} $1"

            fi
            in_command=true
            ;;
        esac
        shift
    done
    command="pip install -e . && ${command}"

}

# Call the function to parse arguments
parse_arguments "$@"

# Rest of your script
echo "image: $image"
echo "command: $command"
echo "gpus: $gpus"

# Look for WANDB_API_KEY
if [ -z "$WANDB_API_KEY" ]; then
    export WANDB_API_KEY=$(awk '/api.wandb.ai/{getline; getline; print $2}' $PWD/../.netrc)
    if [ -z "$WANDB_API_KEY" ]; then
        echo "WANDB_API_KEY not found"
    else
        echo "WANDB_API_KEY found in ~/.netrc"
    fi
else
    echo "WANDB_API_KEY found in environment"
fi

# Tested on chairserver w/ 4x A6000 - doesn't bring speedups
# # https://lightning.ai/docs/pytorch/stable/advanced/model_parallel.html#when-using-ddp-on-a-multi-node-cluster-set-nccl-parameters
# export NCCL_NSOCKS_PERTHREAD=4
# export NCCL_SOCKET_NTHREADS=2
#  --env NCCL_NSOCKS_PERTHREAD --env NCCL_SOCKET_NTHREADS \

# NOTE: --ipc=host for full RAM and CPU access or -m XXXG --cpus XX to control access to RAM and cpus
# You probably want to add addiitonal mounts to your homefolder, e.g. -v /home/username/data:/home/username/data
# IMPORTANT: Use -v /home/username/.cache:/home/mamba/.cache to mount your cache folder to the docker container. The username inside the container is "mamba".
# Other common mounts:  -v /scratch/username/:/scratch/username/ -v /home/username/data/:/home/username/data/
# Add -p 5678:5678 to expose port 5678 for remote debugging. But keep in mind that this will block the port for other docker users on the server, so you might have to choose a different one.

# --user $(id -u):$(id -g) \ # use root user instead
echo "${PWD}/src/gorillawatch"
docker run -it --ipc=host --network=host \
    -v "${PWD}:/workspaces/EasyR1" \
    -w /workspaces/EasyR1 \
    -v "${PWD}/../.netrc:/home/gorilla/.netrc:ro" \
    -v "${PWD}/../.cache:/home/gorilla/.cache:ro" \
    -v "/mnt/vast-gorilla:/workspaces/vast-gorilla:ro" \
    -v "/mnt/vast-gorilla/gorillawatch/data:/workspaces/write_mounts/output" \
    --user 0:0 \
    --env XDG_CACHE_HOME --env HF_DATASETS_CACHE --env WANDB_CACHE_DIR --env WANDB_DATA_DIR --env WANDB_API_KEY \
    --gpus=\"device=${gpus}\" \
    --name gwb-max-gpu0123-grpo_test \
    $image /bin/bash -c "${command}"

# print done to console
echo 'Done'
