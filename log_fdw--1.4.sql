/*
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License").
 * You may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "ALTER EXTENSION log_fdw UPDATE TO '1.4'" to load this file. \quit

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

/*
 * Although pg_ls_logdir() can be used instead of this function, we maintain
 * list_postgres_log_files() as a wrapper around that to not to break
 * applications built around log_fdw extension.
 */
CREATE OR REPLACE FUNCTION list_postgres_log_files(
    OUT file_name TEXT,
    OUT file_size_bytes BIGINT)
 RETURNS SETOF record
 LANGUAGE sql
 VOLATILE PARALLEL SAFE STRICT
BEGIN ATOMIC
    SELECT name AS file_name, size AS file_size_bytes FROM pg_ls_logdir();
END;

CREATE OR REPLACE FUNCTION create_foreign_table_for_log_file(table_name text, server_name text, log_file_name text)
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
		  application_name		text,
		  backend_type			text,
		  leader_pid			integer,
		  query_id			bigint
		) SERVER %I
		OPTIONS (filename %L)',
		$1, $2, $3);
	ELSE
		EXECUTE format('CREATE FOREIGN TABLE %I (
		  log_entry text
		) SERVER %I
		OPTIONS (filename %L)',
		$1, $2, $3);
	END IF;
END
$BODY$
	LANGUAGE plpgsql;

REVOKE ALL ON FUNCTION log_fdw_handler() FROM PUBLIC;
REVOKE ALL ON FUNCTION log_fdw_validator(text[], oid) FROM PUBLIC;
REVOKE ALL ON FOREIGN DATA WRAPPER log_fdw FROM PUBLIC;
REVOKE ALL ON FUNCTION list_postgres_log_files() FROM PUBLIC;
REVOKE ALL ON FUNCTION create_foreign_table_for_log_file(text, text, text) FROM PUBLIC;

/*
 * Let pg_monitor role execute list_postgres_log_files() to be in sync with its
 * core function pg_ls_logdir().
 */
GRANT EXECUTE ON FUNCTION list_postgres_log_files() TO pg_read_server_files, pg_monitor;
GRANT EXECUTE ON FUNCTION create_foreign_table_for_log_file(text, text, text) TO pg_read_server_files;
