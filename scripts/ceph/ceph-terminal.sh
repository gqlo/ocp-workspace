#!/bin/bash
ceph_enabled=$(oc get storagecluster ocs-storagecluster -n openshift-storage -o json | jq -r '.spec.enableCephTools')

if [[ "$ceph_enabled" != "true" ]]; then
  oc patch storagecluster ocs-storagecluster -n openshift-storage --type json --patch '[{ "op": "replace", "path": "/spec/enableCephTools", "value": true }]'
  echo "Patched: enableCephTools set to true."
else
  echo "No patch needed: enableCephTools is already set to true."
fi


NAMESPACE="openshift-storage"
LABEL="app=rook-ceph-tools"
POD_STATUS="Running"

# Loop until the pod is found and is in the Running state
while true; do
    POD=$(oc -n $NAMESPACE get pod -l "$LABEL" -o jsonpath="{.items[0].metadata.name}" 2>/dev/null)

    if [ -z "$POD" ]; then
        echo "Pod not found, waiting..."
    else
        STATUS=$(oc -n $NAMESPACE get pod $POD -o jsonpath="{.status.phase}")
        if [ "$STATUS" == "$POD_STATUS" ]; then
            echo "Pod $POD is up and running."
            break
        else
            echo "Pod $POD found but not in Running state (current state: $STATUS), waiting..."
        fi
    fi
    echo "Waiting for the pod with label $LABEL in namespace $NAMESPACE to be up and running..."
    sleep 2
done


oc -n openshift-storage rsh $(oc get pods -n openshift-storage -l app=rook-ceph-tools -o name)

