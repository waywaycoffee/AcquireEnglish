"""Review the complete K12 batch, retaining drafts and explicit AI provenance."""
import json
import os
from pathlib import Path
from datetime import datetime, timezone
from generate_grades import GRADES, call_llm, validate_one

ROOT = Path(os.environ.get('K12_OUTPUT_DIR', '/opt/acquireenglish/services/api/media/reading/k12'))

def review():
    reviewed = ROOT / 'official'
    reviewed.mkdir(parents=True, exist_ok=True)
    articles = []
    for grade_id, grade in GRADES.items():
        source = json.loads((ROOT / f'{grade_id}.json').read_text())
        path = reviewed / f'{grade_id}.json'
        if path.exists():
            candidate = json.loads(path.read_text())
        else:
            low, high = grade['bounds']
            prompt = f'''你是英语教材责任编辑。逐篇审校并直接返回修订后的完整阅读JSON，保留原结构，仅输出JSON。
questions必须恰好4题，q_no为1至4，options为A/B/C/D。
目标{grade['name']}，grade_id={grade_id}，level={grade['name']}，正文严格{low}–{high}个空格分隔词。
检查英语语法、自然表达、年龄适切性、全文逻辑、科学常识、答案唯一性与干扰项、中文讲解、词汇音标与释义、两条句子讲解、三条数字人口语提问。
必须修订已知问题：a old card改an old card；小学二年级避免endless和infer等超龄命题，用具体短句与简短细节问题；帮助花朵生长应准确说明蜜蜂传播花粉；步行上学题不能有多个原文支持选项；鸟类保护去掉无出处的Studies show，不把铃铛当成可靠保护措施，不引导儿童接触野生鸟；太阳能battery stores energy，非saves power。
初中、高中四题顺序固定：主旨、细节、真正一步推理（不能照抄原文）、词义或作者态度。小学采用简单细节、主旨、具体词义，低年级可中文辅助。每题解释四个选项为什么对错，并引用完整准确的原文句子。
高三不要用“未提到学生用环保袋”这种学生也可能属于家庭的含混否定题；问题若提最后一句，解析须对应最后一句。高中增加适度句式复杂度但不增加超纲术语。
文章必须以原创示例故事或一般知识呈现，不冒充有新闻来源的真实报道，不虚构研究数据，保留article.title与title_zh。
word_list最多3项，long_sentences恰好2项且sentence必须逐字来自修订后正文。question_list恰好3条英文问题。
待审JSON：''' + json.dumps(source, ensure_ascii=False)
            feedback = ''
            for attempt in range(6):
                try:
                    candidate = json.loads(call_llm(prompt + feedback))
                except (ValueError, RuntimeError) as exc:
                    print(grade_id, 'retry', attempt+1, type(exc).__name__, flush=True)
                    feedback = '\n上次输出无效，请只返回完整合法JSON，questions恰好4题。'
                    continue
                candidate['grade_id'] = grade_id
                candidate['level'] = grade['name']
                candidate['article']['word_count'] = len(candidate['article']['passage'].split())
                errors = validate_one(candidate)
                for sentence in candidate.get('long_sentences', []):
                    if sentence['sentence'] not in candidate['article']['passage']:
                        errors.append('句子讲解必须逐字引用原文')
                if not errors:
                    break
                print(grade_id, 'retry', attempt+1, '；'.join(errors), flush=True)
                feedback = '\n本次输出错误：' + '；'.join(errors) + '\n请在下面这版上修正，避免重新扩写：' + json.dumps(candidate, ensure_ascii=False)
            else:
                raise RuntimeError(f'{grade_id} review failed')
            candidate['source_type'] = 'ai_original'
            candidate['publisher'] = '爱快英语'
            candidate['collection'] = 'official_k12_reading'
            candidate['review_status'] = 'ai_reviewed'
            candidate['reviewed_at'] = datetime.now(timezone.utc).isoformat()
            candidate['review_method'] = 'AI editorial review with structural validation; not external news or exam originals'
            path.write_text(json.dumps(candidate, ensure_ascii=False, indent=2))
        if validate_one(candidate):
            raise RuntimeError(f'{grade_id} invalid saved review')
        articles.append(candidate)
        print(grade_id, 'REVIEWED', candidate['article']['word_count'], flush=True)
    # Publish only when all twelve grades pass. Preserve original drafts.
    payload = {'collection': 'official_k12_reading', 'articles': articles}
    tmp = ROOT / 'catalog.reviewed.tmp'
    tmp.write_text(json.dumps(payload, ensure_ascii=False))
    tmp.replace(ROOT / 'catalog.json')
    report = {'grades': len(articles), 'status': 'complete', 'articles': [{'grade_id': a['grade_id'], 'title': a['article'].get('title_zh'), 'word_count': a['article']['word_count'], 'review_status': a['review_status']} for a in articles]}
    (reviewed / 'review_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
    print('COMPLETE 12 / 12 published official catalog', flush=True)

if __name__ == '__main__':
    for line in Path('/opt/acquireenglish/services/api/.env').read_text().splitlines():
        key, sep, value = line.partition('=')
        if sep and key.strip() in ('DEEPSEEK_API_KEY','DEEPSEEK_MODEL'):
            os.environ.setdefault(key.strip(),value.strip().strip('\"\x27'))
    review()
