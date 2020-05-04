These instructions update the instructions in README.txt for Ubuntu Desktop 14.04.

Start by prepping the system:
=============================

 sudo apt-get install libgnome2-perl build-essential git curl ncurses-dev glib2.0 libexpat1-dev libxml2 libxml2-dev libssl-dev libpng-dev libjpeg-dev libmysqlclient-dev mysql-server

 sudo addgroup nobody

 sudo adduser nobody nobody

 sudo /usr/bin/mysql_secure_installation


Add these to your environment:

export OPENSSL_PREFIX=/usr/bin/openssl 
export LD_LIBRARY_PATH=/usr/lib:/usr/lib/x86_64-linux:$LD_LIBRARY_PATH


Now perform all the steps in README.txt.
========================================


If some perl modules fail:
==========================

XML::LibXML might fail due to incompatibility with libxml 2.9.10 so download 2.9.4 and build with:

./configure --prefix=/data/apps
make
make install

Net::SSLeay might fail. You may have to install it manually:

wget https://cpan.metacpan.org/authors/id/C/CH/CHRISN/Net-SSLeay-1.88.tar.gz
tar xfz Net-SSLeay-1.88.tar.gz
cd Net-SSLeay-1.88
OPENSSL_PREFIX=/usr/bin/openssl LD_LIBRARY_PATH=/usr/lib/x86_64-linux:$LD_LIBRARY_PATH perl Makefile.PL 
make
make install






Then make the environment import happen after each login:
=========================================================

ln -s /data/Wing/bin/dataapps.sh /etc/profile.d/dataapps.sh

