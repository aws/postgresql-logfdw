# contrib/file_fdw/Makefile

MODULES = file_fdw

EXTENSION = file_fdw
DATA = file_fdw--1.0.sql
PGFILEDESC = "file_fdw - foreign data wrapper for files"

# Removing regress target for file_fdw. This extension is not
# approved for use on Amazon RDS as of this Postgres version. While we
# still allow the extension to build, we remove the control
# file before bundling the rpm, thus we shouldn't test against it.
REGRESS =

EXTRA_CLEAN = sql/file_fdw.sql expected/file_fdw.out

ifdef USE_PGXS
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
else
subdir = contrib/file_fdw
top_builddir = ../..
include $(top_builddir)/src/Makefile.global
include $(top_srcdir)/contrib/contrib-global.mk
endif
