"""CloudSail 现场助手后端 · 山海坞创客松 Demo
跑法: pip install fastapi uvicorn && uvicorn main:app --host 0.0.0.0 --port 8000
眼镜/手机与电脑同一 Wi-Fi，眼镜端 app.js 里填电脑局域网 IP。
"""
import json
import re
import time
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

app = FastAPI(title="CloudSail Field API")
app.add_middleware(
    CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"]
)

DB = Path(__file__).parent / "db.json"
DB.write_text(DB.read_text() if DB.exists() else json.dumps({
    "visits": [], "reports": [],
    "lines": [
        {"name": "1号线", "free": 62, "earliest": "明天"},
        {"name": "2号线", "free": 35, "earliest": "3天后"},
        {"name": "3号线", "free": 80, "earliest": "明天"},
    ],
}), encoding="utf-8")

data = json.loads(DB.read_text())


def save():
    DB.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")


# ---------- 客户拜访 ----------
class Visit(BaseModel):
    company: str = ""
    person: str = ""
    product: str = ""
    qty: str = ""
    note: str = ""


@app.post("/api/visits")
def add_visit(v: Visit):
    data["visits"].append(v.model_dump())
    save()
    return {"ok": True, "total": len(data["visits"])}


@app.get("/api/visits")
def list_visits():
    return {"visits": data["visits"], "total": len(data["visits"])}


# ---------- 语音抽取兜底（无端侧 LLM 时用规则版） ----------
@app.post("/api/extract")
def extract(body: dict):
    text = body.get("text", "")
    m_qty = re.search(r"(\d+(?:\.\d+)?)\s*(件|个|套|台|箱|柜)", text)
    m_person = re.search(r"(?:找|找一下|联系人?是?)\s*([\u4e00-\u9fa5A-Za-z·]{2,4})(?:,|，|先生|女士|总)", text)
    company = ""
    m_co = re.search(r"([\u4e00-\u9fa5A-Za-z]+(?:公司|集团|贸易|工厂|Inc|Ltd|GmbH))", text)
    if m_co:
        company = m_co.group(1)
    return {
        "company": company,
        "person": m_person.group(1) if m_person else "",
        "product": text[:30],
        "qty": (m_qty.group(1) + m_qty.group(2)) if m_qty else "",
        "note": "",
    }


# ---------- 产能 ----------
@app.get("/api/capacity")
def capacity():
    return {"lines": data["lines"]}


NUM_CN = {"零": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5,
          "六": 6, "七": 7, "八": 8, "九": 9, "十": 10}


@app.post("/api/report")
def report(body: dict):
    text = body.get("text", "")
    m_line = re.search(r"([一二三123])\s*号?线", text)
    line = (m_line.group(1) if m_line in NUM_CN else m_line.group(1)) + "号线" if m_line else "未识别"
    m_out = re.search(r"(\d+(?:\.\d+)?)\s*(件|个|套|台)", text)
    output = m_out.group(1) + m_out.group(2) if m_out else ""
    issues = [k for k in ("停机", "故障", "缺料", "不良", "返工") if k in text]
    rec = {"line": line, "output": output, "issue": "、".join(issues), "raw": text}
    data["reports"].append(rec)
    if line != "未识别":
        for ln in data["lines"]:
            if ln["name"] == line:
                ln["free"] = max(0, ln["free"] - 2)  # demo: 占用一点余量
    save()
    return rec


# ---------- 报价（确定性计算：大模型不碰数字） ----------
class QuoteIn(BaseModel):
    cost: float          # 单件完全成本
    qty: int             # 数量
    urgency: str = "normal"   # normal | rush


@app.post("/api/quote")
def quote(q: QuoteIn):
    scale = 1.0 if q.qty >= 1000 else (1.03 if q.qty >= 500 else 1.08)
    base = q.cost * scale
    if q.urgency == "rush":
        base *= 1.04
    lead = 35 if q.urgency == "normal" else 28
    r = lambda m: round(base * m, 2)
    return {
        "ideal": r(1.22),      # 理想价 毛利~18%
        "deal": r(1.14),       # 可成交价 毛利~12%
        "floor": r(1.08),      # 底价 毛利~7%，低于此需老板审批
        "leadDays": lead,
        "leadRush": 28 if q.urgency == "normal" else 26,
        "currency": "CNY",
        "note": "数字由确定性公式计算，非大模型生成，可审计",
    }


# ---------- 商城 / 推送 / 翻译（创客松 Demo） ----------
data.setdefault("products", [
    {"sku": "cup-500",  "name": "不锈钢保温杯 500ml", "price": 39.0},
    {"sku": "bottle-1l", "name": "运动水壶 1L",       "price": 25.0},
    {"sku": "mask-50",  "name": "防护口罩 50 只",     "price": 19.9},
])
data.setdefault("orders", [])
data.setdefault("notifs", [])
data.setdefault("notif_seq", 0)
save()


@app.get("/api/products")
def products():
    return {"products": data["products"]}


NUM_CN_ORD = {"一": 1, "两": 2, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9, "十": 10}


