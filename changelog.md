# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## 1.5
### Security
- Reject `filename` values that are not a plain file name inside
  `log_directory`: absolute paths, directory separators, `.`, `..` and the
  empty string (path traversal). The check runs when the table is created and
  again on every read, so an existing foreign table whose `filename` contains
  a separator now fails on `SELECT`, and a dump containing such a table fails
  to restore. Recreate it with a name from `list_postgres_log_files()`.
- Revoke `EXECUTE` from `PUBLIC` on the four-argument
  `create_foreign_table_for_log_file()` added in 1.5, matching the
  three-argument form.
### Changed
- Rejecting an absolute `filename` now reports SQLSTATE 22023
  (`invalid_parameter_value`) instead of 42601 (`syntax_error`).
- The composed log file path is rejected when it exceeds `MAXPGPATH` rather
  than being silently truncated.
- `standalone-check` and the meson test refuse to run against an installed
  module that is older than the one just built.
### Added
- `create_foreign_table_for_log_file(text, text, text, bool)` with an
  `IF NOT EXISTS` option; extension version 1.5.
- Standalone meson build and test.
- `standalone-check` Makefile target for out-of-tree testing.
- PostgreSQL 18 in CI.
### Fixed
- Compile against PostgreSQL 18.

## [1.4] - 2024-10-13
First tagged release of this repository.
