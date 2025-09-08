#!/bin/bash

# Script to create DataVolume, VolumeSnapshot, and VirtualMachine resources
# Usage: ./create_vm.sh <number_of_vms> <number_of_namespaces>
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
VM_CPU_REQUEST=
VM_MEMORY_REQUEST=
NUM_VMS=1
NUM_NAMESPACES=1
RUN_STRATEGY=Always
doit=1
mydir=${0%/*}

fatal() {
    echo "$*"
    exit 1
}

help() {
    if [[ -n "$*" ]] ; then echo "$*" ; fi
    cat <<EOF
Usage: $0 [options] [number_of_vms (default $NUM_VMS) [number_of_namespaces (default $NUM_NAMESPACES)]]
    options:
        -n                      Show what commands would be run without running them
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
        --namespaces=N          Number of namespaces ($NUM_NAMESPACES)
        --run-strategy=strategy Run strategy ($RUN_STRATEGY)
        --start                 Start the VMs
                                (equivalent to --run-strategy=Always)
        --stop                  Do not start the VMs
                                (equivalent to --run-strategy=Halted)
EOF
    exit 1
}

process_option() {
    local optstr=${1:-}
    local option=
    local value=
    IFS=$'=' read -r option value <<< "$optstr"
    option=${option//_/-}
    case "${option,,}" in
	dv-url)    DV_URL=$value ;;
	storage*)  STORAGE_SIZE=$value ;;
	snapshot*) SNAPSHOT_CLASS=$value ;;
	pvc*)      BASE_PVC_NAME=$value ;;
	base*)	   VM_BASENAME=$value ;;
	core*)	   VM_CPU_CORES=$value ;;
	mem*)	   VM_MEMORY=$value ;;
	request-m*)VM_MEMORY_REQUEST=$value ;;
	request-c*)VM_CPU_REQUEST=$value ;;
	vms*)	   NUM_VMS=$value ;;
	namesp*)   NUM_NAMESPACES=$value ;;
	run-strat*)RUN_STRATEGY=$value ;;
	start)     RUN_STRATEGY=Always ;;
	stop)      RUN_STRATEGY=Halted ;;
	*) 	   help ;;
    esac
}

while getopts 'nh-:' opt "$@" ; do
    case "$opt" in
	n) doit=0		    ;;
	h) help			    ;;
	-) process_option "$OPTARG" ;;
	*) help			    ;;
    esac
done
shift $((OPTIND-1))

if (($# > 2)) ; then
    help
fi

if ((doit)) ; then
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

check_file_exists() {
    local file=$1
    [[ -f "${mydir}/$file" ]] || fatal "${mydir}/$file not found"
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
  VM Basename: $VM_BASENAME
  VM CPU Cores: $VM_CPU_CORES
  VM Memory: $VM_MEMORY

EOF

# Setup logging
LOG_DIR="logs"
LOG_FILE="${LOG_DIR}/$(date +%Y-%m-%dT%H:%M:%S).log"

# Function to log with timestamp
_log_message() {
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
	    printf "%(%Y-%m-%d %H:%M:%S)T %s\n" -1 "$line"
	done
    else
	printf "%(%Y-%m-%d %H:%M:%S)T %s\n" -1 "$*"
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
    else
	cat
    fi
}

# Function to create namespaces
create_namespaces() {
    log_message "Creating namespaces..."
    local -i ns
    for ((ns=1; ns<=NUM_NAMESPACES; ns++)); do
        namespace="vm-ns-${ns}"

        # Check if namespace already exists
        if ((doit)) && oc get namespace "$namespace" >/dev/null 2>&1; then
            log_message "Namespace $namespace already exists, skipping creation"
        else
            log_message "Creating namespace: $namespace"
            sed "s/{namespace}/$namespace/g" "${mydir}/namespace.yaml" | do_oc
        fi
    done
}

# Function to create VolumeSnapshots
create_volumesnapshots() {
    log_message "Creating VolumeSnapshots..."
    local -i ns
    for ((ns=1; ns<=NUM_NAMESPACES; ns++)); do
        namespace="vm-ns-${ns}"
        log_message "Creating VolumeSnapshot for namespace: $namespace"
        sed -e "s/{vm-ns}/$namespace/g" \
            -e "s|{VM_BASENAME}|$VM_BASENAME|g" \
            -e "s|{SNAPSHOT_CLASS}|$SNAPSHOT_CLASS|g" \
            -e "s|{BASE_PVC_NAME}|$BASE_PVC_NAME|g" \
            "${mydir}/volumesnap.yaml" | do_oc
    done
}

# Function to create DataVolumes
create_datavolumes() {
    log_message "Creating DataVolumes..."
    local -i ns
    for ((ns=1; ns<=NUM_NAMESPACES; ns++)); do
        namespace="vm-ns-${ns}"

        log_message "Creating DataVolume for namespace: $namespace"
        sed -e "s/{vm-ns}/$namespace/g" \
            -e "s|{VM_BASENAME}|$VM_BASENAME|g" \
            -e "s|{DV_URL}|$DV_URL|g" \
            -e "s/{STORAGE_SIZE}/$STORAGE_SIZE/g" \
            -e "s/{STORAGE_CLASS}/$STORAGE_CLASS/g" \
            "${mydir}/dv.yaml" | do_oc
    done
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

# Function to create VirtualMachines
create_virtualmachines() {
    log_message "Creating VirtualMachines..."
    VM_ID=1
    local requeststr=
    local -A requests=()
    if [[ -n "${VM_CPU_REQUEST:-}" ]] ; then
	requests[cpu]=$VM_CPU_REQUEST
    fi
    if [[ -n "${VM_MEMORY_REQUEST:-}" ]] ; then
	requests[memory]=$VM_MEMORY_REQUEST
    fi
    if [[ -n "${requests[*]}" ]] ; then
	requeststr="
resources:
  requests:
$(local resource; for resource in "${!requests[@]}" ; do echo "    $resource: ${requests[$resource]}" ; done)
"
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
            log_message "Creating VirtualMachine $VM_ID for namespace: $namespace"
            sed -e "s/{vm-ns}/$namespace/g" \
                -e "s/{vm-id}/$VM_ID/g" \
                -e "s|{VM_BASENAME}|$VM_BASENAME|g" \
                -e "s/{STORAGE_SIZE}/$STORAGE_SIZE/g" \
                -e "s/{STORAGE_CLASS}/$STORAGE_CLASS/g" \
                -e "s/{VM_CPU_CORES}/$VM_CPU_CORES/g" \
                -e "s/{VM_MEMORY}/$VM_MEMORY/g" \
                -e "s/{RUN_STRATEGY}/$RUN_STRATEGY/g" \
                "${mydir}/vm-snap.yaml" | indent_token RESOURCES "$requeststr" | do_oc

            VM_ID=$((VM_ID + 1))
        done
    done
}

# Function to check if DataVolume is completed
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
                log_message "Error: DataVolume $datavolume_name in namespace $namespace failed"
                return 1
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
    if ((! doit)) ; then
	log_message "Not waiting for datavolumes"
	return
    fi
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

# Function to check if VolumeSnapshot is ready
check_volumesnapshot_status() {
    local namespace=$1
    local snapshot_name="${VM_BASENAME}-${namespace}"

    log_message "Checking VolumeSnapshot status in namespace: $namespace"

    # Wait for VolumeSnapshot to be ready
    while :; do
	local status
        status=$(oc get volumesnapshot "$snapshot_name" -n "$namespace" -o jsonpath='{.status.readyToUse}' 2>/dev/null || echo "false")

        if [[ "$status" = "true" ]]; then
            log_message "VolumeSnapshot $snapshot_name in namespace $namespace is ready"
            return 0
        else
            log_message "VolumeSnapshot $snapshot_name in namespace $namespace is not ready yet, waiting..."
            sleep 10
        fi
    done
}

# Function to wait for all VolumeSnapshots to be ready
wait_for_all_volumesnapshots() {
    if ((! doit)) ; then
	log_message "Not waiting for volumesnapshots"
	return
    fi
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
    wait_for_all_datavolumes
    create_volumesnapshots
    wait_for_all_volumesnapshots
    create_virtualmachines

    if ((doit)) ; then
	log_message "Resource creation completed successfully!"
	log_message "Created $NUM_NAMESPACES namespaces, $NUM_NAMESPACES DataVolumes, $NUM_NAMESPACES VolumeSnapshots, and $NUM_VMS VirtualMachines"
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
