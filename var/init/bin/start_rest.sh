#!/bin/bash
. /data/Wing/bin/dataapps.sh
cd /data/[% project %]/bin
export WING_CONFIG=/data/[% project %]/etc/[% project FILTER lower %].conf
start_server --port 5000 -- starman --workers 2 --user nobody --group nobody --preload-app rest.psgi

