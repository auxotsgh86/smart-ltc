# smart-ltc 系統架構與資料表設計 v0.3（2026-11-19）

> 開發藍圖。開發時以本文件為準；改設計就回來更新這份。
> 相關文件：[`decisions.md`](decisions.md)（業務決定）・資料表 SQL：[`../db/001_init.sql`](../db/001_init.sql)
> 原型：[`../prototypes/`](../prototypes/)
>
> **v0.2 變更**：新增居家量測（LINE 回報）、每位會員的量測頻率設定、血壓早晚時段與 722 平均、居家血壓關懷條件。
> **v0.3 變更**：新增家屬綁定 `family_links`、量測代碼對照 `obs_codes`（LOINC／UCUM）、FHIR（TW Core IG）輸出設計與第四階段；客人端改為「不用識字」設計（拍照 AI 讀數字、語音）。

---

## 1. 範圍與原則

- 單一社區藥局使用（先不做多店），但**資料格式預留對外交換**（FHIR）。
- 使用者是**電腦小白藥師**：不碰安裝、更新、備份；一條引導式流程；大按鈕、少打字。
- 客人多為**不識字但看得懂數字**的長輩：客人端只用圖片、顏色、表情、大數字、語音。
- **店內量測拿來集點，居家量測拿來追蹤**。兩者都存、都畫圖，但分開標示。
- 個資：**不儲存身分證字號**；姓名、電話、生日加密存放；所有查詢與修改留紀錄。
- 身分辨識靠 **LINE 綁定**（藥師在店內協助掃碼），不靠手機門號（LINE 與網頁都讀不到）。
- **內部用 SQLite 自訂資料表，對外交換才輸出 FHIR**；FHIR 不當作日常資料庫。

## 2. 架構總覽

```
[櫃檯 Windows 電腦]
  Chrome（PWA 捷徑）── 櫃檯網頁 ──HTTPS──┐
    ├─ Web Bluetooth → 藍牙血壓計／體脂計／血糖機
    └─ http://127.0.0.1:7788 → 讀卡小幫手（本機，只讀不存）
                                  └─ 健保署讀卡機控制軟體 → 一般讀卡機

[雲端主機 GCE e2-small，asia-east1 台灣]
  Caddy（自動 HTTPS）
   └─ Node.js 後端（Hono + better-sqlite3）
        ├─ SQLite 檔案 ──Litestream──> Cloud Storage（即時備份）
        ├─ 量測照片（Cloud Storage，私有）
        ├─ AI 影像辨識（讀血壓計／血糖機螢幕數字）
        ├─ FHIR 輸出模組（第四階段）
        └─ LINE Messaging API webhook

[客人／家屬手機]
  LINE 官方帳號 → LIFF 網頁（不用識字設計）
    ├─ 記錄：拍照（AI 讀數字）或大鍵盤按數字 → 綠勾確認 → 表情＋語音
    ├─ 變化、禮物、會員碼
    └─ 家屬帳號可切換「幫誰記錄」
```

## 3. 技術選型

| 層 | 選擇 | 備註 |
|---|---|---|
| 語言 | TypeScript（前後端共用型別） | |
| 後端 | Node.js 22 + Hono | 輕量、好維護 |
| 資料庫 | SQLite（WAL 模式）+ better-sqlite3 | 純 SQL migration 檔，不用 ORM |
| 備份 | Litestream → Google Cloud Storage | 可還原到數秒前；每日另存快照保留 90 天 |
| 前端 | React + Vite，PWA | 櫃檯與 LIFF 共用元件 |
| 圖表 | 自繪 SVG（沿用原型） | 不依賴圖表套件 |
| 加密 | Node crypto AES-256-GCM（欄位層） | 金鑰放 Secret Manager／環境變數，不進版控 |
| 主機 | GCE e2-small + Caddy | 約 NT$500／月 |
| LINE | 官方帳號 + Messaging API + LIFF | 報表以「回覆訊息」傳送；居家回報走 LIFF，不消耗推播則數 |
| 讀卡 | 本機小幫手（Windows 常駐） | 呼叫健保署元件，只把卡上基本資料回傳給瀏覽器，不落地 |
| 影像辨識 | 多模態 AI API | 只讀數字；結果一律由客人或藥師確認後才寫入 |
| 語音 | 藥師錄製的台語音檔（固定句型）＋數字念法 | 備案：語音合成 |
| 交換格式 | HL7 FHIR R4，依衛福部 TW Core IG | 第四階段實作 |

