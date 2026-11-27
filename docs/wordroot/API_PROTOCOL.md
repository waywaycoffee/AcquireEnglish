# 词根词缀模块 · 前端数据协议（Flutter / 爱快英语）

本文档规定词根模块怎么给前端供数、前端怎么展示、哪些文案不能写。
对应实现：`app_api/english_api.py`，数据：`app_data/`。

---

## 0. 三条硬约束

> 当前库 2953 条关联全部是 `manual`，即每个词根在该词中的具体义都已人工判定。`derived` 分支保留给后续新增词兜底。

1. **只有 `sense_source = manual` 才可以说"这个词里 port=搬运"**。`derived` 只是把词根通用义切了一个义位，不能冒充"该词中的具体义"。
2. **规则推测（`is_manual = false`）永远不许进库、不许当标注结果展示**，只能作为带提示的临时拆解。
3. **复习调度只走项目既有 FSRS**。本模块只负责"讲清楚这个词是怎么构成的"，并提供"加入复习队列"的入口，不自己算间隔。

---

## 1. 数据来源

| 文件 | 用途 | 加载时机 |
|---|---|---|
| `app_data/roots_app.json` | 前端离线包（roots + words，含每个词的 roots 关联） | App 首次启动后后台加载，约 760 KB |
| `app_data/roots_v2.db` | Python 侧查询库（服务端/本地脚本） | 服务端随服务启动 |
| `app_data/roots.csv` / `words.csv` / `word_root_rel.csv` | 源数据，改数据用 | 编辑时 |

`roots_app.json` 结构：

```json
{
  "meta": {"name": "英语词根词缀库 v2", "roots": 771, "words": 2738, "rels": 2953, "root_sense_manual": 2953},
  "roots": [
    {"root_id": "r0292", "root_text": "port", "root_alt": "", "cn_meaning": "拿，运；港口",
     "lang": "拉丁", "short_etym": "portare 搬运", "type": "root", "level": "core"}
  ],
  "words": [
    {"word_id": "w2575", "word": "transport", "cn_def": "运输", "word_level": "core",
     "roots": [{"root_id": "r0101", "root_text": "trans", "form": "trans", "cn_meaning": "穿过，转变",
                "root_sense": "穿过", "root_sense_source": "manual", "position": "head"}]}
  ]
}
```

字段字典：

| 字段 | 取值 | 说明 |
|---|---|---|
| `type` | `root` / `prefix` / `suffix` | 词根 / 前缀 / 后缀 |
| `level` | `core` / `advanced` | 词根难度档，仅用于排序和角标 |
| `form` | 字符串 | 该词里实际出现的形态，例如 impossible 显示 `im` 而不是词根主形 `il`；展示时用它，别用 root_text |
| `position` | `head` / `middle` / `tail` | 该词根在单词里的位置 |
| `root_sense` | 字符串 | 词根在该词中承担的含义（可能是推导值） |
| `root_sense_source` | `manual` / `derived` | 语义来源，决定前端怎么措辞 |

---

## 2. 服务端接口

```python
from english_api import query_word, query_root, spell_suggest, guess_affix
```

### 2.1 `query_word(word) -> dict`

```json
{
  "ok": true,
  "word_id": "w2575",
  "word": "transport",
  "cn_def": "运输",
  "word_level": "core",
  "is_manual": true,
  "parse": [
    {"root_id": "r0101", "root_text": "trans", "root_alt": "tran", "form": "trans", "type": "prefix",
     "position": "head", "sense": "穿过", "sense_label": "本词义", "sense_source": "manual"},
    {"root_id": "r0292", "root_text": "port", "root_alt": "", "form": "port", "type": "root",
     "position": "tail", "sense": "搬运", "sense_label": "本词义", "sense_source": "manual"}
  ],
  "same_root_words": [
    {"word": "export", "cn_def": "出口", "word_level": "core", "via_root": "port"}
  ]
}
```

查不到时：

```json
{"ok": false, "word": "brexitish", "reason": "not_found", "suggest": [...], "parse": [], "same_root_words": []}
```

有词条但无标注时，额外带：

```json
{"guess": {"ok": true, "is_manual": false, "confidence": "low",
           "segments": [{"segment": "hyper", "type": "prefix", "cn_meaning": "超过，过度", "position": "head"}],
           "stem": "reactiv", "warning": "规则推测，未人工校验，仅作提示"},
 "warning": "该词暂无词根标注，以下为规则推测，仅供参考"}
```

