These instructions update the instructions in README.txt for Ubuntu Desktop 14.04.

Start by prepping the system:
=============================

 sudo apt-get install libgnome2-perl build-essential git curl ncurses-dev glib2.0 libexpat1-dev libxml2 libxml2-dev libssl-dev libpng12-dev libjpeg-dev libmysqlclient-dev

 sudo addgroup nobody

 sudo adduser nobody nobody

 sudo /usr/bin/mysql_secure_installation


Fix MySQL:
==========

Make sure you've updated your my.cnf file to the specs described in README.txt.

 sudo bash

 service mysql stop

 mv /var/log/mysql/ib_logfile /tmp/

 service mysql start


Now perform all the steps in README.txt.
========================================

