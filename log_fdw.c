/*-------------------------------------------------------------------------
 *
 * log_fdw.c
 *     foreign-data wrapper for Postgres log files.
 *
 * Portions Copyright (c) 2022, Amazon Web Services
 * Portions Copyright (c) 2010-2016, PostgreSQL Global Development Group
 *
 * Modifications Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 *
 * IDENTIFICATION
 *     postgresql-log_fdw/log_fdw.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include <sys/stat.h>
#include <unistd.h>

#include "access/htup_details.h"
#include "access/reloptions.h"
#include "access/sysattr.h"
#include "access/table.h"
#include "catalog/pg_foreign_table.h"
#include "commands/copy.h"
#include "commands/defrem.h"
#include "commands/explain.h"
#include "commands/vacuum.h"
#include "common/string.h"
#include "foreign/fdwapi.h"
#include "foreign/foreign.h"
#include "funcapi.h"
#include "miscadmin.h"
#include "nodes/makefuncs.h"
#include "optimizer/optimizer.h"
#include "optimizer/pathnode.h"
#include "optimizer/planmain.h"
#include "optimizer/restrictinfo.h"
#include "postmaster/syslogger.h"
#include "utils/memutils.h"
#include "utils/rel.h"
#include "utils/sampling.h"

#define CSV_FILE_EXTENSION        ".csv"
#define CSV_GZ_FILE_EXTENSION     ".csv.gz"

PG_MODULE_MAGIC;

/*
 * Describes the valid options for objects that use this wrapper.
 */
struct FileFdwOption
{
	const char *optname;
	Oid			optcontext;		/* Oid of catalog in which option may appear */
};

/*
 * Valid options for log_fdw.
 * These options are based on the options for the COPY FROM command.
 * But note that force_not_null and force_null are handled as boolean options
 * attached to a column, not as table options.
 *
 * Note: If you are adding new option for user mapping, you need to modify
 * fileGetOptions(), which currently doesn't bother to look at user mappings.
 */
static const struct FileFdwOption valid_options[] = {
	/* File options */
	{"filename", ForeignTableRelationId},

	/* Sentinel */
	{NULL, InvalidOid}
};

/*
 * FDW-specific information for RelOptInfo.fdw_private.
 */
typedef struct FileFdwPlanState
{
	char	   *filename;		/* file to read */
	List	   *options;		/* merged COPY options, excluding filename */
	BlockNumber pages;			/* estimate of file's physical size */
	double		ntuples;		/* estimate of number of rows in file */
} FileFdwPlanState;

/*
 * FDW-specific information for ForeignScanState.fdw_state.
 */
typedef struct FileFdwExecutionState
{
	char	   *filename;		/* file to read */
	List	   *options;		/* merged COPY options, excluding filename */
	CopyFromState cstate;		/* state of reading file */
} FileFdwExecutionState;

/*
 * SQL functions
 */
PG_FUNCTION_INFO_V1(log_fdw_handler);
PG_FUNCTION_INFO_V1(log_fdw_validator);

/*
 * FDW callback routines
 */
static void fileGetForeignRelSize(PlannerInfo *root,
								  RelOptInfo *baserel,
								  Oid foreigntableid);
static void fileGetForeignPaths(PlannerInfo *root,
								RelOptInfo *baserel,
								Oid foreigntableid);
static ForeignScan *fileGetForeignPlan(PlannerInfo *root,
									   RelOptInfo *baserel,
									   Oid foreigntableid,
									   ForeignPath *best_path,
									   List *tlist,
									   List *scan_clauses,
									   Plan *outer_plan);
static void fileExplainForeignScan(ForeignScanState *node, ExplainState *es);
static void fileBeginForeignScan(ForeignScanState *node, int eflags);
static TupleTableSlot *fileIterateForeignScan(ForeignScanState *node);
static void fileReScanForeignScan(ForeignScanState *node);
static void fileEndForeignScan(ForeignScanState *node);
static bool fileAnalyzeForeignTable(Relation relation,
									AcquireSampleRowsFunc *func,
									BlockNumber *totalpages);
static bool fileIsForeignScanParallelSafe(PlannerInfo *root, RelOptInfo *rel,
										  RangeTblEntry *rte);

/*
 * Helper functions
 */
static bool is_valid_option(const char *option, Oid context);
static void fileGetOptions(Oid foreigntableid,
						   char **filename, List **other_options);
