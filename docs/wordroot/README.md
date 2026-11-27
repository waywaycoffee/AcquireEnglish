# 英语词根词缀 + 同根词数据集（v1，中文简化版）

一套自建、结构化、可直接入库的英语构词数据集：**771 条词根词缀 + 2738 个例词 + 2953 条关联记录**。
面向国内学习者（高中／四级／六级／考研）设计，词源统一改写成一句话中文，去掉原始印欧语考据和学术术语。

## 一、文件清单

| 文件 | 内容 | 说明 |
|---|---|---|
| `roots.csv` | 771 行 | 词根／前缀／后缀主表，含中文释义、来源语言、简化词源、难度、例词 |
| `words.csv` | 2738 行 | 例词表，含中文释义、所属词根数量、等级建议 |
| `word_root_rel.csv` | 2953 行 | 词 ↔ 词根 多对多关联，含匹配形式、在词中的位置、词根中文义、整词释义 |
| `roots.db` | SQLite | 同上三张表已建好索引，可直接拷进 App 做离线库 |
| `roots.json` | JSON | 三张表的打包版，方便前端／Flutter 侧直接 import |
| `build_dataset.py` | 脚本 | 从 `data/*.txt` 源文件重建全部产物，改数据后重跑即可 |
| `query_demo.py` | 脚本 | 查词拆解、查同根词、按前缀筛词三条查询的示例实现 |
| `export_json.py` | 脚本 | 把三张 CSV 打包成 `roots.json` |
| `data/*.txt` | 源数据 | 人工整理的源文件（`|` 分隔 9 字段），是唯一需要维护的内容 |

## 二、表结构

```
roots(root_id, root, variants, type, type_cn, cn_meaning, en_gloss,
      source_lang, simple_etym, level, example_count, examples)

words(word, cn_gloss, root_count, root_ids, root_texts, level_suggest, gloss_variants)

word_root_rel(rel_id, word, root_id, root, type_cn, matched_form, position,
              root_cn_meaning, root_sense, word_gloss)
```

字段要点：

- `type`: `root` / `prefix` / `suffix`，分别对应词根、前缀、后缀（113 条后缀覆盖 -tion、-able、-itis、-ectomy、-phobia 等常用与医学后缀；574 条词根含 odont、gastr、carcin、glyc、angi 等希腊语／医学术语用词根）。
- `level`: 高频 / 进阶 两档，按国内考试出现频率人工分级；`words.csv` 的 `level_suggest` 取所属词根里较高的那档，仅作参考。
- `position`: 词首 / 词中 / 词尾，由 `matched_form` 在词中的实际位置回填，做过一致性校验（异常 0 条）。
- `root_cn_meaning`：该词根／词缀本身的中文义，如 `port=拿，运`，用于在单词卡上直接展示构词逻辑。
- `word_gloss`：这个词整体的中文释义，如 `transport=运输`，**不是**词根在该词里的意思。
- `root_sense`：**在 `word_root_rel.csv`（关联表）**，不是 `roots` 主表。含义是「这个词根在当前这个单词里的具体语义」——同一词根在不同词里可以不同（如 port 在 transport≈运送，在 report≈携带信息）。App 两行展示：本词内=`root_sense`（可空）、通用义=`root_cn_meaning`。**禁止**把规则猜测写入 `root_sense`。补写后重跑 `export_full_json.py`。
- **表头勿改**：当前 CSV 表头是  
  `rel_id,word,root_id,root,type_cn,matched_form,position,root_cn_meaning,root_sense,word_gloss`  
  豆包草稿里的 `rel_id,word_id,root_id,root_sense,position,note` **不兼容**本仓库数据，强行切换会导致列错位、全库变空。
- `gloss_variants`: 同一个词在不同词根下释义不一致时保留的备选释义（21 个词），便于人工校正。

## 三、建库方式（AcquireEnglish App）

**推荐：导出离线 JSON → Flutter asset**