### 2.2 `query_root(root_text, level=None)`

```json
{"ok": true,
 "root": {"root_id": "r0292", "root_text": "port", "cn_meaning": "拿，运；港口", "type": "root", "level": "core"},
 "count": 5,
 "words": [{"word": "export", "cn_def": "出口", "word_level": "core", "sense": "运出", "sense_source": "manual"}]}
```

### 2.3 `spell_suggest(word)` / 2.4 `guess_affix(word)`

`spell_suggest` 返回 `{ok, input, candidates[{word,cn_def,word_level,distance}]}`，供"查词失败"兜底。
`guess_affix` 只做前后缀切分，返回 `is_manual=false`，禁止写库。

---

## 3. 四个接入点（组件契约）

### 3.1 每日背词卡片（主链路，最高优先）

卡片正面只放单词 + 释义 + 发音；**背面/展开区**放词根面板，默认收起。

```
[展开] 词根拆解  trans(穿过) + port(搬运)
        同根词  export / import / support / portable   [查看更多]
```

- 命中 `parse` 且 `is_manual=true` → 正常展示
- 命中 `parse` 但全是 `derived` → 每行后缀统一打「通用义」小灰标，标题写"词根构成"而不是"词义拆解"
- `parse` 为空 → 不显示面板（不要塞猜测结果到背词卡片里，会干扰记忆）

### 3.2 阅读点词弹窗（时文 / 绘本）

生词弹窗三个 Tab：`释义` / `词根` / `例句`。`词根` Tab 直接渲染 `query_word` 返回。

- `ok=false` 且 `suggest` 非空 → 顶部提示"没找到该词，是否查：transport / transmit"

### 3.3 视频字幕查词

与 3.2 共用同一弹窗组件、同一接口，不做第二套逻辑。

### 3.4 单词详情页 / 词根词典页

- 单词页：固定词根模块 + 同根词列表 + 「加入复习队列」按钮
- 词根词典页：`query_root(root_text)`，按 `word_level` 分组（core → advanced），点击进入单词页

---

## 4. 文案规则（照抄可避免误导）

| 数据情况 | 允许文案 | 禁止文案 |
|---|---|---|
| `sense_source = manual` | "port 在这里是**搬运**" / "trans(穿过) + port(搬运)" | — |
| `sense_source = derived` | "port 的词根义是**运、搬**" / 角标「通用义」 | "port 在这个词里是…" |
| `is_manual = false`（规则推测） | "按常见词缀推测：hyper-（过度）+ -ity（名词后缀）" + 灰色提示 | 任何形式的确定性拆解 |

`root_sense` 为空时直接不渲染该行，不要显示 "undefined" 或空白括号。

---

## 5. 与既有 FSRS 的边界

- 词根模块**不提供**任何 `schedule / due / stability` 逻辑，也不建卡片表。
- 「加入复习队列」按钮 → 调项目现有 FSRS 的 add 接口（入参：`word_id`，可选 `source=root_module` 便于埋点）。
- 同根词批量加入时逐个调用主 FSRS，进度与主流程共用一套。

---

## 6. 性能与降级

1. App 启动后后台加载 `roots_app.json`，建 `Map<word, WordEntry>` 与 `Map<root_id, RootEntry>` 两个内存索引，查词不走 IO。
2. 服务端 `roots_v2.db` 已建 `idx_word`、`idx_rel_word`、`idx_rel_root`，单次查询毫秒级；建议上层加 LRU（容量 1000）。
3. `spell_suggest` 是全表编辑距离，2738 词规模可接受；词库过万后加首字母分桶或 BK-tree。
4. 词根面板只在用户展开时请求，避免列表页批量渲染。

---

## 7. 埋点建议

| 事件 | 参数 |
|---|---|
| `root_panel_expand` | word_id, entry(scene: reciting/reading/subtitle/detail), manual_rate |
| `root_word_click` | from_word_id, to_word, via_root |
| `root_to_fsrs` | word_id, count(同根词批量数) |
| `affix_guess_show` | word, confidence, is_manual(false) |

用于评估"词根模块是否真的帮到记忆"：对比开启/关闭词根面板的用户 7 日留存与复习通过率。

> （注：部分内容由豆包 AI 生成）