## 4. 資料表設計（SQLite）

完整 SQL 見 [`db/001_init.sql`](../db/001_init.sql)。表格一覽：

| 表 | 用途 |
|---|---|
| `settings` | 門檻、提醒條件、預設頻率、店名（JSON） |
| `staff` | 藥師／員工，PIN 登入 |
| `members` | 會員；不存身分證號，只存 `nhi_hmac`；姓名、電話、生日加密；識字程度、同意方式 |
| `family_links` | 家屬 LINE 綁定與權限（代填、看報表、偏高通知） |
| `member_plans` | 每位會員每一項的量測頻率（依醫囑或藥師） |
| `visits` | 到店紀錄 |
| `measurements` | 所有讀數；`place`（store/home）、`method`（device/manual/photo_ai/paper）、`entered_by`、`slot`、`reading_no`、作廢欄位 |
| `devices` | 店內與客人自有的儀器 |
| `obs_codes` | LOINC／UCUM 代碼對照 |
| `reward_items`、`redemptions` | 禮品與每月兌換 |
| `care_contacts` | 關懷電話紀錄 |
| `report_tokens` | 報表、回報、綁定用短期連結 |
| `exports` | 對外輸出紀錄（FHIR 等） |
| `audit_log` | 稽核紀錄，只新增不修改 |

**設計說明**
- 集點、達標、連續月數**不另外存**，一律從 `measurements`（`place='store'`、排除作廢）即時計算；同一天同一項只計 1 次。
- 系統**不限制**每天可存幾筆；頻率設定只用來產生提醒、顯示「本週完成度」，不擋輸入。
- 血壓 722 平均：以 `measured_at` 的日期 + `slot`（morning/evening）分組，每組取平均，再算 7 天平均。
- 居家數值可信度較低 → 圖上用空心點標示；`photo_ai` 一律經客人按綠勾確認，`ai_raw` 保留原始辨識結果；藥師核對過（`verified_by`）標示為已核對。
- LINE 開啟 LIFF 時：先查 `members.line_user_id`（本人），再查 `family_links`（家屬）；只對應 1 人就直接顯示，沒有切換鈕。
- 姓名加密後無法用 SQL 模糊搜尋；單店會員數少（數千內），搜尋時以電話末三碼縮小範圍，再在記憶體解密比對。
- `nhi_hmac` 仍屬個資（可用於比對），秘鑰與資料庫分開保存；同意書需載明此用途。
- 會員退出（`withdrawn`）時：清除加密欄位、`nhi_hmac`、照片、解除所有家屬綁定；量測值保留匿名統計或依同意書刪除——**待同意書確定後決定**。

## 5. 業務規則（預設值，存在 settings 可調）

**量測頻率預設**（`member_plans` 可依醫囑覆寫）

| 項目 | 預設頻率 | 地點 |
|---|---|---|
| 血壓 | 722 原則：連續 7 天、早晚各一回、每回 2 次取平均；穩定後每週 3 天 | 主要在家 |
| 血糖 | 依醫囑個別設定；未設定時預設每週 3 次空腹 | 主要在家 |
| 體重體脂 | 每 2–3 天一次（固定時段，如早上如廁後） | 在家或店內 |
| 骨密度 | 每 3–6 個月一次 | 店內 |

**集點（只算店內）**

| 項目 | 預設 |
|---|---|
| 每月門檻 | 血壓 8 次、血糖 4 次、體重體脂 4 次（同一天同一項只算 1 次） |
| 骨密度 | 不列入門檻 |
| 禮品 | 面紙、益生菌：當月達標可選 1；保養品試用組：連續 3 個月達標 |

**燈號（客人端以笑臉／平臉／哭臉呈現）**

| 項目 | 綠 | 黃 | 紅 |
|---|---|---|---|
| 血壓（單次或居家平均） | <130/80 | 130–139 或 80–89 | ≥140/90 |
| 空腹血糖 | <100 | 100–125 | ≥126 |
| 飯後 2 小時血糖 | <140 | 140–199 | ≥200 |
| 骨密度 T 值 | ≥ -1 | -1 ~ -2.5 | ≤ -2.5 |

**關懷名單**

