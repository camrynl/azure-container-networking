# exit on error
set -e

## CONSTANTS
# agnhost timeout in seconds
TIMEOUT=5
CONNECTIVITY_SLEEP=60
# seconds to wait between failed connectivity checks after adding allow-pinger NetworkPolicy
NETPOL_SLEEP=5

printHelp() {
    cat <<EOF
./test-connectivity.sh --num-scale-pods-to-verify=all|<int> --max-wait-for-initial-connectivity=<int> --max-wait-after-adding-netpol=<int> [--kubeconfig=<path>] [--kubectl-binary=<path>]

Verifies that scale test Pods can connect to each other, but cannot connect to a new "pinger" Pod.
Then, adds a NetworkPolicy to allow traffic between the scale test Pods and the "pinger" Pod, and verifies connectivity.

NOTE: You must run ./test-scale.sh first with --num-network-policies=1 or more, and --num-shared-labels-per-pod=3 or more.

USAGE:
1. Follow steps for test-scale.sh
2. Label a node to schedule "pinger" Pods: kubectl label node <name> connectivity-test=true
3. Run this script

REQUIRED PARAMETERS:
    --num-scale-pods-to-verify=all|<int>         number of scale Pods to test. Will verify that each scale Pod can connect to each other [(N-1)^2 connections] and that each Scale Pod cannot connect to a "pinger" Pod [2N connection attempts with a 3-second timeout]
    --max-wait-for-initial-connectivity=<int>    maximum time in seconds to wait for initial connectivity after Pinger Pods are running
    --max-wait-after-adding-netpol=<int>         maximum time in seconds to wait for allowed connections after adding the allow-pinger NetworkPolicy

OPTIONAL PARAMETERS:
    --kubeconfig=<path>                 path to kubeconfig file
    --kubectl-binary=<path>             path to kubectl binary. Default is kubectl

EXIT CODES:
0 - success
6 - non-retriable error
7 - potentially retriable error while getting Pods/IPs
8 - failed on initial connectivity test
9 - failed after adding allow-pinger NetworkPolicy
other - script exited from an unhandled error

EOF
}

log() {
    msg=$1
    # e.g. [2023-05-08 17:16:39-07:00] msg
    echo "[$(date --rfc-3339=seconds)] $msg"
}

## PARAMETERS
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            printHelp
            exit 0
            ;;
        --num-scale-pods-to-verify=*)
            numScalePodsToVerify="${1#*=}"
            ;;
        --max-wait-for-initial-connectivity=*)
            maxWaitForInitialConnectivity="${1#*=}"
            ;;
        --max-wait-after-adding-netpol=*)
            maxWaitAfterAddingNetpol="${1#*=}"
            ;;
        --kubeconfig=*)
            file=${1#*=}
            KUBECONFIG_ARG="--kubeconfig $file"
            test -f $file || {
                log "ERROR: kubeconfig not found: [$file]"
                exit 6
            }
            log "using kubeconfig: $file"
            ;;
        --kubectl-binary=*)
            KUBECTL=${1#*=}
            test -f $KUBECTL || {
                log "ERROR: kubectl binary not found: [$KUBECTL]"
                exit 1
            }
            log "using kubectl binary: $KUBECTL"
            ;;
        *)
            log "ERROR: unknown parameter $1. Make sure you're using '--key=value' for parameters with values"
            exit 6
            ;;
    esac
    shift
done

if [[ -z $numScalePodsToVerify || -z $maxWaitForInitialConnectivity || -z $maxWaitAfterAddingNetpol ]]; then
    log "ERROR: missing required parameter. Check --help for usage"
    exit 6
fi

if [[ -z $KUBECTL ]]; then
    KUBECTL="kubectl"
fi

## PRINT OUT ARGS
cat <<EOF
Starting connectivity script with following args.

numScalePodsToVerify: $numScalePodsToVerify
maxWaitAfterAddingNetpol: $maxWaitAfterAddingNetpol

TIMEOUT: $TIMEOUT
NETPOL_SLEEP: $NETPOL_SLEEP

EOF

## HELPER FUNCTIONS
connectToGoogle() {
    local from=$1
    log "checking connectivity from $from to www.google.com"
    RETVAL="$(k exec -n scale-test "$from" --  curl -sL -w "%{http_code}" www.google.com -o /dev/null)"
    if [ "$RETVAL" = "200" ]; then
        return 0
    else
        return 1
    fi
}

