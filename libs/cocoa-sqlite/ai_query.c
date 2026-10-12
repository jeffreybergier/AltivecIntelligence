#include "ai_query.h"
#include <stdlib.h>
#include <string.h>
#define AI_STATEMENTS 8
struct ai_query_snapshot {
  sqlite3 *db;
  struct { sqlite3_stmt *stmt; int busy; } cache[AI_STATEMENTS];
};
int ai_query_snapshot_open(const char *path, ai_query_snapshot **out)
{
  ai_query_snapshot *s = calloc(1, sizeof(*s)); int rc;
  *out = NULL; if (!s) return SQLITE_NOMEM;
  rc = sqlite3_open_v2(path, &s->db, SQLITE_OPEN_READONLY, NULL);
  /* Reading sqlite_master establishes the snapshot before counts/pages. */
  if (rc == SQLITE_OK) rc = sqlite3_exec(s->db,
    "BEGIN; SELECT count(*) FROM sqlite_master", NULL, NULL, NULL);
  if (rc != SQLITE_OK) { ai_query_snapshot_close(s); return rc; }
  *out = s; return SQLITE_OK;
}
sqlite3 *ai_query_snapshot_database(ai_query_snapshot *s) { return s->db; }
int ai_query_snapshot_prepare(ai_query_snapshot *s, const char *sql,
                              sqlite3_stmt **out)
{
  int i, slot = -1, rc;
  *out = NULL;
  for (i = 0; i < AI_STATEMENTS; ++i) {
    if (s->cache[i].busy) continue;
    if (s->cache[i].stmt && !strcmp(sqlite3_sql(s->cache[i].stmt), sql)) {
      s->cache[i].busy = 1; *out = s->cache[i].stmt; return SQLITE_OK;
    }
    if (slot < 0 || !s->cache[i].stmt) slot = i;
  }
  rc = sqlite3_prepare_v2(s->db, sql, -1, out, NULL);
  if (rc == SQLITE_OK && *out && !sqlite3_stmt_readonly(*out)) {
    sqlite3_finalize(*out); *out = NULL; return SQLITE_READONLY;
  }
  if (rc == SQLITE_OK && *out && slot >= 0) {
    sqlite3_finalize(s->cache[slot].stmt);
    s->cache[slot].stmt = *out; s->cache[slot].busy = 1;
  }
  return rc;
}
int ai_query_snapshot_return(ai_query_snapshot *s, sqlite3_stmt *stmt)
{
  int i, rc;
  if (!stmt) return SQLITE_OK;
  for (i = 0; i < AI_STATEMENTS; ++i) if (s->cache[i].stmt == stmt) {
    rc = sqlite3_reset(stmt); sqlite3_clear_bindings(stmt);
    s->cache[i].busy = 0; return rc;
  }
  return sqlite3_finalize(stmt);
}
void ai_query_snapshot_cancel(ai_query_snapshot *s) { sqlite3_interrupt(s->db); }
void ai_query_snapshot_close(ai_query_snapshot *s)
{
  int i;
  if (!s) return;
  for (i = 0; i < AI_STATEMENTS; ++i) sqlite3_finalize(s->cache[i].stmt);
  if (s->db) { sqlite3_exec(s->db, "ROLLBACK", NULL, NULL, NULL); sqlite3_close(s->db); }
  free(s);
}
