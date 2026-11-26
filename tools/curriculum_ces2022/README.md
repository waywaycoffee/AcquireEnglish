# 课标 2022 附录3 词库基准

从《义务教育英语课程标准（2022年版）》**附录3 词汇表**抽取二级 / 三级词表，作为全局合规白名单（非用户生词本）。

## 合规红线

- 可宣传「对标课标 2022 附录3」；**不可**写「官方配套」「教育部授权」等。
- 只入库附录词表字串；**不**入库教学案例 / 范文正文。
- 教材课文（人教等）另作单元表层，不替代本白名单。

## 抽取（本机 OCR，仅附录页）

源 PDF 无文字层时，脚本只对附录3页做 OCR（约 PDF 第 94–139 页），禁止整本 OCR。

```powershell
pip install -r tools/curriculum_ces2022/requirements.txt
python tools/curriculum_ces2022/extract_appendix3.py `
  --pdf "C:\Users\Administrator\Downloads\《义务教育英语课程标准（2022 版）》.pdf"
```

产出（已纳入 git，勿提交 PDF）：

- `services/api/data/curriculum/ces2022/level2_words.csv`（目标约 505）
- `services/api/data/curriculum/ces2022/level3_words.csv`（目标约 1600，含二级词）
- `services/api/data/curriculum/ces2022/manifest.json`

词数允许 ±2% OCR 误差；人工 diff 见 `tmp/ces2022/extract_summary.json`。

## 入库

```powershell
cd services/api
# 本地默认 sqlite；ECS 设置 DATABASE_URL=postgresql+asyncpg://...
python ../../tools/curriculum_ces2022/seed_to_db.py
```

表：

- `curriculum_vocab_words`：`lemma`（unique）/ `surface` / `band`=`level2|level3` / `source`=`ces2022_appendix3` / `version`=`2022`
- `curriculum_vocab_extend`：拓展池（第1期可空）

不改动用户表 `vocab_items`。

## 校验 API

- `GET /api/curriculum/vocab/classify?word=the` → `{ word, tag, band }`
- `POST /api/curriculum/vocab/classify_batch` body `{ "words": ["the","xyzzy"] }`
- `GET /api/curriculum/vocab/stats`

标签规则：`level2` ⊂ 二级；`level3` = 三级且不在二级；`extend` ∈ 拓展池；否则 `out`。

纯函数服务：`app/services/curriculum_vocab.py`（内存索引，供后续阅读 / 口语 prompt 复用）。

## 验收

- CSV 词数接近 505 / 1600，抽样与 PDF 附录一致
- seed 后 `classify(the)` → `level2`；随机造词 → `out`
- ECS API 可调用；CSV 进 git，PDF 不进仓库
