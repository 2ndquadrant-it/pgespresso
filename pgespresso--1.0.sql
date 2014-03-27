-- pgespresso - PostgreSQL extension for Barman (www.pgbarman.org)

-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pgespresso" to load this file. \quit

CREATE FUNCTION pgespresso_start_backup(label TEXT, fast BOOL) RETURNS TEXT
 AS 'MODULE_PATHNAME'
 LANGUAGE C STRICT;
CREATE FUNCTION pgespresso_stop_backup(label_content TEXT) RETURNS TEXT
 AS 'MODULE_PATHNAME'
 LANGUAGE C STRICT;
CREATE FUNCTION pgespresso_abort_backup() RETURNS VOID
 AS 'MODULE_PATHNAME'
 LANGUAGE C STRICT;