static bool check_selective_binary_conversion(RelOptInfo *baserel,
											  Oid foreigntableid,
											  List **columns);
static void estimate_size(PlannerInfo *root, RelOptInfo *baserel,
						  FileFdwPlanState *fdw_private);
static void estimate_costs(PlannerInfo *root, RelOptInfo *baserel,
						   FileFdwPlanState *fdw_private,
						   Cost *startup_cost, Cost *total_cost);
static int	file_acquire_sample_rows(Relation onerel, int elevel,
									 HeapTuple *rows, int targrows,
									 double *totalrows, double *totaldeadrows);

/*
 * Foreign-data wrapper handler function: return a struct with pointers
 * to my callback routines.
 */
Datum
log_fdw_handler(PG_FUNCTION_ARGS)
{
	FdwRoutine *fdwroutine = makeNode(FdwRoutine);

	fdwroutine->GetForeignRelSize = fileGetForeignRelSize;
	fdwroutine->GetForeignPaths = fileGetForeignPaths;
	fdwroutine->GetForeignPlan = fileGetForeignPlan;
	fdwroutine->ExplainForeignScan = fileExplainForeignScan;
	fdwroutine->BeginForeignScan = fileBeginForeignScan;
	fdwroutine->IterateForeignScan = fileIterateForeignScan;
	fdwroutine->ReScanForeignScan = fileReScanForeignScan;
	fdwroutine->EndForeignScan = fileEndForeignScan;
	fdwroutine->AnalyzeForeignTable = fileAnalyzeForeignTable;
	fdwroutine->IsForeignScanParallelSafe = fileIsForeignScanParallelSafe;

	PG_RETURN_POINTER(fdwroutine);
}

/*
 * Validate the generic options given to a FOREIGN DATA WRAPPER, SERVER,
 * USER MAPPING or FOREIGN TABLE that uses log_fdw.
 *
 * Raise an ERROR if the option or its value is considered invalid.
 */
Datum
log_fdw_validator(PG_FUNCTION_ARGS)
{
	List	   *options_list = untransformRelOptions(PG_GETARG_DATUM(0));
	Oid			catalog = PG_GETARG_OID(1);
	char	   *filename = NULL;
	ListCell   *cell;

	/*
	 * Check that only options supported by log_fdw, and allowed for the
	 * current object type, are given.
	 */
	foreach(cell, options_list)
	{
		DefElem    *def = (DefElem *) lfirst(cell);

		if (!is_valid_option(def->defname, catalog))
		{
			const struct FileFdwOption *opt;
			StringInfoData buf;

			/*
			 * Unknown option specified, complain about it. Provide a hint
			 * with list of valid options for the object.
			 */
			initStringInfo(&buf);
			for (opt = valid_options; opt->optname; opt++)
			{
				if (catalog == opt->optcontext)
					appendStringInfo(&buf, "%s%s", (buf.len > 0) ? ", " : "",
									 opt->optname);
			}

			ereport(ERROR,
					(errcode(ERRCODE_FDW_INVALID_OPTION_NAME),
					 errmsg("invalid option \"%s\"", def->defname),
					 buf.len > 0
					 ? errhint("Valid options in this context are: %s",
							   buf.data)
					 : errhint("There are no valid options in this context.")));
		}

		/* Separate out filename. */
		if (strcmp(def->defname, "filename") == 0)
		{
			if (filename)
				ereport(ERROR,
						(errcode(ERRCODE_SYNTAX_ERROR),
						 errmsg("conflicting or redundant options")));

			filename = defGetString(def);

			if (is_absolute_path(filename))
				ereport(ERROR,
						(errcode(ERRCODE_SYNTAX_ERROR),
						 errmsg("absolute path is not allowed as filename for log_fdw foreign tables")));
		}
	}

	/* Filename option is required for log_fdw foreign tables. */
	if (catalog == ForeignTableRelationId && filename == NULL)
		ereport(ERROR,
				(errcode(ERRCODE_FDW_DYNAMIC_PARAMETER_VALUE_NEEDED),
				 errmsg("filename is required for log_fdw foreign tables")));

	PG_RETURN_VOID();
}

/*
 * Check if the provided option is one of the valid options.
 * context is the Oid of the catalog holding the object the option is for.
 */
