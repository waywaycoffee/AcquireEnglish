"""Expand the reviewed official collection to five distinct articles per grade."""
import json
import os
import hashlib
from pathlib import Path
from datetime import datetime, timezone
from concurrent.futures import ThreadPoolExecutor, as_completed
from batch_generator import call_llm, prompt_template
from grades import GRADES
from validator import validate_one

ROOT = Path(os.environ.get('K12_OUTPUT_DIR', '/opt/acquireenglish/services/api/media/reading/k12'))
TOPICS = ['校园失物招领与诚实','雨天的友善小行动','种子成长观察日记','学校运动日与团队合作']

def validate(data, grade_id):
    errors = validate_one(data)
    if data.get('grade_id') != grade_id:
        errors.append('年级不匹配')
    passage = data.get('article', {}).get('passage', '')
    for sentence in data.get('long_sentences', []):
        if sentence.get('sentence', '') not in passage:
            errors.append('句式讲解不在原文')
    for question in data.get('questions', []):
        quote = question.get('evidence_quote')
        if not isinstance(quote, str) or not quote or quote not in passage:
            errors.append('每题 evidence_quote 必须准确引用原文')
    if grade_id.startswith(('k12_j','k12_s')):
        if [q.get('question_type') for q in data.get('questions', [])] != ['main_idea','detail','inference','vocabulary_attitude']:
            errors.append('中学题序必须main_idea/detail/inference/vocabulary_attitude')
    return errors

def create(grade_id, number):
    grade = GRADES[grade_id]
    path = ROOT / 'official' / f'{grade_id}_{number:02d}.json'
    if path.exists():
        saved = json.loads(path.read_text())
        if not validate(saved, grade_id) and saved.get('review_status') == 'ai_reviewed':
            return saved
    low, high = grade['bounds']
    schema = prompt_template.split('【JSON Schema强制结构，严格遵守】',1)[1]
    prompt = f'''你是K12英语教研编辑，只输出完整合法JSON。为{grade['name']}写一篇原创主题阅读，主题：{TOPICS[number-2]}。
正文严格{low}–{high}个空格分隔英文单词，目标{(low+high)//2}词。不要冒充真实新闻、研究、考试真题，不虚构可核实的真实事件与统计。
小学一二年级只用短句、简单词，题目简短可带中文辅助，不用抽象推理术语。小学其他年级难度循序渐进。中学适当包含因果与观点表达。
article必须有title、title_zh、passage和word_count。questions恰好4题，每题4个不同选项A/B/C/D、唯一正确答案、中文analysis解释每个选项对错。每题额外提供evidence_quote（逐字引用正文完整句），question_type。
初中高中题序必须main_idea、detail、inference、vocabulary_attitude；推理必须需要一步合理推断而非直接复述。小学题型可detail/main_idea/vocabulary，适合具体年级。
word_list最多3项音标释义准确；long_sentences恰好2项，sentence必须逐字来自正文；数字人口语问题3条，难度匹配。语法、科学常识正确，建议安全可行，故事逻辑连贯。所有中文讲解中的原文引用必须和正文一致。
结构参考：{schema}'''
    draft = ROOT / 'official' / f'{grade_id}_{number:02d}.draft.json'
    feedback = ('\n请继续审查修订这版草稿，保持主题和年级，检查题型标注、四选项解析和证据：'+draft.read_text()) if draft.exists() else ''
    for attempt in range(10):
        try:
            data = json.loads(call_llm(prompt + feedback))
            data['grade_id'] = grade_id
            data['level'] = grade['name']
            data['article']['word_count'] = len(data['article']['passage'].split())
            errors = validate(data, grade_id)
            if errors:
                feedback = '\n修正这些错误：'+'；'.join(errors)+'\n在此JSON上修正，同步修正题目和原文引用：'+json.dumps(data,ensure_ascii=False)
                print(grade_id,number,'RETRY',attempt+1,'；'.join(errors),flush=True)
                continue
            (ROOT / 'official' / f'{grade_id}_{number:02d}.draft.json').write_text(json.dumps(data,ensure_ascii=False))
            audit = json.loads(call_llm('你是独立英语教材审校员。检查下面JSON：是否符合'+grade['name']+'难度，语法、逻辑和科学常识是否正确，四题答案是否唯一且有依据，推理题是否真的推理，解析是否说明四选项，音标词义是否准确，原文引用是否一致。低年级不能出现过难题干。只报告实质性错误，不把可选润色或教学偏好当作错误；词义题允许使用生词表里的词、英文释义选项，不要求题干额外附音标；中文解析只要解释各选项即可，不要求每个干扰项都另引一句不存在的原文；接受通行的语法分析。仅输出JSON {"approved":true或false,"issues":[具体问题字符串]}。有实质问题必须false；通过时issues必须为空数组，不添加可选润色建议。\n'+json.dumps(data,ensure_ascii=False)))
            if audit.get('approved') is not True or audit.get('issues'):
                feedback = '\n独立审校要求修正：'+json.dumps(audit.get('issues',[]),ensure_ascii=False)+'\n待修订：'+json.dumps(data,ensure_ascii=False)
                print(grade_id,number,'EDITOR_RETRY',attempt+1,json.dumps(audit.get('issues',[]),ensure_ascii=False),flush=True)
                continue
            data.update(id=f'k12-reading:{grade_id}:{number:02d}',source_type='ai_original',publisher='爱快英语',collection='official_k12_reading',review_status='ai_reviewed',review_method='Independent AI editorial review plus structural and evidence validation',reviewed_at=datetime.now(timezone.utc).isoformat(),sequence=number)
            path.write_text(json.dumps(data,ensure_ascii=False,indent=2))
            print(grade_id,number,'REVIEWED',data['article']['word_count'],flush=True)
            return data
        except Exception as exc:
            print(grade_id,number,'RETRY',attempt+1,type(exc).__name__,flush=True)
    raise RuntimeError(f'{grade_id} article {number} exhausted retries')

