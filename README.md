Log_fdw - (Foreign-Data Wrapper for Postgres log files)

This is a postgres extension which allows you to read PostgreSQL log files in a csv format and non csv format
In log fdw the data source options are filename, and program 
Either filename or program option is required for log_fdw foreign tables
SQL function list_postgres_log_files is used as Foreign-data wrapper handler function
Only superusers are allowed to set options of a file_fdw foreign table. This is because we don't want non-superusers to be able to control which file gets read or which program gets executed.


Quick install instructions

Clone the repository: https://github.com/aws/postgresql-logfdw 
git clone https://github.com/aws/postgresql-logfdw.git 

make clean
make install

Go ahead and create extension:
CREATE EXTENSION log_fdw;

To see the functions created:
\df

￼

SELECT * FROM list_postgres_log_files() LIMIT 10;

￼

SELECT * FROM list_postgres_log_files() ORDER BY 1 DESC LIMIT 2;

￼

Create server:
CREATE SERVER pg_local FOREIGN DATA WRAPPER log_fdw; 

Create tables from csv files and log files
SELECT * FROM create_foreign_table_for_log_file('postgresql_2022_11_14_csv','pg_local','postgresql-2022-11-14.csv');
SELECT * FROM create_foreign_table_for_log_file('postgresql_2022_11_14_log','pg_local','postgresql-2022-11-14.log');

To see tables created:
\detr
￼

Select query on tables created:
SELECT * FROM postgresql_2022_11_14_log LIMIT 2;
￼

\x
SELECT * FROM postgresql_2022_11_14_csv LIMIT 2;

￼


To remove extension:
DROP EXTENSION log_fdw CASCADE;