static bool
is_valid_option(const char *option, Oid context)
{
	const struct FileFdwOption *opt;

	for (opt = valid_options; opt->optname; opt++)
	{
		if (context == opt->optcontext && strcmp(opt->optname, option) == 0)
			return true;
	}
	return false;
}

/*
 * Fetch the options for a log_fdw foreign table.
 *
 * We have to separate out "filename" from the other options because
 * it must not appear in the options list passed to the core COPY code.
 */
static void
fileGetOptions(Oid foreigntableid,
			   char **filename, List **other_options)
{
	ForeignTable *table;
	ForeignServer *server;
	ForeignDataWrapper *wrapper;
	List	   *options;
	ListCell   *lc;
	char	   *full_filename;

	/*
	 * Extract options from FDW objects.  We ignore user mappings because
	 * log_fdw doesn't have any options that can be specified there.
	 *
	 * (XXX Actually, given the current contents of valid_options[], there's
	 * no point in examining anything except the foreign table's own options.
	 * Simplify?)
	 */
	table = GetForeignTable(foreigntableid);
	server = GetForeignServer(table->serverid);
	wrapper = GetForeignDataWrapper(server->fdwid);

	options = NIL;
	options = list_concat(options, wrapper->options);
	options = list_concat(options, server->options);
	options = list_concat(options, table->options);

	/*
	 * Separate out the filename.
	 */
	*filename = NULL;
	foreach(lc, options)
	{
		DefElem    *def = (DefElem *) lfirst(lc);

		if (strcmp(def->defname, "filename") == 0)
		{
			*filename = defGetString(def);
			options = foreach_delete_current(options, lc);
			break;
		}
	}

	/*
	 * The validator should have checked that a filename was included in the
	 * options, but check again, just in case.
	 */
	if (*filename == NULL)
		elog(ERROR, "filename is required for log_fdw foreign tables");

	if (is_absolute_path(*filename))
		ereport(ERROR,
				(errcode(ERRCODE_SYNTAX_ERROR),
				 errmsg("absolute path is not allowed as filename for log_fdw foreign tables")));

	full_filename = (char *) palloc(MAXPGPATH);

	if (strlen(Log_directory) > 0 && is_absolute_path(Log_directory))
		snprintf(full_filename, MAXPGPATH, "%s/%s", Log_directory, *filename);
	else
		snprintf(full_filename, MAXPGPATH, "%s/%s/%s", DataDir, Log_directory, *filename);

	*filename = full_filename;

	/* Determine the format based on the file name. */
	if (pg_str_endswith(full_filename, CSV_FILE_EXTENSION)
		|| pg_str_endswith(full_filename, CSV_GZ_FILE_EXTENSION))
		options = lappend(options, makeDefElem("format", (Node *) makeString("csv"), -1));
	else
	{
		options = lappend(options, makeDefElem("format", (Node *) makeString("text"), -1));

		/*
		 * The default delimiter in text mode is the tab character.  This can
		 * cause problems if the tab character is used in the log file.  To
		 * get around this, set the delimiter to be the EOT character.  This
		 * is a much rarer character to encounter in a log file, so it should
		 * virtually remove the delimiter.
		 *
		 * TODO: find a better way to remove the delimiter character
		 */
		options = lappend(options, makeDefElem("delimiter", (Node *) makeString("\x4"), -1));
	}

	*other_options = options;
}

/*
 * fileGetForeignRelSize
 *        Obtain relation size estimates for a foreign table
 */
static void
fileGetForeignRelSize(PlannerInfo *root,
					  RelOptInfo *baserel,
					  Oid foreigntableid)
{
	FileFdwPlanState *fdw_private;

	/*
	 * Fetch options.  We only need filename at this point, but we might as
	 * well get everything and not need to re-fetch it later in planning.
	 */
	fdw_private = (FileFdwPlanState *) palloc(sizeof(FileFdwPlanState));
	fileGetOptions(foreigntableid,
				   &fdw_private->filename,
				   &fdw_private->options);
	baserel->fdw_private = (void *) fdw_private;

	/* Estimate relation size */
	estimate_size(root, baserel, fdw_private);
}

/*
 * fileGetForeignPaths
 *        Create possible access paths for a scan on the foreign table
 *
 *        Currently we don't support any push-down feature, so there is only one
 *        possible access path, which simply returns all records in the order in
 *        the data file.
 */
