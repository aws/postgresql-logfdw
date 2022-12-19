--
-- Test foreign-data wrapper log_fdw.
--

-- Install log_fdw
CREATE EXTENSION log_fdw;

-- Create foreign server
CREATE SERVER log_fdw_server FOREIGN DATA WRAPPER log_fdw;

-- Invalid option name
CREATE FOREIGN TABLE log_fdw_ftbl_err () SERVER log_fdw_server OPTIONS (foo 'bar');  -- ERROR

-- Invalid option value i.e. absolute path as value
CREATE FOREIGN TABLE log_fdw_ftbl_err () SERVER log_fdw_server OPTIONS (filename '/foo/bar');  -- ERROR

-- Option provided more than once
CREATE FOREIGN TABLE log_fdw_ftbl_err () SERVER log_fdw_server OPTIONS (filename 'foo', filename 'bar');  -- ERROR

-- Provided no option
CREATE FOREIGN TABLE log_fdw_ftbl_err () SERVER log_fdw_server;  -- ERROR

-- Check permissions
CREATE ROLE regress_log_fdw_nsuperuser;

-- A non-superuser has no permission to use log_fdw by default
SELECT has_function_privilege('regress_log_fdw_nsuperuser',
    'create_foreign_table_for_log_file(text, text, text)', 'EXECUTE'); -- no

SELECT has_function_privilege('regress_log_fdw_nsuperuser',
    'list_postgres_log_files()', 'EXECUTE'); -- no

-- A non-superuser can be granted permission to use log_fdw
GRANT EXECUTE ON FUNCTION create_foreign_table_for_log_file(text, text, text)
    TO regress_log_fdw_nsuperuser;

GRANT EXECUTE ON FUNCTION list_postgres_log_files()
    TO regress_log_fdw_nsuperuser;

SELECT has_function_privilege('regress_log_fdw_nsuperuser',
    'create_foreign_table_for_log_file(text, text, text)', 'EXECUTE'); -- yes

SELECT has_function_privilege('regress_log_fdw_nsuperuser',
    'list_postgres_log_files()', 'EXECUTE'); -- yes

-- Users with pg_read_server_files predefined role have permission to use
-- create_foreign_table_for_log_file() by default.
SELECT has_function_privilege('pg_read_server_files',
    'create_foreign_table_for_log_file(text, text, text)', 'EXECUTE'); -- yes


SELECT has_function_privilege('pg_read_server_files',
    'list_postgres_log_files()', 'EXECUTE'); -- yes

-- Users with pg_monitor predefined role have permission to use
-- list_postgres_log_files() by default.
SELECT has_function_privilege('pg_monitor',
    'list_postgres_log_files()', 'EXECUTE'); -- yes

-- Ensure that something gets logged to the server log file
SELECT 1/0;

-- Ensure there exists at least one server log file to work on
SElECT pg_rotate_logfile();
DO $$
DECLARE
    log_file INT := 0;
    loops INT := 0;
BEGIN
    LOOP
        log_file := COUNT(*) FROM list_postgres_log_files();
        -- Check if both .csv and .log files get created
        IF log_file >= 2 OR loops > 180 * 100 THEN EXIT; END IF;
        PERFORM pg_sleep(0.01);
        loops := loops + 1;
    END LOOP;
END
$$;

-- Check if .csv file gets created
SELECT COUNT(*) > 0 AS OK FROM list_postgres_log_files()
    WHERE file_name LIKE '%.csv';

-- Check if .log file gets created
SELECT COUNT(*) > 0 AS OK FROM list_postgres_log_files()
    WHERE file_name LIKE '%.log';

-- Get .csv server log file name and create a foreign table for it
DO $$
DECLARE
    log_file_name TEXT;
BEGIN
    log_file_name := file_name FROM list_postgres_log_files()
             WHERE file_name LIKE '%.csv' ORDER BY file_name ASC LIMIT 1;
    PERFORM create_foreign_table_for_log_file('log_fdw_ftbl_csv','log_fdw_server', log_file_name);
END
$$;

-- Ensure that the foreign table gets created
SELECT COUNT(*) > 0 AS OK FROM pg_foreign_table WHERE ftrelid = 'log_fdw_ftbl_csv'::regclass;

-- Ensure that the foreign table has read data from .csv server log file
SELECT COUNT(*) > 0 AS OK FROM log_fdw_ftbl_csv;

-- Get .log server log file name and create a foreign table for it
DO $$
DECLARE
    log_file_name TEXT;
BEGIN
    log_file_name := file_name FROM list_postgres_log_files()
             WHERE file_name LIKE '%.log' ORDER BY file_name ASC LIMIT 1;
    PERFORM create_foreign_table_for_log_file('log_fdw_ftbl_log','log_fdw_server', log_file_name);
END
$$;

-- Ensure that the foreign table gets created
SELECT COUNT(*) > 0 AS OK FROM pg_foreign_table WHERE ftrelid = 'log_fdw_ftbl_log'::regclass;

-- Ensure that the foreign table has read data from .log server log file
SELECT COUNT(*) > 0 AS OK FROM log_fdw_ftbl_log;

-- Clean up
DROP EXTENSION log_fdw CASCADE;
