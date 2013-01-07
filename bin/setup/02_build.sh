mkdir -p /data/apps

. /data/Wing/bin/dataapps.sh


# on mac install X Code and MySQL instead
if [ uname=='Darwin' ]; then
 echo "NOTICE:"
 echo "You're on a mac. You need to install X Code and MySQL. If you have not already done so, please exit now and do so."
 sleep 10
else 
 yum -y install ncurses-devel gcc make glibc-devel gcc-c++ zlib-devel openssl-devel expat-devel glib2-devel mysql-libs libxml2-devel mysql-common mysql-devel mysql
fi

ln -s /etc/profile.d/dataapps.sh /data/Wing/bin/dataapps.sh

cd perl-5.16.2
./Configure -Dprefix=/data/apps -des
make
make install
cd ..

cpan App::cpanminus

