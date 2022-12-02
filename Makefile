# /Makefile

MODULES = log_fdw

EXTENSION = log_fdw
DATA = log_fdw--1.0.sql
PGFILEDESC = "log_fdw - foreign data wrapper for files"

# Removing regress target for log_fdw. This extension is not
# approved for use on Amazon RDS as of this Postgres version. While we
# still allow the extension to build, we remove the control
# file before bundling the rpm, thus we shouldn't test against it.
REGRESS = log_fdw

EXTRA_CLEAN = sql/log_fdw.sql

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

