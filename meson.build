# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License").

# Standalone meson build for log_fdw.  It builds against an already-installed
# PostgreSQL located through pg_config, mirroring the Makefile's USE_PGXS
# path.  Building inside a postgres source tree stays the Makefile's job:
# contrib subdirectories are not self-contained under meson, they rely on
# variables that postgres' own contrib/meson.build supplies.

project('log_fdw', 'c',
  version: '1.5',
  license: 'Apache-2.0',
  meson_version: '>= 0.56.0',
  default_options: ['warning_level=1'],
)

pg_config = find_program(get_option('pg_config'), required: true)

pgc = {}
foreach var : ['version', 'bindir', 'includedir-server', 'pkglibdir', 'sharedir']
  pgc += {var: run_command(pg_config, '--' + var, check: true).stdout().strip()}
endforeach

# "PostgreSQL 17.11", "PostgreSQL 19beta1" and "PostgreSQL 20devel" all have
# to reduce to the major number.
pg_major = pgc['version'].split(' ')[1].split('.')[0]
foreach tag : ['devel', 'alpha', 'beta', 'rc']
  pg_major = pg_major.split(tag)[0]
endforeach
pg_major = pg_major.to_int()

if pg_major < 14
  error('log_fdw requires PostgreSQL 14 or later, found ' + pgc['version'])
endif

message('building against @0@ (@1@)'.format(pgc['version'], pgc['pkglibdir']))

# Absolute include path rather than include_directories(): the headers live
# outside the project tree.
mod_kwargs = {
  'name_prefix': '',
  'c_args': ['-I' + pgc['includedir-server']],
  'install': true,
  'install_dir': pgc['pkglibdir'],
}

if host_machine.system() == 'darwin'
  # PostgreSQL loads modules named ".so" on macOS too, and backend symbols
  # are only resolved once the module is loaded into the backend.
  mod_kwargs += {
    'name_suffix': 'so',
    'link_args': ['-Wl,-undefined,dynamic_lookup'],
  }
elif host_machine.system() == 'windows'
  error('the meson build does not support Windows; use the Makefile')
endif

log_fdw = shared_module('log_fdw', files('log_fdw.c'), kwargs: mod_kwargs)

install_data(
  'log_fdw.control',
  'log_fdw--1.4.sql',
  'log_fdw--1.4--1.5.sql',
  install_dir: pgc['sharedir'] / 'extension',
)

# The regression test needs a server with logging_collector on, so it runs
# against a temporary instance configured from log_fdw.conf.  pg_regress
# resolves the extension through the server's own sharedir/pkglibdir, so the
# module has to be installed first: "ninja install && meson test".  The test
# refuses to run against an installed module that differs from the one just
# built, since that would silently test stale code.
pg_regress = find_program(
  pgc['pkglibdir'] / 'pgxs/src/test/regress/pg_regress',
  required: false,
)

if not pg_regress.found()
  warning('pg_regress not found under @0@; "meson test" will report no tests'
          .format(pgc['pkglibdir'] / 'pgxs'))
else
  test('regress', find_program('sh'),
    args: [
      '-c',
      'if ! cmp -s "$1" "$2" && [ "$1" -nt "$2" ]; then echo "installed $2 is older than the built module; run: ninja install" >&2; exit 1; fi; shift 2; exec "$@"',
      'regress',
      log_fdw.full_path(),
      pgc['pkglibdir'] / 'log_fdw.so',
      pg_regress.full_path(),
      '--bindir=' + pgc['bindir'],
      '--inputdir=' + meson.current_source_dir(),
      '--outputdir=' + meson.current_build_dir(),
      '--temp-instance=' + meson.current_build_dir() / 'tmp_check',
      '--temp-config=' + meson.current_source_dir() / 'log_fdw.conf',
      '--dbname=contrib_regression',
      'log_fdw',
    ],
    workdir: meson.current_build_dir(),
    depends: log_fdw,
    timeout: 300,
  )
endif
