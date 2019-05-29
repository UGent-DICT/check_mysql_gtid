#!/usr/bin/env bash
# vim: set expandtab sw=4 ts=4:

# Copyright 2019 Dieter Adriaenssens / Ghent University  <dieter.adriaenssens@ugent.be>

MYSQL_DEFAULTS_FILE="./check_mysql_gtid_credentials"

VERSION="1.0.0"

RESULT_OK=0
RESULT_WARNING=1
RESULT_CRITICAL=2
RESULT_UNKNOWN=3

CHECK_NAME="MYSQL_CLUSTER_GTID"
FILTER_CLUSTER=$1
RESULT="$RESULT_OK"
OUTPUT=""
NODES=""

# Return with a critical result code and display message
# call this function with '|| result_critical' after a command you want to check the result of.
# params:
# - error message
function result_critical {
    local error_msg=$1
    RESULT="$RESULT_CRITICAL"
    OUTPUT="$OUTPUT\n$error_msg"
}

# Return with a critical result code and display message after a failed mysql command
# call this function with '|| result_critical' after a command you want to check the result of.
# params:
# - hostname
# - error message
function mysql_critical {
    local hostname=$1
    local error_msg=$2
    result_critical "Error connecting to $hostname : $error_msg"
}

# Compare executed GTIDs between a primary node and a replica of a MySQL cluster
# params:
# - primary
# - replica
function compare_gtid {
    local hostname_replica=$2
    local hostname_primary=$1

    local gtid_executed_replica
    gtid_executed_replica="$(mysql --defaults-file="$MYSQL_DEFAULTS_FILE" -h "$hostname_replica" -Bse "SELECT @@global.gtid_executed" 2>&1)" || {
        mysql_critical "$hostname_replica" "$gtid_executed_replica"
        return
    }

    local gtid_is_subset
    gtid_is_subset="$(mysql --defaults-file="$MYSQL_DEFAULTS_FILE" -h "$hostname_primary" -Bse "SELECT GTID_SUBSET('$gtid_executed_replica', @@global.gtid_executed)" 2>&1)" || {
        mysql_critical "$hostname_primary" "$gtid_is_subset"
        return
    }

    if [[ "$gtid_is_subset" = "1" ]]; then
        OUTPUT="$OUTPUT\n - $hostname_replica : OK"
    else
        RESULT="$RESULT_WARNING"
        NODES="$NODES $hostname_replica"

        OUTPUT="$OUTPUT\n - $hostname_replica : GTIDs only exist on the replica :"
        diff="$(mysql --defaults-file="$MYSQL_DEFAULTS_FILE" -h "$hostname_primary" -Bse "SELECT GTID_SUBTRACT('$gtid_executed_replica', @@global.gtid_executed)")" || {
            mysql_critical "$hostname_primary" "$diff"
            return
        }

        OUTPUT="$OUTPUT\n  $diff\n"
    fi
}

# call orchestrator
# params
#  - params
function call_orchestrator {
    local params=($@)

    local result_orchestrator
    result_orchestrator="$(orchestrator "${params[@]}" 2>/dev/null)" || {
        echo "Error calling orchestrator : orchestrator ${params[*]}"
        echo "$result_orchestrator"
        return 1
    }

    echo "$result_orchestrator"
    return 0
}

# List all primary nodes of each cluster
function get_primaries {
    local result_orchestrator
    result_orchestrator="$(call_orchestrator '-c' 'all-clusters-masters')" || {
        echo "$result_orchestrator"
        return 1
    }

    local result
    result="$(awk -F: '{print $1}' 2>&1 <<< "$result_orchestrator")" || {
        echo "$result"
        return 1
    }

    echo "$result"
    return 0
}

# List all replicas of a primary node
# params
# - primary
function get_replicas {
    local hostname_primary=$1

    # get list of all instances in a cluster, but exclude the primary
    local result_orchestrator
    result_orchestrator="$(call_orchestrator '-c' 'which-cluster-instances' '-i' "$hostname_primary")" || {
        echo "$result_orchestrator"
        return 1
    }

    local result_awk
    result_awk="$(awk -F: '{print $1}' 2>&1 <<< "$result_orchestrator")" || {
        echo "$result_awk"
        return 1
    }

    local result
    result="$(grep -v "$hostname_primary" 2>&1 <<< "$result_awk")" || {
        echo "$result"
        return 1
    }

    echo "$result"
}

# Check if clustername is managed by orchestrator
# params
# - clustername
function check_clustername {
    local param_clustername=$1

    # empty name is OK
    if [[ -z "$param_clustername" ]]; then
        return 0
    fi

    # get list of all clusters managed by orchestrator
    local result_orchestrator
    result_orchestrator="$(call_orchestrator '-c' 'clusters-alias')" || {
        echo "$result_orchestrator"
        return 1
    }

    local clusters
    clusters="$(awk '{print $2}' 2>&1 <<< "$result_orchestrator")" || {
        echo "$clusters"
        return 1
    }

    for cluster in $clusters; do
        if [[ "$param_clustername" == "$cluster" ]]; then
            # OK, cluster exists
            return 0
        fi
    done

    # not OK, cluster doesn't exist
    return 1
}

# Print output
function print_output {
	case $RESULT in
	"$RESULT_OK")
            echo "$CHECK_NAME OK - GTIDs on all nodes are replicated in the cluster!"
            ;;
	"$RESULT_WARNING")
            echo "$CHECK_NAME WARNING : replicas containing unreplicated GTIDs :$NODES"
            ;;
	"$RESULT_CRITICAL")
            echo "$CHECK_NAME CRITICAL : error connecting to nodes"
            ;;
	"$RESULT_UNKNOWN")
            echo "$CHECK_NAME UNKNOWN"
            ;;
	*)
            echo "$CHECK_NAME UNKNOWN"
            ;;
	esac

	echo -e "$OUTPUT"
}

# check if mysql credentials file is readable
if [[ -r $MYSQL_DEFAULTS_FILE ]]; then
    if check_clustername "$FILTER_CLUSTER"; then
	    if primaries=($(get_primaries)); then
	        for primary in "${primaries[@]}"; do

                cluster="$(call_orchestrator '-c' 'which-cluster-domain' '-i' "$primary")" || {
                    result_critical "$cluster"
                    continue
                }

                if [[ -n "$FILTER_CLUSTER" && "$FILTER_CLUSTER" != "$cluster" ]]; then
                    continue
                fi

                OUTPUT="$OUTPUT\nCluster $cluster (primary : $primary) :"

                if replicas=($(get_replicas "$primary")); then
                    for replica in "${replicas[@]}"; do
                        compare_gtid "$primary" "$replica"
                    done
                    OUTPUT="$OUTPUT\n"
                else
                    result_critical "${replicas[*]}"
                fi
            done
        else
            result_critical "${primaries[*]}"
        fi
    else
	    RESULT="$RESULT_UNKNOWN"
	    OUTPUT="$OUTPUT\nUnknown cluster : $FILTER_CLUSTER"
    fi
else
    result_critical "Mysql credentials file '$MYSQL_DEFAULTS_FILE' is not readable."
fi

print_output

exit $RESULT
