create database if not exists testwing;
create user if not exists 'testwing'@'localhost' identified by 'testwing';
grant all privileges on `testwing%`.* to 'testwing'@'localhost';