| 條件 | 預設 |
|---|---|
| 店內最近一次紅燈 | 是 |
| 居家血壓 7 天平均 | ≥130/80（有糖尿病、心血管病史者）或 ≥140/90 |
| 未到店 | 超過 21 天 |
| 居家沒回報 | 有設定居家計畫，但超過 7 天沒回報 |

## 6. API 草案

櫃檯（需員工 PIN 登入）
- `POST /api/checkin` — body：`{by:'nhi_card', nhi:{...}}` / `{by:'qr', token}` / `{by:'search', memberId}` → 回會員摘要 + 建立 visit
- `GET  /api/members/search?q=` — 電話末三碼或姓名
- `POST /api/members` — 建檔（必須帶同意書版本與同意方式）
- `POST /api/members/:id/bind-link?who=self|family` — 產生 LINE 綁定 QR Code
- `GET/DELETE /api/members/:id/family` — 查看／解除家屬綁定
- `GET/PUT /api/members/:id/plans` — 查看／設定量測頻率
- `POST /api/visits/:id/measurements` — 新增店內量測
- `POST /api/measurements/:id/void` — 作廢
- `POST /api/measurements/:id/verify` — 藥師核對居家照片
- `POST /api/paper-cards` — 紙本記錄卡拍照匯入（AI 讀表格 → 藥師逐筆確認）
- `GET  /api/members/:id/summary` — 今日結果、居家 7 天平均、本月集點、可兌換禮品
- `GET  /api/members/:id/trend?days=90` — 店內與居家分開回傳
- `POST /api/members/:id/redeem` — 兌換
- `GET  /api/care-list` / `POST /api/care-contacts`
- `POST /api/members/:id/report-link` — 產生報表 QR Code
- `POST /api/exports/fhir` — 輸出 FHIR Bundle（第四階段）

LINE／客人端
- `POST /line/webhook` — 加好友、綁定（本人／家屬）、傳「我的報表」→ 回覆報表連結
- `GET  /liff/me` — 依 LINE 帳號回傳可看的會員清單（1 人就不顯示切換）
- `POST /liff/photo-read` — 上傳照片 → AI 回傳讀到的數字（尚未寫入）
- `POST /liff/measurements` — 確認後寫入居家量測
- `GET  /liff/report?member=` — 報表（含居家與店內）
- `GET  /liff/voice/:key` — 語音檔
- 提醒：依 `member_plans` 早晚提醒（推播會消耗則數，預設關閉，由客人或家屬自選開啟）

本機讀卡小幫手
- `GET http://127.0.0.1:7788/read` → `{name, birth, sex, id}`（身分證號只在記憶體中轉成 HMAC 比對，不寫入任何檔案）

## 7. FHIR 輸出設計

**標準**：HL7 FHIR R4，依衛福部「臺灣核心實作指引（TW Core IG）」1.0.0（STU）。實作時以當時最新版 IG 的 profile 為準。

**資源對應**

| 內部 | FHIR Resource | TW Core Profile（實作時核對名稱） |
|---|---|---|
| 藥局 | Organization | TWCoreOrganization |
| 藥師 | Practitioner | TWCorePractitioner |
| 會員 | Patient | TWCorePatient |
| 單次血壓 | Observation（含 component 收縮壓／舒張壓） | TWCoreObservationBloodPressure |
| 722 平均血壓 | Observation | TWCoreObservationAverageBloodPressure |
| 體重 | Observation | TWCoreObservationBodyWeight |
| 心率（脈搏） | Observation | TWCoreObservationHeartRate |
| 血糖、體脂率、骨密度 | Observation（一般） | 依 IG 選擇對應 profile 或一般 Observation |
| 儀器 | Device | — |
| 輸出包 | Bundle（collection） | — |

**欄位對應重點**
- `Observation.effectiveDateTime` ← `measured_at`（含 +08:00 時區）
- `Observation.performer` ← 店內：Organization／Practitioner；居家：Patient（本人）或 RelatedPerson（家屬代填）
- `Observation.method` ／ extension ← `method`（儀器、手動、AI 讀照片、紙本）
- `Observation.device` ← `device_id`
- `Observation.status` ← 一般為 `final`；作廢的資料輸出 `entered-in-error`（或不輸出，依交換對象要求）
- `Observation.category` ← `vital-signs`（血壓、體重、心率）

**LOINC／UCUM 對照（初稿，`obs_codes.verified=0`，實作時逐一對照 IG 與 LOINC 官方確認）**

