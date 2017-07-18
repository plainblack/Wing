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


Then make the environment import happen after each login:
=========================================================

echo ". /data/Wing/bin/dataapps.sh" >> ~/.bash_profile


Notes about SSL
===============

Apple has depricated the use of OpenSSL. However, the world of Perl still uses it
extensively. Therefore if you're going to be using SSL from Perl to connect out to
other services you'll likely need to install your own SSL. Here's how:

Download OpenSSL from: https://www.openssl.org/source/

Extract it, and enter the directory. Then configure and install it using these
commands:

 ./Configure --prefix=/data/apps --openssldir=/data/apps/openssl --shared  darwin64-x86_64-cc enable-ec_nistp_64_gcc_128
 make depend
 make
 make install


Then you'll also need to install Perl modules to use it.

SSL Perl Modules
----------------

 cpanm Net::SSLeay --configure-args "INC=-I/data/apps/include LDDLFLAGS=\"-bundle -undefined dynamic_lookup -fstack-protector-strong -L/data/apps/lib\" LD=\"env MACOSX_DEPLOYMENT_TARGET=10.12 cc\" LDFLAGS=\"-fstack-protector-strong -L/data/apps/lib\"" --interactive --verbose

 cpanm --reinstall --verbose IO::Socket::SSL

 cpanm --reinstall --verbose LWP::Protocol::https


