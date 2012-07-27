mkdir -p /data/apps

. /data/Wing/bin/dataapps.sh

ln -s /etc/profile.d/dataapps.sh /data/Wing/bin/dataapps.sh

mv yuicompressor-2.4.7/build/yuicompressor-2.4.7.jar /data/apps/

# on mac install X Code instead
yum -y install ncurses-devel gcc make glibc-devel gcc-c++ zlib-devel openssl-devel java expat-devel glib2-devel

cd perl-5.12.4
./Configure -Dprefix=/data/apps -des
make
make install
cd ..

cpan App::cpanminus

