Wing is a modern web services platform written in Perl. It allows you to define objects and then automatically generates database schemas, restful web services, and even web form handlers to manage those objects. It's got built in users, sessions, single-sign-on and more.


INSTALLATION

1. Clone this repository into /data/Wing on your machine:

  mkdir /data
  cd /data
  git clone git@github.com:plainblack/Wing.git

2. Install the prereqs.

  /data/Wing/bin/setup/setup.sh

 NOTE: If you're trying to install DBD::mysql on Mac and it's giving you trouble, make sure you do first:

  export DYLD_LIBRARY_PATH=/usr/local/mysql/lib:$DYLD_LIBRARY_PATH

3. Create a project in /data/MyApp:

  cd /data/Wing/bin
  export WING_HOME=/data/Wing
  perl wing_init_app.pl --app=MyApp

4. Create a database on your MySQL server to host the project, and edit the Wing config to match:

  mysql -uroot -p -e "create database my_project"
  mysql -uroot -p -e "grant all privileges on my_project.* to some_user@localhost identified by 'some_pass'" 
  mysql -uroot -p -e "flush privileges" 

  vi /data/MyApp/etc/wing.conf  
  # edit the "db" section and add the username and password.

5. Initialize the database:

  cd /data/MyApp/bin
  export WING_HOME=/data/Wing
  export WING_APP=/data/MyApp/
  export WING_CONFIG=/data/MyApp/etc/wing.conf

  wing db --prepare_install
  wing db --install --force

6. Start up the rest server and/or web server:

  cd /data/MyApp/bin
  ./start_rest.sh
  ./start_web.sh

7. Now you can connect to the rest server and see if it's alive:

   curl http://localhost:5000/api/status

   curl http://localhost:5001/account

 NOTE: By default there is one user named 'Admin' with a password of '123qwe'.
   
8. We also provide you with an nginx config file to give you a baseline for serving your apps. You can start it like this:

 nginx -c /data/MyApp/etc/nginx.conf


ADDING FUNCTIONALITY

We also provide you with tools to build out your app. For example, if you want to add a new class to your app, you can:

 wing class --add=NewObject
 
This will dynamically generate a NewObject.pm class file for you in /data/MyApp/lib/MyApp/DB/Result/, and create a Rest
interface at /data/MyApp/lib/MyApp/Rest/NewObject.pm, and create a Web interface at /data/MyApp/lib/MyApp/Web/NewObject.pm.
It will even add the lines needed in /data/MyApp/bin/rest.psgi and /data/MyApp/bin/web.psgi.

To upgrade your database with the schema changes for your new class:

 increment the database version number in MyApp::DB
 wing db --prepare
 wing db --upgrade

For more information on managing the database schema see the DBIx::Class::DeploymentHandler documentation.

Once you've built out your object and you're ready to generate some web templates for it you can do:

 wing class --template=NewObject
 
That will add templates in /data/MyApp/views/newobject/*.tt. 

