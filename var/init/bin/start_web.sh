#!/bin/bash
. /data/Wing/bin/dataapps.sh
cd /data/[% project %]/bin
export WING_CONFIG=/data/[% project %]/etc/wing.conf
start_server --port 5001 -- starman --workers 2 --user nobody --group nobody --preload-app web.psgi

