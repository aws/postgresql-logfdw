/* contrib/file_fdw/file_fdw--1.0.sql */

-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION file_fdw" to load this file. \quit

CREATE FUNCTION file_fdw_handler()
RETURNS fdw_handler
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT;

CREATE FUNCTION file_fdw_validator(text[], oid)
RETURNS void
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT;

CREATE FOREIGN DATA WRAPPER file_fdw
  HANDLER file_fdw_handler
  VALIDATOR file_fdw_validator;


CREATE FUNCTION list_postgres_log_files(
	OUT file_name TEXT,
	OUT file_size_bytes BIGINT)
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT;

CREATE FUNCTION create_foreign_table_for_log_file(table_name text, server_name text, log_file_name text)
RETURNS void AS
$BODY$
BEGIN
	IF $3 LIKE '%.csv' or $3 LIKE '%.csv.gz'
	THEN
		EXECUTE format('CREATE FOREIGN TABLE %I (
		  log_time			timestamp(3) with time zone,
		  user_name			text,
		  database_name			text,
		  process_id			integer,
		  connection_from		text,
		  session_id			text,
		  session_line_num		bigint,
		  command_tag			text,
		  session_start_time		timestamp with time zone,
		  virtual_transaction_id	text,
		  transaction_id		bigint,
		  error_severity		text,
		  sql_state_code		text,
		  message			text,
		  detail			text,
		  hint				text,
		  internal_query		text,
		  internal_query_pos		integer,
		  context			text,
		  query				text,
		  query_pos			integer,
		  location			text,
		  application_name		text
		) SERVER %I
		OPTIONS (filename %L)',
		$1, $2, '/home/kadamnn/workplace/pg_14/data/log/' || $3);
	ELSE
		EXECUTE format('CREATE FOREIGN TABLE %I (
		  log_entry text
		) SERVER %I
		OPTIONS (filename %L)',
		$1, $2, '/home/kadamnn/workplace/pg_14/data/log/' || $3);
	END IF;
END
$BODY$
	LANGUAGE plpgsql;

REVOKE ALL ON FUNCTION file_fdw_handler() FROM PUBLIC;
REVOKE ALL ON FUNCTION file_fdw_validator(text[], oid) FROM PUBLIC;
REVOKE ALL ON FOREIGN DATA WRAPPER file_fdw FROM PUBLIC;
REVOKE ALL ON FUNCTION list_postgres_log_files() FROM PUBLIC;
REVOKE ALL ON FUNCTION create_foreign_table_for_log_file(table_name text, server_name text, log_file_name text) FROM PUBLIC;

--ALTER FUNCTION file_fdw_handler() OWNER TO rds_superuser;
--ALTER FUNCTION file_fdw_validator(text[], oid) OWNER TO rds_superuser;
--ALTER FOREIGN DATA WRAPPER file_fdw OWNER TO rds_superuser;
--ALTER FUNCTION list_postgres_log_files() OWNER TO rds_superuser;
--ALTER FUNCTION create_foreign_table_for_log_file(table_name text, server_name text, log_file_name text) OWNER TO rds_superuser;
