/* log_fdw--1.4--1.5 */

/*
 * Creates foreign table for a given server log file.
 */
CREATE OR REPLACE FUNCTION create_foreign_table_for_log_file(
	table_name TEXT,
	server_name TEXT,
	log_file_name TEXT,
	if_not_exists BOOL)
RETURNS void AS
$BODY$
DECLARE
	l_exists_str    text := '';
BEGIN
	IF if_not_exists
	THEN
		l_exists_str := 'IF NOT EXISTS';
	END IF;

	IF $3 LIKE '%.csv' or $3 LIKE '%.csv.gz'
	THEN
		EXECUTE format('CREATE FOREIGN TABLE %s %I (
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
		l_exists_str, $1, $2, $3);
	ELSE
		EXECUTE format('CREATE FOREIGN TABLE %s %I (
		  log_entry text
		) SERVER %I
		OPTIONS (filename %L)',
		l_exists_str, $1, $2, $3);
	END IF;
END
$BODY$
	LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION create_foreign_table_for_log_file(
	table_name TEXT,
	server_name TEXT,
	log_file_name TEXT)
 RETURNS void
 LANGUAGE sql
BEGIN ATOMIC
	SELECT create_foreign_table_for_log_file(table_name, server_name, log_file_name, false);
END;
