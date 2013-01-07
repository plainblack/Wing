Wing is a modern web services platform written in Perl. It allows you to define objects and then automatically generates database schemas, restful web services, and even web form handlers to manage those objects. It's got built in users, sessions, single-sign-on and more.


INSTALLATION

1. Clone this repository into /data/Wing on your machine:

  mkdir /data
  cd /data
  git clone git@github.com:plainblack/Wing.git

2. Install the prereqs.

  cd /data/Wing/bin/setup
  ./01_download.sh
  ./02_build.sh
  ./03_install_perl_modules.sh
  . /data/Wing/bin/dataapps.sh

3. Create a project:

  cd /data/Wing/bin
  perl wing_init_app.pl --project=MyProject

4. Create a database on your MySQL server to host the project, and edit the Wing config to match:

  mysql -uroot -p -e "create database my_project"
  mysql -uroot -p -e "grant all privileges on my_project.* to some_user@localhost identified by 'some_pass'" 
  mysql -uroot -p -e "flush privileges" 

  vi /data/MyProject/etc/wing.conf  
  # edit the "db" section and add the username and password.

5. Initialize the database:

  cd /data/MyProject/bin
  export WING_HOME=/data/Wing
  export WING_APP=/data/MyProject/
  export WING_CONFIG=/data/MyProject/etc/wing.conf

  perl $WING_HOME/bin/wing_db.pl --install --ok

6. Start up the rest server:

  cd /data/MyProject/bin
  ./start_rest.sh

7. Now you can connect to the rest server and see if it's alive:

   curl http://localhost:5000/api/status


