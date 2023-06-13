#####################################################################################
# Periodically captures CPU/Memory of Pods/nodes and writes to csvs.                #
#####################################################################################
APPEND_TO_EXISTING_FILES=true

FOLDER="100k/disabled/16000podtest2"
RUNNING_PODS_FILE=$FOLDER/cpu-and-mem-running-pods.out
POD_MEM_CSV=$FOLDER/cpu-and-mem-pod-results-16000pod.csv
NODE_MEM_CSV=$FOLDER/cpu-and-mem-node-results-16000pod.csv

# kubectl top seems to refresh every minute
SLEEP_BETWEEN_CAPTURES=10

## RUN
mkdir -p $FOLDER

if [[ $APPEND_TO_EXISTING_FILES != true ]]; then
    if [[ -f $RUNNING_PODS_FILE || -f $POD_MEM_CSV || -f $NODE_MEM_CSV ]]; then
        echo "ERROR: $RUNNING_PODS_FILE, $POD_MEM_CSV, or $NODE_MEM_CSV already exists. Either 1) set APPEND_TO_EXISTING_FILES=true or 2) move the old files"
        exit 1
    fi

    echo "time,pod,cpu,mem" > $POD_MEM_CSV
    echo "time,node,cpu,cpuPercent,mem,memPercent" > $NODE_MEM_CSV
fi

while true; do
    currentTime=`date -u`
    echo "running k top pod"
    lines=`kubectl top pod -A | grep -v NAME | grep cilium | awk '{$1=$1;print}' | tr ' ' ','`
    for line in $lines; do
        echo "$currentTime,$line" >> $POD_MEM_CSV
    done

    currentTime=`date -u`
    echo "running k top node"
    lines=`kubectl top node | grep -v NAME | grep -v kwok | awk '{$1=$1;print}' | tr ' ' ','`
    for line in $lines; do
        echo "$currentTime,$line" >> $NODE_MEM_CSV
    done

    echo `date -u` >> $RUNNING_PODS_FILE
    kubectl get pod -A -owide | grep npm >> $RUNNING_PODS_FILE
    echo " " >> $RUNNING_PODS_FILE

    echo "sleeping $SLEEP_BETWEEN_CAPTURES seconds"
    sleep $SLEEP_BETWEEN_CAPTURES
done
