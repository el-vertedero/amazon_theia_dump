#!/system/bin/sh

function log_counter_metrics()
{
    local tag=$1
    local domain=$2
    local source=$3
    local metric=$4
    local val=$5
    logstr="$domain:$source:$metric=$val;CT;1:NR"
    log -m -t $tag $logstr
}

function kmlogger_counter_metrics()
{
    log_counter_metrics "kmlogger" "kmlogger" $1 $2 $3
}

# Publish single counter metric with the node value if the node value is not 0
function kmlogger_node_counter_metrics()
{
    local node_path=$1
    local source=$2
    local metric=$3

    val=$(cat $node_path)

    if [ "$val" != "0" ]; then
        kmlogger_counter_metrics $source $metric $val
    fi
}

# Publish counter metrics for node with string list value
# The format of string list is like "metric1 metric2 ... metricN"
# This function publishes each metric with counter 1
function kmlogger_strings_node_counter_metrics()
{
    local node_path=$1
    local source=$2

    val=$(cat $node_path)

    for metric in $val; do
        kmlogger_counter_metrics $source $metric "1"
    done
}