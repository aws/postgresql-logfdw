--
-- Test foreign-data wrapper log_fdw.
--

-- Clean up in case a prior regression run failed
SET client_min_messages TO 'error';
DROP ROLE IF EXISTS log_fdw_superuser, log_fdw_user, no_priv_user, "rds_superuser";
RESET client_min_messages;

CREATE ROLE log_fdw_superuser LOGIN SUPERUSER; -- is a superuser
CREATE ROLE log_fdw_user LOGIN;                -- has priv and user mapping
CREATE ROLE no_priv_user LOGIN;                 -- has priv but no user mapping
CREATE ROLE "rds_superuser" nosuperuser nologin nocreaterole inherit noreplication;


DROP extension if exists log_fdw;
-- Install log_fdw
CREATE EXTENSION log_fdw;

-- log_fdw_superuser owns fdw-related objects
SET ROLE log_fdw_superuser;
CREATE SERVER log_server FOREIGN DATA WRAPPER log_fdw;

-- privilege tests
SET ROLE log_fdw_user;
CREATE FOREIGN DATA WRAPPER log_fdw2 HANDLER log_fdw_handler VALIDATOR log_fdw_validator;   -- ERROR
CREATE SERVER log_server2 FOREIGN DATA WRAPPER log_fdw;   -- ERROR
CREATE USER MAPPING FOR log_fdw_user SERVER log_server;   -- ERROR

SET ROLE log_fdw_superuser;
GRANT USAGE ON FOREIGN SERVER log_server TO log_fdw_user;

SET ROLE log_fdw_user;
CREATE USER MAPPING FOR log_fdw_user SERVER log_server;

-- create user mappings and grant privilege to test users
SET ROLE log_fdw_superuser;
CREATE USER MAPPING FOR log_fdw_superuser SERVER log_server;
CREATE USER MAPPING FOR no_priv_user SERVER log_server;

