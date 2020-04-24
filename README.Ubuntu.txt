These instructions update the instructions in README.txt for Ubuntu Desktop 14.04.

Start by prepping the system:
=============================

 sudo apt-get install libgnome2-perl build-essential git curl ncurses-dev glib2.0 libexpat1-dev libxml2 libxml2-dev libssl-dev libpng-dev libjpeg-dev libmysqlclient-dev mysql-server

 sudo addgroup nobody

 sudo adduser nobody nobody

 sudo /usr/bin/mysql_secure_installation


Now perform all the steps in README.txt.
========================================


Then make the environment import happen after each login:
=========================================================

ln -s /data/Wing/bin/dataapps.sh /etc/profile.d/dataapps.sh

