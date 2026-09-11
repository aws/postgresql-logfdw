# postgresql-logfdw/Makefile

MODULES = log_fdw

EXTENSION = log_fdw
DATA = log_fdw--1.4.sql log_fdw--1.4--1.5.sql
PGFILEDESC = "log_fdw - foreign data wrapper for Postgres log files"

REGRESS = log_fdw

ifdef USE_PGXS
REGRESS_OPTS = --temp-config $(CURDIR)/log_fdw.conf
else
REGRESS_OPTS = --temp-config $(top_srcdir)/contrib/postgresql-logfdw/log_fdw.conf
endif

# Disabled because these tests require extra parameters to be set
# (see log_fdw.conf), which some installcheck users do not have
# (e.g. buildfarm clients).
NO_INSTALLCHECK = 1

ifdef USE_PGXS
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

# pgxs.mk's "check" is only a stub, and NO_INSTALLCHECK above removes
# "installcheck", so out-of-tree builds would have no way to run the suite.
# Drive pg_regress directly against a temporary instance instead.  The
# extension has to be installed first, because pg_regress resolves
# CREATE EXTENSION through the server's own sharedir and pkglibdir:
#
#	make USE_PGXS=1 install
#	make USE_PGXS=1 standalone-check
#
PG_REGRESS = $(shell $(PG_CONFIG) --pkglibdir)/pgxs/src/test/regress/pg_regress
INSTALLED_MODULE = $(DESTDIR)$(pkglibdir)/log_fdw$(DLSUFFIX)

standalone-check: all
	@test -x '$(PG_REGRESS)' || { \
		echo 'pg_regress not found at $(PG_REGRESS); install the server development files' >&2; \
		exit 1; }
	@if ! cmp -s log_fdw$(DLSUFFIX) '$(INSTALLED_MODULE)' && [ log_fdw$(DLSUFFIX) -nt '$(INSTALLED_MODULE)' ]; then \
		echo '$(INSTALLED_MODULE) is older than the built module; run: make USE_PGXS=1 install' >&2; \
		exit 1; fi
	$(PG_REGRESS) --bindir='$(shell $(PG_CONFIG) --bindir)' \
		--inputdir=$(srcdir) --outputdir=$(CURDIR) \
		--temp-instance=$(CURDIR)/tmp_check \
		$(REGRESS_OPTS) $(REGRESS)

.PHONY: standalone-check

else
subdir = contrib/postgresql-logfdw
top_builddir = ../..
include $(top_builddir)/src/Makefile.global
include $(top_srcdir)/contrib/contrib-global.mk
endif
