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

 curl -O https://ftp.pcre.org/pub/pcre/pcre-8.42.tar.gz
 tar xfz pcre-8.42.tar.gz
 curl -O http://nginx.org/download/nginx-1.15.0.tar.gz
 tar xfz nginx-1.15.0.tar.gz
 cd nginx-1.15.0
 ./configure --prefix=/data/apps --with-pcre=../pcre-8.42
 make
 make install
 cd ..


Next compile needed libraries:
==============================

 curl -O -L http://prdownloads.sourceforge.net/libpng/libpng-1.6.34.tar.gz?download
 tar xfz libpng-1.6.34.tar.gz?download
 cd libpng-1.6.34
 ./configure --prefix=/data/apps
 make
 make install
 cd ..
 curl -O https://ftp.gnu.org/gnu/libtool/libtool-2.4.6.tar.xz
 tar xfz libtool-2.4.6.tar.xz
 cd libtool-2.4.6
 ./configure --prefix=/data/apps
 make
 make install
 cd..
 curl -O -L https://iweb.dl.sourceforge.net/project/libjpeg/libjpeg/6b/jpegsrc.v6b.tar.gz
 tar xfz jpegsrc.v6b.tar.gz
 cd jpeg-6b
 ln -s /data/apps/bin/libtool
 ./configure --prefix=/data/apps --enable-shared
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


Notes about DBD::mysql
======================

Sometimes you won't be able to compile DBD::mysql and it will complain about a missing package. In that case, make sure you have the environment variable set that is described at the top of this document. However, sometimes even that doesn't seem to be enough, and you have to link some libraries for some reason. Here's what to do:

 sudo ln -s /usr/local/mysql/lib/libmysqlclient.21.dylib /usr/local/lib/libmysqlclient.21.dylib
 sudo ln -s /usr/local/mysql/lib/libssl.1.0.0.dylib /usr/local/lib/libssl.1.0.0.dylib
 sudo ln -s /usr/local/mysql/lib/libcrypto.1.0.0.dylib /usr/local/lib/libcrypto.1.0.0.dylib


