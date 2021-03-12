#!/bin/bash
set -eo pipefail

HUB_DOCKER_USERNAME="king607267"

function initGitRepo() {
  #1 判断是否有对应的文件夹
  if [ ! -d "$1" ]; then
    git clone https://github.com/cmangos/"$1".git --recursive --depth=1 && cd "$1"
  else
    cd "$1" && git pull
  fi
}

function getRepoCurrentMasterCommit() {
  echo $(git log -1 --pretty=format:'%h')
}

function buildImage() {
  #构建
  DOCKER_FILE_NAME=""
  TARGET=""
  if [[ $1 =~ "-db" ]]; then
    DOCKER_FILE_NAME="Dockerfile-db"
  elif [[ $1 =~ "-server" ]]; then
    TARGET="--target mangosd"
    DOCKER_FILE_NAME="Dockerfile-server"
  else
    TARGET="--target realmd"
    DOCKER_FILE_NAME="Dockerfile-server"
  fi
  echo " docker build --build-arg CMANGOS_CORE=${1%-*} --add-host raw.githubusercontent.com:199.232.68.133 -t ${HUB_DOCKER_USERNAME}/cmangos-$1:$2 ${TARGET} -f ${DOCKER_FILE_NAME} ."
  docker build --build-arg CMANGOS_CORE=${1%-*} --add-host raw.githubusercontent.com:199.232.68.133 -t ${HUB_DOCKER_USERNAME}/cmangos-$1:$2 ${TARGET} -f ${DOCKER_FILE_NAME} .
}

declare -A DOCKER_REPO_NAMES
DOCKER_REPO_NAMES["mangos-classic"]="classic-server,classic-realmd"
DOCKER_REPO_NAMES["mangos-tbc"]="tbc-server,tbc-realmd"
DOCKER_REPO_NAMES["mangos-wotlk"]="wotlk-server,wotlk-realmd"
DOCKER_REPO_NAMES["classic-db"]="classic-db"
DOCKER_REPO_NAMES["tbc-db"]="tbc-db"
DOCKER_REPO_NAMES["wotlk-db"]="wotlk-db"

function autoBuildGitMaster() {
  for key in ${!DOCKER_REPO_NAMES[*]}; do
    cd ~/autoBuildContext
    initGitRepo ${key}
    sleep 8m
    CURRENT_MASTER_COMMIT=$(getRepoCurrentMasterCommit)
    #获取server和realmd的docker repo
    NAMES=($(echo ${DOCKER_REPO_NAMES[$key]} | sed "s/,/\n/g"))
    for NAME in ${NAMES[*]}; do
      cd ../file
      buildImage ${NAME} ${CURRENT_MASTER_COMMIT}
    done
  done
}

IMAGES=$(docker images --format "{{.Repository}}:{{.Tag}}" --filter=reference="king607267/*")

function modifyImageTag() {
  for key in ${IMAGES}; do
    REPO=${key%:*}
    if [ "${key#*:}" == "latest" ]; then
      continue
    fi
    echo "docker tag $key to ${REPO}:latest"
    docker tag $key $REPO:latest
  done
}

function imagePush() {
  docker login -u "$1" -p "$2" docker.io
  for key in ${IMAGES}; do
    echo "docker push $key to hub"
    docker push $key
  done
}

function imageDelete() {
  for i in $(docker images --filter "dangling=true" --format "{{.ID}}" && docker images --filter=reference="${HUB_DOCKER_USERNAME}/*:latest" --format "{{.ID}}"); do
    docker rmi -f $i
  done
  for i in $(docker images --filter=reference="${HUB_DOCKER_USERNAME}/*:*" --format "{{.ID}}"); do
    docker rmi -f $i
  done
}

function initBuildContext() {
  if [ ! -d ~/autoBuildContext ]; then
    mkdir ~/autoBuildContext
  fi

    if [ ! -d ~/autoBuildContext/file ]; then
    mkdir ~/autoBuildContext/file
  fi
  cp -f ../Dockerfile-* ~/autoBuildContext/file
}

start_time=$(date +%s)
initBuildContext
imageDelete
autoBuildGitMaster
sleep 2
modifyImageTag
imagePush "$@"
cost_time=$(($(date +%s) - start_time))
echo "build time is $((cost_time / 3600))hours $((cost_time % 3600 / 60))min $((cost_time % 3600 % 60))s"
