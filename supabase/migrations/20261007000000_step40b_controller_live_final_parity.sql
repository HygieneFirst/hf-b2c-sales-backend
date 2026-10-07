-- Step 40B: consolidated parity of controller-verified live final state (2026-10-07).

-- Source: HF_40B_REPO_PARITY_CONTROLLER_EXPORT.zip; no reconstructed migration history.

-- JSON SHA-256: 92f22bc1d338f9bc173b78da1ed7ba7df8e542d5720aec9ad65c30fbda6f3cdc

-- RPC SHA-256: 2c27e218d919c31917cacb5658f15b9de610b85113b655289338ae991b8215e1

-- Fresh reset artifact only; do not apply to the existing live KB.

BEGIN;

CREATE TABLE public.b2c_kb_versions (
  version_id text NOT NULL,
  status text NOT NULL CHECK (status IN ('DRAFT', 'APPROVED_FROZEN', 'WITHDRAWN')),
  approved_at timestamptz,
  approved_by text,
  source_artifact text NOT NULL,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (version_id)
);

ALTER TABLE public.b2c_kb_versions OWNER TO postgres;

ALTER TABLE public.b2c_kb_versions ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.b2c_kb_versions FROM PUBLIC, anon, authenticated, service_role;

GRANT SELECT ON TABLE public.b2c_kb_versions TO service_role;

CREATE TABLE public.b2c_kb_entries (
  version_id text NOT NULL,
  kb_fact_id text NOT NULL,
  service_topic text NOT NULL,
  title text NOT NULL,
  customer_answer text NOT NULL,
  response_class text NOT NULL CHECK (response_class IN ('STATIC_ANSWER', 'HUMAN_CONFIRMATION', 'LIVE_CONFIRMATION', 'CLINICAL_HUMAN', 'PRICE_HUMAN')),
  search_terms text[] NOT NULL DEFAULT '{}'::text[],
  answer_limitations text[] NOT NULL DEFAULT '{}'::text[],
  must_not_claim text[] NOT NULL DEFAULT '{}'::text[],
  human_confirmation_required boolean NOT NULL DEFAULT false,
  status text NOT NULL DEFAULT 'APPROVED' CHECK (status IN ('APPROVED', 'STALE', 'WITHDRAWN')),
  priority integer NOT NULL DEFAULT 100,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (version_id, kb_fact_id),
  FOREIGN KEY (version_id) REFERENCES public.b2c_kb_versions (version_id)
);

ALTER TABLE public.b2c_kb_entries OWNER TO postgres;

ALTER TABLE public.b2c_kb_entries ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.b2c_kb_entries FROM PUBLIC, anon, authenticated, service_role;

GRANT SELECT ON TABLE public.b2c_kb_entries TO service_role;

CREATE INDEX b2c_kb_entries_version_service_idx
  ON public.b2c_kb_entries (version_id, service_topic, status);

INSERT INTO public.b2c_kb_versions (version_id, status, approved_at, approved_by, source_artifact, notes)
SELECT version_id, status, approved_at, approved_by, source_artifact, notes
FROM jsonb_to_recordset($step40b_seed$
[
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "status": "APPROVED_FROZEN",
    "approved_at": "2026-10-06T09:00:00Z",
    "approved_by": "Project Controller / Roy business authority chain",
    "source_artifact": "HF_WA_SALES_KB_CONTENT_v0.2_FINAL_CANDIDATE.md",
    "notes": "Dedicated WhatsApp Sales Enquiry KB. Drive documents are reference only."
  }
]
$step40b_seed$::jsonb) AS seed(version_id text, status text, approved_at timestamptz, approved_by text, source_artifact text, notes text);

