#!/bin/bash

# Create output directory
OUTPUT_DIR="vmim_backups_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTPUT_DIR"

echo "Fetching all VMIM objects across all namespaces..."

# Get all vmim objects from all namespaces
oc get vmim --all-namespaces -o json | jq -r '.items[] | @json' | while read -r item; do
    # Extract namespace and name
    NAMESPACE=$(echo "$item" | jq -r '.metadata.namespace')
    NAME=$(echo "$item" | jq -r '.metadata.name')
    
    # Create namespace directory if it doesn't exist
    mkdir -p "$OUTPUT_DIR/$NAMESPACE"
    
    # Save to file
    echo "$item" | jq '.' > "$OUTPUT_DIR/$NAMESPACE/${NAME}.json"
    
    echo "Saved: $NAMESPACE/$NAME.json"
done

echo "Done! All VMIM objects saved to $OUTPUT_DIR/"