static void
fileGetForeignPaths(PlannerInfo *root,
					RelOptInfo *baserel,
					Oid foreigntableid)
{
	FileFdwPlanState *fdw_private = (FileFdwPlanState *) baserel->fdw_private;
	Cost		startup_cost;
	Cost		total_cost;
	List	   *columns;
	List	   *coptions = NIL;

	/* Decide whether to selectively perform binary conversion */
	if (check_selective_binary_conversion(baserel,
										  foreigntableid,
										  &columns))
		coptions = list_make1(makeDefElem("convert_selectively",
										  (Node *) columns, -1));

	/* Estimate costs */
	estimate_costs(root, baserel, fdw_private,
				   &startup_cost, &total_cost);

	/*
	 * Create a ForeignPath node and add it as only possible path.  We use the
	 * fdw_private list of the path to carry the convert_selectively option;
	 * it will be propagated into the fdw_private list of the Plan node.
	 */
	add_path(baserel, (Path *)
			 create_foreignscan_path(root, baserel,
									 NULL,	/* default pathtarget */
									 baserel->rows,
									 startup_cost,
									 total_cost,
									 NIL,	/* no pathkeys */
									 baserel->lateral_relids,
									 NULL,	/* no extra plan */
									 coptions));

	/*
	 * If data file was sorted, and we knew it somehow, we could insert
	 * appropriate pathkeys into the ForeignPath node to tell the planner
	 * that.
	 */
}

/*
 * fileGetForeignPlan
 *        Create a ForeignScan plan node for scanning the foreign table
 */
static ForeignScan *
fileGetForeignPlan(PlannerInfo *root,
				   RelOptInfo *baserel,
				   Oid foreigntableid,
				   ForeignPath *best_path,
				   List *tlist,
				   List *scan_clauses,
				   Plan *outer_plan)
{
	Index		scan_relid = baserel->relid;

	/*
	 * We have no native ability to evaluate restriction clauses, so we just
	 * put all the scan_clauses into the plan node's qual list for the
	 * executor to check.  So all we have to do here is strip RestrictInfo
	 * nodes from the clauses and ignore pseudoconstants (which will be
	 * handled elsewhere).
	 */
	scan_clauses = extract_actual_clauses(scan_clauses, false);

	/* Create the ForeignScan node */
	return make_foreignscan(tlist,
							scan_clauses,
							scan_relid,
							NIL,	/* no expressions to evaluate */
							best_path->fdw_private,
							NIL,	/* no custom tlist */
							NIL,	/* no remote quals */
							outer_plan);
}

/*
 * fileExplainForeignScan
 *        Produce extra output for EXPLAIN
 */
static void
fileExplainForeignScan(ForeignScanState *node, ExplainState *es)
{
	char	   *filename;
	List	   *options;

	/* Fetch options --- we only need filename at this point */
	fileGetOptions(RelationGetRelid(node->ss.ss_currentRelation),
				   &filename, &options);

	ExplainPropertyText("Foreign File", filename, es);

	/* Suppress file size if we're not showing cost details */
	if (es->costs)
	{
		struct stat stat_buf;

		if (stat(filename, &stat_buf) == 0)
			ExplainPropertyInteger("Foreign File Size", "b",
								   (int64) stat_buf.st_size, es);
	}
}

/*
 * fileBeginForeignScan
 *        Initiate access to the file by creating CopyFromState
 */
static void
fileBeginForeignScan(ForeignScanState *node, int eflags)
{
	ForeignScan *plan = (ForeignScan *) node->ss.ps.plan;
	char	   *filename;
	List	   *options;
	CopyFromState cstate;
	FileFdwExecutionState *festate;

	/*
	 * Do nothing in EXPLAIN (no ANALYZE) case.  node->fdw_state stays NULL.
	 */
	if (eflags & EXEC_FLAG_EXPLAIN_ONLY)
		return;

	/* Fetch options of foreign table */
	fileGetOptions(RelationGetRelid(node->ss.ss_currentRelation),
				   &filename, &options);

	/* Add any options from the plan (currently only convert_selectively) */
	options = list_concat(options, plan->fdw_private);

	/*
	 * Create CopyFromState from FDW options.  We always acquire all columns,
	 * so as to match the expected ScanTupleSlot signature.
	 */
	cstate = BeginCopyFrom(NULL,
						   node->ss.ss_currentRelation,
						   NULL,
						   filename,
						   false,
						   NULL,
						   NIL,
						   options);

	/*
	 * Save state in node->fdw_state.  We must save enough information to call
	 * BeginCopyFrom() again.
	 */
	festate = (FileFdwExecutionState *) palloc(sizeof(FileFdwExecutionState));
	festate->filename = filename;
	festate->options = options;
	festate->cstate = cstate;

	node->fdw_state = (void *) festate;
}

