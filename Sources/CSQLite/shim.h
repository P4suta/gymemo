#include <sqlite3.h>

static inline sqlite3_destructor_type gymemo_sqlite_transient(void) {
    return SQLITE_TRANSIENT;
}