@app.post("/api/orders")
def create_order(body: dict):
    text = body.get("text", "")
    m = re.search(r"(\d+|一|两|二|三|四|五|六|七|八|九|十)\s*(件|个|只|瓶|盒)?\s*(.+)", text)
    if not m:
        return {"ok": False, "msg": "请说'买两件保温杯'这样的句子"}
    qty_raw, _, name = m.group(1), m.group(2), m.group(3)
    qty = int(qty_raw) if qty_raw.isdigit() else NUM_CN_ORD.get(qty_raw, 1)
    prod = next((pp for pp in data["products"] if pp["name"].split(" ")[0] in name or any(w in name for w in pp["name"][:4])), None)
    if not prod:
        return {"ok": False, "msg": "没有找到商品：" + name[:12]}
    order = {
        "orderId": "SO" + str(int(time.time()) % 100000).zfill(5),
        "sku": prod["sku"], "name": prod["name"], "qty": qty,
        "total": round(prod["price"] * qty, 2), "raw": text,
    }
    data["orders"].append(order); save()
    data["notif_seq"] += 1
    data["notifs"].append({"id": data["notif_seq"], "from": "商城",
                           "text": "订单 %s 已确认：%s ×%d" % (order["orderId"], order["name"], qty)})
    save()
    return {"ok": True, **order}


@app.get("/api/orders")
def list_orders():
    return {"orders": data["orders"]}


@app.post("/api/notifications")
def push_notif(body: dict):
    data["notif_seq"] += 1
    n = {"id": data["notif_seq"], "from": body.get("from", "总部"), "text": body.get("text", "")}
    data["notifs"].append(n); save()
    return {"ok": True, "id": n["id"]}


@app.get("/api/notifications")
def get_notifs(after: int = 0):
    return {"msgs": [n for n in data["notifs"] if n["id"] > after]}


# 简易翻译兜底（无端侧模型时）。target 传 "auto"：自动识别语种，中文→英语、其他→中文
@app.post("/api/translate")
def translate(body: dict):
    text = body.get("text", "")
    target = body.get("target", "英语")
    if target == "auto":
        src = detect_lang(text)
        target = "英语" if src == "中文" else "中文"
        return {"text": text, "target": target, "detected": src,
                "note": "fallback: 端侧模型不可用，请配置翻译API"}
    return {"text": text, "target": target, "note": "fallback: 端侧模型不可用，请配置翻译API"}


# ---------- 语种自动识别 + 交流洞察（合规：只分析对话内容，不做面部/生物特征分析） ----------
LANG_RULES = [
    ("韩语", lambda s: sum('\uac00' <= c <= '\ud7af' for c in s)),
    ("日语", lambda s: sum('\u3040' <= c <= '\u30ff' for c in s)),
    ("俄语", lambda s: sum('\u0400' <= c <= '\u04ff' for c in s)),
    ("阿拉伯语", lambda s: sum('\u0600' <= c <= '\u06ff' for c in s)),
    ("泰语", lambda s: sum('\u0e00' <= c <= '\u0e7f' for c in s)),
    ("印地语", lambda s: sum('\u0900' <= c <= '\u097f' for c in s)),
    ("中文", lambda s: sum('\u4e00' <= c <= '\u9fff' for c in s)),
]
LATIN_HINTS = {
    "英语": {"the", "and", "is", "we", "you", "can", "price", "need", "want", "please", "quality", "order"},
    "西班牙语": {"que", "de", "para", "precio", "como", "gracias", "necesito", "queremos"},
    "葡萄牙语": {"nao", "não", "obrigado", "preco", "preço", "quero", "por", "muito", "fazemos"},
    "法语": {"le", "les", "nous", "prix", "merci", "bonjour", "besoin"},
    "德语": {"und", "ich", "wir", "preis", "danke", "nicht", "brauchen"},
    "意大利语": {"che", "per", "prezzo", "grazie", "noi", "voglio"},
    "印尼语": {"saya", "kami", "harga", "terima", "kasih", "bisa", "mau"},
    "土耳其语": {"bir", "icin", "için", "fiyat", "tesekkur", "teşekkür", "istiyorum"},
    "越南语": {"cua", "của", "gia", "giá", "cam", "ơn", "chung"},
}


def detect_lang(text: str) -> str:
    for name, fn in LANG_RULES:
        if fn(text) >= 2:
            return name
    words = {w.strip(".,?!;:").lower() for w in text.split()}
    best, hits = "英语", 0
    for name, hints in LATIN_HINTS.items():
        n = len(words & hints)
        if n > hits:
            best, hits = name, n
    return best if hits else "英语"


POS_WORDS = ["感兴趣", "不错", "可以", "很好", "合作", "下单", "订", "样品寄", "看看样品",
             "interested", "good", "great", "like", "sample", "order", "deal", "ok"]
NEG_WORDS = ["太贵", "贵了", "考虑", "再看看", "不满意", "便宜点", "降价", "别家", "同行",
             "expensive", "high", "cheaper", "discount", "competitor", "maybe", "later"]
