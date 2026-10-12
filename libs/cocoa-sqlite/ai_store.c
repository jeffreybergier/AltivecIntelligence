/* Copyright (c) 2026 Jeffrey Bergier. MIT; see ../../LICENSE. */
#include "ai_store.h"
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <limits.h>
struct ai_store_feed {
  pthread_mutex_t mutex;
  char *identity;
  ai_store_change *items;
  size_t capacity;
  uint64_t revision, generation;
};
ai_store_feed *ai_store_feed_create(const char *identity, size_t capacity)
{
  ai_store_feed *f;
  if (!identity || !capacity || capacity > INT_MAX) return NULL;
  f = calloc(1, sizeof(*f));
  if (!f) return NULL;
  f->identity = malloc(strlen(identity) + 1);
  f->items = calloc(capacity, sizeof(*f->items));
  if (!f->identity || !f->items || pthread_mutex_init(&f->mutex, NULL)) {
    free(f->identity); free(f->items); free(f); return NULL;
  }
  strcpy(f->identity, identity); f->capacity = capacity; f->generation = 1;
  return f;
}
void ai_store_feed_destroy(ai_store_feed *f)
{
  if (!f) return;
  pthread_mutex_destroy(&f->mutex); free(f->identity); free(f->items); free(f);
}
const char *ai_store_feed_identity(ai_store_feed *f) { return f->identity; }
static void keys(ai_store_change *c, const char *scope, const char *record)
{
  c->scope_key[0] = c->record_key[0] = 0;
  if (scope && strlen(scope) < sizeof(c->scope_key)) strcpy(c->scope_key, scope);
  else if (scope) c->full_refresh = 1;
  if (record && strlen(record) < sizeof(c->record_key)) strcpy(c->record_key, record);
  else c->full_refresh = 1;
}
static void publish(ai_store_feed *f, unsigned int topics, int64_t scope,
                    int64_t record, int full)
{
  ai_store_change *c;
  ++f->revision;
  c = &f->items[f->revision % f->capacity];
  c->generation = f->generation; c->revision = f->revision;
  c->topics = topics; c->scope = scope; c->record = record;
  c->full_refresh = full;
  c->scope_key[0] = c->record_key[0] = 0;
  if (scope) snprintf(c->scope_key,sizeof(c->scope_key),"%lld",(long long)scope);
  if (record) snprintf(c->record_key,sizeof(c->record_key),"%lld",(long long)record);
}
void ai_store_feed_publish(ai_store_feed *f, unsigned int topics,
                           int64_t scope, int64_t record, int full)
{
  if (!f) return;
  pthread_mutex_lock(&f->mutex);
  publish(f, topics, scope, record, full);
  pthread_mutex_unlock(&f->mutex);
}
void ai_store_feed_publish_key(ai_store_feed *f, unsigned int topics,
                               const char *scope, const char *record)
{
  ai_store_change *c;
  if (!f) return;
  pthread_mutex_lock(&f->mutex);
  publish(f, topics, 0, 0, 0); c = &f->items[f->revision % f->capacity];
  keys(c, scope, record);
  pthread_mutex_unlock(&f->mutex);
}
void ai_store_feed_reset(ai_store_feed *f)
{
  pthread_mutex_lock(&f->mutex);
  ++f->generation; publish(f, ~0U, 0, 0, 1);
  pthread_mutex_unlock(&f->mutex);
}
int ai_store_feed_read_key(ai_store_feed *f, uint64_t after, unsigned int topics,
                       const char *scope, uint64_t *next, ai_store_change *out,
                       size_t capacity)
{
  uint64_t r;
  size_t n = 0, i;
  int full = 0;
  if (!f || !next || (!out && capacity)) return -1;
  pthread_mutex_lock(&f->mutex); *next = f->revision;
  if (!after || after > *next || *next - after > f->capacity) full = 1;
  else for (r = after + 1; r <= *next; ++r) {
    ai_store_change *c = &f->items[r % f->capacity];
    if (!(c->topics & topics) || (scope && *scope && c->scope_key[0] && strcmp(c->scope_key,scope))) continue;
    if (c->full_refresh || !c->record_key[0] || (scope && *scope && !c->scope_key[0])) { full = 1; break; }
    for (i = 0; i < n; ++i)
      if (!strcmp(out[i].record_key,c->record_key) && !strcmp(out[i].scope_key,c->scope_key)) break;
    if (i == n) {
      if (n == capacity) { full = 1; break; }
      out[n++] = *c;
    } else { out[i].topics |= c->topics; out[i].revision = c->revision; }
  }
  pthread_mutex_unlock(&f->mutex);
  return full ? -1 : (int)n;
}
int ai_store_feed_read(ai_store_feed *f, uint64_t after, unsigned int topics,
                       int64_t scope, uint64_t *next, ai_store_change *out,
                       size_t capacity)
{
  char key[32]; key[0] = 0;
  if (scope) snprintf(key,sizeof(key),"%lld",(long long)scope);
  return ai_store_feed_read_key(f,after,topics,key,next,out,capacity);
}
#define AI_PENDING 256
#define AI_SAVEPOINTS 32
struct ai_store_writer {
  sqlite3 *db;
  ai_store_feed *feed;
  ai_store_change pending[AI_PENDING];
  int count, dirty, overflow, depth, active;
  struct { int count, dirty, overflow; } saves[AI_SAVEPOINTS];
};
static void update_hint(void *context, int operation, const char *db,
                        const char *table, sqlite3_int64 row)
{
  ai_store_writer *w = context;
  (void)operation; (void)db; (void)table; (void)row;
  w->dirty = 1; /* No SQL, allocations, or Objective-C in hooks. */
}
int ai_store_writer_open(const char *path, ai_store_feed *feed, int hooks,
                         ai_store_writer **out)
{
  ai_store_writer *w = calloc(1, sizeof(*w)); int rc;
  *out = NULL; if (!w) return SQLITE_NOMEM;
  rc = sqlite3_open(path, &w->db);
  if (rc != SQLITE_OK) { sqlite3_close(w->db); free(w); return rc; }
  w->feed = feed;
  if (hooks) sqlite3_update_hook(w->db, update_hint, w);
  *out = w; return SQLITE_OK;
}
sqlite3 *ai_store_writer_database(ai_store_writer *w) { return w->db; }
int ai_store_writer_begin(ai_store_writer *w)
{
  int rc;
  if (w->active) return SQLITE_MISUSE;
  rc = sqlite3_exec(w->db, "BEGIN IMMEDIATE", NULL, NULL, NULL);
  if (rc == SQLITE_OK) { w->active = 1; w->count = w->dirty = w->overflow = w->depth = 0; }
  return rc;
}
int ai_store_writer_savepoint(ai_store_writer *w)
{
  char sql[64]; int rc;
  if (!w->active || w->depth == AI_SAVEPOINTS) return SQLITE_MISUSE;
  snprintf(sql, sizeof(sql), "SAVEPOINT ai_%d", w->depth);
  rc = sqlite3_exec(w->db, sql, NULL, NULL, NULL);
  if (rc == SQLITE_OK) {
    w->saves[w->depth].count = w->count;
    w->saves[w->depth].dirty = w->dirty;
    w->saves[w->depth].overflow = w->overflow; ++w->depth;
  }
  return rc;
}
int ai_store_writer_release(ai_store_writer *w)
{
  char sql[64]; int rc;
  if (!w->active || !w->depth) return SQLITE_MISUSE;
  snprintf(sql, sizeof(sql), "RELEASE ai_%d", w->depth - 1);
  rc = sqlite3_exec(w->db, sql, NULL, NULL, NULL);
  if (rc == SQLITE_OK) --w->depth;
  return rc;
}
int ai_store_writer_rollback_to(ai_store_writer *w)
{
  char sql[64]; int rc;
  if (!w->active || !w->depth) return SQLITE_MISUSE;
  snprintf(sql, sizeof(sql), "ROLLBACK TO ai_%d", w->depth - 1);
  rc = sqlite3_exec(w->db, sql, NULL, NULL, NULL);
  if (rc == SQLITE_OK) {
    w->count = w->saves[w->depth - 1].count;
    w->dirty = w->saves[w->depth - 1].dirty;
    w->overflow = w->saves[w->depth - 1].overflow;
  }
  return rc;
}
int ai_store_writer_change(ai_store_writer *w, unsigned int topics,
                           int64_t scope, int64_t record)
{
  ai_store_change *c;
  if (!w->active || sqlite3_get_autocommit(w->db)) return SQLITE_MISUSE;
  if (w->count == AI_PENDING) { w->overflow = 1; return SQLITE_OK; }
  c = &w->pending[w->count++]; memset(c, 0, sizeof(*c));
  c->topics = topics; c->scope = scope; c->record = record;
  c->full_refresh = !record;
  if (scope) snprintf(c->scope_key,sizeof(c->scope_key),"%lld",(long long)scope);
  if (record) snprintf(c->record_key,sizeof(c->record_key),"%lld",(long long)record);
  return SQLITE_OK;
}
int ai_store_writer_change_key(ai_store_writer *w, unsigned int topics,
                               const char *scope, const char *record)
{
  ai_store_change *c;
  if (!w->active || sqlite3_get_autocommit(w->db)) return SQLITE_MISUSE;
  if (w->count == AI_PENDING) { w->overflow = 1; return SQLITE_OK; }
  c = &w->pending[w->count++]; memset(c,0,sizeof(*c)); c->topics = topics;
  keys(c,scope,record); return SQLITE_OK;
}
int ai_store_writer_commit(ai_store_writer *w)
{
  int rc, i;
  if (!w->active || sqlite3_get_autocommit(w->db)) return SQLITE_MISUSE;
  rc = sqlite3_exec(w->db, "COMMIT", NULL, NULL, NULL);
  if (rc == SQLITE_OK) {
    if (w->overflow || w->dirty) ai_store_feed_publish(w->feed, ~0U, 0, 0, 1);
    else for (i = 0; i < w->count; ++i) {
      ai_store_change *c = &w->pending[i];
      if (c->record || c->scope || c->full_refresh)
        ai_store_feed_publish(w->feed, c->topics, c->scope, c->record, c->full_refresh);
      else ai_store_feed_publish_key(w->feed,c->topics,c->scope_key,c->record_key);
    }
    w->active = 0;
  } else if (sqlite3_get_autocommit(w->db)) w->active = 0;
  return rc;
}
int ai_store_writer_rollback(ai_store_writer *w)
{
  int rc = sqlite3_get_autocommit(w->db) ? SQLITE_OK :
    sqlite3_exec(w->db, "ROLLBACK", NULL, NULL, NULL);
  if (rc == SQLITE_OK) w->active = w->count = w->dirty = w->overflow = w->depth = 0;
  return rc;
}
void ai_store_writer_close(ai_store_writer *w)
{
  if (!w) return;
  ai_store_writer_rollback(w); sqlite3_close(w->db); free(w);
}
