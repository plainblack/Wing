Wing is a modern web services platform written in Perl. It allows you to define objects and then automatically generates database schemas, restful web services, and even web form handlers to manage those objects. It's got built in users, sessions, single-sign-on and more.


INSTALLATION

1. Clone this repository into /data/Wing on your machine:

  mkdir /data
  cd /data
  git clone git@github.com:plainblack/Wing.git

2. Install the prereqs.

  /data/Wing/bin/setup/setup.sh

3. Create a project:

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

  /data/apps/bin/perl $WING_HOME/bin/wing db --install --force

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

 wing_add_class.pl --class=NewObject
 
This will dynamically generate a NewObject.pm class file for you in /data/MyApp/lib/MyApp/DB/Result/, and create a Rest
interface at /data/MyApp/lib/MyApp/Rest/NewObject.pm, and create a Web interface at /data/MyApp/lib/MyApp/Web/NewObject.pm.
It will even add the lines needed in /data/MyApp/bin/rest.psgi and /data/MyApp/bin/web.psgi.

Once you've built out your object and you're ready to generate some web templates for it you can do:

 wing_template_class.pl --class=NewObject
 
That will add templates in /data/MyApp/views/newobject/*.tt. 