-- validator tests
CREATE FOREIGN TABLE tbl () SERVER log_server OPTIONS (format 'xml');  -- ERROR
CREATE FOREIGN TABLE tbl () SERVER log_server OPTIONS (format 'text', header 'true');      -- ERROR
CREATE FOREIGN TABLE tbl () SERVER log_server OPTIONS (format 'text', quote ':');          -- ERROR
CREATE FOREIGN TABLE tbl () SERVER log_server OPTIONS (format 'text', escape ':');         -- ERROR
CREATE FOREIGN TABLE tbl () SERVER log_server OPTIONS (format 'binary', header 'true');    -- ERROR
CREATE FOREIGN TABLE tbl () SERVER log_server OPTIONS (format 'binary', quote ':');        -- ERROR
CREATE FOREIGN TABLE tbl () SERVER log_server OPTIONS (format 'binary', escape ':');       -- ERROR
CREATE FOREIGN TABLE tbl () SERVER log_server OPTIONS (format 'text', delimiter 'a');      -- ERROR
CREATE FOREIGN TABLE tbl () SERVER log_server OPTIONS (format 'text', escape '-');         -- ERROR
CREATE FOREIGN TABLE tbl () SERVER log_server OPTIONS (format 'csv', quote '-', null '=-=');   -- ERROR
CREATE FOREIGN TABLE tbl () SERVER log_server OPTIONS (format 'csv', delimiter '-', null '=-=');    -- ERROR
CREATE FOREIGN TABLE tbl () SERVER log_server OPTIONS (format 'csv', delimiter '-', quote '-');    -- ERROR
CREATE FOREIGN TABLE tbl () SERVER log_server OPTIONS (format 'csv', delimiter '---');     -- ERROR
CREATE FOREIGN TABLE tbl () SERVER log_server OPTIONS (format 'csv', quote '---');         -- ERROR
CREATE FOREIGN TABLE tbl () SERVER log_server OPTIONS (format 'csv', escape '---');        -- ERROR
CREATE FOREIGN TABLE tbl () SERVER log_server OPTIONS (format 'text', delimiter '\');       -- ERROR
CREATE FOREIGN TABLE tbl () SERVER log_server OPTIONS (format 'text', delimiter '.');       -- ERROR
CREATE FOREIGN TABLE tbl () SERVER log_server OPTIONS (format 'text', delimiter '1');       -- ERROR
CREATE FOREIGN TABLE tbl () SERVER log_server OPTIONS (format 'text', delimiter 'a');       -- ERROR
CREATE FOREIGN TABLE tbl () SERVER log_server OPTIONS (format 'csv', delimiter '');       -- ERROR
CREATE FOREIGN TABLE tbl () SERVER log_server OPTIONS (format 'csv', null '');       -- ERROR
CREATE FOREIGN TABLE tbl () SERVER log_server;  -- ERROR

-- file path validation tests
CREATE FOREIGN TABLE agg_text (
	a	int2 CHECK (a >= 0),
	b	float4
) SERVER log_server
OPTIONS (filename 'a');
CREATE FOREIGN TABLE agg_text (
        a       int2 CHECK (a >= 0),
        b       float4
) SERVER log_server
OPTIONS (filename 'alsdfkjalskdjfhlsdkjhasdflkjahsdflkjhasdflkjhasdlfkjahsdlfkjhasdlkfjhasdf');
CREATE FOREIGN TABLE agg_text (
        a       int2 CHECK (a >= 0),
        b       float4
) SERVER log_server
OPTIONS (filename '/rdsdbdata/log/error/../../../hax.csv');
CREATE FOREIGN TABLE agg_text (
        a       int2 CHECK (a >= 0),
        b       float4
) SERVER log_server
OPTIONS (filename '/rdsdbdata/log/error/postgresql.log.abcdef.csv');

CREATE FOREIGN TABLE pglog_1 (
  log_time timestamp(3) with time zone,
  user_name text,
  database_name text,
  process_id integer,
  connection_from text,
  session_id text,
  session_line_num bigint,
  command_tag text,
  session_start_time timestamp with time zone,
  virtual_transaction_id text,
  transaction_id bigint,
  error_severity text,
  sql_state_code text,
  message text,
  detail text,
  hint text,
  internal_query text,
  internal_query_pos integer,
  context text,
  query text,
  query_pos integer,
  location text,
  application_name text,
  backend_type text,
  leader_pid integer,
  query_id bigint
) SERVER log_server
OPTIONS ( filename '/rdsdbdata/log/error/postgresql.log.2016-08-09-22.csv');
GRANT SELECT ON pglog_1 to log_fdw_user;
ALTER FOREIGN TABLE pglog_1 ADD CHECK (process_id > 0);

CREATE FOREIGN TABLE pglog_2 (
  log_time timestamp(3) with time zone,
  user_name text,
  database_name text,
  process_id integer,
  connection_from text,
  session_id text,
  session_line_num bigint,
  command_tag text,
  session_start_time timestamp with time zone,
  virtual_transaction_id text,
  transaction_id bigint,
  error_severity text,
  sql_state_code text,
  message text,
  detail text,
  hint text,
  internal_query text,
  internal_query_pos integer,
  context text,
  query text,
  query_pos integer,
  location text,
  application_name text,
  backend_type text,
  leader_pid integer,
  query_id bigint
) SERVER log_server
OPTIONS ( filename '/rdsdbdata/log/error/postgresql.log.2016-08-09-23.csv');
ALTER FOREIGN TABLE pglog_2 ADD CHECK (process_id > 0);

CREATE FOREIGN TABLE pglog_3 (
  log_time timestamp(3) with time zone,
  user_name text,
  database_name text,
  process_id integer,
  connection_from text,
  session_id text,
  session_line_num bigint,
  command_tag text,
  session_start_time timestamp with time zone,
  virtual_transaction_id text,
  transaction_id bigint,
  error_severity text,
  sql_state_code text,
  message text,
  detail text,
  hint text,
  internal_query text,
  internal_query_pos integer,
  context text,
  query text,
  query_pos integer,
  location text,
  application_name text,
  backend_type text,
  leader_pid integer,
  query_id bigint
) SERVER log_server
OPTIONS ( filename '/rdsdbdata/log/error/postgresql.log.2016-08-10-00.csv');
ALTER FOREIGN TABLE pglog_3 ADD CHECK (process_id > 0);

CREATE FOREIGN TABLE pglog_bad (
  user_name text,
  database_name text,
  process_id integer,
  connection_from text,
  session_id text,
  session_line_num bigint,
  command_tag text,
  session_start_time timestamp with time zone,
  virtual_transaction_id text,
  transaction_id bigint,
  error_severity text,
  sql_state_code text,
  message text,
  detail text,
  hint text,
  internal_query text,
  internal_query_pos integer,
  context text,
  query text
) SERVER log_server
OPTIONS ( filename '/rdsdbdata/log/error/postgresql.log.2016-08-10-01.csv');

-- basic query tests
SELECT log_time, process_id, error_severity, message FROM pglog_1 where error_severity = 'LOG';
SELECT log_time, process_id, error_severity, message FROM pglog_2 ORDER BY log_time DESC;
SELECT log_time, process_id, error_severity, message FROM pglog_3 where log_time = 'Tue Aug 09 15:45:20.066 2016 PDT';

-- error context report tests
SELECT * FROM pglog_bad;               -- ERROR

-- misc query tests
\t on
EXPLAIN (VERBOSE, COSTS FALSE) SELECT * FROM pglog_1;
\t off
PREPARE st(text) AS SELECT * FROM pglog_1 WHERE error_severity = $1;
EXECUTE st('DEBUG');
EXECUTE st('DEBUG');
DEALLOCATE st;

-- tableoid
SELECT tableoid::regclass, log_time FROM pglog_2;

-- updates aren't supported
UPDATE pglog_1 SET error_severity = 'WARNING';
DELETE FROM pglog_2 WHERE error_severity = 'DEBUG';
-- but this should be allowed
SELECT * FROM pglog_3 FOR UPDATE;

-- constraint exclusion tests
\t on
EXPLAIN (VERBOSE, COSTS FALSE) SELECT * FROM pglog_1 WHERE process_id < 0;
\t off
SELECT * FROM pglog_1 WHERE process_id < 0;
SET constraint_exclusion = 'on';
\t on
EXPLAIN (VERBOSE, COSTS FALSE) SELECT * FROM pglog_1 WHERE process_id < 0;
\t off
SELECT * FROM pglog_1 WHERE process_id < 0;
RESET constraint_exclusion;

-- table inheritance tests
CREATE TABLE agg (
  log_time timestamp(3) with time zone,
  user_name text,
  database_name text,
  process_id integer,
  connection_from text,
  session_id text,
  session_line_num bigint,
  command_tag text,
  session_start_time timestamp with time zone,
  virtual_transaction_id text,
  transaction_id bigint,
  error_severity text,
  sql_state_code text,
  message text,
  detail text,
  hint text,
  internal_query text,
  internal_query_pos integer,
  context text,
  query text,
  query_pos integer,
  location text,
  application_name text,
  backend_type text,
  leader_pid integer,
  query_id bigint);
ALTER FOREIGN TABLE pglog_1 INHERIT agg;
SELECT tableoid::regclass, * FROM agg;
SELECT tableoid::regclass, * FROM pglog_1;
SELECT tableoid::regclass, * FROM ONLY agg;
-- updates aren't supported
UPDATE agg SET error_severity = 'WARNING';
DELETE FROM agg WHERE error_severity = 'LOG';
-- but this should be allowed
SELECT tableoid::regclass, * FROM agg FOR UPDATE;
ALTER FOREIGN TABLE pglog_1 NO INHERIT agg;
DROP TABLE agg;

-- privilege tests
SET ROLE log_fdw_superuser;
SELECT * FROM pglog_2 ORDER BY log_time;
SET ROLE log_fdw_user;
SELECT * FROM pglog_2 ORDER BY log_time;
SET ROLE no_priv_user;
SELECT * FROM pglog_2 ORDER BY log_time;   -- ERROR
SET ROLE log_fdw_user;
\t on
EXPLAIN (VERBOSE, COSTS FALSE) SELECT * FROM pglog_2 WHERE process_id > 0;
\t off
-- log FDW allows foreign tables to be accessed without user mapping
DROP USER MAPPING FOR log_fdw_user SERVER log_server;
SELECT * FROM pglog_2 ORDER BY log_time;

-- privilege tests for object
SET ROLE log_fdw_superuser;
ALTER FOREIGN TABLE pglog_3 OWNER TO log_fdw_user;
ALTER FOREIGN TABLE pglog_3 OPTIONS (SET filename 'a');
ALTER FOREIGN TABLE pglog_3 OPTIONS (SET format 'text');
ALTER FOREIGN TABLE pglog_3 OPTIONS (SET filename '/rdsdbdata/log/error/postgresql.log.2016-08-10-01.csv');
SET ROLE log_fdw_user;
ALTER FOREIGN TABLE pglog_3 OPTIONS (SET filename '/rdsdbdata/log/error/postgresql.log.2016-08-10-01.csv');
SET ROLE log_fdw_superuser;

-- make sure list function works
SELECT * from list_postgres_log_files() order by 1;
SELECT list_postgres_log_files() ORDER BY 1;

-- make sure helper function for creating table works
SELECT create_foreign_table_for_log_file('my_postgres_error_log', 'log_server', 'postgresql.log.2016-08-09-22.csv');
SELECT log_time, message from my_postgres_error_log order by 1;

-- make sure helper function for creating table errors out at appropriate times
SELECT create_foreign_table_for_log_file('my_postgres_error_log_2', 'log_server', 'postgresql.log.doesnt_exist.csv');
SELECT create_foreign_table_for_log_file('my_postgres_error_log', 'log_server', 'postgresql.log.2016-08-09-22.csv');
SELECT create_foreign_table_for_log_file('my_postgres_error_log_2', 'doesnt_exist', 'postgresql.log.2016-08-09-22.csv');
SELECT create_foreign_table_for_log_file(123, 456, 789);

-- double check the identifier quoting
SELECT create_foreign_table_for_log_file('quote me', 'log_server', 'postgresql.log.2016-08-09-22.csv');
SELECT log_time, message from "quote me" order by 1;

-- make sure you cannot hax the helper function for creating table
SELECT create_foreign_table_for_log_file('dealwithit"; select 1; --', 'whatever', 'whatever');

-- make sure you cannot create a foreign table for the log directory or its parent directory
SELECT create_foreign_table_for_log_file('postgres_log_dir', 'log_server', '.');
SELECT create_foreign_table_for_log_file('postgres_log_dir', 'log_server', '..');
SELECT create_foreign_table_for_log_file('postgres_log_dir', 'log_server', '');

-- make sure you can create foreign table for non-CSV files
SELECT create_foreign_table_for_log_file('sonnet116', 'log_server', 'sonnet116.txt');
SELECT create_foreign_table_for_log_file('n', 'log_server', 'n');
SELECT * from sonnet116;
SELECT * from n;


-- make sure we can create foreign table for compressed csv and non-csv files
SELECT create_foreign_table_for_log_file('sonnet116_compressed', 'log_server', 'sonnet116.compressed.txt.gz');
SELECT create_foreign_table_for_log_file('pglog_compressed', 'log_server', 'postgresql.log.2016-08-09-22.compressed.csv.gz');
SELECT * from sonnet116_compressed;
SELECT log_time, message from "pglog_compressed" order by 1;

-- make sure badly formatted compressed files throw error
SELECT create_foreign_table_for_log_file('badcsv_compressed', 'log_server', 'badcsvformat.csv.gz');
SELECT * from badcsv_compressed; --ERROR

SELECT create_foreign_table_for_log_file('badgz_compressed', 'log_server', 'postgresql.log.bad.gzfile.gz');
SELECT * from badgz_compressed; --ERROR

-- make sure log_fdw will generate apporiate error report when log file or a portion of the log file was created by a version of PostgreSQL that the installed version of log_fdw cannot read
SELECT create_foreign_table_for_log_file('pglog_old', 'log_server', 'postgresql.log.old.csv');
SELECT * from pglog_old;

SELECT create_foreign_table_for_log_file('pglog_mix', 'log_server', 'postgresql.log.mix.csv');
SELECT * from pglog_mix;

-- non-rds_superusers can run create_foreign_table_for_log_file()
GRANT EXECUTE ON FUNCTION create_foreign_table_for_log_file(text, text, text) TO no_priv_user;
GRANT USAGE ON FOREIGN SERVER log_server TO no_priv_user;
SET ROLE no_priv_user;
SELECT create_foreign_table_for_log_file('priv_test', 'log_server', 'sonnet116.txt');
RESET ROLE;

-- file path is checked even without validator function
ALTER FOREIGN DATA WRAPPER log_fdw NO VALIDATOR;
CREATE FOREIGN TABLE validator1 (a INT) SERVER log_server OPTIONS (filename '/a/b/c');
CREATE FOREIGN TABLE validator2 (a INT) SERVER log_server OPTIONS (filename 'alsdfkjalskdjfhlsdkjhasdflkjahsdflkjhasdflkjhasdlfkjahsdlfkjhasdlkfjhasdf');
CREATE FOREIGN TABLE validator3 (a INT) SERVER log_server OPTIONS (filename '/rdsdbdata/log/error/../../../hax.csv');
CREATE FOREIGN TABLE validator4 (a INT) SERVER log_server OPTIONS (filename '/rdsdbdata/log/error/postgresql.log.abcdef.csv');
CREATE FOREIGN TABLE validator5 (a INT) SERVER log_server OPTIONS (filename '/rdsdbdata/log/error');
CREATE FOREIGN TABLE validator6 (a INT) SERVER log_server OPTIONS (filename '/rdsdbdata/log/error/');
CREATE FOREIGN TABLE validator7 (a INT) SERVER log_server OPTIONS (filename '/rdsdbdata/log/error/../../../somefile.txt');
SELECT * FROM validator1;
SELECT * FROM validator2;
SELECT * FROM validator3;
SELECT * FROM validator4;
SELECT * FROM validator5;
SELECT * FROM validator6;
SELECT * FROM validator7;

-- cleanup
DROP EXTENSION log_fdw CASCADE;
DROP ROLE log_fdw_superuser, log_fdw_user, no_priv_user;

