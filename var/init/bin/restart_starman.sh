#!/bin/bash
. /data/Wing/bin/dataapps.sh
cd /data/[% project %]/bin
export WING_CONFIG=/data/[% project %]/etc/wing.conf
killall -HUP start_server
