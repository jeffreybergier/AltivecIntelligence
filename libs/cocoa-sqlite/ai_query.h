#ifndef AI_QUERY_H
#define AI_QUERY_H
#include <sqlite3.h>
#ifdef __cplusplus
extern "C" {
#endif
/* A serialized, read-only connection pinned to one committed snapshot. No
 * migrations/writes. Release promptly: live snapshots retain WAL history.
 * The caller serializes queries; cancellation may run on another thread while
 * the snapshot is alive. SQLite return codes are never converted to empty rows. */
typedef struct ai_query_snapshot ai_query_snapshot;
int ai_query_snapshot_open(const char *path, ai_query_snapshot **out);
sqlite3 *ai_query_snapshot_database(ai_query_snapshot *snapshot);
/* Up to eight reusable statements. Borrowed until return; nested checkouts of
 * the same SQL are permitted. Every checkout must be returned before close. */
int ai_query_snapshot_prepare(ai_query_snapshot *snapshot, const char *sql,
                              sqlite3_stmt **out);
int ai_query_snapshot_return(ai_query_snapshot *snapshot, sqlite3_stmt *statement);
void ai_query_snapshot_cancel(ai_query_snapshot *snapshot);
void ai_query_snapshot_close(ai_query_snapshot *snapshot);
#ifdef __cplusplus
}
#endif
#endif
