// SQLite Web Worker for sqflite_common_ffi_web
importScripts('https://cdn.jsdelivr.net/npm/sql.js@1.8.0/dist/sql-wasm.js');

let db = null;

self.onmessage = function(e) {
  const { id, method, args } = e.data;

  try {
    switch (method) {
      case 'init':
        initSqlJs().then((SQL) => {
          db = new SQL.Database();
          self.postMessage({ id, result: 'initialized' });
        }).catch((error) => {
          self.postMessage({ id, error: error.message });
        });
        break;

      case 'execute':
        if (!db) {
          self.postMessage({ id, error: 'Database not initialized' });
          return;
        }

        const result = db.exec(args[0]);
        self.postMessage({ id, result });
        break;

      case 'close':
        if (db) {
          db.close();
          db = null;
        }
        self.postMessage({ id, result: 'closed' });
        break;

      default:
        self.postMessage({ id, error: `Unknown method: ${method}` });
    }
  } catch (error) {
    self.postMessage({ id, error: error.message });
  }
};