/*
 * fileIterateForeignScan
 *        Read next record from the data file and store it into the
 *        ScanTupleSlot as a virtual tuple
 */
static TupleTableSlot *
fileIterateForeignScan(ForeignScanState *node)
{
	FileFdwExecutionState *festate = (FileFdwExecutionState *) node->fdw_state;
	TupleTableSlot *slot = node->ss.ss_ScanTupleSlot;
	bool		found;
	ErrorContextCallback errcallback;
	MemoryContext ccxt = CurrentMemoryContext;

	/* Set up callback to identify error line number. */
	errcallback.callback = CopyFromErrorCallback;
	errcallback.arg = (void *) festate->cstate;
	errcallback.previous = error_context_stack;
	error_context_stack = &errcallback;

	/*
	 * The protocol for loading a virtual tuple into a slot is first
	 * ExecClearTuple, then fill the values/isnull arrays, then
	 * ExecStoreVirtualTuple.  If we don't find another row in the file, we
	 * just skip the last step, leaving the slot empty as required.
	 *
	 * We can pass ExprContext = NULL because we read all columns from the
	 * file, so no need to evaluate default expressions.
	 *
	 * We can also pass tupleOid = NULL because we don't allow oids for
	 * foreign tables.
	 */
	ExecClearTuple(slot);

	/*
	 * In Postgres version 13, we add one additional column "backend_type" in
	 * csvlog file, thus we need to update log_fdw to 1.2 handle it. But if
	 * still use log_fdw 1.1 to read a log file part of which have this
	 * additional column , we will get error from NextCopyFrom(), about
	 * "ERROR: extra data after last expected column"; similarly if we use
	 * log_fdw 1.2 to read a log file part of which do not contain this
	 * column, we will get error from NextCopyFrom(), about "ERROR: missing
	 * data after last expected column". Thus we wanna give proper hint to
	 * customer about why it happens by catching these 2 errors. Notice that
	 * some other problems like wrong format for some certain columns will be
	 * catched as well, for which we did not replace original error message
	 * and error hints, as their errors are irrelevant with "backend_type"
	 * issue, thus we just reuse existing hints. Moreover this code change is
	 * generically applicable to any log formatting change in the future,
	 * which we should keep an eye on it for future update.
	 */
	PG_TRY();
	{
		found = NextCopyFrom(festate->cstate, NULL,
							 slot->tts_values, slot->tts_isnull);
	}
	PG_CATCH();
	{
		ErrorData  *errdata;
		char	   *customhint = "This could mean that the log file or a portion of the log "
		"file was created by a version of PostgreSQL that the installed "
		"version of log_fdw cannot read. It may be possible to read the "
		"file after running the command 'ALTER EXTENSION log_fdw UPDATE' "
		"and recreating the foreign table.";

		MemoryContextSwitchTo(ccxt);
		errdata = CopyErrorData();
		FlushErrorState();
		ereport(ERROR,
				(errcode(errdata->sqlerrcode),
				 errmsg("%s", errdata->message),
				 errdata->hint ? errhint("%s", errdata->hint) : errhint("%s", customhint)));
		FreeErrorData(errdata);
	}
	PG_END_TRY();

	if (found)
		ExecStoreVirtualTuple(slot);

	/* Remove error callback. */
	error_context_stack = errcallback.previous;

	return slot;
}

/*
 * fileReScanForeignScan
 *        Rescan table, possibly with new parameters
 */
static void
fileReScanForeignScan(ForeignScanState *node)
{
	FileFdwExecutionState *festate = (FileFdwExecutionState *) node->fdw_state;

	EndCopyFrom(festate->cstate);

	festate->cstate = BeginCopyFrom(NULL,
									node->ss.ss_currentRelation,
									NULL,
									festate->filename,
									false,
									NULL,
									NIL,
									festate->options);
}

/*
 * fileEndForeignScan
 *        Finish scanning foreign table and dispose objects used for this scan
 */
