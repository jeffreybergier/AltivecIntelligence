#define _POSIX_C_SOURCE 200809L
#include "ai_store.h"
#include "ai_query.h"
#include <assert.h>
#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <time.h>
#include <string.h>
#include <sys/stat.h>
static void exec(sqlite3 *db, const char *sql) { assert(sqlite3_exec(db,sql,0,0,0)==SQLITE_OK); }
static int veto(void *p) { (void)p; return 1; }
int main(void)
{
  char path[] = "/tmp/ai-store-XXXXXX";
  int fd = mkstemp(path), i, rc; uint64_t a, b, next;
  ai_store_feed *f = ai_store_feed_create("fixture", 4);
  ai_store_change changes[8]; ai_store_writer *w; sqlite3 *db;
  ai_query_snapshot *s; sqlite3_stmt *q, *reused;
  assert(fd >= 0); close(fd);
  assert(ai_store_writer_open(path,f,0,&w)==SQLITE_OK);
  db = ai_store_writer_database(w);
  exec(db,"PRAGMA journal_mode=WAL; CREATE TABLE rows(id INTEGER PRIMARY KEY, value TEXT)");
  ai_store_feed_publish(f,1,1,1,0);
  assert(ai_store_feed_read(f,0,1,1,&a,changes,8)==-1); b=a;
  assert(ai_store_writer_begin(w)==SQLITE_OK);
  exec(db,"INSERT INTO rows VALUES(1,'one')");
  assert(ai_store_writer_change(w,1,1,1)==SQLITE_OK);
  assert(ai_store_feed_read(f,a,1,1,&next,changes,8)==0);
  assert(ai_store_writer_savepoint(w)==SQLITE_OK);
  exec(db,"INSERT INTO rows VALUES(2,'two')");
  assert(ai_store_writer_change(w,1,1,2)==SQLITE_OK);
  assert(ai_store_writer_rollback_to(w)==SQLITE_OK);
  assert(ai_store_writer_release(w)==SQLITE_OK);
  assert(ai_store_writer_commit(w)==SQLITE_OK);
  assert(ai_store_feed_read(f,a,1,1,&a,changes,8)==1 && changes[0].record==1);
  assert(ai_store_feed_read(f,b,1,1,&b,changes,8)==1 && a==b);
  assert(ai_query_snapshot_open(path,&s)==SQLITE_OK);
  assert(ai_query_snapshot_prepare(s,"SELECT count(*) FROM rows",&q)==SQLITE_OK);
  reused=q; assert(sqlite3_step(q)==SQLITE_ROW && sqlite3_column_int(q,0)==1);
  assert(ai_query_snapshot_return(s,q)==SQLITE_OK);
  assert(ai_store_writer_begin(w)==SQLITE_OK);
  exec(db,"INSERT INTO rows VALUES(3,'three')");
  assert(ai_store_writer_change(w,1,1,3)==SQLITE_OK);
  assert(ai_store_writer_rollback(w)==SQLITE_OK);
  assert(ai_store_feed_read(f,a,1,1,&next,changes,8)==0);
  assert(ai_store_writer_begin(w)==SQLITE_OK);
  exec(db,"INSERT INTO rows VALUES(3,'three')");
  assert(ai_store_writer_change(w,1,1,3)==SQLITE_OK);
  assert(ai_store_writer_commit(w)==SQLITE_OK);
  assert(ai_query_snapshot_prepare(s,"SELECT count(*) FROM rows",&q)==SQLITE_OK && q==reused);
  assert(sqlite3_step(q)==SQLITE_ROW && sqlite3_column_int(q,0)==1);
  ai_query_snapshot_return(s,q); ai_query_snapshot_close(s);
  assert(ai_store_feed_read(f,a,1,1,&a,changes,8)==1);
  /* Even a called commit hook is not a committed change. */
  sqlite3_commit_hook(db,veto,NULL);
  assert(ai_store_writer_begin(w)==SQLITE_OK);
  exec(db,"INSERT INTO rows VALUES(4,'four')");
  assert(ai_store_writer_change(w,1,1,4)==SQLITE_OK);
  rc=ai_store_writer_commit(w); assert(rc!=SQLITE_OK);
  assert(ai_store_feed_read(f,a,1,1,&next,changes,8)==0);
  sqlite3_commit_hook(db,NULL,NULL);
  for(i=0;i<5;++i) ai_store_feed_publish(f,1,1,i+10,0);
  assert(ai_store_feed_read(f,a,1,1,&a,changes,8)==-1);
  ai_store_feed_reset(f);
  assert(ai_store_feed_read(f,a,1,1,&a,changes,8)==-1);
  /* Capture cursor before read; a concurrent write remains pending. */
  b=a; ai_store_feed_publish(f,1,1,99,0);
  assert(ai_store_feed_read(f,b,1,1,&a,changes,8)==1);
  ai_store_feed_publish(f,1,1,100,0);
  assert(ai_store_feed_read(f,a,1,1,&next,changes,8)==1 && changes[0].record==100);
  ai_store_writer_close(w);
  assert(ai_store_writer_open(path,f,1,&w)==SQLITE_OK);
  db=ai_store_writer_database(w);
  assert(ai_store_writer_begin(w)==SQLITE_OK);
  exec(db,"INSERT INTO rows VALUES(200,'hook')");
  assert(ai_store_writer_rollback(w)==SQLITE_OK);
  assert(ai_store_feed_read(f,next,1,1,&a,changes,8)==0);
  assert(ai_store_writer_begin(w)==SQLITE_OK);
  exec(db,"INSERT INTO rows VALUES(200,'hook')");
  assert(ai_store_writer_commit(w)==SQLITE_OK);
  assert(ai_store_feed_read(f,a,1,1,&a,changes,8)==-1);
  /* Savepoint hook candidates are discarded, not published as phantom writes. */
  assert(ai_store_writer_begin(w)==SQLITE_OK);
  assert(ai_store_writer_savepoint(w)==SQLITE_OK);
  exec(db,"INSERT INTO rows VALUES(201,'discard')");
  assert(ai_store_writer_rollback_to(w)==SQLITE_OK);
  assert(ai_store_writer_release(w)==SQLITE_OK);
  assert(ai_store_writer_commit(w)==SQLITE_OK);
  assert(ai_store_feed_read(f,a,1,1,&a,changes,8)==0);
  /* Exact reporting covers hook omissions and deferred COMMIT failures. */
  exec(db,"PRAGMA foreign_keys=ON; CREATE TABLE keyed(k TEXT PRIMARY KEY) WITHOUT ROWID;"
          "CREATE TABLE child(k INTEGER REFERENCES rows(id) DEFERRABLE INITIALLY DEFERRED)");
  assert(ai_store_writer_begin(w)==SQLITE_OK);
  exec(db,"INSERT INTO keyed VALUES('stable-key')");
  assert(ai_store_writer_change(w,1,1,500)==SQLITE_OK);
  assert(ai_store_writer_commit(w)==SQLITE_OK);
  assert(ai_store_feed_read(f,a,1,1,&a,changes,8)==1 && changes[0].record==500);
  assert(ai_store_writer_begin(w)==SQLITE_OK);
  exec(db,"INSERT INTO child VALUES(999999)");
  assert(ai_store_writer_change(w,1,1,999)==SQLITE_OK);
  assert(ai_store_writer_commit(w)!=SQLITE_OK);
  assert(ai_store_feed_read(f,a,1,1,&a,changes,8)==0);
  assert(ai_store_writer_rollback(w)==SQLITE_OK);
  assert(ai_store_writer_begin(w)==SQLITE_OK);
  exec(db,"INSERT INTO keyed VALUES('text:composite/key')");
  assert(ai_store_writer_change_key(w,1,"account-A","text:composite/key")==SQLITE_OK);
  assert(ai_store_writer_commit(w)==SQLITE_OK);
  assert(ai_store_feed_read_key(f,a,1,"account-A",&a,changes,8)==1);
  assert(!strcmp(changes[0].record_key,"text:composite/key"));
  /* Deterministic large fixture, duplicate/NULL sort values and random jumps. */
  exec(db,"CREATE TABLE large(id INTEGER PRIMARY KEY, sort INTEGER);"
          "CREATE INDEX large_order ON large(sort DESC,id DESC); BEGIN");
  assert(sqlite3_prepare_v2(db,"INSERT INTO large VALUES(?1,?2)",-1,&q,NULL)==SQLITE_OK);
  for(i=1;i<=100000;++i) {
    sqlite3_bind_int(q,1,i);
    if(i%7) sqlite3_bind_int(q,2,i/10); else sqlite3_bind_null(q,2);
    assert(sqlite3_step(q)==SQLITE_DONE); sqlite3_reset(q);
  }
  sqlite3_finalize(q); exec(db,"COMMIT");
  {
    clock_t start=clock(); int queries=0; char wal[128]; struct stat info;
    assert(ai_query_snapshot_open(path,&s)==SQLITE_OK);
    assert(ai_query_snapshot_prepare(s,"SELECT count(*) FROM large",&q)==SQLITE_OK);
    assert(sqlite3_step(q)==SQLITE_ROW && sqlite3_column_int(q,0)==100000);
    ai_query_snapshot_return(s,q); ++queries;
    for(i=0;i<64;++i) {
      assert(ai_query_snapshot_prepare(s,
        "SELECT id,sort FROM large ORDER BY sort DESC,id DESC LIMIT 32 OFFSET ?1",&q)==SQLITE_OK);
      sqlite3_bind_int(q,1,i<32?i*32:(i*3571)%99968);
      while((rc=sqlite3_step(q))==SQLITE_ROW) assert(sqlite3_column_int(q,0)>0);
      assert(rc==SQLITE_DONE); ai_query_snapshot_return(s,q); ++queries;
    }
    exec(db,"DELETE FROM large WHERE id%3=0");
    assert(ai_query_snapshot_prepare(s,"SELECT count(*) FROM large",&q)==SQLITE_OK);
    assert(sqlite3_step(q)==SQLITE_ROW && sqlite3_column_int(q,0)==100000);
    ai_query_snapshot_return(s,q); ++queries;
    snprintf(wal,sizeof(wal),"%s-wal",path);
    assert(stat(wal,&info)==0);
    printf("100000 rows: %d queries, %.2f ms CPU, pinned WAL %lld bytes\n",
      queries,1000.0*(double)(clock()-start)/CLOCKS_PER_SEC,(long long)info.st_size);
    ai_query_snapshot_close(s); exec(db,"PRAGMA wal_checkpoint(TRUNCATE)");
    assert(stat(wal,&info)==0 && info.st_size==0);
  }
  ai_store_writer_close(w); ai_store_feed_destroy(f); unlink(path);
  puts("SQLite feed/savepoints/rollback/independent cursors/snapshots: PASS");
  return 0;
}
