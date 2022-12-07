EXTENSION = log_fdw
EXTVERSION = 1.4

MODULES = log_fdw

DB_SUPERUSER ?= postgres

DATA = log_fdw.control log_fdw--1.4.sql
PGFILEDESC = "log_fdw - foreign data wrapper for Postgres log files"

#REGRESS = log_fdw

EXTRA_CLEAN = log_fdw.control log_fdw--1.4.sql
#EXTRA_CHECK = set_up_test_files.sh

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

all: log_fdw--1.4.sql 

log_fdw.control: log_fdw.control.in
	sed 's,EXTVERSION,$(EXTVERSION),g' $< > $@;

log_fdw--1.4.sql: log_fdw--1.4.sql.in
	sed 's,DB_SUPERUSER,$(DB_SUPERUSER),g' $< > $@;

