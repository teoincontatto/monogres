"""
Module to expose all extensions via a `CFGS_ALL` variable.
"""

load("//extensions/contrib:cfg.bzl", CFGS_CONTRIB = "CFGS")
load("//extensions/acl:cfg.bzl", CFG_ACL = "CFG")
load("//extensions/age:cfg.bzl", CFG_AGE = "CFG")
load("//extensions/aggs_for_arrays:cfg.bzl", CFG_AGGS_FOR_ARRAYS = "CFG")
load("//extensions/aggs_for_vecs:cfg.bzl", CFG_AGGS_FOR_VECS = "CFG")
load("//extensions/asn1oid:cfg.bzl", CFG_ASN1OID = "CFG")
load("//extensions/base36:cfg.bzl", CFG_BASE36 = "CFG")
load("//extensions/biscuit:cfg.bzl", CFG_BISCUIT = "CFG")
load("//extensions/citus:cfg.bzl", CFG_CITUS = "CFG")
load("//extensions/collection:cfg.bzl", CFG_COLLECTION = "CFG")
load("//extensions/count_distinct:cfg.bzl", CFG_COUNT_DISTINCT = "CFG")
load("//extensions/country:cfg.bzl", CFG_COUNTRY = "CFG")
load("//extensions/cryptint:cfg.bzl", CFG_CRYPTINT = "CFG")
load("//extensions/currency:cfg.bzl", CFG_CURRENCY = "CFG")
load("//extensions/dbt2:cfg.bzl", CFG_DBT2 = "CFG")
load("//extensions/ddsketch:cfg.bzl", CFG_DDSKETCH = "CFG")
load("//extensions/decoderbufs:cfg.bzl", CFG_DECODERBUFS = "CFG")
load("//extensions/documentdb:cfg.bzl", CFG_DOCUMENTDB = "CFG")
load("//extensions/duckdb_fdw:cfg.bzl", CFG_DUCKDB_FDW = "CFG")
load("//extensions/envvar:cfg.bzl", CFG_ENVVAR = "CFG")
load("//extensions/extra_window_functions:cfg.bzl", CFG_EXTRA_WINDOW_FUNCTIONS = "CFG")
load("//extensions/financial:cfg.bzl", CFG_FINANCIAL = "CFG")
load("//extensions/firebird_fdw:cfg.bzl", CFG_FIREBIRD_FDW = "CFG")
load("//extensions/first_last_agg:cfg.bzl", CFG_FIRST_LAST_AGG = "CFG")
load("//extensions/floatfile:cfg.bzl", CFG_FLOATFILE = "CFG")
load("//extensions/floatvec:cfg.bzl", CFG_FLOATVEC = "CFG")
load("//extensions/gzip:cfg.bzl", CFG_GZIP = "CFG")
load("//extensions/hashtypes:cfg.bzl", CFG_HASHTYPES = "CFG")
load("//extensions/hdfs_fdw:cfg.bzl", CFG_HDFS_FDW = "CFG")
load("//extensions/http:cfg.bzl", CFG_HTTP = "CFG")
load("//extensions/hypopg:cfg.bzl", CFG_HYPOPG = "CFG")
load("//extensions/icu_ext:cfg.bzl", CFG_ICU_EXT = "CFG")
load("//extensions/informix_fdw:cfg.bzl", CFG_INFORMIX_FDW = "CFG")
load("//extensions/ip4r:cfg.bzl", CFG_IP4R = "CFG")
load("//extensions/jdbc_fdw:cfg.bzl", CFG_JDBC_FDW = "CFG")
load("//extensions/jsquery:cfg.bzl", CFG_JSQUERY = "CFG")
load("//extensions/logerrors:cfg.bzl", CFG_LOGERRORS = "CFG")
load("//extensions/log_fdw:cfg.bzl", CFG_LOG_FDW = "CFG")
load("//extensions/login_hook:cfg.bzl", CFG_LOGIN_HOOK = "CFG")
load("//extensions/lolor:cfg.bzl", CFG_LOLOR = "CFG")
load("//extensions/lower_quantile:cfg.bzl", CFG_LOWER_QUANTILE = "CFG")
load("//extensions/mobilitydb:cfg.bzl", CFG_MOBILITYDB = "CFG")
load("//extensions/mongo_fdw:cfg.bzl", CFG_MONGO_FDW = "CFG")
load("//extensions/multicorn:cfg.bzl", CFG_MULTICORN = "CFG")
load("//extensions/mysql_fdw:cfg.bzl", CFG_MYSQL_FDW = "CFG")
load("//extensions/nominatim_fdw:cfg.bzl", CFG_NOMINATIM_FDW = "CFG")
load("//extensions/noset:cfg.bzl", CFG_NOSET = "CFG")
load("//extensions/numeral:cfg.bzl", CFG_NUMERAL = "CFG")
load("//extensions/odbc_fdw:cfg.bzl", CFG_ODBC_FDW = "CFG")
load("//extensions/ogr_fdw:cfg.bzl", CFG_OGR_FDW = "CFG")
load("//extensions/omnisketch:cfg.bzl", CFG_OMNISKETCH = "CFG")
load("//extensions/oracle_fdw:cfg.bzl", CFG_ORACLE_FDW = "CFG")
load("//extensions/orafce:cfg.bzl", CFG_ORAFCE = "CFG")
load("//extensions/periods:cfg.bzl", CFG_PERIODS = "CFG")
load("//extensions/permuteseq:cfg.bzl", CFG_PERMUTESEQ = "CFG")
load("//extensions/pgactive:cfg.bzl", CFG_PGACTIVE = "CFG")
load("//extensions/pgaudit:cfg.bzl", CFG_PGAUDIT = "CFG")
load("//extensions/pgauditlogtofile:cfg.bzl", CFG_PGAUDITLOGTOFILE = "CFG")
load("//extensions/pg_auth_mon:cfg.bzl", CFG_PG_AUTH_MON = "CFG")
load("//extensions/pgautofailover:cfg.bzl", CFG_PGAUTOFAILOVER = "CFG")
load("//extensions/pg_background:cfg.bzl", CFG_PG_BACKGROUND = "CFG")
load("//extensions/pg_bigm:cfg.bzl", CFG_PG_BIGM = "CFG")
load("//extensions/pg_bulkload:cfg.bzl", CFG_PG_BULKLOAD = "CFG")
load("//extensions/pg_cron:cfg.bzl", CFG_PG_CRON = "CFG")
load("//extensions/pg_dbms_errlog:cfg.bzl", CFG_PG_DBMS_ERRLOG = "CFG")
load("//extensions/pg_dirtyread:cfg.bzl", CFG_PG_DIRTYREAD = "CFG")
load("//extensions/pg_fact_loader:cfg.bzl", CFG_PG_FACT_LOADER = "CFG")
load("//extensions/pgfincore:cfg.bzl", CFG_PGFINCORE = "CFG")
load("//extensions/pg_hashids:cfg.bzl", CFG_PG_HASHIDS = "CFG")
load("//extensions/pg_hint_plan:cfg.bzl", CFG_PG_HINT_PLAN = "CFG")
load("//extensions/pg_incremental:cfg.bzl", CFG_PG_INCREMENTAL = "CFG")
load("//extensions/pg_ivm:cfg.bzl", CFG_PG_IVM = "CFG")
load("//extensions/pgl_ddl_deploy:cfg.bzl", CFG_PGL_DDL_DEPLOY = "CFG")
load("//extensions/pglogical_ticker:cfg.bzl", CFG_PGLOGICAL_TICKER = "CFG")
load("//extensions/pg_math:cfg.bzl", CFG_PG_MATH = "CFG")
load("//extensions/pgmemcache:cfg.bzl", CFG_PGMEMCACHE = "CFG")
load("//extensions/pgmeminfo:cfg.bzl", CFG_PGMEMINFO = "CFG")
load("//extensions/pgmp:cfg.bzl", CFG_PGMP = "CFG")
load("//extensions/pg_net:cfg.bzl", CFG_PG_NET = "CFG")
load("//extensions/pgnodemx:cfg.bzl", CFG_PGNODEMX = "CFG")
load("//extensions/pg_partman:cfg.bzl", CFG_PG_PARTMAN = "CFG")
load("//extensions/pgpdf:cfg.bzl", CFG_PGPDF = "CFG")
load("//extensions/pg_proctab:cfg.bzl", CFG_PG_PROCTAB = "CFG")
load("//extensions/pg_profile:cfg.bzl", CFG_PG_PROFILE = "CFG")
load("//extensions/pg_protobuf:cfg.bzl", CFG_PG_PROTOBUF = "CFG")
load("//extensions/pg_pwhash:cfg.bzl", CFG_PG_PWHASH = "CFG")
load("//extensions/pgq:cfg.bzl", CFG_PGQ = "CFG")
load("//extensions/pgqr:cfg.bzl", CFG_PGQR = "CFG")
load("//extensions/pg_qualstats:cfg.bzl", CFG_PG_QUALSTATS = "CFG")
load("//extensions/pg_rational:cfg.bzl", CFG_PG_RATIONAL = "CFG")
load("//extensions/pg_readme:cfg.bzl", CFG_PG_README = "CFG")
load("//extensions/pg_readonly:cfg.bzl", CFG_PG_READONLY = "CFG")
load("//extensions/pg_relusage:cfg.bzl", CFG_PG_RELUSAGE = "CFG")
load("//extensions/pg_repack:cfg.bzl", CFG_PG_REPACK = "CFG")
load("//extensions/pg_rewrite:cfg.bzl", CFG_PG_REWRITE = "CFG")
load("//extensions/pgroonga:cfg.bzl", CFG_PGROONGA = "CFG")
load("//extensions/pgroonga_database:cfg.bzl", CFG_PGROONGA_DATABASE = "CFG")
load("//extensions/pg_rrule:cfg.bzl", CFG_PG_RRULE = "CFG")
load("//extensions/pgsentinel:cfg.bzl", CFG_PGSENTINEL = "CFG")
load("//extensions/pg_show_plans:cfg.bzl", CFG_PG_SHOW_PLANS = "CFG")
load("//extensions/pg_similarity:cfg.bzl", CFG_PG_SIMILARITY = "CFG")
load("//extensions/pg_snakeoil:cfg.bzl", CFG_PG_SNAKEOIL = "CFG")
load("//extensions/pgsodium:cfg.bzl", CFG_PGSODIUM = "CFG")
load("//extensions/pg_sphere:cfg.bzl", CFG_PG_SPHERE = "CFG")
load("//extensions/pgspider_ext:cfg.bzl", CFG_PGSPIDER_EXT = "CFG")
load("//extensions/pg_squeeze:cfg.bzl", CFG_PG_SQUEEZE = "CFG")
load("//extensions/pg_stat_kcache:cfg.bzl", CFG_PG_STAT_KCACHE = "CFG")
load("//extensions/pg_stat_monitor:cfg.bzl", CFG_PG_STAT_MONITOR = "CFG")
load("//extensions/pg_store_plans:cfg.bzl", CFG_PG_STORE_PLANS = "CFG")
load("//extensions/pg_strom:cfg.bzl", CFG_PG_STROM = "CFG")
load("//extensions/pgtap:cfg.bzl", CFG_PGTAP = "CFG")
load("//extensions/pg_task:cfg.bzl", CFG_PG_TASK = "CFG")
load("//extensions/pg_tde:cfg.bzl", CFG_PG_TDE = "CFG")
load("//extensions/pg_textsearch:cfg.bzl", CFG_PG_TEXTSEARCH = "CFG")
load("//extensions/pg_tracing:cfg.bzl", CFG_PG_TRACING = "CFG")
load("//extensions/pg_track_optimizer:cfg.bzl", CFG_PG_TRACK_OPTIMIZER = "CFG")
load("//extensions/pgtt:cfg.bzl", CFG_PGTT = "CFG")
load("//extensions/pg_ttl_index:cfg.bzl", CFG_PG_TTL_INDEX = "CFG")
load("//extensions/pg_uuidv7:cfg.bzl", CFG_PG_UUIDV7 = "CFG")
load("//extensions/pg_wait_sampling:cfg.bzl", CFG_PG_WAIT_SAMPLING = "CFG")
load("//extensions/pldbgapi:cfg.bzl", CFG_PLDBGAPI = "CFG")
load("//extensions/pljs:cfg.bzl", CFG_PLJS = "CFG")
load("//extensions/pllua:cfg.bzl", CFG_PLLUA = "CFG")
load("//extensions/plpgsql_check:cfg.bzl", CFG_PLPGSQL_CHECK = "CFG")
load("//extensions/plprofiler:cfg.bzl", CFG_PLPROFILER = "CFG")
load("//extensions/plproxy:cfg.bzl", CFG_PLPROXY = "CFG")
load("//extensions/plr:cfg.bzl", CFG_PLR = "CFG")
load("//extensions/plsh:cfg.bzl", CFG_PLSH = "CFG")
load("//extensions/plxslt:cfg.bzl", CFG_PLXSLT = "CFG")
load("//extensions/pointcloud:cfg.bzl", CFG_POINTCLOUD = "CFG")
load("//extensions/prefix:cfg.bzl", CFG_PREFIX = "CFG")
load("//extensions/pre_prepare:cfg.bzl", CFG_PRE_PREPARE = "CFG")
load("//extensions/q3c:cfg.bzl", CFG_Q3C = "CFG")
load("//extensions/quantile:cfg.bzl", CFG_QUANTILE = "CFG")
load("//extensions/repmgr:cfg.bzl", CFG_REPMGR = "CFG")
load("//extensions/roaringbitmap:cfg.bzl", CFG_ROARINGBITMAP = "CFG")
load("//extensions/rum:cfg.bzl", CFG_RUM = "CFG")
load("//extensions/semver:cfg.bzl", CFG_SEMVER = "CFG")
load("//extensions/sequential_uuids:cfg.bzl", CFG_SEQUENTIAL_UUIDS = "CFG")
load("//extensions/session_variable:cfg.bzl", CFG_SESSION_VARIABLE = "CFG")
load("//extensions/set_user:cfg.bzl", CFG_SET_USER = "CFG")
load("//extensions/snowflake:cfg.bzl", CFG_SNOWFLAKE = "CFG")
load("//extensions/spat:cfg.bzl", CFG_SPAT = "CFG")
load("//extensions/sqlite_fdw:cfg.bzl", CFG_SQLITE_FDW = "CFG")
load("//extensions/sslutils:cfg.bzl", CFG_SSLUTILS = "CFG")
load("//extensions/supabase_vault:cfg.bzl", CFG_SUPABASE_VAULT = "CFG")
load("//extensions/supautils:cfg.bzl", CFG_SUPAUTILS = "CFG")
load("//extensions/system_stats:cfg.bzl", CFG_SYSTEM_STATS = "CFG")
load("//extensions/table_log:cfg.bzl", CFG_TABLE_LOG = "CFG")
load("//extensions/tdigest:cfg.bzl", CFG_TDIGEST = "CFG")
load("//extensions/tds_fdw:cfg.bzl", CFG_TDS_FDW = "CFG")
load("//extensions/timescaledb:cfg.bzl", CFG_TIMESCALEDB = "CFG")
load("//extensions/timestamp9:cfg.bzl", CFG_TIMESTAMP9 = "CFG")
load("//extensions/toastinfo:cfg.bzl", CFG_TOASTINFO = "CFG")
load("//extensions/topn:cfg.bzl", CFG_TOPN = "CFG")
load("//extensions/uint:cfg.bzl", CFG_UINT = "CFG")
load("//extensions/uint128:cfg.bzl", CFG_UINT128 = "CFG")
load("//extensions/unit:cfg.bzl", CFG_UNIT = "CFG")
load("//extensions/uri:cfg.bzl", CFG_URI = "CFG")
load("//extensions/url_encode:cfg.bzl", CFG_URL_ENCODE = "CFG")
load("//extensions/vasco:cfg.bzl", CFG_VASCO = "CFG")
load("//extensions/vector:cfg.bzl", CFG_VECTOR = "CFG")
load("//extensions/xicor:cfg.bzl", CFG_XICOR = "CFG")
load("//extensions/xxhash:cfg.bzl", CFG_XXHASH = "CFG")
load("//extensions/zhparser:cfg.bzl", CFG_ZHPARSER = "CFG")
load("//extensions/zstd:cfg.bzl", CFG_ZSTD = "CFG")

