// Read-only Flyway migration dashboard.
// Reads flyway_schema_history from dev_db, test_db and prod_db, and the migration
// files from /sql. It never writes to any database.
const http = require('http');
const fs = require('fs');
const path = require('path');
const { Client } = require('pg');

const ENVS = ['dev', 'test', 'prod'];
const PORT = 3000;
const SQL_DIR = process.env.SQL_DIR || '/sql';

function dbConfig(db) {
  return {
    host: process.env.PGHOST || 'postgres',
    port: Number(process.env.PGPORT || 5432),
    user: process.env.PGUSER || 'admin',
    password: process.env.PGPASSWORD || 'admin123',
    database: db,
    connectionTimeoutMillis: 3000,
  };
}

async function readEnv(env) {
  const client = new Client(dbConfig(`${env}_db`));
  try {
    await client.connect();
    const exists = await client.query("SELECT to_regclass('public.flyway_schema_history') AS t");
    if (!exists.rows[0].t) {
      return { env, reachable: true, initialised: false, rows: [] };
    }
    const r = await client.query(
      `SELECT installed_rank, version, description, type, script, checksum,
              installed_by, installed_on, execution_time, success
       FROM flyway_schema_history ORDER BY installed_rank`
    );
    return { env, reachable: true, initialised: true, rows: r.rows };
  } catch (e) {
    return { env, reachable: false, initialised: false, error: e.message, rows: [] };
  } finally {
    try { await client.end(); } catch (_) { /* ignore */ }
  }
}

function readFiles() {
  let names = [];
  try { names = fs.readdirSync(SQL_DIR); } catch (_) { /* folder missing */ }
  const files = [];
  for (const n of names) {
    let m = n.match(/^V(\d+(?:[._]\d+)*)__(.+)\.sql$/);
    if (m) {
      files.push({ kind: 'V', version: m[1].replace(/_/g, '.'), description: m[2].replace(/_/g, ' '), script: n });
      continue;
    }
    m = n.match(/^R__(.+)\.sql$/);
    if (m) files.push({ kind: 'R', version: null, description: m[1].replace(/_/g, ' '), script: n });
  }
  return files;
}

const keyOf = (version, description) => (version ? `V${version}` : `R:${description}`);

function cmpVersion(a, b) {
  const pa = a.split('.').map(Number);
  const pb = b.split('.').map(Number);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const d = (pa[i] || 0) - (pb[i] || 0);
    if (d !== 0) return d;
  }
  return 0;
}

function buildState(files, results) {
  // Union of every migration known from files or from any history table.
  const known = new Map();
  for (const f of files) {
    known.set(keyOf(f.version, f.description), { ...f, key: keyOf(f.version, f.description), onDisk: true });
  }
  for (const res of results) {
    for (const r of res.rows) {
      if (r.type === 'SCHEMA') continue;
      const k = keyOf(r.version, r.description);
      if (!known.has(k)) {
        known.set(k, {
          key: k, kind: r.version ? 'V' : 'R', version: r.version,
          description: r.description, script: r.script, onDisk: false,
        });
      }
    }
  }
  const ordered = [...known.values()].sort((a, b) => {
    if (a.kind !== b.kind) return a.kind === 'V' ? -1 : 1;
    if (a.kind === 'V') return cmpVersion(a.version, b.version);
    return a.description.localeCompare(b.description);
  });

  // Latest history row per migration per environment.
  const byEnv = {};
  for (const res of results) {
    const m = new Map();
    for (const r of res.rows) {
      if (r.type === 'SCHEMA') continue;
      m.set(keyOf(r.version, r.description), r);
    }
    byEnv[res.env] = m;
  }

  const ref = results.find((r) => r.env === 'dev' && r.initialised) || results.find((r) => r.initialised);
  const refEnv = ref ? ref.env : null;

  const rows = ordered.map((mig) => {
    const cells = {};
    for (const res of results) {
      const h = byEnv[res.env].get(mig.key);
      let status;
      if (h) status = h.success ? 'applied' : 'failed';
      else status = mig.onDisk ? 'pending' : 'absent';
      let mismatch = false;
      if (h && refEnv && res.env !== refEnv) {
        const rh = byEnv[refEnv].get(mig.key);
        if (rh && rh.success && h.success && rh.checksum !== h.checksum) mismatch = true;
      }
      cells[res.env] = h
        ? { status, mismatch, checksum: h.checksum, installedOn: h.installed_on, executionTime: h.execution_time }
        : { status, mismatch };
    }
    return {
      key: mig.key, kind: mig.kind, version: mig.version,
      description: mig.description, script: mig.script, onDisk: mig.onDisk, cells,
    };
  });

  const envs = results.map((res) => {
    const out = {
      env: res.env, reachable: res.reachable, initialised: res.initialised, error: res.error || null,
      current: null, applied: 0, failed: 0, pending: 0, drift: 0, status: 'sync',
      history: res.rows.filter((r) => r.type !== 'SCHEMA'),
    };
    if (!res.reachable) { out.status = 'unreachable'; return out; }
    if (!res.initialised) {
      out.status = 'uninitialised';
      out.pending = rows.filter((r) => r.onDisk).length;
      return out;
    }
    for (const row of rows) {
      const c = row.cells[res.env];
      if (c.status === 'applied') out.applied++;
      if (c.status === 'failed') out.failed++;
      if (c.status === 'pending') out.pending++;
      if (refEnv && res.env !== refEnv) {
        if (c.mismatch || c.status !== row.cells[refEnv].status) out.drift++;
      }
      if (c.status === 'applied' && row.kind === 'V') {
        if (!out.current || cmpVersion(row.version, out.current) > 0) out.current = row.version;
      }
    }
    if (out.failed > 0) out.status = 'failed';
    else if (out.pending > 0) out.status = 'pending';
    else if (out.drift > 0) out.status = 'drift';
    else out.status = 'sync';
    return out;
  });

  return { generatedAt: new Date().toISOString(), reference: refEnv, rows, envs };
}

async function getState() {
  const results = await Promise.all(ENVS.map(readEnv));
  return buildState(readFiles(), results);
}

if (require.main === module) {
  const indexPath = path.join(__dirname, 'public', 'index.html');
  http.createServer(async (req, res) => {
    try {
      if (req.url === '/api/state') {
        const state = await getState();
        res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
        res.end(JSON.stringify(state));
      } else if (req.url === '/' || req.url === '/index.html') {
        res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
        res.end(fs.readFileSync(indexPath));
      } else {
        res.writeHead(404); res.end('Not found');
      }
    } catch (e) {
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: e.message }));
    }
  }).listen(PORT, () => console.log(`Dashboard on http://localhost:${PORT}`));
}

module.exports = { buildState, cmpVersion };
