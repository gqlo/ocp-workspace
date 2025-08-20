#!/bin/bash

# Script to create DataVolume, VolumeSnapshot, and VirtualMachine resources
# Usage: ./create_vm.sh <number_of_vms> <number_of_namespaces>
# cursor assisted script

set -e

# Configuration variables - modify these as needed
DV_URL="http://10.6.67.194:8080/rhel9_uefi_bootscript.qcow2"
STORAGE_SIZE="22Gi"
STORAGE_CLASS="ocs-storagecluster-ceph-rbd-virtualization"
SNAPSHOT_CLASS="ocs-storagecluster-rbdplugin-snapclass"
BASE_PVC_NAME="rhel9-base"
VM_BASENAME="rhel9"
VM_CPU_CORES="1"
VM_MEMORY="1Gi"

# Check if correct number of arguments provided
if [ $# -ne 2 ]; then
    echo "Usage: $0 <number_of_vms> <number_of_namespaces>"
    echo "Example: $0 12 3"
    exit 1
fi

NUM_VMS=$1
NUM_NAMESPACES=$2

# Validate inputs
if ! [[ "$NUM_VMS" =~ ^[0-9]+$ ]] || [ "$NUM_VMS" -lt 1 ]; then
    echo "Error: Number of VMs must be a positive integer"
    exit 1
fi

if ! [[ "$NUM_NAMESPACES" =~ ^[0-9]+$ ]] || [ "$NUM_NAMESPACES" -lt 1 ]; then
    echo "Error: Number of namespaces must be a positive integer"
    exit 1
fi

if [ "$NUM_VMS" -lt "$NUM_NAMESPACES" ]; then
    echo "Error: Number of VMs must be greater than or equal to number of namespaces"
    exit 1
fi

# Check if template files exist
if [ ! -f "namespace.yaml" ] || [ ! -f "dv.yaml" ] || [ ! -f "volumesnap.yaml" ] || [ ! -f "vm-snap.yaml" ]; then
    echo "Error: Required template files not found. Please ensure namespace.yaml, dv.yaml, volumesnap.yaml, and vm-snap.yaml exist in the current directory."
    exit 1
fi

# Calculate VMs per namespace
VMS_PER_NAMESPACE=$((NUM_VMS / NUM_NAMESPACES))
REMAINDER_VMS=$((NUM_VMS % NUM_NAMESPACES))

echo "Creating resources for:"
echo "  Total VMs: $NUM_VMS"
echo "  Namespaces: $NUM_NAMESPACES"
echo "  VMs per namespace: $VMS_PER_NAMESPACE"
echo "  Extra VMs in first $REMAINDER_VMS namespaces: $((REMAINDER_VMS > 0 ? 1 : 0))"
echo "  DataVolume URL: $DV_URL"
echo "  Storage Size: $STORAGE_SIZE"
echo "  Storage Class: $STORAGE_CLASS"
echo "  VM Basename: $VM_BASENAME"
echo "  VM CPU Cores: $VM_CPU_CORES"
echo "  VM Memory: $VM_MEMORY"
echo ""

# Function to get timestamp
get_timestamp() {
    date '+%Y-%m-%dT %H:%M:%S'
}

# Function to log with timestamp
log_message() {
    local message="$1"
    local timestamped_message="$(get_timestamp) $message"
    echo "$timestamped_message"
    echo "$timestamped_message" >> "$LOG_FILE"
}

# Setup logging
LOG_DIR="logs"
LOG_FILE="${LOG_DIR}/$(date +%Y%m%d).log"

# Create log directory if it doesn't exist
if [ ! -d "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR"
    echo "Created log directory: $LOG_DIR"
fi

log_message "Log file created: $LOG_FILE"

# Function to create namespaces
create_namespaces() {
    log_message "Creating namespaces..."
    for ((ns=1; ns<=NUM_NAMESPACES; ns++)); do
        namespace="vm-ns-${ns}"
        
        # Check if namespace already exists
        if oc get namespace "$namespace" >/dev/null 2>&1; then
            log_message "Namespace $namespace already exists, skipping creation"
        else
            log_message "Creating namespace: $namespace"
            sed "s/{namespace}/$namespace/g" namespace.yaml | oc apply -f -
        fi
    done
}

# Function to create VolumeSnapshots
create_volumesnapshots() {
    log_message "Creating VolumeSnapshots..."
    for ((ns=1; ns<=NUM_NAMESPACES; ns++)); do
        namespace="vm-ns-${ns}"
        log_message "Creating VolumeSnapshot for namespace: $namespace"
        sed -e "s/{vm-ns}/$namespace/g" \
            -e "s|{VM_BASENAME}|$VM_BASENAME|g" \
            -e "s|{SNAPSHOT_CLASS}|$SNAPSHOT_CLASS|g" \
            -e "s|{BASE_PVC_NAME}|$BASE_PVC_NAME|g" \
            volumesnap.yaml | oc apply -f -
    done
}

# Function to create DataVolumes
create_datavolumes() {
    log_message "Creating DataVolumes..."
    for ((ns=1; ns<=NUM_NAMESPACES; ns++)); do
        namespace="vm-ns-${ns}"
        
        log_message "Creating DataVolume for namespace: $namespace"
        sed -e "s/{vm-ns}/$namespace/g" \
            -e "s|{VM_BASENAME}|$VM_BASENAME|g" \
            -e "s|{DV_URL}|$DV_URL|g" \
            -e "s/{STORAGE_SIZE}/$STORAGE_SIZE/g" \
            -e "s/{STORAGE_CLASS}/$STORAGE_CLASS/g" \
            dv.yaml | oc apply -f -
    done
}

# Function to create VirtualMachines
create_virtualmachines() {
    log_message "Creating VirtualMachines..."
    VM_ID=1
    for ((ns=1; ns<=NUM_NAMESPACES; ns++)); do
        namespace="vm-ns-${ns}"
        
        # Calculate VMs for this namespace
        vms_in_this_namespace=$VMS_PER_NAMESPACE
        if [ $ns -le $REMAINDER_VMS ]; then
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
                vm-snap.yaml | oc apply -f -
            
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
    while true; do
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
    log_message "Waiting for all DataVolumes to complete..."
    
    for ((ns=1; ns<=NUM_NAMESPACES; ns++)); do
        namespace="vm-ns-${ns}"
        
        if ! check_datavolume_status "$namespace"; then
            log_message "Error: Failed to create DataVolume in namespace $namespace"
            exit 1
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
    while true; do
        status=$(oc get volumesnapshot "$snapshot_name" -n "$namespace" -o jsonpath='{.status.readyToUse}' 2>/dev/null || echo "false")
        
        if [ "$status" = "true" ]; then
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
    log_message "Waiting for all VolumeSnapshots to be ready..."
    
    for ((ns=1; ns<=NUM_NAMESPACES; ns++)); do
        namespace="vm-ns-${ns}"
        
        if ! check_volumesnapshot_status "$namespace"; then
            log_message "Error: Failed to create VolumeSnapshot in namespace $namespace"
            exit 1
        fi
    done
    
    log_message "All VolumeSnapshots are ready successfully!"
}

# Main execution
main() {
    log_message "Starting resource creation process..."
    log_message "Configuration: $NUM_VMS VMs across $NUM_NAMESPACES namespaces"
    
    create_namespaces
    create_datavolumes
    wait_for_all_datavolumes
    create_volumesnapshots
    wait_for_all_volumesnapshots
    create_virtualmachines
    
    log_message "Resource creation completed successfully!"
    log_message "Created $NUM_NAMESPACES namespaces, $NUM_NAMESPACES DataVolumes, $NUM_NAMESPACES VolumeSnapshots, and $NUM_VMS VirtualMachines"
    echo ""
    echo "To check the created resources:"
    echo "  oc get namespaces | grep vm-ns"
    echo "  oc get datavolumes --all-namespaces | grep $VM_BASENAME"
    echo "  oc get volumesnapshots --all-namespaces | grep $VM_BASENAME"
    echo "  oc get vms --all-namespaces | grep $VM_BASENAME"
}

# Run the main function
main 
