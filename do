#!/bin/bash

set -e

# find the nearest Dockerfile up the tree
Dockerfile_dir=$(pwd)
while [[ "$Dockerfile_dir" != "/" ]]; do
	if [[ -f "$Dockerfile_dir/Dockerfile" ]]; then
		break
	else
		Dockerfile_dir=$(dirname "$Dockerfile_dir")
	fi
done

if [[ "$Dockerfile_dir" == "/" ]]; then
	echo >&2 "$0: could not find Dockerfile anywhere up this tree"
	exit 1
fi

base_dir=$(readlink -f $Dockerfile_dir)
do_dir=$base_dir/.do

# find where we are relative to $base_dir
# e.g. if $base_dir is "/tmp/" and the current working-dir is "/tmp/a"
#      then we want to get just "a"
abs_wd=$(readlink -f $(pwd))
rel_wd=$(python -c "import os.path; print os.path.relpath(\"$abs_wd\", \"$base_dir\")")

# build the command to run inside the docker container
cmd="cd $rel_wd"
if [[ "$#" -ne 0 ]]; then
	cmd="$cmd && $*"
fi

# find out the current user id
user_id=$(id -u)

# create $do_dir if necessary
mkdir -p $do_dir

# run `docker build` if necessary
if [[ -f $do_dir/image_name ]]; then
	image_name=$(cat $do_dir/image_name)
else
	cur_dir_name=$(basename $(dirname $(readlink -f $0)))
	unique_id=$(date | md5sum | awk '{print $1}')
	image_name=$cur_dir_name-$unique_id
	echo $image_name > $do_dir/image_name
	cd $base_dir
	docker build -t $image_name .
	cd -
fi

# abort if the docker image does not have
#    ENTRYPOINT ["/bin/sh", "-c"]
if [[ '{[/bin/sh -c]}' != "$(docker inspect -f '{{.Config.Entrypoint}}' $image_name)" ]]; then
	echo >&2 "$0: Dockerfile ENTRYPOINT must be set to: [\"/bin/sh\", \"-c\"]. aborting"
	exit 1
fi

docker run --rm \
           -it \
           -u $user_id \
           -v $base_dir:/workspace \
           $image_name \
           "$cmd"

