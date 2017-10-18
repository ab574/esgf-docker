#!/bin/bash

################################# SETTINGS #####################################

readonly BASE_DIR_PATH="$(pwd)"
SCRIPT_PARENT_DIR_PATH="$(dirname $0)"; cd "${SCRIPT_PARENT_DIR_PATH}"
readonly SCRIPT_PARENT_DIR_PATH="$(pwd)" ; cd "${BASE_DIR_PATH}"

source "${SCRIPT_PARENT_DIR_PATH}/common"

readonly DEFAULT_NB_NODES=2
readonly NODE_NAME_PREFIX='node'
readonly DEFAULT_VM_DRIVER='virtualbox'
readonly DEFAULT_SWARM_PORT=2377

set -u

################################ FUNCTIONS #####################################

function usage
{
  echo -e "usage:\n\
  \n${SCRIPT_NAME}\
  \n-d | --driver NAME the virtual infrastructure driver name\
  \n-n | --num-node INT the number of nodes (>0)\
  \n-a | --driver-args STRING arguments for the driver\
  \n-h | --help : print usage"
}

############################ CONTROL VARIABLES #################################

nb_nodes=${DEFAULT_NB_NODES}
vm_driver="${DEFAULT_VM_DRIVER}"
driver_args=''

################################## MAIN ########################################

params="$(getopt -o n:d:a:h -l driver:,num-node:,driver-args:,help --name "$(basename "$0")" -- "$@")"

if [ ${?} -ne 0 ]
then
    usage
    exit ${SETTINGS_ERROR}
fi

eval set -- "$params"
unset params

while true; do
  case $1 in
    -d|--driver)
      case "${2}" in
        "") echo "#### missing value. Abort ####"; exit ${SETTINGS_ERROR} ;;
        *)  vm_driver="${2}" ; shift 2 ;;
      esac ;;
    -n|--num-node)
      case "${2}" in
        "") echo "#### missing value. Abort ####"; exit ${SETTINGS_ERROR} ;;
        *)  nb_nodes="${2}" ; shift 2 ;;
      esac ;;
    -a|--driver-args)
      case "${2}" in
        "") echo "#### missing value. Abort ####"; exit ${SETTINGS_ERROR} ;;
        *)  driver_args="${2}" ; shift 2 ;;
      esac ;;
    -h|--help)
      usage
      exit ${SUCCESS_CODE}
      ;;
    --)
      shift
      break
      ;;
    *)
      usage
      echo "#### abort ####"
      exit ${SETTINGS_ERROR}
      ;;
  esac
done

if [[ -z "${vm_driver}" ]]; then
  echo "## you must give an driver name ! ##"
  usage
  echo "#### abort ####"
  exit ${SETTINGS_ERROR}
fi

if [ ${nb_nodes} -lt 1 ]; then
  echo "#### the number of nodes must be > 0 ####"
  exit ${SETTINGS_ERROR}
fi

readonly node_max_index=$(( ${nb_nodes}-1 ))

echo "> create up to ${nb_nodes} nodes"

for node_index in `seq 0 ${node_max_index}`;
do
  node_names[${node_index}]="${NODE_NAME_PREFIX}${node_index}"
  echo "  > creating '${node_names[${node_index}]}'"
  if [[ "${driver_args}" != '' ]]; then
    docker-machine create --driver "${vm_driver}" ${driver_args} "${node_names[${node_index}]}"
  else
    docker-machine create --driver "${vm_driver}" "${node_names[${node_index}]}"
  fi
done

# Initialize the swarm master node, always the first node.
master_node_name="${node_names[0]}"
master_node_ip="$(docker-machine ip ${master_node_name})"
echo "> intializing the swarm cluster on ${master_node_name} (${master_node_ip})"
docker-machine ssh "${master_node_name}" "docker swarm init" --advertise-addr ${master_node_ip} > /dev/null
swarm_token="$(docker-machine ssh ${master_node_name} "docker swarm join-token -q worker")"
echo "> swarm token is: '${swarm_token}'"

if [ ${nb_nodes} -gt 1 ]; then
  echo "> join the other nodes to the swarm cluster"
  for node_index in `seq 1 ${node_max_index}`;
  do
    current_node_name="${node_names[${node_index}]}"
    current_node_ip="$(docker-machine ip ${current_node_name})"
    echo "  > joining ${current_node_name}"
    docker-machine ssh "${current_node_name}" "docker swarm join --token ${swarm_token} ${master_node_ip}:${DEFAULT_SWARM_PORT}" --advertise-addr "${current_node_ip}"
  done
fi

echo "> display the list of nodes"
docker-machine ssh "${master_node_name}" "docker node ls"

echo "**** ${SCRIPT_NAME} has successfully completed ****"

exit ${SUCCESS_CODE}