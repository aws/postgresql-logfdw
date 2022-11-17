/* /log_fdw--1.0.sql */

-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION log_fdw" to load this file. \quit


CREATE FUNCTION log_fdw_handler()
RETURNS fdw_handler
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT;

CREATE FUNCTION log_fdw_validator(text[], oid)
RETURNS void
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT;

CREATE FOREIGN DATA WRAPPER log_fdw
  HANDLER log_fdw_handler
  VALIDATOR log_fdw_validator;


CREATE OR REPLACE FUNCTION create_foreign_table_for_log_file(table_name text, server_name text, log_file_name text)
RETURNS void AS
$BODY$

DECLARE
log_file_dir TEXT;

BEGIN	
	SELECT setting INTO log_file_dir FROM pg_settings WHERE name='log_directory';
	
    IF substring(log_file_dir FROM 1 for 1) <> '/'
	THEN
		SELECT (SELECT setting FROM pg_settings WHERE name = 'data_directory') || '/' || (SELECT setting FROM pg_settings WHERE name = 'log_directory') INTO log_file_dir;
	END IF;

	IF log_file_name LIKE '%.csv' or log_file_name LIKE '%.csv.gz'
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
		  application_name		text,
		  backend_type			text,
		  leader_pid			integer,
		  query_id			bigint
		) SERVER %I
		OPTIONS (filename %L)',
		table_name, server_name, log_file_dir || '/' || log_file_name);
	ELSE
		EXECUTE format('CREATE FOREIGN TABLE %I (
		  log_entry text
		) SERVER %I
		OPTIONS (filename %L)',
		table_name, server_name, log_file_dir || '/' || log_file_name);
	END IF;
END
$BODY$
	LANGUAGE plpgsql;


/*
 * Redefine list_postgres_log_files() as an SRF so that queries like
 *
 *     SELECT list_postgres_log_files();
 *
 * do not fail with this error:
 *
 *     ERROR:  materialize mode required, but it is not allowed in this context
 */

DROP FUNCTION IF EXISTS list_postgres_log_files();
CREATE OR REPLACE FUNCTION list_postgres_log_files(
	OUT file_name TEXT,
	OUT file_size_bytes BIGINT)
RETURNS setof record
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT;
REVOKE ALL ON FUNCTION list_postgres_log_files() FROM PUBLIC;
ALTER FUNCTION list_postgres_log_files() OWNER TO pg_read_server_files;


REVOKE ALL ON FUNCTION log_fdw_handler() FROM PUBLIC;
REVOKE ALL ON FUNCTION log_fdw_validator(text[], oid) FROM PUBLIC;
REVOKE ALL ON FOREIGN DATA WRAPPER log_fdw FROM PUBLIC;
REVOKE ALL ON FUNCTION create_foreign_table_for_log_file(table_name text, server_name text, log_file_name text) FROM PUBLIC;