```bash
cd docs/wordroot
python3 export_full_json.py
# 生成 roots_full.json，并复制到
# apps/mobile/assets/data/wordroot/roots_full.json
```

App 侧：

- 单词页入口「词根词缀」→ `/words/roots`
- 查词拆解 / 同根词 / 词根反向检索 / 拼写建议：`WordRootCatalog`
- 「加入背词」写入《情景记忆》并进入现有 FSRS 队列（**已删除**独立 `fsrs_memory_api.py`）
- 主学习流自动注入：新学卡 / 复习揭晓后 / 查词弹层 / 词卡详情；设置「自动显示词根拆解」默认开
- 库外单词：形态规则降级，标记 `is_manual: false`，文案提示「仅供参考」

配套文件：

| 文件 | 用途 |
|---|---|
| `query_demo.py` | 三条核心查询示例（拆解 / 同根 / 按类型筛）；需本地 `roots.db` |
| `roots.db.zip` | SQLite 离线库压缩包（解压得 `roots.db`） |
| `roots.json` | 前端友好打包（roots 列表 + words 字典） |
| `roots_full.json` | App 实际加载的紧凑包（含 rels，由 `export_full_json.py` 从 CSV 生成） |

```bash
unzip -o roots.db.zip   # → roots.db
python3 query_demo.py
```

Python 查询脚本：

- `word_query_api.py` → `query_word_detail("transport")`（读 CSV）
- `root_reverse_api.py` → `query_root_words("port")`
- `spell_suggest_api.py` → 拼写建议（依赖 `roots.db` 时需表结构匹配）

CSV 均为 UTF-8 BOM 编码；用 `utf-8-sig` 读取可去掉 BOM。

> App 离线包以 **CSV → `roots_full.json`** 为准（含完整 rel / `root_sense` 字段）。
> `roots.json` / `roots.db` 便于脚本演示；字段略精简，勿与 CSV 行数强行对齐。

## 四、典型查询（对应 App 里的三个核心页面）

1. **查词拆解**：`transport` → `trans(穿过) + port(搬运)`。
2. **同根词**：`port` → transport / export / import / portable / support / report。
3. **按词根学习**：按 `level` 和 `example_count` 排序，取高频词根做每日一组。

对应实现见 `query_demo.py`，可直接跑。

## 五、数据口径与已知局限

1. **词源是简化改写**，不是 Etymonline 原文翻译：只保留"源语言 + 核心义"，例如"拉丁 portare（搬运）"。适合记忆，不适合做词源学研究。
2. **构词归属存在学术分歧**：同一个词可以合理拆到不同词根（如 `biology` 可拆 bio + logy，也可算 -ology 后缀），本库按"对记忆最有用"的原则取一种，不追求唯一正确。
3. **等级是经验分级**，不是严格按词表统计，建议按你的题库再校准。
4. **例词覆盖 2738 个**，以考试高频词为主，长尾专业词（医学、法律）覆盖有限。
5. 少数字段（如 `damage` 归 `dam`）材料本身有争议，已在 `gloss_variants` 里留了痕迹，建议上线前抽检 10%。

## 六、版权与商用

本数据集为**按公开词根常识自建整理**，未抓取趣词、Etymonline、培根词汇等站的页面内容，因此不继承它们的授权限制，可自由修改、商用。

但请注意：词根释义本身属于公共知识，而**具体词条的组织方式、例词选择、中文表述**由你决定，如果你后续用 LLM 批量扩充，建议在 README 里保留"生成 + 人工抽检"的记录，便于应对应用商店的内容合规问询。

## 七、扩充到更多词条

维护只在 `data/*.txt` 里做，每行一条：

```
主形|异形|类型|中文义|英文义|来源语言|简化词源|难度|例词(word=中文,...)
```

改完执行：

```bash
python3 build_dataset.py
```

会自动重算 `example_count`、位置字段、去重、合并多词根词，并重建 `roots.db` 和 CSV。

> （注：部分内容由豆包 AI 生成）