static void
fileEndForeignScan(ForeignScanState *node)
{
	FileFdwExecutionState *festate = (FileFdwExecutionState *) node->fdw_state;

	/* if festate is NULL, we are in EXPLAIN; nothing to do */
	if (festate)
		EndCopyFrom(festate->cstate);
}

/*
 * fileAnalyzeForeignTable
 *        Test whether analyzing this foreign table is supported
 */
static bool
fileAnalyzeForeignTable(Relation relation,
						AcquireSampleRowsFunc *func,
						BlockNumber *totalpages)
{
	char	   *filename;
	List	   *options;
	struct stat stat_buf;

	/* Fetch options of foreign table */
	fileGetOptions(RelationGetRelid(relation), &filename, &options);

	/*
	 * Get size of the file.  (XXX if we fail here, would it be better to just
	 * return false to skip analyzing the table?)
	 */
	if (stat(filename, &stat_buf) < 0)
		ereport(ERROR,
				(errcode_for_file_access(),
				 errmsg("could not stat file \"%s\": %m",
						filename)));

	/*
	 * Convert size to pages.  Must return at least 1 so that we can tell
	 * later on that pg_class.relpages is not default.
	 */
	*totalpages = (stat_buf.st_size + (BLCKSZ - 1)) / BLCKSZ;
	if (*totalpages < 1)
		*totalpages = 1;

	*func = file_acquire_sample_rows;

	return true;
}

/*
 * fileIsForeignScanParallelSafe
 *         Reading a file in a parallel worker should work just the same as
 *         reading it in the leader, so mark scans safe.
 */
static bool
fileIsForeignScanParallelSafe(PlannerInfo *root, RelOptInfo *rel,
							  RangeTblEntry *rte)
{
	return true;
}

/*
 * check_selective_binary_conversion
 *
 * Check to see if it's useful to convert only a subset of the file's columns
 * to binary.  If so, construct a list of the column names to be converted,
 * return that at *columns, and return TRUE.  (Note that it's possible to
 * determine that no columns need be converted, for instance with a COUNT(*)
 * query.  So we can't use returning a NIL list to indicate failure.)
 */
