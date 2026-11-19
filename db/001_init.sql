-- smart-ltc 初始資料表（對應 docs/architecture.md v0.3）
-- 個資原則：不存身分證字號；姓名、電話、生日以 AES-256-GCM 加密後存入 *_enc 欄位。

PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;

-- 系統設定（門檻、提醒條件、預設頻率、店名等）
CREATE TABLE settings (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL            -- JSON
);

-- 藥師／員工（PIN 登入，閒置自動上鎖）
CREATE TABLE staff (
  id         INTEGER PRIMARY KEY,
  name       TEXT NOT NULL,
  pin_hash   TEXT NOT NULL,      -- argon2/bcrypt
  role       TEXT NOT NULL CHECK (role IN ('pharmacist','assistant','admin')),
  active     INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- 會員（不存身分證字號）
CREATE TABLE members (
  id              INTEGER PRIMARY KEY,
  member_no       TEXT NOT NULL UNIQUE,     -- 例 000101，對外唯一識別
  nhi_hmac        TEXT UNIQUE,              -- HMAC-SHA256(身分證號, 秘鑰)，只用於刷卡比對，不可逆
  name_enc        BLOB NOT NULL,
  phone_enc       BLOB,
  phone_last3     TEXT,                     -- 搜尋用
  birth_enc       BLOB,
  birth_year      INTEGER,                  -- 算年齡、統計用
  sex             TEXT CHECK (sex IN ('F','M')),
  focus           TEXT,                     -- 最想追蹤：bp/glu/body/bmd
  literacy        TEXT DEFAULT 'numbers' CHECK (literacy IN ('full','numbers','none')),
  consent_version TEXT NOT NULL,
  consent_at      TEXT NOT NULL,
  consent_method  TEXT NOT NULL DEFAULT 'signature'
                  CHECK (consent_method IN ('signature','thumbprint_witnessed','seal_witnessed')),
  line_user_id    TEXT UNIQUE,              -- 本人 LINE 綁定後才有
  member_qr_token TEXT NOT NULL UNIQUE,     -- 會員 QR Code 內容（隨機，可重發）
  status          TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','withdrawn')),
  created_at      TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_members_phone3 ON members(phone_last3);

-- 家屬綁定：一個 LINE 可照顧多位會員，一位會員可有多位家屬
CREATE TABLE family_links (
  id            INTEGER PRIMARY KEY,
  member_id     INTEGER NOT NULL REFERENCES members(id),
  line_user_id  TEXT NOT NULL,
  relation      TEXT NOT NULL,              -- 子女／配偶／其他
  can_entry     INTEGER NOT NULL DEFAULT 1,
  can_view      INTEGER NOT NULL DEFAULT 1,
  notify_alert  INTEGER NOT NULL DEFAULT 1,
  consent_at    TEXT NOT NULL,              -- 會員本人同意綁定的時間
  created_by    INTEGER REFERENCES staff(id),
  revoked_at    TEXT,
  UNIQUE (member_id, line_user_id)
);
CREATE INDEX idx_family_line ON family_links(line_user_id);

-- 每位會員的量測頻率（沒有設定就用 settings 的預設值）
CREATE TABLE member_plans (
  id          INTEGER PRIMARY KEY,
  member_id   INTEGER NOT NULL REFERENCES members(id),
  type        TEXT NOT NULL CHECK (type IN ('bp','glu','body','bmd')),
  schedule    TEXT NOT NULL,                -- JSON，例 {"mode":"722"}、{"every_days":3}
  basis       TEXT NOT NULL DEFAULT 'default' CHECK (basis IN ('default','doctor_order','pharmacist')),
  note        TEXT,
  set_by      INTEGER REFERENCES staff(id),
  active_from TEXT NOT NULL DEFAULT (date('now')),
  active_to   TEXT,                         -- NULL = 目前有效
  UNIQUE (member_id, type, active_from)
);

-- 到店紀錄（一次接待 = 一筆）
CREATE TABLE visits (
  id         INTEGER PRIMARY KEY,
  member_id  INTEGER NOT NULL REFERENCES members(id),
  staff_id   INTEGER REFERENCES staff(id),
  checkin_by TEXT NOT NULL CHECK (checkin_by IN ('nhi_card','qr','search')),
  visit_at   TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_visits_member ON visits(member_id, visit_at);

-- 量測設備（店內與客人自有）
CREATE TABLE devices (
  id        INTEGER PRIMARY KEY,
  type      TEXT NOT NULL CHECK (type IN ('bp','glu','body','bmd','card','scanner')),
  name      TEXT NOT NULL,
  model     TEXT,
  ble_id    TEXT,
  owner     TEXT NOT NULL DEFAULT 'store' CHECK (owner IN ('store','member')),
  member_id INTEGER REFERENCES members(id),
  active    INTEGER NOT NULL DEFAULT 1
);

-- 量測值（一列一次讀數；店內與居家共用）
CREATE TABLE measurements (
  id             INTEGER PRIMARY KEY,
  member_id      INTEGER NOT NULL REFERENCES members(id),
  type           TEXT NOT NULL CHECK (type IN ('bp','glu','body','bmd')),
  place          TEXT NOT NULL CHECK (place IN ('store','home')),   -- 集點只算 store
  method         TEXT NOT NULL CHECK (method IN ('device','manual','photo_ai','paper')),
  entered_by     TEXT NOT NULL DEFAULT 'self' CHECK (entered_by IN ('self','family','staff')),
  family_link_id INTEGER REFERENCES family_links(id),
  visit_id       INTEGER REFERENCES visits(id),                     -- 店內必填
  device_id      INTEGER REFERENCES devices(id),
  measured_at    TEXT NOT NULL,
  received_at    TEXT NOT NULL DEFAULT (datetime('now')),
  slot           TEXT CHECK (slot IN ('morning','evening','fasting','post2h','bedtime','random')),
  reading_no     INTEGER,                                           -- 同一回第幾遍（722 的 1、2）
  sys INTEGER, dia INTEGER, pulse INTEGER,
  glucose INTEGER,
  weight REAL, body_fat REAL,
  bmd_t REAL,
  photo_key      TEXT,
  ai_raw         TEXT,                                              -- AI 原始辨識結果 JSON
  verified_by    INTEGER REFERENCES staff(id),
  light          TEXT CHECK (light IN ('g','y','r','n')),
  voided_at      TEXT,
  void_reason    TEXT,
  CHECK (place = 'home' OR visit_id IS NOT NULL)
);
CREATE INDEX idx_meas_member ON measurements(member_id, type, measured_at);
CREATE INDEX idx_meas_place  ON measurements(member_id, place, measured_at);

-- 量測代碼對照（FHIR 輸出與跨系統統一用）
CREATE TABLE obs_codes (
  key      TEXT PRIMARY KEY,
  loinc    TEXT NOT NULL,
  display  TEXT NOT NULL,
  ucum     TEXT NOT NULL,
  verified INTEGER NOT NULL DEFAULT 0     -- 已對照 TW Core IG 與 LOINC 官方確認
);

-- 禮品
CREATE TABLE reward_items (
  id              INTEGER PRIMARY KEY,
  name            TEXT NOT NULL,
  picture         TEXT,
  required_streak INTEGER NOT NULL DEFAULT 1,
  stock           INTEGER,
  active          INTEGER NOT NULL DEFAULT 1
);

-- 兌換紀錄（每人每月一次）
CREATE TABLE redemptions (
  id             INTEGER PRIMARY KEY,
  member_id      INTEGER NOT NULL REFERENCES members(id),
  month          TEXT NOT NULL,                 -- 'YYYY-MM'
  reward_item_id INTEGER NOT NULL REFERENCES reward_items(id),
  staff_id       INTEGER REFERENCES staff(id),
  redeemed_at    TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE (member_id, month)
);

-- 關懷聯絡紀錄
CREATE TABLE care_contacts (
  id           INTEGER PRIMARY KEY,
  member_id    INTEGER NOT NULL REFERENCES members(id),
  staff_id     INTEGER REFERENCES staff(id),
  reason       TEXT NOT NULL,   -- store_red/home_bp_avg_high/glu_high/no_visit/no_home_report
  result       TEXT CHECK (result IN ('reached','no_answer','declined')),
  note         TEXT,
  contacted_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- 報表／回報表單／綁定用的短期連結
CREATE TABLE report_tokens (
  token      TEXT PRIMARY KEY,
  member_id  INTEGER NOT NULL REFERENCES members(id),
  purpose    TEXT NOT NULL DEFAULT 'report'
             CHECK (purpose IN ('report','home_entry','bind_self','bind_family')),
  expires_at TEXT NOT NULL
);

-- 對外輸出紀錄（FHIR 等）
CREATE TABLE exports (
  id          INTEGER PRIMARY KEY,
  kind        TEXT NOT NULL CHECK (kind IN ('fhir_identified','fhir_deidentified','csv')),
  member_id   INTEGER REFERENCES members(id),
  recipient   TEXT NOT NULL,
  consent_at  TEXT,
  period_from TEXT,
  period_to   TEXT,
  staff_id    INTEGER REFERENCES staff(id),
  created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

-- 稽核紀錄（只新增不修改）
CREATE TABLE audit_log (
  id        INTEGER PRIMARY KEY,
  at        TEXT NOT NULL DEFAULT (datetime('now')),
  staff_id  INTEGER,
  actor     TEXT NOT NULL,      -- staff/line/family/system
  action    TEXT NOT NULL,
  member_id INTEGER,
  detail    TEXT
);
CREATE TRIGGER audit_log_no_update BEFORE UPDATE ON audit_log
BEGIN SELECT RAISE(ABORT, 'audit_log is append-only'); END;
CREATE TRIGGER audit_log_no_delete BEFORE DELETE ON audit_log
BEGIN SELECT RAISE(ABORT, 'audit_log is append-only'); END;

-- ---------- 預設資料 ----------

INSERT INTO settings (key, value) VALUES
 ('monthly_goals',  '{"bp":8,"glu":4,"body":4}'),
 ('default_plans',  '{"bp":{"mode":"722","then":{"days_per_week":3}},"glu":{"per_week":3,"slots":["fasting"]},"body":{"every_days":3},"bmd":{"every_months":6}}'),
 ('lights',         '{"bp":{"y":[130,80],"r":[140,90]},"glu_fasting":{"y":100,"r":126},"glu_post2h":{"y":140,"r":200},"bmd_t":{"y":-1,"r":-2.5}}'),
 ('care_rules',     '{"no_visit_days":21,"no_home_report_days":7,"home_bp_avg_high":[140,90],"home_bp_avg_high_risk":[130,80]}');

INSERT INTO reward_items (name, required_streak) VALUES
 ('抽取式面紙一串', 1),
 ('益生菌體驗包',   1),
 ('保養品試用組',   3);

-- LOINC／UCUM 初稿；verified=0 表示實作 FHIR 前須再確認
INSERT INTO obs_codes (key, loinc, display, ucum, verified) VALUES
 ('bp_panel',      '85354-9', 'Blood pressure panel',                    '',       0),
 ('bp_sys',        '8480-6',  'Systolic blood pressure',                 'mm[Hg]', 0),
 ('bp_dia',        '8462-4',  'Diastolic blood pressure',                'mm[Hg]', 0),
 ('bp_avg_panel',  '96607-7', 'Blood pressure panel mean (待確認)',       '',       0),
 ('bp_avg_sys',    '96608-5', 'Mean systolic blood pressure (待確認)',    'mm[Hg]', 0),
 ('bp_avg_dia',    '96609-3', 'Mean diastolic blood pressure (待確認)',   'mm[Hg]', 0),
 ('pulse',         '8867-4',  'Heart rate',                              '/min',   0),
 ('weight',        '29463-7', 'Body weight',                             'kg',     0),
 ('body_fat',      '41982-0', 'Percentage of body fat (待確認)',          '%',      0),
 ('glu_capillary', '41653-7', 'Glucose capillary by glucometer (待確認)', 'mg/dL',  0);
