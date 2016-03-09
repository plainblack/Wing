Wing is a modern web services platform written in Perl. It allows you to define objects and then automatically generates database schemas, restful web services, and even web form handlers to manage those objects. It's got built in users, sessions, single-sign-on and more.


INSTALLATION

0. Do the prep for your OS. For example, if you're on Amazon Linux, then look at README.Amazon.txt to see the prep steps.

1. Clone this repository into /data/Wing on your machine:

  mkdir /data
  cd /data
  git clone https://github.com/plainblack/Wing.git

2. Install the prereqs.

  /data/Wing/bin/setup/setup.sh

3. Verify/set apps paths.

  perl -v  # should return 5.16.2, the version required by Wing.  If not:
  source /data/Wing/bin/dataapps.sh
  perl -v  # should return 5.16.2

4. Create a project in /data/MyApp:

  cd /data/Wing/bin
  export WING_HOME=/data/Wing
  perl wing_init_app.pl --app=MyApp

  NOTE: If you get an error a la "Illegal division by zero" from warnings.pm in this step, revisit step 3.

5. Create a database on your MySQL server to host the project, and edit the Wing config to match:

  mysql -uroot -p -e "create database my_project"
  mysql -uroot -p -e "grant all privileges on my_project.* to some_user@localhost identified by 'some_pass'" 
  mysql -uroot -p -e "flush privileges" 

6. Modify the config file. You need to at least edit the "db" section to tell Wing how to log in to your database. You may also wish to update other settings.

  vi /data/MyApp/etc/wing.conf  

NOTE: You can also edit the location of the logs in /data/MyApp/etc/log4perl.conf. It is defaultly set to /data/apps/logs/MyApp.log

7. Initialize the database:

  cd /data/MyApp/bin
  export WING_HOME=/data/Wing
  export WING_APP=/data/MyApp/
  export WING_CONFIG=/data/MyApp/etc/wing.conf

  wing db --prepare_install
  wing db --install --force

8. Start up the rest server and/or web server:

  cd /data/MyApp/bin
  ./start_rest.sh
  ./start_web.sh

9. Now you can connect to the rest server and see if it's alive:

  curl http://localhost:5000/api/status

  curl http://localhost:5001/account

  NOTE: By default there is one user named 'Admin' with a password of '123qwe'.

10. We also provide you with an nginx config file to give you a baseline for serving your apps. You can start it like this:

  nginx -c /data/MyApp/etc/nginx.conf

  NOTE: This is required to merge together the two services, as well as serve up static files.

  WARNING: There is no "home" page. Wing is expecting you to create it. After you start Nginx you'll be able to access /account and /admin. Everything is will 404. 


OPTIONAL

11. Wing has a job server called Wingman, which is backed by beanstalkd. To run it you simply install beanstalkd, which you can download from here: http://kr.github.io/beanstalkd/

Then you can run it like so:

beanstalkd &

And finally you run Wing's job server by typing:

wingman.pl start






ADDING FUNCTIONALITY

We also provide you with tools to build out your app. For example, if you want to add a new class to your app, you can:

  wing class --add=NewObject
 
This will dynamically generate a NewObject.pm class file for you in /data/MyApp/lib/MyApp/DB/Result/, and create a Rest
interface at /data/MyApp/lib/MyApp/Rest/NewObject.pm, and create a Web interface at /data/MyApp/lib/MyApp/Web/NewObject.pm.
It will even add the lines needed in /data/MyApp/lib/MyQpp/Rest.pm and /data/MyApp/lib/MyApp/Web.pm.

After adding a new class you'll need to restart a few services:

  cd /data/MyApp/bin
  ./restart_web.sh
  ./restart_rest.sh
  wingman.pl restart

To upgrade your database with the schema changes for your new class:

  increment the database version number in MyApp::DB
  wing db --prepare
  wing db --upgrade

For more information on managing the database schema see the DBIx::Class::DeploymentHandler documentation.

Once you've built out your object and you're ready to generate some web templates for it you can do:

  wing class --template=NewObject
 
That will add templates in /data/MyApp/views/newobject/*.tt. 

We can even generate some basic tests for you:

  wing class --test=NewObject

That will add tests in /data/MyApp/t


For more information type:

  perldoc lib/Wing/FirstApp.pod