CFGS_ALL = {
    "contrib": [CFGS_CONTRIB[pgext_name] for pgext_name in CFGS_CONTRIB],
    "acl": [CFG_ACL],
    "age": [CFG_AGE],
    "aggs_for_arrays": [CFG_AGGS_FOR_ARRAYS],
    "aggs_for_vecs": [CFG_AGGS_FOR_VECS],
    "asn1oid": [CFG_ASN1OID],
    "base36": [CFG_BASE36],
    "biscuit": [CFG_BISCUIT],
    "citus": [CFG_CITUS],
    "collection": [CFG_COLLECTION],
    "count_distinct": [CFG_COUNT_DISTINCT],
    "country": [CFG_COUNTRY],
    "cryptint": [CFG_CRYPTINT],
    "currency": [CFG_CURRENCY],
    "dbt2": [CFG_DBT2],
    "ddsketch": [CFG_DDSKETCH],
    "decoderbufs": [CFG_DECODERBUFS],
    "documentdb": [CFG_DOCUMENTDB],
    "duckdb_fdw": [CFG_DUCKDB_FDW],
    "envvar": [CFG_ENVVAR],
    "extra_window_functions": [CFG_EXTRA_WINDOW_FUNCTIONS],
    "financial": [CFG_FINANCIAL],
    "firebird_fdw": [CFG_FIREBIRD_FDW],
    "first_last_agg": [CFG_FIRST_LAST_AGG],
    "floatfile": [CFG_FLOATFILE],
    "floatvec": [CFG_FLOATVEC],
    "gzip": [CFG_GZIP],
    "hashtypes": [CFG_HASHTYPES],
    "hdfs_fdw": [CFG_HDFS_FDW],
    "http": [CFG_HTTP],
    "hypopg": [CFG_HYPOPG],
    "icu_ext": [CFG_ICU_EXT],
    "informix_fdw": [CFG_INFORMIX_FDW],
    "ip4r": [CFG_IP4R],
    "jdbc_fdw": [CFG_JDBC_FDW],
    "jsquery": [CFG_JSQUERY],
    "logerrors": [CFG_LOGERRORS],
    "log_fdw": [CFG_LOG_FDW],
    "login_hook": [CFG_LOGIN_HOOK],
    "lolor": [CFG_LOLOR],
    "lower_quantile": [CFG_LOWER_QUANTILE],
    "mobilitydb": [CFG_MOBILITYDB],
    "mongo_fdw": [CFG_MONGO_FDW],
    "multicorn": [CFG_MULTICORN],
    "mysql_fdw": [CFG_MYSQL_FDW],
    "nominatim_fdw": [CFG_NOMINATIM_FDW],
    "noset": [CFG_NOSET],
    "numeral": [CFG_NUMERAL],
    "odbc_fdw": [CFG_ODBC_FDW],
    "ogr_fdw": [CFG_OGR_FDW],
    "omnisketch": [CFG_OMNISKETCH],
    "oracle_fdw": [CFG_ORACLE_FDW],
    "orafce": [CFG_ORAFCE],
    "periods": [CFG_PERIODS],
    "permuteseq": [CFG_PERMUTESEQ],
    "pgactive": [CFG_PGACTIVE],
    "pgaudit": [CFG_PGAUDIT],
    "pgauditlogtofile": [CFG_PGAUDITLOGTOFILE],
    "pg_auth_mon": [CFG_PG_AUTH_MON],
    "pgautofailover": [CFG_PGAUTOFAILOVER],
    "pg_background": [CFG_PG_BACKGROUND],
    "pg_bigm": [CFG_PG_BIGM],
    "pg_bulkload": [CFG_PG_BULKLOAD],
    "pg_cron": [CFG_PG_CRON],
    "pg_dbms_errlog": [CFG_PG_DBMS_ERRLOG],
    "pg_dirtyread": [CFG_PG_DIRTYREAD],
    "pg_fact_loader": [CFG_PG_FACT_LOADER],
    "pgfincore": [CFG_PGFINCORE],
    "pg_hashids": [CFG_PG_HASHIDS],
    "pg_hint_plan": [CFG_PG_HINT_PLAN],
    "pg_incremental": [CFG_PG_INCREMENTAL],
    "pg_ivm": [CFG_PG_IVM],
    "pgl_ddl_deploy": [CFG_PGL_DDL_DEPLOY],
    "pglogical_ticker": [CFG_PGLOGICAL_TICKER],
    "pg_math": [CFG_PG_MATH],
    "pgmemcache": [CFG_PGMEMCACHE],
    "pgmeminfo": [CFG_PGMEMINFO],
    "pgmp": [CFG_PGMP],
    "pg_net": [CFG_PG_NET],
    "pgnodemx": [CFG_PGNODEMX],
    "pg_partman": [CFG_PG_PARTMAN],
    "pgpdf": [CFG_PGPDF],
    "pg_proctab": [CFG_PG_PROCTAB],
    "pg_profile": [CFG_PG_PROFILE],
    "pg_protobuf": [CFG_PG_PROTOBUF],
    "pg_pwhash": [CFG_PG_PWHASH],
    "pgq": [CFG_PGQ],
    "pgqr": [CFG_PGQR],
    "pg_qualstats": [CFG_PG_QUALSTATS],
    "pg_rational": [CFG_PG_RATIONAL],
    "pg_readme": [CFG_PG_README],
    "pg_readonly": [CFG_PG_READONLY],
    "pg_relusage": [CFG_PG_RELUSAGE],
    "pg_repack": [CFG_PG_REPACK],
    "pg_rewrite": [CFG_PG_REWRITE],
    "pgroonga": [CFG_PGROONGA],
    "pgroonga_database": [CFG_PGROONGA_DATABASE],
    "pg_rrule": [CFG_PG_RRULE],
    "pgsentinel": [CFG_PGSENTINEL],
    "pg_show_plans": [CFG_PG_SHOW_PLANS],
    "pg_similarity": [CFG_PG_SIMILARITY],
    "pg_snakeoil": [CFG_PG_SNAKEOIL],
    "pgsodium": [CFG_PGSODIUM],
    "pg_sphere": [CFG_PG_SPHERE],
    "pgspider_ext": [CFG_PGSPIDER_EXT],
    "pg_squeeze": [CFG_PG_SQUEEZE],
    "pg_stat_kcache": [CFG_PG_STAT_KCACHE],
    "pg_stat_monitor": [CFG_PG_STAT_MONITOR],
    "pg_store_plans": [CFG_PG_STORE_PLANS],
    "pg_strom": [CFG_PG_STROM],
    "pgtap": [CFG_PGTAP],
    "pg_task": [CFG_PG_TASK],
    "pg_tde": [CFG_PG_TDE],
    "pg_textsearch": [CFG_PG_TEXTSEARCH],
    "pg_tracing": [CFG_PG_TRACING],
    "pg_track_optimizer": [CFG_PG_TRACK_OPTIMIZER],
    "pgtt": [CFG_PGTT],
    "pg_ttl_index": [CFG_PG_TTL_INDEX],
    "pg_uuidv7": [CFG_PG_UUIDV7],
    "pg_wait_sampling": [CFG_PG_WAIT_SAMPLING],
    "pldbgapi": [CFG_PLDBGAPI],
    "pljs": [CFG_PLJS],
    "pllua": [CFG_PLLUA],
    "plpgsql_check": [CFG_PLPGSQL_CHECK],
    "plprofiler": [CFG_PLPROFILER],
    "plproxy": [CFG_PLPROXY],
    "plr": [CFG_PLR],
    "plsh": [CFG_PLSH],
    "plxslt": [CFG_PLXSLT],
    "pointcloud": [CFG_POINTCLOUD],
    "prefix": [CFG_PREFIX],
    "pre_prepare": [CFG_PRE_PREPARE],
    "q3c": [CFG_Q3C],
    "quantile": [CFG_QUANTILE],
    "repmgr": [CFG_REPMGR],
    "roaringbitmap": [CFG_ROARINGBITMAP],
    "rum": [CFG_RUM],
    "semver": [CFG_SEMVER],
    "sequential_uuids": [CFG_SEQUENTIAL_UUIDS],
    "session_variable": [CFG_SESSION_VARIABLE],
    "set_user": [CFG_SET_USER],
    "snowflake": [CFG_SNOWFLAKE],
    "spat": [CFG_SPAT],
    "sqlite_fdw": [CFG_SQLITE_FDW],
    "sslutils": [CFG_SSLUTILS],
    "supabase_vault": [CFG_SUPABASE_VAULT],
    "supautils": [CFG_SUPAUTILS],
    "system_stats": [CFG_SYSTEM_STATS],
    "table_log": [CFG_TABLE_LOG],
    "tdigest": [CFG_TDIGEST],
    "tds_fdw": [CFG_TDS_FDW],
    "timescaledb": [CFG_TIMESCALEDB],
    "timestamp9": [CFG_TIMESTAMP9],
    "toastinfo": [CFG_TOASTINFO],
    "topn": [CFG_TOPN],
    "uint": [CFG_UINT],
    "uint128": [CFG_UINT128],
    "unit": [CFG_UNIT],
    "uri": [CFG_URI],
    "url_encode": [CFG_URL_ENCODE],
    "vasco": [CFG_VASCO],
    "vector": [CFG_VECTOR],
    "xicor": [CFG_XICOR],
    "xxhash": [CFG_XXHASH],
    "zhparser": [CFG_ZHPARSER],
    "zstd": [CFG_ZSTD],
}
