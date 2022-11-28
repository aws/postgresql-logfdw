# Log_fdw - (A Foreign-Data Wrapper to enable reading PostgreSQL log files)

This is a postgres extension which enables reading PostgreSQL log files via SQL
In log fdw the data source options are filename, and program 
Either filename or program option is required for log_fdw foreign tables
SQL function list_postgres_log_files is used as Foreign-data wrapper handler function
Only superusers are allowed to set options of a log_fdw foreign table. This is because we don't want non-superusers to be able to control which file gets read or which program gets executed.


## Quick install instructions
Clone the repository: https://github.com/aws/postgresql-logfdw 

```
git clone https://github.com/aws/postgresql-logfdw.git
``` 

```
make clean
make install
```

Go ahead and create extension:

```
postgres=# create extension log_fdw;
CREATE EXTENSION
```

To see the functions created:

```
postgres=# \df
                                                      List of functions
 Schema |               Name                | Result data type |                  Argument data types                  | Type 
--------+-----------------------------------+------------------+-------------------------------------------------------+------
 public | create_foreign_table_for_log_file | void             | table_name text, server_name text, log_file_name text | func
 public | list_postgres_log_files           | SETOF record     | OUT file_name text, OUT file_size_bytes bigint        | func
 public | log_fdw_handler                   | fdw_handler      |                                                       | func
 public | log_fdw_validator                 | void             | text[], oid                                           | func
(4 rows)
￼```

```
postgres=# SELECT * FROM list_postgres_log_files() LIMIT 10;
         file_name         | file_size_bytes 
---------------------------+-----------------
 postgresql-2022-10-13.csv |               0
 postgresql-2022-11-14.log |            8006
 postgresql-2022-11-01.csv |            4025
 postgresql-2022-10-27.csv |               0
 postgresql-2022-10-24.log |               0
 postgresql-2022-11-05.log |               0
 postgresql-2022-11-23.log |          789872
 postgresql-2022-11-07.csv |               0
 postgresql-2022-11-04.csv |            3943
 postgresql-2022-11-16.log |               0
(10 rows)
```

```
postgres=# SELECT * FROM list_postgres_log_files() ORDER BY 1 DESC LIMIT 2;
         file_name         | file_size_bytes 
---------------------------+-----------------
 postgresql-2022-11-28.log |            1754
 postgresql-2022-11-28.csv |            1948
(2 rows)
```

Create server:

```
postgres=# CREATE SERVER pg_local FOREIGN DATA WRAPPER log_fdw;
CREATE SERVER
```

Create tables from csv files and log files:

```
postgres=# SELECT * FROM create_foreign_table_for_log_file('postgresql_2022_11_28_csv','pg_local','postgresql-2022-11-28.csv');
 create_foreign_table_for_log_file 
-----------------------------------
 
(1 row)
```

```
postgres=# SELECT * FROM create_foreign_table_for_log_file('postgresql_2022_11_28_log','pg_local','postgresql-2022-11-28.log');
 create_foreign_table_for_log_file 
-----------------------------------
 
(1 row)
```

To see tables created:

```
postgres=# \detr
            List of foreign tables
 Schema |           Table           |  Server  
--------+---------------------------+----------
 public | postgresql_2022_11_28_csv | pg_local
 public | postgresql_2022_11_28_log | pg_local
(2 rows)￼
```

Switch on expanded display:

```
postgres=# \x
Expanded display is on.
```

Select query on tables created:
SELECT * FROM postgresql_2022_11_14_log LIMIT 2;

```
postgres=# select * from postgresql_2022_11_28_log limit 2;
-[ RECORD 1 ]---------------------------------------------------------------------------------------------------------------------------
log_entry | 2022-11-28 20:37:51.767 UTC   14170  637e8d69.375a 7  2022-11-23 21:15:21 UTC  0 00000LOG:  received fast shutdown request
-[ RECORD 2 ]---------------------------------------------------------------------------------------------------------------------------
log_entry | 2022-11-28 20:37:51.769 UTC   14170  637e8d69.375a 8  2022-11-23 21:15:21 UTC  0 00000LOG:  aborting any active transactions
```

SELECT * FROM postgresql_2022_11_28_csv LIMIT 2;

```
postgres=# select * from postgresql_2022_11_28_csv limit 2;
-[ RECORD 1 ]----------+---------------------------------
log_time               | 2022-11-28 20:37:51.767+00
user_name              | 
database_name          | 
process_id             | 14170
connection_from        | 
session_id             | 637e8d69.375a
session_line_num       | 5
command_tag            | 
session_start_time     | 2022-11-23 21:15:21+00
virtual_transaction_id | 
transaction_id         | 0
error_severity         | LOG
sql_state_code         | 00000
message                | received fast shutdown request
detail                 | 
hint                   | 
internal_query         | 
internal_query_pos     | 
context                | 
query                  | 
query_pos              | 
location               | 
application_name       | 
backend_type           | postmaster
leader_pid             | 
query_id               | 0
-[ RECORD 2 ]----------+---------------------------------
log_time               | 2022-11-28 20:37:51.769+00
user_name              | 
database_name          | 
process_id             | 14170
connection_from        | 
session_id             | 637e8d69.375a
session_line_num       | 6
command_tag            | 
session_start_time     | 2022-11-23 21:15:21+00
virtual_transaction_id | 
transaction_id         | 0
error_severity         | LOG
sql_state_code         | 00000
message                | aborting any active transactions
detail                 | 
hint                   | 
internal_query         | 
internal_query_pos     | 
context                | 
query                  | 
query_pos              | 
location               | 
application_name       | 
backend_type           | postmaster
leader_pid             | 
query_id               | 0
```

￼


To remove extension:
DROP EXTENSION log_fdw CASCADE;

```
postgres=# DROP EXTENSION log_fdw CASCADE;
NOTICE:  drop cascades to 3 other objects
DETAIL:  drop cascades to server pg_local
drop cascades to foreign table postgresql_2022_11_28_csv
drop cascades to foreign table postgresql_2022_11_28_log
DROP EXTENSION
```

