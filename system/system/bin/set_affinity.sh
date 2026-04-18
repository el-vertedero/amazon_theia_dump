#!/system/bin/sh
## Copyright (c) 2021 Amazon.com, Inc. or its affiliates.  All rights reserved.
##
## PROPRIETARY/CONFIDENTIAL.  USE IS SUBJECT TO LICENSE TERMS.

echo "Set CPU affinity for wifi driver threads"

function set_wifi_thread_affinity {
  taskset -p 0f `pidof main_thread`
  if [ $? -ne 0 ]; then
    echo "failed to set cpu affinity of main_thread"
  fi
  taskset -p 0f `pidof hif_thread`
  if [ $? -ne 0 ]; then
    echo "failed to set cpu affinity of hif_thread"
  fi
  taskset -p 0f `pidof rx_thread`
  if [ $? -ne 0 ]; then
    echo "failed to set cpu affinity of rx_thread"
  fi
}

set_wifi_thread_affinity