def run():
    articles = []
    for grade_id in GRADES:
        first = json.loads((ROOT/'official'/f'{grade_id}.json').read_text())
        if validate_one(first) or first.get('review_status') != 'ai_reviewed':
            raise RuntimeError(f'{grade_id} first article is not reviewed')
        first.setdefault('id',f'k12-reading:{grade_id}')
        first['sequence'] = 1
        articles.append(first)
    failures = []
    with ThreadPoolExecutor(max_workers=8) as pool:
        jobs={pool.submit(create,g,n):(g,n) for g in GRADES for n in range(2,6)}
        for job in as_completed(jobs):
            try: articles.append(job.result())
            except Exception as exc:
                failures.append(jobs[job]);print('FAILED',jobs[job],type(exc).__name__,flush=True)
    if failures:
        print('INCOMPLETE',failures,flush=True)
        return 1
    articles.sort(key=lambda a:(list(GRADES).index(a['grade_id']),a['sequence']))
    if len({a['id'] for a in articles}) != 60: raise RuntimeError('Duplicate ids')
    hashes=[hashlib.sha256(a['article']['passage'].encode()).hexdigest() for a in articles]
    if len(set(hashes))!=60:raise RuntimeError('Duplicate passages')
    payload={'collection':'official_k12_reading','articles':articles}
    tmp=ROOT/'catalog.expand.tmp';tmp.write_text(json.dumps(payload,ensure_ascii=False));tmp.replace(ROOT/'catalog.json')
    report={'status':'complete','grades':12,'articles':60,'per_grade':{g:sum(a['grade_id']==g for a in articles) for g in GRADES}}
    (ROOT/'official'/'expansion_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
    print('COMPLETE',json.dumps(report),flush=True)
    return 0

if __name__=='__main__':
    for line in Path('/opt/acquireenglish/services/api/.env').read_text().splitlines():
        key,sep,value=line.partition('=')
        if sep and key.strip() in ('DEEPSEEK_API_KEY','DEEPSEEK_MODEL'):
            os.environ.setdefault(key.strip(),value.strip().strip('\"\x27'))
    raise SystemExit(run())