SIGNALS = [
    ("询价", ["价格", "多少钱", "报价", "price", "cost", "quote"]),
    ("问交期", ["交期", "多久", "什么时候", "lead time", "delivery", "how long"]),
    ("要样品", ["样品", "sample"]),
    ("谈定制", ["定制", "OEM", "logo", "custom", "印刷"]),
    ("谈付款", ["付款", "账期", "预付", "payment", "T/T", "LC"]),
    ("比价中", ["别家", "同行", "另一家", "competitor", "other supplier"]),
    ("大数量", ["万件", "柜", "批量", "container", "bulk"]),
]


@app.post("/api/insight")
def insight(body: dict):
    text = (body.get("text") or "").strip()
    if not text:
        return {"lang": "中文", "langLabel": "中文", "sentiment": "neutral", "interest": "—", "score": 0,
                "signals": [], "suggestion": "继续介绍产品卖点"}
    lang = detect_lang(text)
    low = text.lower()
    pos = sum(1 for w in POS_WORDS if w in low)
    neg = sum(1 for w in NEG_WORDS if w in low)
    score = max(0, min(100, 50 + 18 * pos - 20 * neg))
    sentiment = "positive" if score >= 65 else ("negative" if score <= 35 else "neutral")
    interest = "高" if score >= 65 else ("低" if score <= 35 else "中")
    signals = [name for name, kws in SIGNALS if any(k.lower() in low for k in kws)]
    if sentiment == "positive":
        sug = "意向高：当场报价并约定下一步（寄样/验厂）"
    elif "询价" in signals and sentiment == "neutral":
        sug = "客户在询价：报可成交价，主动问目标价"
    elif "比价中" in signals:
        sug = "客户在比价：强调交期与品控差异，不放底价"
    elif sentiment == "negative":
        sug = "有异议：先问顾虑（价格/交期/质量），不要急着让价"
    else:
        sug = "继续挖需求：问用途、数量和目标市场"
    rec = {"lang": lang, "langLabel": lang, "sentiment": sentiment, "interest": interest,
           "score": score, "signals": signals, "suggestion": sug, "raw": text, "ts": int(time.time())}
    data.setdefault("convos", []).append(rec)
    save()
    return rec


@app.get("/api/convos")
def list_convos():
    return {"convos": data.get("convos", [])[-50:]}


# ---------- 客户社媒档案 + 风险预警 ----------
# 演示版：按公司名做确定性生成（同一公司每次结果一致），正式版接真实数据源
import hashlib as _hashlib

SOCIAL_TPL = [
    ("LinkedIn",  "linkedin.com/company/{slug}"),
    ("Instagram", "instagram.com/{slug}"),
    ("TikTok",    "tiktok.com/@{slug}"),
    ("官网",       "www.{slug}.com"),
]

RISK_POOL = [
    "过去 12 个月有 1 笔应收逾期 30 天以上",
    "同时比价 3 家以上供应商，压价明显",
    "注册资本与询购量严重不匹配，警惕皮包公司",
    "近 9 个月更换过 1 次中国供应商，有切换意愿",
    "社媒粉丝量远低于其声称的采购规模",
    "主要联系人职位频繁变动，决策链不稳",
]


@app.get("/api/profile")
def profile(name: str = ""):
    name = name.strip() or "未知客户"
    h = _hashlib.md5(name.encode()).hexdigest()
    slug = "".join(ch for ch in name.lower() if ch.isascii() and ch.isalnum()) or ("c" + h[:6])
    n_risk = int(h[0], 16) % 3 + 1          # 1–3 条风险
    risks = [RISK_POOL[(int(h[i], 16) + j * 3) % len(RISK_POOL)] for j, i in enumerate(range(1, 1 + n_risk))]
    level = "B" if n_risk == 1 else ("C" if n_risk == 3 else "B")
    if n_risk == 3 and int(h[2], 16) % 2:
        level = "C"
    if n_risk == 1 and int(h[2], 16) % 3 == 0:
        level = "A"
    level_text = {"A": "A级 · 优质客户，建议重点跟进", "B": "B级 · 中腰部，按标准流程",
                  "C": "C级 · 高风险，谨慎投入"}[level]
    socials = [{"k": k, "v": v.format(slug=slug)} for k, v in SOCIAL_TPL]
    advice = {
        "A": "打法：优先安排二次会谈，可送样，报价给理想价。",
        "B": "打法：按底价 +3% 报价，不主动送样，先确认付款方式。",
        "C": "打法：只给公开价目表，坚持 30% 预付款，不放账期。",
    }[level]
    return {"company": name, "level": level, "levelText": level_text,
            "socials": socials, "risks": risks, "advice": advice}


# ---------- 识别（条码 / 名片门头 OCR）----------
# 演示版：返回确定性样例，正式版接真实 OCR/仓储条码数据
@app.get("/api/ocr")
def ocr(kind: str = "barcode"):
    if kind == "card":
        return {"big": "华信贸易 王建国 采购经理", "sub": "识别结果 · 名片（演示数据）"}
    return {"big": "SKU-CUP-500-SS", "sub": "识别结果 · 条码（演示数据）"}
