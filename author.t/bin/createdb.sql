create database testwing;
create user 'testwing'@'localhost' identified by 'testwing';
grant all privileges on `testwing%`.* to 'testwing'@'localhost';
