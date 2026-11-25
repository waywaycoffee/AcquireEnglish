【README.md】

# 爱快英语 K12 时文生成流水线

用 DeepSeek 批量生成 K12 英语时文 JSON，自动校验后交由人工审核，再导入 MySQL，对接双工数字人。

## 文件清单

- `prompt_template.txt` 定义提示词、命题规范和 JSON 结构。
- `batch_generator.py` 调用 DeepSeek，内置初中和高中各 8 个主题。
- `validator.py` 检查 JSON 并输出 `review_report.csv`。
- `mysql_import.py` 批量导入审核后的 JSON。
- `schema.sql` 定义 MySQL 的文章、试题、生词和长难句表。

## 内容契约

初中 220–280 词，高中 300–360 词。题序固定为主旨大意、细节事实、推理判断、词义猜测或作者态度。四题均有 A/B/C/D 选项、答案和解析。解析引用原文定位句并说明各选项正误。

JSON 包含 `article`、`questions`、`word_list`、`long_sentences` 和 `digital_human`。生成脚本补充 `level`。数字人读取 `digital_human.topic_name` 和含 3 条英文口语问题的 `digital_human.question_list`。导入后分别存入文章表的 `topic_name` 和 `digital_human_questions`。

## 生成与审校

使用 Python 3.9 或更高版本。在当前终端环境设置 `DEEPSEEK_API_KEY`，或在 `reading_generator/.env` 写入 `DEEPSEEK_API_KEY=实际密钥`。终端环境优先。可选用 `DEEPSEEK_MODEL` 覆盖默认的 `deepseek-flash`。接口启用 JSON 输出。在项目根目录运行以下命令，先单篇验证。 [DeepSeek JSON 输出文档](https://api-docs.deepseek.com/guides/json_mode/)

```bash
python3 reading_generator/batch_generator.py --limit 1
python3 reading_generator/validator.py
```

移除 `--limit 1` 即可运行全部主题。生成文件位于 `reading_generator/ik_english_reading/`。审校报告位于 `reading_generator/review_report.csv`。根据报告筛选结构校验通过的文件，人工核对考纲词汇、原创性、题型与答案、原文定位和数字人提问，再将审核通过的 JSON 汇总到导入目录。

## 导入

在目标 MySQL 中先创建 `ik_english` 数据库并执行 `schema.sql`。安装 PyMySQL，通过 `MYSQL_HOST`、`MYSQL_PORT`、`MYSQL_USER`、`MYSQL_PASSWORD` 和 `MYSQL_DATABASE` 配置连接。

```bash
python3 -m pip install PyMySQL
mysql -u root -p ik_english < reading_generator/schema.sql
python3 reading_generator/mysql_import.py /path/to/reviewed-json
```

每篇文章及其从表数据在同一事务中提交，按约定入库为 `ai_original` 和 `pending`。重复运行导入会新增文章记录。

## 全年级 ECS 主题阅读

`generate_grades.py` 按 `grades.py` 的 12 个年级生成首批各一篇（小学一年级至高三），独立校验篇幅、试题及数字人字段，失败最多重试 6 次，已通过的文件可断点复用。当前主题为原创校园生活材料，不宣称为有新闻来源的实时报道。结构校验不代表人工内容审校。

在 ECS 配置 `K12_OUTPUT_DIR=/opt/acquireenglish/services/api/media/reading/k12` 后运行 `python3 reading_generator/generate_grades.py`。密钥复用 API `.env`，不输出密钥。输出包含 `grade_id`，按年级保存 JSON，原子更新 `catalog.json`，App 的 K12 年级书架按该字段筛选，仅显示通过校验的内容。所有文本从 ECS 下载；本流程不生成或打包音视频。完整题目、词汇、句式与数字人问题保留在 JSON，当前书架打开正文进入现有阅读器。

验证：`python3 -m unittest discover -s reading_generator -p test_grades.py`。

## 全年级审校与官方资料发布

在 ECS 运行 `python3 reading_generator/review_grades.py`，对现有 12 篇逐篇进行 AI 编辑审校：修订语法、年级难度、题型、答案唯一性和中文解析，验证篇幅及讲解句逐字来自正文。修订结果存入 ECS `reading/k12/official/<grade_id>.json`，保留原稿，支持断点继续。仅在全部 12 年级通过后原子替换线上目录，并输出 `official/review_report.json`。官方资料指爱快英语自有资料，保留 `source_type=ai_original`、`review_status=ai_reviewed`，不冒充官方考试真题或真实新闻。App 年级书架仅展示相应集合内已审校文章。

首批 12 篇已在 AI 审校后逐篇由代理复核修订：二年级节水文简化，四年级冠词修正，五年级场景与题目去歧义，中学统一主旨/细节/推理/词义或态度题序，并修正太阳能储能用语和城市鸟类保护的无来源引述。线上 `review_method` 记录 AI 审校与代理编辑，保留 AI 来源标记。发布内容与审校报告在 ECS，不随 APK 打包、不提交生成 JSON。
