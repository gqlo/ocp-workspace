#!/bin/bash

# Configuration
NAMESPACE="openshift-cnv"
CSV_NAME="kubevirt-hyperconverged-operator.v4.19.3"
TARGET_IMAGE="quay.io/ramlavi/kubemacpool:initmap"
CHECK_INTERVAL=5

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to log with timestamp
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to get current KUBEMACPOOL_IMAGE value
get_current_image() {
    oc get csv "$CSV_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.install.spec.deployments[?(@.name=="cluster-network-addons-operator")].spec.template.spec.containers[0].env[?(@.name=="KUBEMACPOOL_IMAGE")].value}' 2>/dev/null
}

# Function to patch the image
patch_image() {
    local deployment_index
    local env_index
    
    # Find the deployment index for cluster-network-addons-operator
    deployment_index=$(oc get csv "$CSV_NAME" -n "$NAMESPACE" -o json | jq '.spec.install.spec.deployments | map(.name) | index("cluster-network-addons-operator")')
    
    if [ "$deployment_index" = "null" ] || [ -z "$deployment_index" ]; then
        log "${RED}ERROR: Could not find cluster-network-addons-operator deployment${NC}"
        return 1
    fi
    
    # Find the environment variable index for KUBEMACPOOL_IMAGE
    env_index=$(oc get csv "$CSV_NAME" -n "$NAMESPACE" -o json | jq ".spec.install.spec.deployments[$deployment_index].spec.template.spec.containers[0].env | map(.name) | index(\"KUBEMACPOOL_IMAGE\")")
    
    if [ "$env_index" = "null" ] || [ -z "$env_index" ]; then
        log "${RED}ERROR: Could not find KUBEMACPOOL_IMAGE environment variable${NC}"
        return 1
    fi
    
    # Create the patch
    local patch_path="/spec/install/spec/deployments/$deployment_index/spec/template/spec/containers/0/env/$env_index/value"
    
    log "${YELLOW}Patching KUBEMACPOOL_IMAGE to: $TARGET_IMAGE${NC}"
    
    if oc patch csv "$CSV_NAME" -n "$NAMESPACE" --type='json' -p="[{\"op\": \"replace\", \"path\": \"$patch_path\", \"value\": \"$TARGET_IMAGE\"}]"; then
        log "${GREEN}✓ Successfully patched KUBEMACPOOL_IMAGE${NC}"
        return 0
    else
        log "${RED}✗ Failed to patch KUBEMACPOOL_IMAGE${NC}"
        return 1
    fi
}

# Function to check if oc and jq are available
check_dependencies() {
    if ! command -v oc &> /dev/null; then
        log "${RED}ERROR: oc is not installed or not in PATH${NC}"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        log "${RED}ERROR: jq is not installed or not in PATH${NC}"
        exit 1
    fi
}

# Function to verify CSV exists
verify_csv_exists() {
    if ! oc get csv "$CSV_NAME" -n "$NAMESPACE" &> /dev/null; then
        log "${RED}ERROR: CSV '$CSV_NAME' not found in namespace '$NAMESPACE'${NC}"
        exit 1
    fi
}

# Main monitoring loop
main() {
    log "${GREEN}Starting KUBEMACPOOL_IMAGE monitor...${NC}"
    log "Target image: $TARGET_IMAGE"
    log "Check interval: ${CHECK_INTERVAL}s"
    log "CSV: $CSV_NAME"
    log "Namespace: $NAMESPACE"
    echo "Press Ctrl+C to stop"
    echo "----------------------------------------"
    
    while true; do
        current_image=$(get_current_image)
        
        if [ -z "$current_image" ]; then
            log "${RED}WARNING: Could not retrieve current KUBEMACPOOL_IMAGE value${NC}"
        elif [ "$current_image" != "$TARGET_IMAGE" ]; then
            log "${YELLOW}Image mismatch detected!${NC}"
            log "Current: $current_image"
            log "Target:  $TARGET_IMAGE"
            
            if patch_image; then
                log "${GREEN}Image successfully updated${NC}"
            else
                log "${RED}Failed to update image${NC}"
            fi
        else
            log "${GREEN}✓ Image is correct: $current_image${NC}"
        fi
        
        sleep "$CHECK_INTERVAL"
    done
}

# Signal handler for graceful shutdown
cleanup() {
    log "${YELLOW}Received interrupt signal. Stopping monitor...${NC}"
    exit 0
}

# Set up signal handlers
trap cleanup SIGINT SIGTERM

# Run dependency checks
check_dependencies
verify_csv_exists

# Start main loop
main
