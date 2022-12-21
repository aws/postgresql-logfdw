# log_fdw

This is a PostgreSQL extension built using Foreign-Data Wrapper facility to
enable reading log files via SQL. It basically provides SQL interface to create
foreign tables for each PostgreSQL log file through which the file contents can
be read and analyzed. Only superusers are allowed to create this extension.

## SQL functions
To create foreign table, use:
```
create_foreign_table_for_log_file(IN table_name TEXT, IN server_name TEXT, IN log_file_name TEXT)
```
To list files and their sizes present in PostgreSQL log directory, use:
```
list_postgres_log_files(OUT file_name TEXT, OUT file_size_bytes BIGINT)
```
Note that `list_postgres_log_files()` function is a wrapper around PostgreSQL's
core function [pg_ls_logdir](https://www.postgresql.org/docs/current/functions-admin.html#FUNCTIONS-ADMIN-GENFILE)
and exists for compatibility reasons.

By default, use of this extension's functions is restricted to superusers.
Access may be granted by superusers to others using GRANT as needed.
For instance, following are the minimal things that one needs to do for
enabling others to use the extension's functions:
```
CREATE ROLE foo; -- a non-superuser
GRANT pg_monitor TO foo; -- do this only when list_postgres_log_files() is used because the underlying function pg_ls_logdir() needs it
GRANT CREATE ON SCHEMA bar TO foo; -- to create foreign tables in schema named bar
GRANT USAGE ON FOREIGN SERVER log_fdw_server TO foo; -- to use log_fdw foreign server
SET ROLE foo;
SELECT * FROM create_foreign_table_for_log_file('log_file_tbl', 'log_fdw_server', 'log_file.csv');
```

## Quick install instructions

Clone the repository from https://github.com/aws/postgresql-logfdw:

```
git clone https://github.com/aws/postgresql-logfdw.git
``` 
Run `make clean` and `make install` to install the extension. Remember to set
`PATH` environment variable to point to `pg_config`. Alternatively, copy the
extension source code to `contrib` directory under PostgreSQL source tree and
install it.

## Usage

### Create extension:

```
postgres=# create extension log_fdw;
CREATE EXTENSION
```

### See functions created by extension:

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
```

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

### Create server:

```
postgres=# CREATE SERVER log_fdw_server FOREIGN DATA WRAPPER log_fdw;
CREATE SERVER
```

### Create foreign tables from csv files and log files:

```
postgres=# SELECT * FROM create_foreign_table_for_log_file('postgresql_2022_11_28_csv','log_fdw_server','postgresql-2022-11-28.csv');
 create_foreign_table_for_log_file 
-----------------------------------
 
(1 row)
```

```
postgres=# SELECT * FROM create_foreign_table_for_log_file('postgresql_2022_11_28_log','log_fdw_server','postgresql-2022-11-28.log');
 create_foreign_table_for_log_file 
-----------------------------------
 
(1 row)
```

### See foreign tables created:

```
postgres=# \detr
            List of foreign tables
 Schema |           Table           |  Server  
--------+---------------------------+----------------
 public | postgresql_2022_11_28_csv | log_fdw_server
 public | postgresql_2022_11_28_log | log_fdw_server
(2 rows)￼
```

### Read log file contents via foreign tables created:

SELECT * FROM postgresql_2022_11_14_log LIMIT 2;

```
postgres=# \x
Expanded display is on.
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

### Remove extension:

DROP EXTENSION log_fdw CASCADE;

```
postgres=# DROP EXTENSION log_fdw CASCADE;
NOTICE:  drop cascades to 3 other objects
DETAIL:  drop cascades to server log_fdw_server
drop cascades to foreign table postgresql_2022_11_28_csv
drop cascades to foreign table postgresql_2022_11_28_log
DROP EXTENSION
```

## Compatibility with PostgreSQL

This extension currently works well with PostgreSQL version 14, 15 and 16devel.

## LICENSE

See [LICENSE](https://github.com/aws/postgresql-logfdw/blob/main/LICENSE) for
detailed information.

## Contributing

See [CODE_OF_CONDUCT](https://github.com/aws/postgresql-logfdw/blob/main/CODE_OF_CONDUCT.md)
and [CONTRIBUTING](https://github.com/aws/postgresql-logfdw/blob/main/CONTRIBUTING.md)
for detailed information.