| key | LOINC | 說明 | UCUM |
|---|---|---|---|
| bp_panel | 85354-9 | 血壓組合 | — |
| bp_sys | 8480-6 | 收縮壓 | mm[Hg] |
| bp_dia | 8462-4 | 舒張壓 | mm[Hg] |
| bp_avg_panel | 96607-7 | 平均血壓組合（待確認） | — |
| bp_avg_sys | 96608-5 | 平均收縮壓（待確認） | mm[Hg] |
| bp_avg_dia | 96609-3 | 平均舒張壓（待確認） | mm[Hg] |
| pulse | 8867-4 | 心率 | /min |
| weight | 29463-7 | 體重 | kg |
| body_fat | 41982-0 | 體脂率（待確認） | % |
| glu_capillary | 41653-7 | 微血管血糖（血糖機）（待確認） | mg/dL |
| glu_fasting / glu_post2h | 待確認 | 依時機選代碼，或以 41653-7 加註時機 | mg/dL |
| bmd_t | 待確認 | 依量測部位與方式（DXA／超音波）選代碼 | {T-score} |

**兩種輸出**
1. **個人輸出（給醫院、醫師）**：本人在場刷健保卡，當下才把身分證號放進 `Patient.identifier`；輸出完不留存。每次需本人同意，記在 `exports`。
2. **去識別化輸出（多家藥局統一收集、統計研究）**：`Patient` 只放隨機代碼，出生只到年，不帶姓名、電話、身分證號；記在 `exports`。

## 8. 開發階段

**第一階段：基本版（不需硬體）**
- 員工 PIN 登入、會員建檔、電話搜尋報到
- 店內手動輸入量測、燈號、今日結果、本月集點、兌換
- 會員量測頻率設定（含預設值）
- 趨勢圖、關懷名單、設定頁
- `obs_codes` 先建好（代碼對照表，未實作輸出也先存）
- 部署到雲端主機 + Litestream 備份 + 還原演練
- 驗收：藥師不看說明書，3 分鐘內完成一位客人的報到→量測→結果→下一位

**第二階段：LINE 與居家回報**
- 官方帳號、本人與家屬綁定、會員 QR Code、報表回覆
- 客人端 LIFF（不用識字）：拍照 AI 讀數字、大鍵盤、綠勾確認、表情＋語音、一週早晚格
- 藥師錄製台語語音、紙本記錄卡匯入
- 居家 722 平均、居家／店內對照圖、居家相關關懷條件、家屬通知
- 驗收：不識字長輩不用教學能完成一次居家血壓回報；客人掃碼後 10 秒內在 LINE 看到當天報表

**第三階段：硬體**
- 讀卡小幫手（Windows 安裝檔，開機自動啟動）
- Web Bluetooth 串接店內藍牙血壓計、體脂計、血糖機
- （選配）客人自己的藍牙血壓計上傳
- 驗收：插卡 3 秒內帶出會員；量完血壓數值自動出現在畫面上

**第四階段：FHIR 輸出（有交換對象時再做）**
- 依交換對象要求的 TW Core IG 版本實作 Bundle 輸出
- 個人輸出（刷卡帶入身分證號、不留存）與去識別化輸出
- 用官方 FHIR Validator 驗證輸出檔；`obs_codes` 全數 `verified=1`
- 驗收：輸出檔通過 TW Core IG 驗證，交換對象可成功匯入

## 9. 待確認事項

- [ ] 健保署分區業務組：健保卡可否用於會員建檔比對
- [ ] 藥師公會／衛生局：獎勵設計是否妥當
- [ ] 健康資料同意書內容（含 HMAC 比對、LINE 傳送、居家回報與照片保存、家屬代填、對外輸出）
- [ ] 不識字者的同意方式（口頭說明、按指印或蓋章、見證人簽名）——請律師確認
- [ ] 藍牙儀器選型（需支援標準 BLE 血壓／體重／血糖協定）
- [ ] 骨密度：要不要買儀器，或改用合作篩檢活動
- [ ] 台語語音：藥師錄音句型清單
- [ ] FHIR 交換對象與其要求的 IG 版本；LOINC 代碼逐一確認
- [ ] 申請 Google Cloud、LINE 官方帳號（藥局名義）
- [ ] 開發環境：開放網路設定，或在藥局電腦安裝 Claude Code