connectToBing() {
    local from=$1
    log "checking connectivity from $from to www.bing.com"
    RETVAL="$(k exec -n scale-test "$from" --  curl -sL -w "%{http_code}" www.bing.com -o /dev/null)"
    if [ "$RETVAL" = "200" ]; then
        return 1
    else
        return 0
    fi
}

## RUN
set -e
startDate=`date -u`
log "STARTING CONNECTIVITY TEST at $startDate"

## GET SCALE PODS
if [[ $numScalePodsToVerify == "all" ]]; then
    log "setting numScalePodsToVerify=9999 since 'all' was passed in"
    numScalePodsToVerify=9999
fi

log "getting scale Pods..."
scalePodNameIPs=(`$KUBECTL $KUBECONFIG_ARG get pods -n scale-test --field-selector=status.phase==Running -l is-real="true" -o jsonpath='{range .items[*]}{@.metadata.name}{","}{@.status.podIP}{" "}{end}'`)
scalePods=()
scalePodIPs=()
for nameIP in "${scalePodNameIPs[@]}"; do
    nameIP=(`echo $nameIP | tr ',' ' '`)
    name=${nameIP[0]}
    ip=${nameIP[1]}

    log "scale Pod: $name, IP: $ip"

    if [[ -z $name || -z $ip ]]; then
        log "ERROR: expected scale Pod name and IP to be non-empty"
        exit 7
    fi

    scalePods+=($name)
    scalePodIPs+=($ip)

    if [[ ${#scalePods[@]} -eq $numScalePodsToVerify ]]; then
        break
    fi
done

numScalePodsFound=${#scalePods[@]}
if [[ $numScalePodsFound == 0 ]]; then
    log "ERROR: expected namespace scale-test to exist with real (non-kwok) Pods. Run test/scale/test-scale.sh with real Pods first."
    kubectl get pod -n scale-test -owide
    exit 7
elif [[ $numScalePodsFound -lt $numScalePodsToVerify ]]; then
    log "WARNING: there are only $numScalePodsFound real scale Pods running which is less than numScalePodsToVerify=$numScalePodsToVerify. Will verify just these $numScalePodsFound Pods"
    numScalePodsToVerify=$numScalePodsFound
else
    log "will verify connectivity to $numScalePodsToVerify scale Pods"
fi

## VERIFY CONNECTIVITY

# TODO: Add initial connectivity check + deploy actual CilNetPol here.

verifyNetPol() {
        for i in $(seq 0 $(( ${#scalePods[@]} - 1 ))); do
        scalePod=${scalePods[$i]}
        scalePodIP=${scalePodIPs[$i]}

        connectToGoogle $scalePod || {
            log "WARNING: expected scale Pod $scalePod to be able to connect to Google after adding CiliumNetworkPolicy"
            return 9
        }

        connectToBing $scalePod || {
            log "WARNING: expected scale Pod $scalePod to not be able to connect to Bing after adding CiliumNetworkPolicy"
            return 9
        }
    done

    return 0
}

log "verifying allow-pinger NetworkPolicy at $(date)..."
netpolStartDate=`date +%s`
maxWaitDate=$(( $netpolStartDate + $maxWaitAfterAddingNetpol ))
prevTryDate=$netpolStartDate
while : ; do
    verifyNetPol && break

    currDate=`date +%s`
    if [[ $currDate -gt $maxWaitDate ]]; then
        log "ERROR: allow-pinger NetworkPolicy has not taken effact. Last try was at least $(( $prevTryDate - $netpolStartDate )) seconds after creating allow-pinger NetworkPolicy"
        exit 9
    fi

    log "WARNING: verifying CiliumNetworkPolicy failed. Current time: $(date). Retrying in $NETPOL_SLEEP seconds..."
    sleep $NETPOL_SLEEP

    prevTryDate=$currDate
done

low=0
if [[ $prevTryDate -gt $netpolStartDate ]]; then
    low=$(( $prevTryDate - $netpolStartDate - $NETPOL_SLEEP ))
fi
high=$(( `date +%s` - $netpolStartDate ))
log "SUCCESS: all connectivity tests passed after adding CiliumNetworkPolicy. Took between $low and $high seconds to take effect"

echo
log "FINISHED at $(date -u). Had started at $startDate."
echo
