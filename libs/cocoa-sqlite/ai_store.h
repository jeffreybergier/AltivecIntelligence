/* Copyright (c) 2026 Jeffrey Bergier. MIT; see ../../LICENSE. */
#ifndef AI_STORE_H
#define AI_STORE_H
#include <stddef.h>
#include <stdint.h>
#include <sqlite3.h>
#ifdef __cplusplus
extern "C" {
#endif
/* One feed per store/account lifetime. Callers own IPC and domain mapping.
 * All feed operations are thread safe. Destroy only after producers stop.
 * A read never advances another reader: acknowledge its returned revision only
 * after applying the corresponding authoritative read. Zero requests resync. */
typedef struct ai_store_feed ai_store_feed;
typedef struct {
  uint64_t generation, revision;
  unsigned int topics;
  int64_t scope, record;
  int full_refresh;
  char scope_key[128], record_key[128];
} ai_store_change;
ai_store_feed *ai_store_feed_create(const char *identity, size_t capacity);
void ai_store_feed_destroy(ai_store_feed *feed);
const char *ai_store_feed_identity(ai_store_feed *feed);
/* Only call after successful commit, or for an IPC invalidation hint. */
void ai_store_feed_publish(ai_store_feed *feed, unsigned int topics,
                           int64_t scope, int64_t record, int full_refresh);
/* Text identities are copied, including non-rowid/composite application keys.
 * Keys exceeding 127 UTF-8 bytes conservatively invalidate the whole scope. */
void ai_store_feed_publish_key(ai_store_feed *feed, unsigned int topics,
                               const char *scope, const char *record);
int ai_store_feed_read_key(ai_store_feed *feed, uint64_t after,
                           unsigned int topics, const char *scope, uint64_t *next,
                           ai_store_change *changes, size_t capacity);
/* Reconnect/account replacement invalidates all cursors. */
void ai_store_feed_reset(ai_store_feed *feed);
/* -1 = full resync (overflow, missing scope/identity, reset), >=0 = count.
 * Captures next before the caller starts its read, preserving racing writes. */
int ai_store_feed_read(ai_store_feed *feed, uint64_t after,
                       unsigned int topics, int64_t scope, uint64_t *next,
                       ai_store_change *changes, size_t capacity);

/* An explicitly owned writer: no hook can replace an existing consumer because
 * this API opens the connection. The optional update hook only marks a dirty
 * hint; commit publication comes from the successful COMMIT return value.
 * All writes must be enclosed by these transaction/savepoint operations.
 * Direct transaction SQL and installing hooks on this connection are forbidden.
 * Serialize all writer access externally. feed is borrowed until close. */
typedef struct ai_store_writer ai_store_writer;
int ai_store_writer_open(const char *path, ai_store_feed *feed,
                         int hook_hints, ai_store_writer **out);
sqlite3 *ai_store_writer_database(ai_store_writer *writer);
int ai_store_writer_begin(ai_store_writer *writer);
/* Savepoints are nested, library named, and released/rolled back LIFO. */
int ai_store_writer_savepoint(ai_store_writer *writer);
int ai_store_writer_release(ai_store_writer *writer);
int ai_store_writer_rollback_to(ai_store_writer *writer);
/* Explicit changes cover WITHOUT ROWID, REPLACE and domain identities. */
int ai_store_writer_change(ai_store_writer *writer, unsigned int topics,
                           int64_t scope, int64_t record);
int ai_store_writer_change_key(ai_store_writer *writer, unsigned int topics,
                               const char *scope, const char *record);
int ai_store_writer_commit(ai_store_writer *writer);
int ai_store_writer_rollback(ai_store_writer *writer);
void ai_store_writer_close(ai_store_writer *writer);
#ifdef __cplusplus
}
#endif
#endif
