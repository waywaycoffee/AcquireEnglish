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
