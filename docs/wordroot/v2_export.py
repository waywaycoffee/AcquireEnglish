#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 v1 数据（roots.csv/words.csv/word_root_rel.csv）转成 App 侧统一 schema，并写入 root_sense。

输出目录 app_data/：
  roots.csv            词根词缀主表
  words.csv            单词表
  word_root_rel.csv    关联表（含 root_sense 与来源标记）
  roots_v2.db          SQLite

root_sense 口径：
  - root_sense        ：该词根**在这个单词里**承担的含义
  - root_sense_source ：manual = 人工判定；derived = 由词根通用义规则推导（前端只按"通用义"展示）
"""
import csv
import os
import sqlite3

BASE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(BASE, "app_data")
os.makedirs(OUT, exist_ok=True)

LEVEL_MAP = {"高频": "core", "进阶": "advanced"}
TYPE_MAP = {"root": "root", "prefix": "prefix", "suffix": "suffix"}

# ---------- 人工判定：词根在某词中的实际含义（高频词优先） ----------
from manual_senses import extra_sense

MANUAL = {
    ("transport", "trans"): "穿过", ("transport", "port"): "搬运",
    ("import", "im"): "向内", ("import", "port"): "运入",
    ("export", "ex"): "向外", ("export", "port"): "运出",
    ("portable", "port"): "携带", ("portable", "able"): "可…的",
    ("support", "port"): "承载",
    ("report", "re"): "回", ("report", "port"): "带来（消息）",
    ("passport", "port"): "关口",
    ("inspect", "in"): "向内", ("inspect", "spect"): "看",
    ("respect", "re"): "再次", ("respect", "spect"): "看（看重）",
    ("suspect", "spect"): "看（审视）",
    ("prospect", "pro"): "向前", ("prospect", "spect"): "看",
    ("submit", "sub"): "向下", ("submit", "mit"): "送出",
    ("emit", "mit"): "发送", ("permit", "mit"): "放行",
    ("admit", "mit"): "送入", ("transmit", "trans"): "穿过", ("transmit", "mit"): "传送",
    ("commit", "mit"): "交付", ("dismiss", "miss"): "送走", ("missile", "miss"): "投掷",
    ("visible", "vis"): "看见", ("visible", "in"): "否定",
    ("vision", "vis"): "视觉", ("television", "vis"): "观看",
    ("supervise", "super"): "在上", ("supervise", "vis"): "看",
    ("advise", "vis"): "看（看法）",
    ("conduct", "con"): "共同", ("conduct", "duct"): "引导",
    ("produce", "pro"): "向前", ("produce", "duc"): "引出",
    ("reduce", "re"): "回", ("reduce", "duc"): "引导（降）",
    ("introduce", "duc"): "引导", ("educate", "duc"): "引导",
    ("preview", "pre"): "预先", ("preview", "vis"): "看",
    ("postpone", "post"): "之后", ("postpone", "pon"): "放置",
    ("compose", "pos"): "放置", ("position", "pos"): "放置",
    ("deposit", "pos"): "放置", ("expose", "pos"): "放置", ("propose", "pos"): "放置",
    ("geography", "geo"): "大地", ("geography", "graph"): "书写",
    ("biology", "bio"): "生命", ("biology", "log"): "学说",
    ("biography", "bio"): "生命", ("biography", "graph"): "记录",
    ("democracy", "dem"): "人民", ("democracy", "crat"): "统治",
    ("telephone", "tele"): "远", ("telephone", "phon"): "声音",
    ("chronic", "chron"): "时间", ("chronology", "chron"): "时间",
    ("manual", "manu"): "手", ("manufacture", "manu"): "手", ("manufacture", "fact"): "做",
    ("aquarium", "aqu"): "水", ("aquatic", "aqu"): "水",
    ("audience", "aud"): "听", ("audio", "aud"): "听",
    ("century", "cent"): "百", ("percent", "cent"): "百",
    ("bicycle", "bi"): "二", ("bicycle", "circ"): "轮",
    ("dictate", "dict"): "说", ("dictionary", "dict"): "说",
    ("predict", "pre"): "预先", ("predict", "dict"): "说",
    ("contradict", "contra"): "相反", ("contradict", "dict"): "说",
    ("confer", "con"): "共同", ("confer", "fer"): "带来",
    ("transfer", "trans"): "转移", ("transfer", "fer"): "携带",
    ("refer", "re"): "回", ("offer", "fer"): "带来", ("differ", "fer"): "带（相异）",
    ("reform", "re"): "再", ("reform", "form"): "形状",
    ("uniform", "uni"): "一", ("uniform", "form"): "形状",
    ("inform", "form"): "形成（告知）", ("transform", "form"): "形状", ("conform", "form"): "形状",
    ("telegram", "tele"): "远", ("telegram", "gram"): "写",
    ("photograph", "photo"): "光", ("photograph", "graph"): "记录",
    ("judge", "jur"): "法", ("justice", "jur"): "法", ("injury", "jur"): "法（公正）",
    ("collect", "col"): "共同", ("collect", "lect"): "选",
    ("select", "lect"): "选", ("elect", "lect"): "选", ("lecture", "lect"): "读",
    ("local", "loc"): "地方", ("locate", "loc"): "地方",
    ("inspire", "spir"): "呼吸", ("spirit", "spir"): "呼吸",
    ("expire", "ex"): "出", ("expire", "spir"): "呼吸",
    ("conspiracy", "spir"): "呼吸（同气）",
    ("structure", "struct"): "建造", ("construct", "struct"): "建造", ("instruct", "struct"): "建造",
    ("contact", "tact"): "触摸", ("tactile", "tact"): "触",
    ("contain", "tain"): "握住", ("maintain", "tain"): "握住", ("retain", "tain"): "握住",
    ("continue", "tin"): "保持",
    ("terminal", "termin"): "界限", ("determine", "termin"): "界限",
    ("territory", "terr"): "土地", ("terrain", "terr"): "土地",
    ("thermometer", "therm"): "热", ("thermometer", "meter"): "测量",
    ("attract", "at"): "向", ("attract", "tract"): "拉",
    ("abstract", "abs"): "离开", ("abstract", "tract"): "拉",
    ("contract", "con"): "共同", ("contract", "tract"): "拉",
    ("extract", "ex"): "出", ("extract", "tract"): "拉",
    ("distract", "dis"): "分开", ("distract", "tract"): "拉",
    ("urban", "urb"): "城市", ("suburb", "urb"): "城市",
    ("vacuum", "vac"): "空", ("vacant", "vac"): "空", ("vacation", "vac"): "空（空闲）",
    ("value", "val"): "价值", ("valid", "val"): "强", ("prevail", "val"): "强", ("evaluate", "val"): "价值",
    ("convene", "ven"): "来", ("prevent", "ven"): "来", ("invent", "ven"): "来",
    ("intervene", "ven"): "来", ("event", "ven"): "来",
    ("convert", "con"): "完全", ("convert", "vert"): "转",
    ("divert", "di"): "分开", ("divert", "vert"): "转",
    ("reverse", "vert"): "转", ("universe", "uni"): "一", ("universe", "vert"): "转",
    ("survive", "viv"): "活", ("revive", "viv"): "活", ("vivid", "viv"): "活",
    ("evolve", "volv"): "滚", ("involve", "volv"): "滚", ("revolution", "volv"): "转",
    ("incredible", "in"): "不", ("incredible", "cred"): "相信", ("credit", "cred"): "相信",
    ("cognition", "cogn"): "知道", ("recognize", "cogn"): "知道",
    ("cordial", "cord"): "心", ("accord", "cord"): "心", ("discord", "cord"): "心",
    ("corporation", "corpor"): "团体", ("corpse", "corpor"): "身体",
    ("create", "cre"): "生长", ("increase", "cre"): "生长", ("concrete", "cre"): "生长",
    ("criterion", "crit"): "判断",
    ("current", "cur"): "跑", ("occur", "cur"): "跑", ("excursion", "cur"): "跑",
    ("defect", "fact"): "做", ("perfect", "fact"): "做", ("effect", "fact"): "做",
    ("efficient", "fic"): "做", ("factory", "fact"): "做",
    ("defend", "fend"): "打击", ("offend", "fend"): "打击",
    ("final", "fin"): "结束", ("define", "fin"): "界限", ("infinite", "fin"): "界限", ("confine", "fin"): "界限",
    ("confirm", "firm"): "坚固", ("affirm", "firm"): "坚固",
    ("flexible", "flex"): "弯曲", ("reflect", "flect"): "弯曲",
    ("conflict", "flict"): "打击", ("inflict", "flict"): "打击",
    ("influence", "flu"): "流", ("fluent", "flu"): "流", ("fluid", "flu"): "流",
    ("fragment", "frag"): "破", ("fracture", "fract"): "破", ("fragile", "frag"): "易破",
    ("fraction", "fract"): "破（部分）",
    ("refuge", "fug"): "逃", ("refugee", "fug"): "逃", ("fugitive", "fug"): "逃",
    ("refuse", "fus"): "倾倒", ("confuse", "fus"): "混（流）", ("transfusion", "fus"): "灌",
    ("generate", "gen"): "产生", ("genius", "gen"): "天生", ("generous", "gen"): "出身（慷慨）",
    ("suggest", "gest"): "带", ("digest", "gest"): "带（消化）", ("congest", "gest"): "带",
    ("grade", "grad"): "步", ("gradual", "grad"): "步",
    ("progress", "gress"): "走", ("aggressive", "gress"): "走", ("congress", "gress"): "走",
    ("gravity", "grav"): "重", ("grave", "grav"): "重", ("aggravate", "grav"): "重",
    ("adhere", "hes"): "粘", ("coherent", "hes"): "粘", ("hesitate", "hes"): "粘（犹豫）",
    ("inherent", "hes"): "粘",
    ("heterogeneous", "hetero"): "异", ("homogeneous", "homo"): "同",
    ("hypothesis", "hypo"): "在下", ("hypothesis", "thes"): "放置",
    ("hyperactive", "hyper"): "过度", ("hypertension", "hyper"): "过度",
    ("interact", "inter"): "之间", ("interrupt", "inter"): "之间", ("interrupt", "rupt"): "破",
    ("intravenous", "intra"): "内", ("introvert", "vert"): "转",
    ("microscope", "micro"): "小", ("microscope", "scope"): "看",
    ("mistake", "mis"): "错", ("misunderstand", "mis"): "错",
    ("monologue", "mono"): "单", ("monopoly", "mono"): "单", ("monotone", "mono"): "单",
    ("multiply", "multi"): "多", ("multimedia", "multi"): "多",
    ("neoclassical", "neo"): "新", ("nonprofit", "non"): "不",
    ("panorama", "pan"): "全", ("pandemic", "pan"): "全", ("pandemic", "dem"): "人民",
    ("parallel", "para"): "旁", ("paradox", "para"): "旁（反常）",
    ("parasite", "para"): "旁", ("paralysis", "para"): "旁", ("paralysis", "lysis"): "松（瘫）",
    ("persist", "sist"): "站", ("permanent", "per"): "彻底", ("permanent", "man"): "停留",
    ("perimeter", "peri"): "周围", ("perimeter", "meter"): "测量",
    ("polygon", "poly"): "多", ("polygon", "gon"): "角", ("polymer", "poly"): "多",
    ("prototype", "proto"): "原始", ("protocol", "proto"): "原始",
    ("pseudoscience", "pseudo"): "假",
    ("retrospect", "retro"): "向后", ("retrospect", "spect"): "看",
    ("semicircle", "semi"): "半", ("semiconductor", "semi"): "半",
    ("superior", "super"): "上", ("supermarket", "super"): "上",
    ("sympathy", "sym"): "共同", ("sympathy", "path"): "感受",
    ("symphony", "sym"): "共同", ("symphony", "phon"): "声音",
    ("synchronize", "syn"): "共同", ("synchronize", "chron"): "时间",
    ("synonym", "syn"): "共同", ("synonym", "onym"): "名",
    ("telescope", "tele"): "远", ("telescope", "scope"): "看",
    ("ultrasonic", "ultra"): "超",
    ("undergo", "under"): "下", ("underground", "under"): "下", ("underestimate", "under"): "不足",
    ("action", "act"): "做", ("react", "act"): "做", ("agent", "ag"): "做",
    ("agenda", "ag"): "做", ("exact", "act"): "做（精确）", ("activate", "act"): "做",
    ("active", "act"): "做", ("activity", "act"): "做",
    ("natural", "nat"): "天生", ("nature", "nat"): "天生", ("native", "nat"): "出生",
    ("nation", "nat"): "出生（民族）",
    ("accuracy", "cur"): "关心",
    ("kingdom", "dom"): "领域", ("freedom", "dom"): "领域",
    ("efficiency", "fic"): "做",
    ("bookish", "ish"): "略带", ("reddish", "ish"): "略带",
    ("actress", "ess"): "女性",
    ("leaflet", "let"): "小", ("streamlet", "let"): "小",
    ("twofold", "fold"): "倍",
    ("childhood", "hood"): "身份", ("neighborhood", "hood"): "身份",
    ("physics", "phys"): "自然",
    ("magnify", "magn"): "大", ("magnify", "ify"): "使", ("clarify", "clar"): "清楚", ("clarify", "ify"): "使",
    ("simplify", "ify"): "使",
    ("capitalism", "ism"): "主义",
    ("gratitude", "itude"): "状态",
    ("laboratory", "ory"): "场所",
    ("poisonous", "ous"): "充满",
    ("friendship", "ship"): "关系",
    ("tiresome", "some"): "易于",
    ("acceptable", "able"): "可…的",
}

# 高频但上面没覆盖的通用派生词根，按"取词根通用义第一义位"派生
def derive_sense(cn_meaning: str) -> str:
    for sep in ("；", ";", "、", "，", "/"):
        if sep in cn_meaning:
            return cn_meaning.split(sep)[0].strip()
    return cn_meaning.strip()


def main():
    roots = list(csv.DictReader(open(os.path.join(BASE, "roots.csv"), encoding="utf-8-sig")))
    rels = list(csv.DictReader(open(os.path.join(BASE, "word_root_rel.csv"), encoding="utf-8-sig")))

    # roots
    root_id_map = {}
    out_roots = []
    for i, r in enumerate(roots, start=1):
        rid = f"r{i:04d}"
        root_id_map[r["root_id"]] = rid
        alt = ",".join([v.strip().strip("-") for v in r["variants"].split(",")
                        if v.strip() and v.strip().strip("-") != r["root"].strip().strip("-")])
        out_roots.append({
            "root_id": rid,
            "root_text": r["root"].strip().strip("-"),
            "root_alt": alt,
            "cn_meaning": r["cn_meaning"],
            "lang": r["source_lang"],
            "short_etym": r["simple_etym"],
            "type": TYPE_MAP.get(r["type"], r["type"]),
            "level": LEVEL_MAP.get(r["level"], r["level"]),
        })

    # words 聚合
    word_map = {}
    for r in rels:
        w = r["word"]
        if w not in word_map:
            word_map[w] = {"gloss": r["word_gloss"], "roots": [], "root_levels": []}
        word_map[w]["roots"].append(r["root_id"])
    root_level = {r["root_id"]: r["level"] for r in roots}
    out_words = []
    word_id_map = {}
    for i, (w, rec) in enumerate(sorted(word_map.items()), start=1):
        wid = f"w{i:04d}"
        word_id_map[w] = wid
        lv = "advanced" if any(root_level.get(x) == "进阶" for x in rec["roots"]) else "core"
        out_words.append({"word_id": wid, "word": w, "cn_def": rec["gloss"],
                          "word_level": lv, "_roots": rec["roots"]})

    # rels
    out_rels = []
    for i, r in enumerate(rels, start=1):
        key = (r["word"], r["root"].strip().strip("-"))
        if key in MANUAL:
            sense, src = MANUAL[key], "manual"
        else:
            _rt = r["root"].strip().strip("-")
            _extra = extra_sense(r["word"], root_id_map[r["root_id"]], _rt)
            if _extra:
                sense, src = _extra, "manual"
            else:
                sense, src = derive_sense(r["root_cn_meaning"]), "derived"
        out_rels.append({
            "rel_id": f"rel{i:05d}",
            "word_id": word_id_map[r["word"]],
            "root_id": root_id_map[r["root_id"]],
            "root_sense": sense,
            "root_sense_source": src,
            "form": r["matched_form"],
            "position": {"词首": "head", "词中": "middle", "词尾": "tail"}.get(r["position"], "middle"),
            "note": f'{r["word"]} = {r["matched_form"]} ({sense})',
        })

    # 写 CSV
    def dump(name, cols, rows):
        with open(os.path.join(OUT, name), "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=cols)
            w.writeheader()
            for row in rows:
                w.writerow({k: row[k] for k in cols})

    dump("roots.csv", ["root_id", "root_text", "root_alt", "cn_meaning", "lang",
                       "short_etym", "type", "level"], out_roots)
    dump("words.csv", ["word_id", "word", "cn_def", "word_level"], out_words)
    dump("word_root_rel.csv", ["rel_id", "word_id", "root_id", "root_sense",
                               "root_sense_source", "form", "position", "note"], out_rels)

    # SQLite
    db = os.path.join(OUT, "roots_v2.db")
    if os.path.exists(db):
        os.remove(db)
    con = sqlite3.connect(db)
    cur = con.cursor()
    cur.executescript("""
    CREATE TABLE roots(root_id TEXT PRIMARY KEY, root_text TEXT, root_alt TEXT,
      cn_meaning TEXT, lang TEXT, short_etym TEXT, type TEXT, level TEXT);
    CREATE TABLE words(word_id TEXT PRIMARY KEY, word TEXT UNIQUE, cn_def TEXT, word_level TEXT);
    CREATE TABLE word_root_rel(rel_id TEXT PRIMARY KEY, word_id TEXT, root_id TEXT,
      root_sense TEXT, root_sense_source TEXT, form TEXT, position TEXT, note TEXT);
    CREATE INDEX idx_rel_word ON word_root_rel(word_id);
    CREATE INDEX idx_rel_root ON word_root_rel(root_id);
    CREATE INDEX idx_word ON words(word);
    """)
    cur.executemany("INSERT INTO roots VALUES(?,?,?,?,?,?,?,?)",
                    [[r[k] for k in ["root_id", "root_text", "root_alt", "cn_meaning", "lang",
                                     "short_etym", "type", "level"]] for r in out_roots])
    cur.executemany("INSERT INTO words VALUES(?,?,?,?)",
                    [[r[k] for k in ["word_id", "word", "cn_def", "word_level"]] for r in out_words])
    cur.executemany("INSERT INTO word_root_rel VALUES(?,?,?,?,?,?,?,?)",
                    [[r[k] for k in ["rel_id", "word_id", "root_id", "root_sense",
                                     "root_sense_source", "form", "position", "note"]] for r in out_rels])
    con.commit()
    con.close()

    manual = sum(1 for r in out_rels if r["root_sense_source"] == "manual")
    print(f"roots={len(out_roots)} words={len(out_words)} rels={len(out_rels)} "
          f"manual={manual} derived={len(out_rels)-manual}")


if __name__ == "__main__":
    main()
#（注：内容由AI生成）
