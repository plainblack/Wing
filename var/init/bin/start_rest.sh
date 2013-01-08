#!/bin/bash
. /data/Wing/bin/dataapps.sh
cd /data/[% project %]/bin
export WING_CONFIG=/data/[% project %]/etc/wing.conf

if [ $UID == 0 ] 
  then
	echo "switching root to nobody"
	export RUNAS="--user nobody --group nobody"
fi

start_server --port 5000 -- starman --workers 2 --user nobody --group nobody --preload-app rest.psgi