static bool
check_selective_binary_conversion(RelOptInfo *baserel,
								  Oid foreigntableid,
								  List **columns)
{
	ListCell   *lc;
	Relation	rel;
	TupleDesc	tupleDesc;
#if (PG_VERSION_NUM >= 160000)	
	int 		attidx;
#else	
	AttrNumber	attnum;
#endif	
	Bitmapset  *attrs_used = NULL;
	bool		has_wholerow = false;
	int			numattrs;
	int			i;

	*columns = NIL;				/* default result */

	/* Collect all the attributes needed for joins or final output. */
	pull_varattnos((Node *) baserel->reltarget->exprs, baserel->relid,
				   &attrs_used);

	/* Add all the attributes used by restriction clauses. */
	foreach(lc, baserel->baserestrictinfo)
	{
		RestrictInfo *rinfo = (RestrictInfo *) lfirst(lc);

		pull_varattnos((Node *) rinfo->clause, baserel->relid,
					   &attrs_used);
	}

	/* Convert attribute numbers to column names. */
	rel = table_open(foreigntableid, AccessShareLock);
	tupleDesc = RelationGetDescr(rel);

#if (PG_VERSION_NUM >= 160000)
	attidx = -1;
	while ((attidx = bms_next_member(attrs_used, attidx)) >= 0)
	{
		/* attidx is zero-based, attnum is the normal attribute number */
		AttrNumber	attnum = attidx + FirstLowInvalidHeapAttributeNumber;
#else	
	while ((attnum = bms_first_member(attrs_used)) >= 0)
	{
		/* Adjust for system attributes. */
		attnum += FirstLowInvalidHeapAttributeNumber;
#endif
		if (attnum == 0)
		{
			has_wholerow = true;
			break;
		}

		/* Ignore system attributes. */
		if (attnum < 0)
			continue;

		/* Get user attributes. */
		if (attnum > 0)
		{
			Form_pg_attribute attr = TupleDescAttr(tupleDesc, attnum - 1);
			char	   *attname = NameStr(attr->attname);

			/* Skip dropped attributes (probably shouldn't see any here). */
			if (attr->attisdropped)
				continue;
			*columns = lappend(*columns, makeString(pstrdup(attname)));
		}
	}

	/* Count non-dropped user attributes while we have the tupdesc. */
	numattrs = 0;
	for (i = 0; i < tupleDesc->natts; i++)
	{
		Form_pg_attribute attr = TupleDescAttr(tupleDesc, i);

		if (attr->attisdropped)
			continue;
		numattrs++;
	}

	table_close(rel, AccessShareLock);

	/* If there's a whole-row reference, fail: we need all the columns. */
	if (has_wholerow)
	{
		*columns = NIL;
		return false;
	}

	/* If all the user attributes are needed, fail. */
	if (numattrs == list_length(*columns))
	{
		*columns = NIL;
		return false;
	}

	return true;
}

/*
 * Estimate size of a foreign table.
 *
 * The main result is returned in baserel->rows.  We also set
 * fdw_private->pages and fdw_private->ntuples for later use in the cost
 * calculation.
 */
static void
estimate_size(PlannerInfo *root, RelOptInfo *baserel,
			  FileFdwPlanState *fdw_private)
{
	struct stat stat_buf;
	BlockNumber pages;
	double		ntuples;
	double		nrows;

	/*
	 * Get size of the file.  It might not be there at plan time, though, in
	 * which case we have to use a default estimate.
	 */
	if (stat(fdw_private->filename, &stat_buf) < 0)
		stat_buf.st_size = 10 * BLCKSZ;

	/*
	 * Convert size to pages for use in I/O cost estimate later.
	 */
	pages = (stat_buf.st_size + (BLCKSZ - 1)) / BLCKSZ;
	if (pages < 1)
		pages = 1;
	fdw_private->pages = pages;

	/*
	 * Estimate the number of tuples in the file.
	 */
	if (baserel->pages > 0)
	{
		/*
		 * We have # of pages and # of tuples from pg_class (that is, from a
		 * previous ANALYZE), so compute a tuples-per-page estimate and scale
		 * that by the current file size.
		 */
		double		density;

		density = baserel->tuples / (double) baserel->pages;
		ntuples = clamp_row_est(density * (double) pages);
	}
	else
	{
		/*
		 * Otherwise we have to fake it.  We back into this estimate using the
		 * planner's idea of the relation width; which is bogus if not all
		 * columns are being read, not to mention that the text representation
		 * of a row probably isn't the same size as its internal
		 * representation.  Possibly we could do something better, but the
		 * real answer to anyone who complains is "ANALYZE" ...
		 */
		int			tuple_width;

		tuple_width = MAXALIGN(baserel->reltarget->width) +
			MAXALIGN(SizeofHeapTupleHeader);
		ntuples = clamp_row_est((double) stat_buf.st_size /
								(double) tuple_width);
	}
	fdw_private->ntuples = ntuples;

	/*
	 * Now estimate the number of rows returned by the scan after applying the
	 * baserestrictinfo quals.
	 */
	nrows = ntuples *
		clauselist_selectivity(root,
							   baserel->baserestrictinfo,
							   0,
							   JOIN_INNER,
							   NULL);

	nrows = clamp_row_est(nrows);

	/* Save the output-rows estimate for the planner */
	baserel->rows = nrows;
}

/*
 * Estimate costs of scanning a foreign table.
 *
 * Results are returned in *startup_cost and *total_cost.
 */
static void
estimate_costs(PlannerInfo *root, RelOptInfo *baserel,
			   FileFdwPlanState *fdw_private,
			   Cost *startup_cost, Cost *total_cost)
{
	BlockNumber pages = fdw_private->pages;
	double		ntuples = fdw_private->ntuples;
	Cost		run_cost = 0;
	Cost		cpu_per_tuple;

	/*
	 * We estimate costs almost the same way as cost_seqscan(), thus assuming
	 * that I/O costs are equivalent to a regular table file of the same size.
	 * However, we take per-tuple CPU costs as 10x of a seqscan, to account
	 * for the cost of parsing records.
	 */
	run_cost += seq_page_cost * pages;

	*startup_cost = baserel->baserestrictcost.startup;
	cpu_per_tuple = cpu_tuple_cost * 10 + baserel->baserestrictcost.per_tuple;
	run_cost += cpu_per_tuple * ntuples;
	*total_cost = *startup_cost + run_cost;
}

/*
 * file_acquire_sample_rows -- acquire a random sample of rows from the table
 *
 * Selected rows are returned in the caller-allocated array rows[],
 * which must have at least targrows entries.
 * The actual number of rows selected is returned as the function result.
 * We also count the total number of rows in the file and return it into
 * *totalrows.  Note that *totaldeadrows is always set to 0.
 *
 * Note that the returned list of rows is not always in order by physical
 * position in the file.  Therefore, correlation estimates derived later
 * may be meaningless, but it's OK because we don't use the estimates
 * currently (the planner only pays attention to correlation for indexscans).
 */
static int
file_acquire_sample_rows(Relation onerel, int elevel,
						 HeapTuple *rows, int targrows,
						 double *totalrows, double *totaldeadrows)
{
	int			numrows = 0;
	double		rowstoskip = -1;	/* -1 means not set yet */
	ReservoirStateData rstate;
	TupleDesc	tupDesc;
	Datum	   *values;
	bool	   *nulls;
	bool		found;
	char	   *filename;
	List	   *options;
	CopyFromState cstate;
	ErrorContextCallback errcallback;
	MemoryContext oldcontext = CurrentMemoryContext;
	MemoryContext tupcontext;

	Assert(onerel);
	Assert(targrows > 0);

	tupDesc = RelationGetDescr(onerel);
	values = (Datum *) palloc(tupDesc->natts * sizeof(Datum));
	nulls = (bool *) palloc(tupDesc->natts * sizeof(bool));

	/* Fetch options of foreign table */
	fileGetOptions(RelationGetRelid(onerel), &filename, &options);

	/*
	 * Create CopyFromState from FDW options.
	 */
	cstate = BeginCopyFrom(NULL, onerel, NULL, filename, false, NULL, NIL, options);

	/*
	 * Use per-tuple memory context to prevent leak of memory used to read
	 * rows from the file with Copy routines.
	 */
	tupcontext = AllocSetContextCreate(CurrentMemoryContext,
									   "log_fdw temporary context",
									   ALLOCSET_DEFAULT_SIZES);

	/* Prepare for sampling rows */
	reservoir_init_selection_state(&rstate, targrows);

	/* Set up callback to identify error line number. */
	errcallback.callback = CopyFromErrorCallback;
	errcallback.arg = (void *) cstate;
	errcallback.previous = error_context_stack;
	error_context_stack = &errcallback;

	*totalrows = 0;
	*totaldeadrows = 0;
	for (;;)
	{
		/* Check for user-requested abort or sleep */
		vacuum_delay_point();

		/* Fetch next row */
		MemoryContextReset(tupcontext);
		MemoryContextSwitchTo(tupcontext);

		found = NextCopyFrom(cstate, NULL, values, nulls);

		MemoryContextSwitchTo(oldcontext);

		if (!found)
			break;

		/*
		 * The first targrows sample rows are simply copied into the
		 * reservoir.  Then we start replacing tuples in the sample until we
		 * reach the end of the relation. This algorithm is from Jeff Vitter's
		 * paper (see more info in commands/analyze.c).
		 */
		if (numrows < targrows)
		{
			rows[numrows++] = heap_form_tuple(tupDesc, values, nulls);
		}
		else
		{
			/*
			 * t in Vitter's paper is the number of records already processed.
			 * If we need to compute a new S value, we must use the
			 * not-yet-incremented value of totalrows as t.
			 */
			if (rowstoskip < 0)
				rowstoskip = reservoir_get_next_S(&rstate, *totalrows, targrows);

			if (rowstoskip <= 0)
			{
				/*
				 * Found a suitable tuple, so save it, replacing one old tuple
				 * at random
				 */
#if (PG_VERSION_NUM < 150000)
				int			k = (int) (targrows * sampler_random_fract(rstate.randstate));
#else
				int			k = (int) (targrows * sampler_random_fract(&rstate.randstate));
#endif
				Assert(k >= 0 && k < targrows);
				heap_freetuple(rows[k]);
				rows[k] = heap_form_tuple(tupDesc, values, nulls);
			}

			rowstoskip -= 1;
		}

		*totalrows += 1;
	}

	/* Remove error callback. */
	error_context_stack = errcallback.previous;

	/* Clean up. */
	MemoryContextDelete(tupcontext);

	EndCopyFrom(cstate);

	pfree(values);
	pfree(nulls);

	/*
	 * Emit some interesting relation info
	 */
	ereport(elevel,
			(errmsg("\"%s\": file contains %.0f rows; "
					"%d rows in sample",
					RelationGetRelationName(onerel),
					*totalrows, numrows)));

	return numrows;
}
