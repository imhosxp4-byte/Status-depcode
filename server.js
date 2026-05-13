const express = require('express');
const path = require('path');
const fs = require('fs');
const crypto = require('crypto');

const app = express();
app.use(express.json());

const CONFIG_FILE = path.join(__dirname, 'config.json');

// ป้องกันไม่ให้ดาวน์โหลด config.json ผ่าน HTTP
app.get('/config.json', (_req, res) => res.status(403).end());

// Serve static files
app.use(express.static(__dirname));

// ─── Helpers ───────────────────────────────────────────────────────────────

function loadConfig() {
  try { return JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8')); }
  catch { return null; }
}

function saveConfig(cfg) {
  fs.writeFileSync(CONFIG_FILE, JSON.stringify(cfg, null, 2), 'utf8');
}

function md5hex(str) {
  return crypto.createHash('md5').update(str, 'utf8').digest('hex');
}

async function openDb(cfg) {
  if (cfg.dbType === 'mysql') {
    const mysql = require('mysql2/promise');
    const conn = await mysql.createConnection({
      host: cfg.host,
      port: parseInt(cfg.port, 10) || 3306,
      database: cfg.database,
      user: cfg.dbUser,
      password: cfg.dbPassword,
      connectTimeout: 8000,
    });
    return { type: 'mysql', conn };
  }
  const { Client } = require('pg');
  const client = new Client({
    host: cfg.host,
    port: parseInt(cfg.port, 10) || 5432,
    database: cfg.database,
    user: cfg.dbUser,
    password: cfg.dbPassword,
    connectionTimeoutMillis: 8000,
  });
  await client.connect();
  return { type: 'pg', conn: client };
}

async function runQuery(db, sql, params = []) {
  if (db.type === 'mysql') {
    const [rows] = await db.conn.execute(sql, params);
    return rows;
  }
  // แปลง ? → $1, $2, ... สำหรับ PostgreSQL
  let i = 0;
  const pgSql = sql.replace(/\?/g, () => `$${++i}`);
  return (await db.conn.query(pgSql, params)).rows;
}

async function closeDb(db) { try { await db.conn.end(); } catch {} }

// ─── API Routes ─────────────────────────────────────────────────────────────

// GET /api/settings — โหลดค่าตั้ง (ไม่ส่ง password กลับ)
app.get('/api/settings', (_req, res) => {
  const cfg = loadConfig();
  if (!cfg) return res.json({});
  const { dbPassword, ...safe } = cfg;
  res.json({ ...safe, hasDbPassword: !!dbPassword });
});

// POST /api/settings — บันทึกค่าตั้ง
app.post('/api/settings', (req, res) => {
  try {
    saveConfig(req.body);
    res.json({ ok: true });
  } catch (e) {
    res.json({ ok: false, message: e.message });
  }
});

// POST /api/test-connection — ทดสอบการเชื่อมต่อ
app.post('/api/test-connection', async (req, res) => {
  let db;
  try {
    db = await openDb(req.body);
    await runQuery(db, 'SELECT 1');
    res.json({ ok: true, message: 'เชื่อมต่อฐานข้อมูลสำเร็จ' });
  } catch (e) {
    res.json({ ok: false, message: e.message });
  } finally {
    if (db) await closeDb(db);
  }
});

// POST /api/login — ตรวจสอบผู้ใช้จากตาราง officer
app.post('/api/login', async (req, res) => {
  const { username, password } = req.body || {};

  if (!username || !password)
    return res.json({ ok: false, message: 'กรุณากรอกชื่อผู้ใช้และรหัสผ่าน' });

  const cfg = loadConfig();
  if (!cfg?.host)
    return res.json({
      ok: false,
      message: 'ยังไม่ได้ตั้งค่าการเชื่อมต่อฐานข้อมูล กรุณากดปุ่ม "ตั้งค่าการเชื่อมต่อ" ก่อน',
    });

  let db;
  try {
    db = await openDb(cfg);
    const rows = await runQuery(
      db,
      `SELECT officer_login_name
       FROM officer
       WHERE officer_login_name = ?
         AND LOWER(officer_login_password_md5) = LOWER(?)
       LIMIT 1`,
      [username, md5hex(password)]
    );

    if (rows.length > 0) {
      res.json({ ok: true });
    } else {
      res.json({ ok: false, message: 'ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง' });
    }
  } catch (e) {
    res.json({ ok: false, message: 'เกิดข้อผิดพลาดในการเชื่อมต่อ: ' + e.message });
  } finally {
    if (db) await closeDb(db);
  }
});

// GET /api/departments — ดึงรายชื่อห้องตรวจที่เปิดใช้งาน (depcode_active = 'Y')
app.get('/api/departments', async (req, res) => {
  const cfg = loadConfig();
  if (!cfg?.host)
    return res.json({ ok: false, message: 'ยังไม่ได้ตั้งค่าการเชื่อมต่อฐานข้อมูล' });

  let db;
  try {
    db = await openDb(cfg);
    const rows = await runQuery(db, `
      SELECT depcode, department
      FROM kskdepartment
      WHERE depcode_active = 'Y'
      ORDER BY department
    `, []);
    res.json({ ok: true, rows });
  } catch (e) {
    res.json({ ok: false, message: e.message });
  } finally {
    if (db) await closeDb(db);
  }
});

// GET /api/status — ดึงรายชื่อผู้ป่วยรอรับบริการวันนี้ (กรองห้องได้ด้วย ?dep=DEPCODE)
app.get('/api/status', async (req, res) => {
  const cfg = loadConfig();
  if (!cfg?.host)
    return res.json({ ok: false, message: 'ยังไม่ได้ตั้งค่าการเชื่อมต่อฐานข้อมูล' });

  const dep = req.query.dep; // ถ้าไม่ส่งมา = แสดงทุกห้อง

  let db;
  try {
    db = await openDb(cfg);

    let sql = `
      SELECT
        v.vn,
        v.oqueue                                AS qn,
        v.hn,
        CONCAT(p.pname, p.fname, ' ', p.lname) AS ptname,
        k.department,
        ot.name                                 AS status_name,
        CASE WHEN COUNT(l.vn) > 0 THEN 1 ELSE 0 END AS has_lab,
        MAX(l.lab_receive)                      AS lab_receive,
        MAX(l.confirm_report)                   AS confirm_report
      FROM ovst v
        LEFT OUTER JOIN patient       p  ON p.hn      = v.hn
        LEFT OUTER JOIN kskdepartment k  ON k.depcode  = v.cur_dep
        LEFT OUTER JOIN ovstost       ot ON ot.ovstost = v.ovstost
        LEFT OUTER JOIN lab_head      l  ON l.vn = v.vn
      WHERE v.vstdate = CURRENT_DATE`;

    const params = [];
    if (dep) {
      sql += `\n        AND v.cur_dep = ?`;
      params.push(dep);
    }
    sql += `
      GROUP BY v.vn, v.hn, p.pname, p.fname, p.lname, k.department, ot.name, v.oqueue
      ORDER BY v.oqueue`;

    const rows = await runQuery(db, sql, params);
    res.json({ ok: true, rows });
  } catch (e) {
    res.json({ ok: false, message: e.message });
  } finally {
    if (db) await closeDb(db);
  }
});

// ─── Shared Display Settings (sync across all clients) ──────────────────────

const DISPLAY_SETTINGS_FILE = path.join(__dirname, 'display-settings.json');
let sseClients = [];

function loadDisplaySettings() {
  try { return JSON.parse(fs.readFileSync(DISPLAY_SETTINGS_FILE, 'utf8')); }
  catch { return {}; }
}

function saveDisplaySettings(data) {
  fs.writeFileSync(DISPLAY_SETTINGS_FILE, JSON.stringify(data, null, 2), 'utf8');
}

// GET /api/display-settings
app.get('/api/display-settings', (req, res) => {
  res.json({ ok: true, settings: loadDisplaySettings() });
});

// POST /api/display-settings — บันทึกและ broadcast ไปทุก client
app.post('/api/display-settings', (req, res) => {
  try {
    const settings = req.body || {};
    saveDisplaySettings(settings);
    const payload = `data: ${JSON.stringify(settings)}\n\n`;
    sseClients.forEach(c => { try { c.write(payload); } catch {} });
    res.json({ ok: true });
  } catch (e) {
    res.json({ ok: false, message: e.message });
  }
});

// GET /api/display-settings/stream — SSE realtime sync
app.get('/api/display-settings/stream', (req, res) => {
  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');
  res.flushHeaders();
  res.write(': connected\n\n');
  sseClients.push(res);
  req.on('close', () => { sseClients = sseClients.filter(c => c !== res); });
});

// ─── Start ──────────────────────────────────────────────────────────────────

const PORT = process.env.PORT || 5000;
app.listen(PORT, () => {
  console.log(`ระบบแสดงสถานะผู้ป่วย - เซิร์ฟเวอร์ทำงานที่ http://localhost:${PORT}`);
});
