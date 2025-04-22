# postgresql-logfdw/Makefile

MODULES = log_fdw

EXTENSION = log_fdw
DATA = log_fdw--1.4.sql log_fdw--1.4--1.5.sql
PGFILEDESC = "log_fdw - foreign data wrapper for Postgres log files"

REGRESS = log_fdw

REGRESS_OPTS = --temp-config $(top_srcdir)/contrib/postgresql-logfdw/log_fdw.conf

# Disabled because these tests require extra parameters to be set
# (see log_fdw.conf), which some installcheck users do not have
# (e.g. buildfarm clients).
NO_INSTALLCHECK = 1

ifdef USE_PGXS
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
else
subdir = contrib/postgresql-logfdw
top_builddir = ../..
include $(top_builddir)/src/Makefile.global
include $(top_srcdir)/contrib/contrib-global.mk
endif