INSERT INTO public.b2c_kb_entries (version_id, kb_fact_id, service_topic, title, customer_answer, response_class, search_terms, answer_limitations, must_not_claim, human_confirmation_required, status, priority)
SELECT version_id, kb_fact_id, service_topic, title, customer_answer, response_class, search_terms, answer_limitations, must_not_claim, human_confirmation_required, status, priority
FROM jsonb_to_recordset($step40b_seed$
[
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-CATALOGUE",
    "service_topic": "cross_service",
    "title": "服務目錄",
    "customer_answer": "我哋可以協助查詢健康送飯、家居照顧、家居清潔、復康服務、傷口護理，同埋陪診／陪同外出。你想了解邊一項？如果係其他需要，都可以先話我哋知。",
    "response_class": "STATIC_ANSWER",
    "search_terms": [
      "有咩服務",
      "提供咩服務",
      "服務種類",
      "你哋做咩",
      "服務項目"
    ],
    "answer_limitations": [
      "CCSV係資助／資格背景，唔係獨立服務"
    ],
    "must_not_claim": [
      "不可將CCSV當獨立服務"
    ],
    "human_confirmation_required": false,
    "status": "APPROVED",
    "priority": 10
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-CCSV",
    "service_topic": "cross_service",
    "title": "CCSV",
    "customer_answer": "如果你係想以長者社區照顧服務券查詢，可以先講低想了解嘅服務；資格、券額、共同付款同實際安排需要同事確認。",
    "response_class": "HUMAN_CONFIRMATION",
    "search_terms": [
      "CCSV",
      "長者券",
      "社區照顧服務券",
      "服務券"
    ],
    "answer_limitations": [
      "CCSV係funding/eligibility context"
    ],
    "must_not_claim": [
      "AI不可判資格",
      "AI不可判券額",
      "AI不可計共同付款"
    ],
    "human_confirmation_required": true,
    "status": "APPROVED",
    "priority": 10
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-X01",
    "service_topic": "cross_service",
    "title": "地區查詢",
    "customer_answer": "你可以先提供服務地區；實際能否安排同有冇額外交通費，需要按服務同地址確認。",
    "response_class": "LIVE_CONFIRMATION",
    "search_terms": [
      "邊區",
      "地區",
      "服務範圍",
      "全港",
      "邊度有服務"
    ],
    "answer_limitations": [
      "實際serviceability屬live／人工確認"
    ],
    "must_not_claim": [
      "不可宣稱全港保證覆蓋"
    ],
    "human_confirmation_required": true,
    "status": "APPROVED",
    "priority": 20
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-X02",
    "service_topic": "cross_service",
    "title": "價格／報價",
    "customer_answer": "收費由同事按你的服務需要確認。",
    "response_class": "PRICE_HUMAN",
    "search_terms": [
      "幾錢",
      "價錢",
      "收費",
      "報價",
      "費用",
      "幾多錢"
    ],
    "answer_limitations": [
      "AI完全唔報價"
    ],
    "must_not_claim": [
      "不可引用價目表報價",
      "不可按時數計價"
    ],
    "human_confirmation_required": true,
    "status": "APPROVED",
    "priority": 5
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-X03",
    "service_topic": "cross_service",
    "title": "今日／聽日／指定時間有冇位",
    "customer_answer": "你可以先提供希望日期、時間同地區，實際能否安排需要同事確認。",
    "response_class": "LIVE_CONFIRMATION",
    "search_terms": [
      "有冇位",
      "今日有冇",
      "聽日有冇",
      "幾時有位",
      "即日",
      "今日可以",
      "聽日可以"
    ],
    "answer_limitations": [
      "requested date/time只係偏好"
    ],
    "must_not_claim": [
      "不可話有位",
      "不可話已留位",
      "不可話已安排",
      "不可話已確認預約"
    ],
    "human_confirmation_required": true,
    "status": "APPROVED",
    "priority": 5
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-X04",
    "service_topic": "cross_service",
    "title": "真人協助",
    "customer_answer": "可以，你可以先講低需要協助嘅事項；實際轉交同接手狀態由系統／同事確認。",
    "response_class": "HUMAN_CONFIRMATION",
    "search_terms": [
      "真人",
      "人工",
      "搵人",
      "同事跟進",
      "想有人覆"
    ],
    "answer_limitations": [
      "exact routing同已轉交／已接手字眼屬40C/40D"
    ],
    "must_not_claim": [
      "不可因資料未齊阻擋真人要求",
      "不可無證據聲稱已接手"
    ],
    "human_confirmation_required": true,
    "status": "APPROVED",
    "priority": 5
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-M01",
    "service_topic": "meal_delivery",
    "title": "正式餐類",
    "customer_answer": "目前可以查詢普通餐、糖尿餐、碎餐、無骨餐同糊餐。實際餐單同個別飲食需要要再按當期安排確認。",
    "response_class": "STATIC_ANSWER",
    "search_terms": [
      "送飯",
      "送餐",
      "餐類",
      "餐款",
      "普通餐",
      "糖尿餐",
      "碎餐",
      "無骨餐",
      "糊餐"
    ],
    "answer_limitations": [
      "實際餐單及個別飲食需要要按當期安排確認"
    ],
    "must_not_claim": [
      "不可聲稱臨床適合性",
      "不可聲稱療效"
    ],
    "human_confirmation_required": false,
    "status": "APPROVED",
    "priority": 20
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-M02",
    "service_topic": "meal_delivery",
    "title": "特殊飲食／敏感／質地需要",
    "customer_answer": "如果有食物敏感、忌口、吞嚥／質地或者其他特殊飲食需要，可以先話我哋知；實際可否安排要再確認。",
    "response_class": "HUMAN_CONFIRMATION",
    "search_terms": [
      "食物敏感",
      "過敏",
      "忌口",
      "吞嚥",
      "質地",
      "軟餐",
      "特別餐",
      "特殊飲食"
    ],
    "answer_limitations": [
      "供應能力需要確認"
    ],
    "must_not_claim": [
      "不可保證所有特殊飲食",
      "不可作臨床營養判斷"
    ],
    "human_confirmation_required": true,
    "status": "APPROVED",
    "priority": 15
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-M03",
    "service_topic": "meal_delivery",
    "title": "星期日／公眾假期",
    "customer_answer": "星期日或公眾假期嘅送餐安排需要由同事確認。",
    "response_class": "HUMAN_CONFIRMATION",
    "search_terms": [
      "星期日送餐",
      "星期日送飯",
      "公眾假期送餐",
      "紅日送餐",
      "假期送飯",
      "星期日",
      "公眾假期",
      "紅日"
    ],
    "answer_limitations": [
      "不可由static KB發布一刀切禁日規則"
    ],
    "must_not_claim": [
      "不可話星期日一定不送",
      "不可話公眾假期一定不送"
    ],
    "human_confirmation_required": true,
    "status": "APPROVED",
    "priority": 5
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-M04",
    "service_topic": "meal_delivery",
    "title": "一般送餐時段",
    "customer_answer": "一般預計送餐時段約為上午10時至下午1時30分，實際時間會按當日路線安排。",
    "response_class": "STATIC_ANSWER",
    "search_terms": [
      "幾點送餐",
      "送餐時間",
      "幾點送到",
      "送飯時間"
    ],
    "answer_limitations": [
      "只係一般預計時段"
    ],
    "must_not_claim": [
      "不可當可選slot",
      "不可保證指定到達時間"
    ],
    "human_confirmation_required": false,
    "status": "APPROVED",
    "priority": 20
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-M05",
    "service_topic": "meal_delivery",
    "title": "最低訂餐要求",
    "customer_answer": "一般最少訂3個服務日；實際開始日期同安排仍要再確認。",
    "response_class": "STATIC_ANSWER",
    "search_terms": [
      "最少訂幾多日",
      "最低訂餐",
      "3日",
      "三日",
      "服務日"
    ],
    "answer_limitations": [
      "3個服務日唔等於提前3日預約"
    ],
    "must_not_claim": [
      "不可推算3日後一定開始"
    ],
    "human_confirmation_required": false,
    "status": "APPROVED",
    "priority": 20
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-M06-CCSV",
    "service_topic": "meal_delivery",
    "title": "CCSV下月安排cut-off",
    "customer_answer": "CCSV下月送餐安排需要喺每月25號前提供。",
    "response_class": "STATIC_ANSWER",
    "search_terms": [
      "CCSV 25號",
      "CCSV下月",
      "25號前",
      "服務券送餐下月",
      "CCSV下個月",
      "每月25號",
      "幾時前要交安排",
      "25號"
    ],
    "answer_limitations": [
      "只適用CCSV下月送餐安排"
    ],
    "must_not_claim": [
      "不可將25號規則套用所有私客"
    ],
    "human_confirmation_required": false,
    "status": "APPROVED",
    "priority": 15
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-M06-PRIVATE",
    "service_topic": "meal_delivery",
    "title": "私客下月安排",
    "customer_answer": "私客建議喺月尾前提供下月送餐安排；實際開始日期要再確認。",
    "response_class": "STATIC_ANSWER",
    "search_terms": [
      "私客月尾",
      "下月送餐",
      "下個月送餐",
      "月尾前"
    ],
    "answer_limitations": [
      "實際開始日期需要確認"
    ],
    "must_not_claim": [
      "不可聲稱已預約"
    ],
    "human_confirmation_required": false,
    "status": "APPROVED",
    "priority": 25
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-M07",
    "service_topic": "meal_delivery",
    "title": "送飯價格",
    "customer_answer": "送飯服務收費由同事確認。",
    "response_class": "PRICE_HUMAN",
    "search_terms": [
      "送飯幾錢",
      "送餐幾錢",
      "餐價",
      "送飯收費"
    ],
    "answer_limitations": [
      "AI完全唔報價"
    ],
    "must_not_claim": [
      "不可報套餐價",
      "不可計每餐價"
    ],
    "human_confirmation_required": true,
    "status": "APPROVED",
    "priority": 5
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-H01",
    "service_topic": "home_care",
    "title": "服務範圍",
    "customer_answer": "家居照顧可以按需要協助個人衛生、如廁／沐浴、扶抱轉身、輔助餵食、日常生活照顧，同埋由合適人員監察維生指數。實際工作內容同人員安排需要再確認。",
    "response_class": "STATIC_ANSWER",
    "search_terms": [
      "家居照顧做咩",
      "護理員做咩",
      "沖涼",
      "如廁",
      "扶抱",
      "轉身",
      "餵食",
      "維生指數"
    ],
    "answer_limitations": [
      "人員資格及實際工作內容需要確認"
    ],
    "must_not_claim": [
      "AI不可解讀維生指數",
      "不可承諾專業醫療程序"
    ],
    "human_confirmation_required": false,
    "status": "APPROVED",
    "priority": 20
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-H02",
    "service_topic": "home_care",
    "title": "最低服務時數",
    "customer_answer": "家居照顧一般最低2小時起；實際時數同安排由同事確認。",
    "response_class": "STATIC_ANSWER",
    "search_terms": [
      "家居照顧最少幾個鐘",
      "護理最少幾耐",
      "最低2小時",
      "最少幾多個鐘",
      "最少幾個鐘",
      "幾多個鐘"
    ],
    "answer_limitations": [
      "實際安排需確認"
    ],
    "must_not_claim": [
      "不可承諾有位"
    ],
    "human_confirmation_required": false,
    "status": "APPROVED",
    "priority": 20
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-H03",
    "service_topic": "home_care",
    "title": "提前預約",
    "customer_answer": "如有需要，建議盡快提供希望日期、時間同地區，方便同事確認安排。",
    "response_class": "LIVE_CONFIRMATION",
    "search_terms": [
      "家居照顧幾早book",
      "護理幾早預約",
      "幾時可以開始"
    ],
    "answer_limitations": [
      "建議盡快提出"
    ],
    "must_not_claim": [
      "不可保證開始日期"
    ],
    "human_confirmation_required": true,
    "status": "APPROVED",
    "priority": 20
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-H04",
    "service_topic": "home_care",
    "title": "服務地區",
    "customer_answer": "可以先提供服務地區；較偏遠地區可能涉及額外交通費，實際安排由同事確認。",
    "response_class": "LIVE_CONFIRMATION",
    "search_terms": [
      "家居照顧邊區",
      "護理邊區",
      "偏遠交通費"
    ],
    "answer_limitations": [
      "冇固定通用地區禁區"
    ],
    "must_not_claim": [
      "不可保證所有地區都有即時人手"
    ],
    "human_confirmation_required": true,
    "status": "APPROVED",
    "priority": 20
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-H05",
    "service_topic": "home_care",
    "title": "取消／改期",
    "customer_answer": "已收取嘅服務費一般唔作取消退款，如有需要可以改期；如使用者去世等特殊情況，會由同事按證明再處理。",
    "response_class": "HUMAN_CONFIRMATION",
    "search_terms": [
      "家居照顧取消",
      "護理取消",
      "家居照顧退款",
      "護理改期",
      "使用者去世"
    ],
    "answer_limitations": [
      "特殊例外由人工處理"
    ],
    "must_not_claim": [
      "不可自行批退款"
    ],
    "human_confirmation_required": true,
    "status": "APPROVED",
    "priority": 15
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-H06",
    "service_topic": "home_care",
    "title": "家居照顧價格",
    "customer_answer": "家居照顧收費由同事確認。",
    "response_class": "PRICE_HUMAN",
    "search_terms": [
      "家居照顧幾錢",
      "護理幾錢",
      "護理收費"
    ],
    "answer_limitations": [
      "AI完全唔報價"
    ],
    "must_not_claim": [
      "不可按小時計價"
    ],
    "human_confirmation_required": true,
    "status": "APPROVED",
    "priority": 5
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-C01",
    "service_topic": "home_cleaning",
    "title": "一般服務範圍",
    "customer_answer": "一般可以協助房間、客廳、廚房、浴室、地板同家居表面清潔；其他項目可以先講低，再由同事確認。",
    "response_class": "STATIC_ANSWER",
    "search_terms": [
      "清潔包括咩",
      "家居清潔做咩",
      "抹地",
      "廚房清潔",
      "浴室清潔"
    ],
    "answer_limitations": [
      "特殊項目需確認"
    ],
    "must_not_claim": [
      "不可承諾高空外窗",
      "不可承諾裝修後工程級清潔",
      "不可承諾設備拆卸維修",
      "不可保證定時完成全屋"
    ],
    "human_confirmation_required": false,
    "status": "APPROVED",
    "priority": 20
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-C02",
    "service_topic": "home_cleaning",
    "title": "服務時數",
    "customer_answer": "可以查詢2、3或4小時嘅家居清潔；實際時間同人員安排需要確認。",
    "response_class": "STATIC_ANSWER",
    "search_terms": [
      "清潔幾多小時",
      "2小時清潔",
      "3小時清潔",
      "4小時清潔",
      "清潔時數",
      "2.5小時",
      "2.5個鐘",
      "兩個半鐘",
      "兩個半小時"
    ],
    "answer_limitations": [
      "批准選項只包括2/3/4小時"
    ],
    "must_not_claim": [
      "不可增加其他時數選項"
    ],
    "human_confirmation_required": false,
    "status": "APPROVED",
    "priority": 15
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-C03",
    "service_topic": "home_cleaning",
    "title": "清潔用品",
    "customer_answer": "一般清潔用品由客戶提供；如有特別需要可以先同同事確認。",
    "response_class": "STATIC_ANSWER",
    "search_terms": [
      "清潔用品",
      "清潔劑",
      "工具邊個提供",
      "要唔要自備",
      "用品自備"
    ],
    "answer_limitations": [
      "特殊用品另確認"
    ],
    "must_not_claim": [
      "不可聲稱公司一定提供用品"
    ],
    "human_confirmation_required": false,
    "status": "APPROVED",
    "priority": 20
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-C04",
    "service_topic": "home_cleaning",
    "title": "服務地區",
    "customer_answer": "可以先提供服務地區；較偏遠地區可能涉及額外交通費，實際安排由同事確認。",
    "response_class": "LIVE_CONFIRMATION",
    "search_terms": [
      "清潔邊區",
      "家務助理邊區",
      "清潔偏遠"
    ],
    "answer_limitations": [
      "實際serviceability需確認"
    ],
    "must_not_claim": [
      "不可保證全港有位"
    ],
    "human_confirmation_required": true,
    "status": "APPROVED",
    "priority": 20
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-C05",
    "service_topic": "home_cleaning",
    "title": "取消／改期",
    "customer_answer": "已收取嘅服務費一般唔作取消退款，如有需要可以改期。",
    "response_class": "HUMAN_CONFIRMATION",
    "search_terms": [
      "清潔取消",
      "清潔退款",
      "清潔改期",
      "家務取消"
    ],
    "answer_limitations": [
      "實際個案由人工處理"
    ],
    "must_not_claim": [
      "不可自行批退款"
    ],
    "human_confirmation_required": true,
    "status": "APPROVED",
    "priority": 15
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-C06",
    "service_topic": "home_cleaning",
    "title": "家居清潔價格",
    "customer_answer": "家居清潔收費由同事確認。",
    "response_class": "PRICE_HUMAN",
    "search_terms": [
      "清潔幾錢",
      "家務幾錢",
      "清潔收費"
    ],
    "answer_limitations": [
      "AI完全唔報價"
    ],
    "must_not_claim": [
      "不可按2/3/4小時計價"
    ],
    "human_confirmation_required": true,
    "status": "APPROVED",
    "priority": 5
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-R01",
    "service_topic": "rehabilitation",
    "title": "復康服務基本說明",
    "customer_answer": "可以查詢上門復康服務；實際治療內容會由相關同事／專業人員按需要確認。",
    "response_class": "STATIC_ANSWER",
    "search_terms": [
      "復康服務",
      "物理治療",
      "PT服務",
      "上門復康"
    ],
    "answer_limitations": [
      "復康服務係customer-facing catalogue name"
    ],
    "must_not_claim": [
      "不可自行新增治療模式",
      "不可承諾療效"
    ],
    "human_confirmation_required": false,
    "status": "APPROVED",
    "priority": 20
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-R02",
    "service_topic": "rehabilitation",
    "title": "可服務場地",
    "customer_answer": "復康服務可以查詢上門安排，亦可以視乎情況喺公園或合適嘅會所設施進行；實際地點要由同事確認。",
    "response_class": "LIVE_CONFIRMATION",
    "search_terms": [
      "復康喺邊做",
      "物理治療上門",
      "公園復康",
      "會所復康",
      "復康地點"
    ],
    "answer_limitations": [
      "實際地點需確認"
    ],
    "must_not_claim": [
      "不可承諾指定地點有位"
    ],
    "human_confirmation_required": true,
    "status": "APPROVED",
    "priority": 20
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-R03",
    "service_topic": "rehabilitation",
    "title": "最低服務時數",
    "customer_answer": "復康服務一般最少1小時起；實際安排由同事確認。",
    "response_class": "STATIC_ANSWER",
    "search_terms": [
      "復康最少幾耐",
      "物理治療幾耐",
      "復康1小時",
      "session幾耐"
    ],
    "answer_limitations": [
      "只係最低服務時數"
    ],
    "must_not_claim": [
      "不可推論臨床session一定60分鐘"
    ],
    "human_confirmation_required": false,
    "status": "APPROVED",
    "priority": 20
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-R04",
    "service_topic": "rehabilitation",
    "title": "初步查詢資料",
    "customer_answer": "你可以先講低想處理嘅復康需要、希望時間同地區；如有同安排相關嘅基本健康資料亦可以提供。臨床評估會由專業人員處理。",
    "response_class": "HUMAN_CONFIRMATION",
    "search_terms": [
      "復康要提供咩資料",
      "物理治療要咩資料",
      "復康查詢資料"
    ],
    "answer_limitations": [
      "唔係硬gate"
    ],
    "must_not_claim": [
      "不可要求完整病歷作初次查詢硬gate"
    ],
    "human_confirmation_required": true,
    "status": "APPROVED",
    "priority": 25
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-R05",
    "service_topic": "rehabilitation",
    "title": "臨床適合性",
    "customer_answer": "是否適合接受復康／物理治療，需要由合資格專業人士評估；AI唔會代你作臨床判斷。",
    "response_class": "CLINICAL_HUMAN",
    "search_terms": [
      "適唔適合物理治療",
      "適唔適合復康",
      "我呢個情況做唔做得",
      "治療建議",
      "痛症點算",
      "中風後",
      "適唔適合我",
      "可唔可以做復康",
      "可唔可以做物理治療"
    ],
    "answer_limitations": [
      "clinical judgement only"
    ],
    "must_not_claim": [
      "不可診斷",
      "不可建議療程",
      "不可判斷適合性"
    ],
    "human_confirmation_required": true,
    "status": "APPROVED",
    "priority": 1
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-R06",
    "service_topic": "rehabilitation",
    "title": "復康服務價格",
    "customer_answer": "復康服務收費由同事確認。",
    "response_class": "PRICE_HUMAN",
    "search_terms": [
      "復康幾錢",
      "物理治療幾錢",
      "PT幾錢"
    ],
    "answer_limitations": [
      "AI完全唔報價"
    ],
    "must_not_claim": [
      "不可引用舊PT價目"
    ],
    "human_confirmation_required": true,
    "status": "APPROVED",
    "priority": 5
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-W01",
    "service_topic": "wound_care",
    "title": "傷口護理基本服務",
    "customer_answer": "我哋可以協助傷口護理查詢，服務由註冊護士或登記護士提供。實際傷口護理安排要由同事確認。",
    "response_class": "STATIC_ANSWER",
    "search_terms": [
      "傷口護理",
      "洗傷口",
      "換症",
      "wound care",
      "傷口服務"
    ],
    "answer_limitations": [
      "具體程序需人工確認"
    ],
    "must_not_claim": [
      "不可由員工技能表推論額外服務"
    ],
    "human_confirmation_required": false,
    "status": "APPROVED",
    "priority": 20
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-W02",
    "service_topic": "wound_care",
    "title": "建議提供傷口資料",
    "customer_answer": "如方便，建議提供傷口相片，以及出院時醫生醫囑或護士診所嘅護理概要，方便同事初步了解；未能即時提供亦唔代表一定唔可以先作查詢。",
    "response_class": "HUMAN_CONFIRMATION",
    "search_terms": [
      "傷口相",
      "傷口照片",
      "醫囑",
      "護理概要",
      "要準備咩",
      "換症紙"
    ],
    "answer_limitations": [
      "相片同文件都係建議，唔係硬gate"
    ],
    "must_not_claim": [
      "不可因未有相片或文件阻擋初步查詢",
      "AI不可睇相診斷"
    ],
    "human_confirmation_required": true,
    "status": "APPROVED",
    "priority": 10
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-W03",
    "service_topic": "wound_care",
    "title": "拆線",
    "customer_answer": "拆線需要由同事／專業人員再確認，會交俾人工跟進。",
    "response_class": "CLINICAL_HUMAN",
    "search_terms": [
      "拆線",
      "拆針",
      "remove stitches",
      "suture removal"
    ],
    "answer_limitations": [
      "所有拆線查詢人工／專業確認"
    ],
    "must_not_claim": [
      "AI不可判斷幾時拆線",
      "AI不可承諾可以拆"
    ],
    "human_confirmation_required": true,
    "status": "APPROVED",
    "priority": 1
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-W04",
    "service_topic": "wound_care",
    "title": "傷口護理地區",
    "customer_answer": "請提供服務地區；實際能否安排同有冇額外交通費，需要由同事確認。",
    "response_class": "LIVE_CONFIRMATION",
    "search_terms": [
      "傷口護理邊區",
      "洗傷口邊區",
      "wound care area"
    ],
    "answer_limitations": [
      "實際serviceability需確認"
    ],
    "must_not_claim": [
      "不可保證全港上門"
    ],
    "human_confirmation_required": true,
    "status": "APPROVED",
    "priority": 20
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-W05",
    "service_topic": "wound_care",
    "title": "傷口護理價格／耗材",
    "customer_answer": "傷口護理收費同耗材安排由同事確認。",
    "response_class": "PRICE_HUMAN",
    "search_terms": [
      "傷口護理幾錢",
      "洗傷口幾錢",
      "敷料幾錢",
      "耗材費"
    ],
    "answer_limitations": [
      "AI完全唔報價"
    ],
    "must_not_claim": [
      "不可自行加耗材費",
      "不可引用護士時薪當服務價"
    ],
    "human_confirmation_required": true,
    "status": "APPROVED",
    "priority": 5
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-W06",
    "service_topic": "wound_care",
    "title": "傷口臨床判斷",
    "customer_answer": "傷口情況同適合嘅處理，需要由合資格醫護評估；AI唔會判斷傷口嚴重程度或決定處理方法。",
    "response_class": "CLINICAL_HUMAN",
    "search_terms": [
      "傷口發炎",
      "傷口感染",
      "傷口嚴重",
      "傷口點處理",
      "用咩敷料",
      "傷口適唔適合",
      "睇傷口",
      "紅腫",
      "感染",
      "係咪感染",
      "傷口紅"
    ],
    "answer_limitations": [
      "clinical judgement only"
    ],
    "must_not_claim": [
      "不可診斷感染",
      "不可判嚴重程度",
      "不可揀敷料",
      "不可決定治療"
    ],
    "human_confirmation_required": true,
    "status": "APPROVED",
    "priority": 1
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-E01",
    "service_topic": "medical_escort",
    "title": "可承接目的地",
    "customer_answer": "除咗醫院／診所，亦可以查詢銀行、政府部門、購物或其他陪同外出需要；實際行程同協助範圍要再確認。",
    "response_class": "STATIC_ANSWER",
    "search_terms": [
      "陪診去邊",
      "銀行陪同",
      "政府部門陪同",
      "購物陪同",
      "陪同外出",
      "銀行",
      "政府部門",
      "醫院",
      "診所",
      "購物"
    ],
    "answer_limitations": [
      "實際行程需確認"
    ],
    "must_not_claim": [
      "不可承諾代辦銀行交易",
      "不可作法律代表",
      "不可代作醫療決定"
    ],
    "human_confirmation_required": false,
    "status": "APPROVED",
    "priority": 20
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-E02",
    "service_topic": "medical_escort",
    "title": "單程／來回",
    "customer_answer": "單程同來回都可以查詢；如果係單程，需要提供到達目的地後嘅對接人資料，實際安排由同事確認。",
    "response_class": "STATIC_ANSWER",
    "search_terms": [
      "單程陪診",
      "來回陪診",
      "往返陪診",
      "單程",
      "來回"
    ],
    "answer_limitations": [
      "單程需要目的地對接人"
    ],
    "must_not_claim": [
      "不可承諾交通工具或返程時間"
    ],
    "human_confirmation_required": false,
    "status": "APPROVED",
    "priority": 20
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-E03",
    "service_topic": "medical_escort",
    "title": "提前預約",
    "customer_answer": "建議最好提前2個工作天提出預約需要，實際可否安排仍要由同事確認。",
    "response_class": "LIVE_CONFIRMATION",
    "search_terms": [
      "陪診幾早book",
      "陪診提前",
      "兩個工作天",
      "2個工作天",
      "幾早預約陪診",
      "最好幾早預約",
      "幾早預約",
      "幾日前預約"
    ],
    "answer_limitations": [
      "只係建議提前期"
    ],
    "must_not_claim": [
      "不可保證兩個工作天一定有位"
    ],
    "human_confirmation_required": true,
    "status": "APPROVED",
    "priority": 15
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-E04",
    "service_topic": "medical_escort",
    "title": "最低服務時數",
    "customer_answer": "陪診／陪同外出一般最低2小時起；實際安排由同事確認。",
    "response_class": "STATIC_ANSWER",
    "search_terms": [
      "陪診最少幾耐",
      "陪診最低時數",
      "陪診2小時"
    ],
    "answer_limitations": [
      "實際安排需確認"
    ],
    "must_not_claim": [
      "不可保證有位"
    ],
    "human_confirmation_required": false,
    "status": "APPROVED",
    "priority": 20
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-E05",
    "service_topic": "medical_escort",
    "title": "超時計費單位",
    "customer_answer": "如超出原定服務時間，計費方式會按客戶類別同適用安排由同事確認。",
    "response_class": "PRICE_HUMAN",
    "search_terms": [
      "陪診超時",
      "超時點計",
      "15分鐘",
      "30分鐘"
    ],
    "answer_limitations": [
      "內部規則：私客30分鐘、B2B 15分鐘；AI唔計價"
    ],
    "must_not_claim": [
      "不可計超時費",
      "不可向客報金額"
    ],
    "human_confirmation_required": true,
    "status": "APPROVED",
    "priority": 10
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-E06",
    "service_topic": "medical_escort",
    "title": "交通費",
    "customer_answer": "服務期間需要嘅交通費一般由客戶負責；實際交通安排由同事確認。",
    "response_class": "HUMAN_CONFIRMATION",
    "search_terms": [
      "陪診交通費",
      "車費邊個畀",
      "的士費",
      "交通邊個畀",
      "午夜返程",
      "午夜的士",
      "返程的士",
      "車費係咪我畀"
    ],
    "answer_limitations": [
      "午夜返程另人工回覆"
    ],
    "must_not_claim": [
      "不可自動聲稱午夜返程的士一定由客戶負責"
    ],
    "human_confirmation_required": true,
    "status": "APPROVED",
    "priority": 10
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-E07",
    "service_topic": "medical_escort",
    "title": "取消／改期",
    "customer_answer": "已收取嘅服務費一般唔作取消退款，如有需要可以改期；實際安排由同事確認。",
    "response_class": "HUMAN_CONFIRMATION",
    "search_terms": [
      "陪診取消",
      "陪診退款",
      "陪診改期"
    ],
    "answer_limitations": [
      "實際個案人工確認"
    ],
    "must_not_claim": [
      "不可自行批退款"
    ],
    "human_confirmation_required": true,
    "status": "APPROVED",
    "priority": 15
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-E08",
    "service_topic": "medical_escort",
    "title": "陪診價格",
    "customer_answer": "陪診／陪同外出收費由同事確認。",
    "response_class": "PRICE_HUMAN",
    "search_terms": [
      "陪診幾錢",
      "陪同外出幾錢",
      "陪診收費"
    ],
    "answer_limitations": [
      "AI完全唔報價"
    ],
    "must_not_claim": [
      "不可引用舊價表"
    ],
    "human_confirmation_required": true,
    "status": "APPROVED",
    "priority": 5
  },
  {
    "version_id": "HF_WA_SALES_KB_CONTENT_v0.2",
    "kb_fact_id": "KB-O01",
    "service_topic": "other",
    "title": "其他／未支援查詢",
    "customer_answer": "你可以先講低需要協助嘅事項；如果唔屬於以上服務，會由同事確認可以點樣跟進。",
    "response_class": "HUMAN_CONFIRMATION",
    "search_terms": [
      "其他服務",
      "其他需要",
      "唔係以上服務"
    ],
    "answer_limitations": [
      "只係safe fallback"
    ],
    "must_not_claim": [
      "不可發明新服務",
      "不可聲稱已轉交"
    ],
    "human_confirmation_required": true,
    "status": "APPROVED",
    "priority": 100
  }
]
$step40b_seed$::jsonb) AS seed(version_id text, kb_fact_id text, service_topic text, title text, customer_answer text, response_class text, search_terms text[], answer_limitations text[], must_not_claim text[], human_confirmation_required boolean, status text, priority integer);

