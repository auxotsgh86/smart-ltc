-- smart-ltc 002：語音健康日誌、緊急聯絡人、居家安全欄位（對應 docs/architecture.md v0.4）

-- 語音健康日誌（病人主觀陳述，供醫師看診時作為 SOAP 的 S）
CREATE TABLE health_journal (
  id                INTEGER PRIMARY KEY,
  member_id         INTEGER NOT NULL REFERENCES members(id),
  recorded_at       TEXT NOT NULL,                 -- 錄音時間（LINE 訊息時間戳）
  received_at       TEXT NOT NULL DEFAULT (datetime('now')),
  source            TEXT NOT NULL CHECK (source IN ('line_voice','liff_voice','pharmacist')),
  entered_by        TEXT NOT NULL DEFAULT 'self' CHECK (entered_by IN ('self','family','staff')),
  family_link_id    INTEGER REFERENCES family_links(id),
  audio_key         TEXT,                          -- 原始錄音（Cloud Storage 私有），永久保留
  audio_seconds     INTEGER,
  stt_status        TEXT NOT NULL DEFAULT 'pending' CHECK (stt_status IN ('pending','done','failed')),
  stt_vendor        TEXT,                          -- 使用的語音轉文字服務與模型
  transcript        TEXT,                          -- 機器轉寫原文（不覆寫）
  transcript_lang   TEXT,                          -- zh-TW / nan-TW / mixed
  transcript_edited TEXT,                          -- 藥師修正後版本
  edited_by         INTEGER REFERENCES staff(id),
  summary_s         TEXT,                          -- AI 整理的 S：JSON {symptoms, onset, duration, associated, patient_words}；不含診斷
  red_flags         TEXT,                          -- 命中的危險字眼 JSON
  alert_sent_at     TEXT,                          -- 已通知家屬／藥師時間
  reviewed_by       INTEGER REFERENCES staff(id),  -- 藥師已讀
  reviewed_at       TEXT,
  voided_at         TEXT,
  void_reason       TEXT
);
CREATE INDEX idx_journal_member ON health_journal(member_id, recorded_at);
CREATE INDEX idx_journal_pending ON health_journal(stt_status) WHERE stt_status = 'pending';

-- 緊急聯絡人
CREATE TABLE emergency_contacts (
  id         INTEGER PRIMARY KEY,
  member_id  INTEGER NOT NULL REFERENCES members(id),
  name_enc   BLOB NOT NULL,
  phone_enc  BLOB NOT NULL,
  relation   TEXT NOT NULL,
  priority   INTEGER NOT NULL DEFAULT 1,       -- 1 = 第一聯絡人
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  removed_at TEXT
);
CREATE INDEX idx_emerg_member ON emergency_contacts(member_id, priority);

-- 居家安全
ALTER TABLE members ADD COLUMN lives_alone INTEGER;                        -- 1 = 獨居
ALTER TABLE members ADD COLUMN ers_status TEXT
  CHECK (ers_status IN ('none','referred','installed'));                   -- 政府緊急救援裝置：無／已轉介／已安裝
ALTER TABLE members ADD COLUMN phone_sos_setup_at TEXT;                    -- 藥師協助設定手機內建緊急求救的時間

-- 危險字眼（需藥師與醫師審閱後定版；命中時語音回覆「請馬上打 119」並通知家屬、藥師）
INSERT INTO settings (key, value) VALUES
 ('journal_red_flags', '{"reviewed":false,"zh":["胸痛","胸口悶","喘不過氣","呼吸困難","講話不清楚","嘴歪","半邊沒力","手腳無力","昏倒","暈倒","吐血","解黑便","跌倒爬不起來"],"nan":[]}'),
 ('journal_policy',    '{"keep_audio":"forever","summary_no_diagnosis":true,"not_emergency_notice":true}');
