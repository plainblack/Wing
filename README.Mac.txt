These instructions update the instructions in README.txt for Mac OSX 10.11.

Start by prepping the system:
=============================

 Install X Code from the App store.

 export DYLD_LIBRARY_PATH=/usr/local/mysql/lib:$DYLD_LIBRARY_PATH

 Install MySQL from http://dev.mysql.com/downloads/mysql/


Then perform steps 1 and 2 from README.txt.
===========================================


Next compile nginx:
===================

 wget http://superb-dca2.dl.sourceforge.net/project/pcre/pcre/8.32/pcre-8.32.tar.gz
 tar xfz pcre-8.32.tar.gz
 wget http://nginx.org/download/nginx-1.2.6.tar.gz
 tar xfz nginx-1.2.6.tar.gz
 cd nginx-1.2.6
 ./configure --prefix=/data/apps --with-pcre=../pcre-8.32
 make
 make install
 cd ..


Then perform the remaining steps in README.txt.
===============================================