CREATE OR REPLACE FUNCTION public.b2c_kb_lookup_v1(p_query text, p_service_topic text DEFAULT NULL::text, p_limit integer DEFAULT 3)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_query text;
  v_version text;
  v_results jsonb;
begin
  if p_query is null or btrim(p_query) = '' then
    return jsonb_build_object('kb_version',null,'retrieval_status','NO_AUTHORITATIVE_ANSWER','reason','EMPTY_QUERY','matches','[]'::jsonb);
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 5 then p_limit := 3; end if;

  select version_id into v_version
  from public.b2c_kb_versions
  where status='APPROVED_FROZEN'
  order by approved_at desc nulls last, created_at desc
  limit 1;

  if v_version is null then
    return jsonb_build_object('kb_version',null,'retrieval_status','NO_AUTHORITATIVE_ANSWER','reason','NO_APPROVED_KB_VERSION','matches','[]'::jsonb);
  end if;

  v_query := lower(regexp_replace(btrim(p_query), '[[:space:][:punct:]]+', '', 'g'));

  with base as (
    select e.*,
      coalesce((
        select max(
          case
            when v_query = lower(regexp_replace(term, '[[:space:][:punct:]]+', '', 'g')) then 100
            when v_query like '%' || lower(regexp_replace(term, '[[:space:][:punct:]]+', '', 'g')) || '%' then 50
            when lower(regexp_replace(term, '[[:space:][:punct:]]+', '', 'g')) like '%' || v_query || '%' and length(v_query) >= 3 then 30
            else 0
          end
        )
        from unnest(e.search_terms) term
      ),0) as term_score
    from public.b2c_kb_entries e
    where e.version_id=v_version
      and e.status='APPROVED'
      and (p_service_topic is null or e.service_topic=p_service_topic or e.service_topic='cross_service')
  ),
  ranked as (
    select b.*,
      term_score
      + case when p_service_topic is not null and b.service_topic=p_service_topic then 10 else 0 end
      - least(b.priority,100) * 0.01 as score
    from base b
    where term_score > 0
    order by score desc, priority asc, kb_fact_id
    limit p_limit
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'kb_fact_id',kb_fact_id,
    'service_topic',service_topic,
    'title',title,
    'customer_answer',customer_answer,
    'response_class',response_class,
    'human_confirmation_required',human_confirmation_required,
    'answer_limitations',answer_limitations,
    'must_not_claim',must_not_claim,
    'score',score
  ) order by score desc, priority asc, kb_fact_id),'[]'::jsonb)
  into v_results
  from ranked;

  if jsonb_array_length(v_results)=0 then
    return jsonb_build_object('kb_version',v_version,'retrieval_status','NO_AUTHORITATIVE_ANSWER','reason','NO_APPROVED_MATCH','matches',v_results);
  end if;

  return jsonb_build_object('kb_version',v_version,'retrieval_status','MATCH','matches',v_results);
end;
$function$;

ALTER FUNCTION public.b2c_kb_lookup_v1(text, text, integer) OWNER TO postgres;

REVOKE ALL ON FUNCTION public.b2c_kb_lookup_v1(text, text, integer) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.b2c_kb_lookup_v1(text, text, integer) TO service_role, postgres;

COMMIT;
