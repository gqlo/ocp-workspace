#!/bin/bash

# Script to create DataVolume, VolumeSnapshot, and VirtualMachine resources
# Usage: ./create_vm.sh <options> [<total-VMs> [<namespaces>]]
# cursor assisted script

set -eu

# Configuration variables - modify these as needed
DV_URL="http://10.6.67.194:8080/rhel9_uefi_bootscript.qcow2"
STORAGE_SIZE="22Gi"
STORAGE_CLASS="ocs-storagecluster-ceph-rbd-virtualization"
SNAPSHOT_CLASS="ocs-storagecluster-rbdplugin-snapclass"
BASE_PVC_NAME="rhel9-base"
VM_BASENAME="rhel9"
VM_CPU_CORES="1"
VM_MEMORY="1Gi"
# Default to using scripts in the directory in which this script resides.
# $0 is the script name, %/* removes everything after the /, so we get the directory name
CREATE_VM_PATH=${CREATE_VM_PATH:-.:${0%/*}}
VM_CPU_REQUEST=
VM_MEMORY_REQUEST=
NUM_VMS=1
NUM_VMS_PER_NAMESPACE=
NUM_NAMESPACES=1
RUN_STRATEGY=Always
WAIT=0
RECREATE_EXISTING_VMS=1
yamlpath=()
declare -A expected_vms=()
# If CREATE_VM_PATH is explicitly provided, search for
# YAML files on that path.
# Split the CREATE_VM_PATH into an array using : as the delimiter
IFS=: read -r -a yamlpath <<< "$CREATE_VM_PATH"

doit=1
quiet=0

fatal() {
    echo "$*"
    exit 1
}

# | | | represents spaces that creates indentation for te continuation lines
help() {
    if [[ -n "$*" ]] ; then echo "$*" ; fi
    cat <<EOF
Usage: $0 [options] [number_of_vms (default $NUM_VMS) [number_of_namespaces (default $NUM_NAMESPACES)]]
    options:
        -n                      Show what commands would be run
                                without running them
        -q                      Only list objects to be created
        --dv-url=URL            Origin of DV ($DV_URL)
        --storage-size=N        Storage size ($STORAGE_SIZE)
        --snapshot-class=class  Snapshot class ($SNAPSHOT_CLASS)
        --pvc-base-name=name    base PVC name ($BASE_PVC_NAME)
        --basename=name         VM basename ($VM_BASENAME)
        --cores=N               VM CPU cores ($VM_CPU_CORES)
        --memory=N              VM memory size ($VM_MEMORY)
        --request-memory=N      VM memory request (VM memory size)
        --request-cpu=N         VM CPU request (VM CPU cores)
        --vms=N                 Number of VMs ($NUM_VMS)
        --vms-per-namespace=N   Number of VMs per namespace (not set)
        --namespaces=N          Number of namespaces ($NUM_NAMESPACES)
        --run-strategy=strategy Run strategy ($RUN_STRATEGY)
        --create-existing-vm    Attempt to re-create existing VMs
        --no-create-existing-vm Do not attempt to re-create existing VMs (default)
        --wait                  Wait for VMs to start
        --nowait                Do not wait for VMs to start (default)
        --start                 Start the VMs
                                (equivalent to --run-strategy=Always)
        --stop                  Do not start the VMs
                                (equivalent to --run-strategy=Halted)
    Specify either --vms (total VMs) or --vms-per-namespace.
    --vms-per-namespace takes precedence.
EOF
    exit 1
}

# Process long options.  Handle options names case-insensitive
# and allow either -, _, or neither in names.
process_option() {
    local optstr=${1:-}
    local option=
    local value=
    IFS=$'=' read -r option value <<< "$optstr"
    # Normalize the option name to use - instead of _
    option=${option//_/-}
    option=${option//-/}
    # Convert the option to lowercase for case-insensitive matching
    case "${option,,}" in
	dvurl)     DV_URL=$value ;;
	storage*)  STORAGE_SIZE=$value ;;
	snapshot*) SNAPSHOT_CLASS=$value ;;
	pvc*)      BASE_PVC_NAME=$value ;;
	base*)	   VM_BASENAME=$value ;;
	core*)	   VM_CPU_CORES=$value ;;
	mem*)	   VM_MEMORY=$value ;;
	requestm*) VM_MEMORY_REQUEST=$value ;;
	requestc*) VM_CPU_REQUEST=$value ;;
	vmsper*)   NUM_VMS_PER_NAMESPACE=$value ;;
	vms*)	   NUM_VMS=$value ;;
	namesp*)   NUM_NAMESPACES=$value ;;
	runstrat*) RUN_STRATEGY=$value ;;
	wait)	   WAIT=1 ;;
	nowait)	   WAIT=0 ;;
	createex*) RECREATE_EXISTING_VMS=1 ;;
	nocreate*) RECREATE_EXISTING_VMS=0 ;;
	start)     RUN_STRATEGY=Always ;;
	stop)      RUN_STRATEGY=Halted ;;
	*) 	   help ;;
    esac
}

# process all the options one by one, - is treated as the option"-"
while getopts 'nqh-:' opt "$@" ; do
    case "$opt" in
	n) doit=0		    ;;
	q) quiet=1; doit=0	    ;;
	h) help			    ;;
	-) process_option "$OPTARG" ;;
	*) help	                    ;;
    esac
done

# clean all the optional arguments that have been processed by getopts so that the positional arguments are now the remaining arguments
shift $((OPTIND-1))

# no more than 2 positional arguments are allowed
if (($# > 2)) ; then
    help
fi

# Check for prerequisites.
if ((doit)) ; then
    if [[ -z "$(type -t oc)" ]] ; then
	fatal "Error: oc command is not installed on system"
    fi

    if ! oc get ns openshift-cnv >/dev/null 2>&1 ; then
	fatal "Error: openshift-cnv is not installed"
    fi

    if ! oc get ns openshift-storage >/dev/null 2>&1 ; then
	fatal "Error: openshift-storage is not installed"
    fi

    if ! oc get storageclass "$STORAGE_CLASS" >/dev/null 2>&1 ; then
	fatal "Error: storaclass $STORAGE_CLASS is not created"
    fi
fi

NUM_VMS=${1:-$NUM_VMS}
NUM_NAMESPACES=${2:-$NUM_NAMESPACES}

# If user specified --vms-per-namespace, calculate the total number of
# VMs from that.
if [[ -n "$NUM_VMS_PER_NAMESPACE" ]] ; then
    NUM_VMS=$((NUM_VMS_PER_NAMESPACE * NUM_NAMESPACES))
fi

# Validate inputs
if ! [[ "$NUM_VMS" =~ ^[0-9]+$ && "$NUM_VMS" -ge 1 ]]; then
    help "Error: Number of VMs must be a positive integer"
fi

if ! [[ "$NUM_NAMESPACES" =~ ^[0-9]+$ && "$NUM_NAMESPACES" -ge 1 ]]; then
    help "Error: Number of namespaces must be a positive integer"
fi

if ((NUM_VMS < NUM_NAMESPACES)) ; then
    help "Error: Number of VMs must be greater than or equal to number of namespaces"
fi

# Check if template files exist
find_file_on_path() {
    local file=$1
    local ydir
    for ydir in "${yamlpath[@]}" ; do
	if [[ -f "${ydir:-.}/$file" ]] ; then
	    echo "${ydir:-.}/$file"
	    return 0
	fi
    done
    return 1
}

check_file_exists() {
    find_file_on_path "${1:-}" >/dev/null || fatal "$file not found on $CREATE_VM_PATH"
}

check_file_exists namespace.yaml
check_file_exists dv.yaml
check_file_exists volumesnap.yaml
check_file_exists vm-snap.yaml

# Calculate VMs per namespace
VMS_PER_NAMESPACE=$((NUM_VMS / NUM_NAMESPACES))
REMAINDER_VMS=$((NUM_VMS % NUM_NAMESPACES))

cat <<EOF
Creating resources for:
  Total VMs: $NUM_VMS
  Namespaces: $NUM_NAMESPACES
  VMs per namespace: $VMS_PER_NAMESPACE
  Extra VMs in first $REMAINDER_VMS namespaces: $((REMAINDER_VMS > 0 ? 1 : 0))
  DataVolume URL: $DV_URL
  Storage Size: $STORAGE_SIZE
  Storage Class: $STORAGE_CLASS
  Snapshot Class: $SNAPSHOT_CLASS
  VM Basename: $VM_BASENAME
  VM CPU Cores: $VM_CPU_CORES
  VM Memory: $VM_MEMORY

EOF

# Setup logging
LOG_DIR="logs"
LOG_FILE="${LOG_DIR}/$(date +%Y-%m-%dT%H:%M:%S).log"

# Function to log with timestamp
# Output may be provided on command line; if not, it is
# read line by line from stdin with timestamp prepended.
# Only timestamp if we're doing something; if it's a dry
# run, the timestamp won't be interesting.
_log_message() {
    # avoid conflicts with the global OPTIND variable
    local -i OPTIND=0
    local -i from_stdin=0
    while getopts v- opt "$@" ; do
	case "$opt" in
	    -) from_stdin=1 ;;
	    *)		    ;;
	esac
    done
    shift $((OPTIND-1))
    if ((from_stdin)) ; then
	local line
	while IFS= read -r line ; do
	    if ((doit)) ; then
		printf "%(%Y-%m-%d %H:%M:%S)T %s\n" -1 "$line"
	    else
		echo "$line"
	    fi
	done
    else
	if ((doit)) ; then
	    printf "%(%Y-%m-%d %H:%M:%S)T %s\n" -1 "$*"
	else
	    echo "$*"
	fi
    fi
}

log_message() {
    if ((doit)) ; then
	_log_message "$*" | tee -a "$LOG_FILE"
    else
	_log_message "$*"
    fi
}

if ((doit)) ; then
    # Create log directory if it doesn't exist
    if [[ ! -d "$LOG_DIR" ]]; then
	mkdir -p "$LOG_DIR"
	echo "Created log directory: $LOG_DIR"
    fi

    log_message "Log file created: $LOG_FILE"
fi

do_oc() {
    if ((doit)) ; then
	oc apply -f -
    elif ((quiet)) ; then
	local line
	while read -r line ; do : ; done
    else
	cat
    fi
}

# Replace templated variables in YAML files with their values.
function process_template() {
    local file=$1
    sed -e "s/{vm-ns}/$namespace/g" \
        -e "s/{vm-id}/${VM_ID:-}/g" \
        -e "s/{VM_BASENAME}/$VM_BASENAME/g" \
        -e "s|{DV_URL}|$DV_URL|g" \
        -e "s/{BASE_PVC_NAME}/$BASE_PVC_NAME/g" \
        -e "s/{STORAGE_SIZE}/$STORAGE_SIZE/g" \
        -e "s/{STORAGE_CLASS}/$STORAGE_CLASS/g" \
        -e "s/{SNAPSHOT_CLASS}/$SNAPSHOT_CLASS/g" \
        -e "s/{VM_CPU_CORES}/$VM_CPU_CORES/g" \
        -e "s/{VM_MEMORY}/$VM_MEMORY/g" \
        -e "s/{RUN_STRATEGY}/$RUN_STRATEGY/g" \
        "$file"
}

# Indent replacement text based on indentation of
# a templated token.  Purpose is to allow indentation of
# YAML fragments based on indentation of the template
# in the text stream.
indent_token() {
    local token=$1
    local text=$2
    local line
    while IFS='' read -r line ; do
	if [[ $line =~ ^([ ]+)\{$token\}$ ]] ; then
	    local prefix=${BASH_REMATCH[1]}
	    while IFS='' read -r repl ; do
		if [[ -n "$repl" ]] ; then
		    echo "${prefix}${repl}"
		fi
	    done <<< "$text"
	else
	    echo "$line"
	fi
    done
}

################################################################
# Function to create namespaces
create_namespaces() {
    log_message "Creating namespaces..."
    local -i ns
    local ns_file
    ns_file=$(find_file_on_path "namespace.yaml") || fatal "Can't find namespace.yaml on CREATE_VM_PATH"
    local -A existing_namespaces=()
    if ((doit)) ; then
	local namespace
	while read -r namespace ; do
	    if [[ -n "$namespace" ]] ; then existing_namespaces["$namespace"]=1; fi
	done <<< "$(oc get namespace --no-headers 2>/dev/null | awk '{print $1}')"
    fi
    for ((ns=1; ns<=NUM_NAMESPACES; ns++)); do
        namespace="vm-ns-${ns}"

        # Check if namespace already exists
	if [[ -n "${existing_namespaces[$namespace]:-}" ]] ; then
            log_message "Namespace $namespace already exists, skipping creation"
        else
            log_message "Creating namespace: $namespace"
            process_template "$ns_file" | do_oc
        fi
    done
}

################################################################
# DataVolumes
check_datavolume_status() {
    local namespace=$1
    local datavolume_name="${VM_BASENAME}-base"

    log_message "Checking DataVolume status in namespace: $namespace"

    # Wait for DataVolume to be completed
    while :; do
	local status
        status=$(oc get datavolume "$datavolume_name" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")

        case $status in
            "Succeeded")
                log_message "DataVolume $datavolume_name in namespace $namespace is completed"
                return 0
                ;;
            "Failed")
                fatal "Error: DataVolume $datavolume_name in namespace $namespace failed"
                ;;
            "Pending"|"Running"|"ImportScheduled"|"ImportInProgress")
                log_message "DataVolume $datavolume_name in namespace $namespace is still $status, waiting..."
                sleep 10
                ;;
            *)
                log_message "DataVolume $datavolume_name in namespace $namespace has unknown status: $status"
                sleep 10
                ;;
        esac
    done
}

# Function to wait for all DataVolumes to complete
wait_for_all_datavolumes() {
    log_message "Waiting for all DataVolumes to complete..."

    local -i ns
    for ((ns=1; ns<=NUM_NAMESPACES; ns++)); do
        namespace="vm-ns-${ns}"

        if ! check_datavolume_status "$namespace"; then
            fatal "Error: Failed to create DataVolume in namespace $namespace"
        fi
    done

    log_message "All DataVolumes are completed successfully!"
}

create_datavolumes() {
    log_message "Creating DataVolumes..."
    local -i ns
    local dv_file
    dv_file=$(find_file_on_path "dv.yaml") || fatal "Can't find dv.yaml on CREATE_VM_PATH"
    for ((ns=1; ns<=NUM_NAMESPACES; ns++)); do
        namespace="vm-ns-${ns}"

        log_message "Creating DataVolume for namespace: $namespace"
        process_template "$dv_file" | do_oc
    done
    if ((doit)) ; then wait_for_all_datavolumes; fi
}

################################################################
# VolumeSnapshots
check_volumesnapshot_status() {
    local namespace=$1
    local snapshot_name="${VM_BASENAME}-${namespace}"

    log_message "Checking VolumeSnapshot status in namespace: $namespace"

    # Wait for VolumeSnapshot to be ready
    while :; do
	local status
        status=$(oc get volumesnapshot "$snapshot_name" -n "$namespace" -o jsonpath='{.status.readyToUse}' 2>/dev/null || echo "false")

	case "$status" in
	    "true")
		log_message "VolumeSnapshot $snapshot_name in namespace $namespace is ready"
		return 0
		;;
	    *)
		log_message "VolumeSnapshot $snapshot_name in namespace $namespace is not ready yet, waiting..."
		sleep 10
		;;
	esac
    done
}

# Function to wait for all VolumeSnapshots to be ready
wait_for_all_volumesnapshots() {
    log_message "Waiting for all VolumeSnapshots to be ready..."

    local -i ns
    for ((ns=1; ns<=NUM_NAMESPACES; ns++)); do
        namespace="vm-ns-${ns}"

        if ! check_volumesnapshot_status "$namespace"; then
            fatal "Error: Failed to create VolumeSnapshot in namespace $namespace"
        fi
    done

    log_message "All VolumeSnapshots are ready successfully!"
}

create_volumesnapshots() {
    log_message "Creating VolumeSnapshots..."
    local -i ns
    local vs_file
    vs_file=$(find_file_on_path "volumesnap.yaml") || fatal "Can't find volumesnap.yaml on CREATE_VM_PATH"
    for ((ns=1; ns<=NUM_NAMESPACES; ns++)); do
        namespace="vm-ns-${ns}"
        log_message "Creating VolumeSnapshot for namespace: $namespace"
        process_template "$vs_file" | do_oc
    done
    if ((doit)) ; then wait_for_all_datavolumes; fi
}

################################################################
# VMs
wait_for_all_vms() {
    log_message "Waiting for all VMs to be ready"
    local -i total_vms="${#expected_vms[@]}"
    local -i ready_vms=0

    while : ; do
	# We expect to have a lot more VMs than we do other objects, which are
	# have only one per namespace.  Therefore the algorithm of waiting in turn for
	# each one to be ready will be inefficient, and we use the method of listing
	# all VMs that are ready and checking them off our list.
	while read -r vm ; do
	    if [[ -n "$vm" && -n "${expected_vms[$vm]:-}" ]] ; then
		unset "expected_vms[$vm]"
		ready_vms=$((ready_vms + 1))
	    fi
	done <<< "$(oc get vm -A --no-headers | awk '{if ($5 == "True" && $4 == "Running") {printf "%s/%s\n", $1, $2}}')"
	if (("${#expected_vms[@]}" == 0)) ; then
	    log_message "All VMs are ready"
	    return
	else
	    log_message "${ready_vms}/${total_vms} ready"
	    sleep 60
	fi
    done
}

create_virtualmachines() {
    log_message "Creating VirtualMachines..."
    VM_ID=1
    local vm_file
    vm_file=$(find_file_on_path "vm-snap.yaml") || fatal "Can't find vm-snap.yaml on CREATE_VM_PATH"
    local requeststr=
    local -A requests=()
    if [[ -n "${VM_CPU_REQUEST:-}" ]] ; then requests[cpu]=$VM_CPU_REQUEST; fi
    if [[ -n "${VM_MEMORY_REQUEST:-}" ]] ; then requests[memory]=$VM_MEMORY_REQUEST; fi
    if [[ -n "${requests[*]}" ]] ; then
	requeststr="
resources:
  requests:
$(local resource; for resource in "${!requests[@]}" ; do echo "    $resource: ${requests[$resource]}" ; done)
"
    fi
    local -A existing_vms=()
    if ((! RECREATE_EXISTING_VMS)) ; then
	local vm
	while read -r vm ; do
	    if [[ -n "$vm" ]] ; then existing_vms["$vm"]=1; fi
	done <<< "$(oc get vm -A --no-headers | awk '{printf "%s/%s\n", $1, $2}')"
    fi
    for ((ns=1; ns<=NUM_NAMESPACES; ns++)); do
        namespace="vm-ns-${ns}"

        # Calculate VMs for this namespace
        vms_in_this_namespace=$VMS_PER_NAMESPACE
        if [[ $ns -le $REMAINDER_VMS ]]; then
            vms_in_this_namespace=$((vms_in_this_namespace + 1))
        fi

        # Create VMs for this namespace
        for ((vm=1; vm<=vms_in_this_namespace; vm++)); do
	    local vm_name="${namespace}/${VM_BASENAME}-${VM_ID}"
	    if [[ -z "${existing_vms[$vm_name]:-}" ]] ; then
		log_message "Creating VirtualMachine $VM_ID for namespace: $namespace"
		process_template "$vm_file" | indent_token RESOURCES "$requeststr" | do_oc ||
		    fatal "Cannot create vm $vm_name!"
	    fi
	    expected_vms["$vm_name"]=1
            VM_ID=$((VM_ID + 1))
        done
    done
    if ((doit)) ; then
	if ((WAIT)) ; then
	    wait_for_all_vms
	else
	    log_message "Not waiting for all VMs"
	fi
    fi
}

################################################################
# Main execution
main() {
    log_message "Starting resource creation process..."
    log_message "Configuration: $NUM_VMS VMs across $NUM_NAMESPACES namespaces"

    log_message "DV URL:        $DV_URL"
    log_message "Storage size:  $STORAGE_SIZE"
    log_message "Storage class: $STORAGE_CLASS"
    log_message "VM CPU cores:  $VM_CPU_CORES"
    log_message "VM memory:     $VM_MEMORY"
    log_message "Run strategy:  $RUN_STRATEGY"

    create_namespaces
    create_datavolumes
    create_volumesnapshots
    create_virtualmachines

    if ((doit)) ; then
	log_message "Resource creation completed successfully!"
	log_message "Created $NUM_NAMESPACES namespaces, $NUM_NAMESPACES DataVolumes, $NUM_NAMESPACES VolumeSnapshots, and $NUM_VMS total VirtualMachines"
	echo ""
	echo "To check the created resources:"
	echo "  oc get namespaces | grep vm-ns"
	echo "  oc get datavolumes --all-namespaces | grep $VM_BASENAME"
	echo "  oc get volumesnapshots --all-namespaces | grep $VM_BASENAME"
	echo "  oc get vms --all-namespaces | grep $VM_BASENAME"
    fi
}

# Run the main function
main
