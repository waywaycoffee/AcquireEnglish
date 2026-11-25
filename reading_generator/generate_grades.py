"""Generate and validate one article per grade; publish an atomic ECS catalog."""
import json
import os
from pathlib import Path
from batch_generator import call_llm, prompt_template
from grades import GRADES
from validator import validate_one, count_english_words

BASE = Path(__file__).resolve().parent

def run():
    output = Path(os.environ.get('K12_OUTPUT_DIR', str(BASE / 'grade_readings')))
    output.mkdir(parents=True, exist_ok=True)
    topics = ['校园旧书交换','节约用水的小行动','校园花园里的蜜蜂','用旧纸制作新书签','一起步行上学','社区图书角','太阳能校园小装置','减少午餐食物浪费','保护城市鸟类','社区共享花园','博物馆数字展览','低碳生活与青年行动']
    results = []
    for (grade_id, grade), topic in zip(GRADES.items(), topics):
        path = output / f'{grade_id}.json'
        data = None
        if path.exists():
            existing = json.loads(path.read_text())
            if existing.get('grade_id') == grade_id and not validate_one(existing):
                data = existing
        feedback = ''
        previous = None
        for attempt in range(6):
            if data is not None:
                break
            low, high = grade['bounds']
            prompt = '你是K12英语教研员，只输出合法JSON。主题：' + topic + '。包含4题，每题四个选项和引用原文的中文解析；word_list最多3项，long_sentences为2项，digital_human含3条英文口语问题。\n' + prompt_template.split('【JSON Schema强制结构，严格遵守】', 1)[1]
            prompt += f'\n【本次年级覆盖规则，优先于上述学段通用规则】目标为{grade["name"]}，正文必须{low}–{high}个空格分隔的英文单词，目标{(low+high)//2}词。word_list最多3项。'
            prompt += '\n小学低年级仅用简短日常句；题目用简单英文，可配中文辅助，推理限一步，词义题用具体日常词，long_sentences提供2句原文基础句的中文讲解，不强行使用复杂句。'
            prompt += '\n这是原创校园与生活主题阅读，不得捏造有日期、媒体出处的真实新闻。article额外提供title英文标题与title_zh中文标题。'
            if feedback:
                prompt += '\n上次未通过，必须修正：' + feedback
                if previous is not None:
                    prompt += '\n请编辑下列JSON来修正错误，调整正文后同步修改问题、原文引用和讲解，勿重新扩写：' + json.dumps(previous, ensure_ascii=False)
            try:
                candidate = json.loads(call_llm(prompt))
                candidate['grade_id'] = grade_id
                candidate['level'] = grade['name']
                candidate['article']['word_count'] = count_english_words(candidate['article']['passage'])
                previous = candidate
                errors = validate_one(candidate)
                if errors:
                    feedback = '；'.join(errors)
                    print(grade_id, 'retry', attempt + 1, feedback, flush=True)
                    continue
                data = candidate
                path.write_text(json.dumps(data, ensure_ascii=False, indent=2))
            except Exception as exc:
                feedback = str(exc)
                print(grade_id, 'retry', attempt + 1, feedback, flush=True)
        if data is None:
            print(grade_id, 'FAILED', flush=True)
            continue
        results.append(data)
        catalog = output / 'catalog.json'
        tmp = output / 'catalog.tmp'
        tmp.write_text(json.dumps({'articles': results}, ensure_ascii=False))
        tmp.replace(catalog)
        print(grade_id, grade['name'], 'OK', data['article']['word_count'], flush=True)
    print('COMPLETE', len(results), '/', len(GRADES), flush=True)
    return 0 if len(results) == len(GRADES) else 1

if __name__ == '__main__':
    # Load only the required credentials; never log secrets.
    env = Path('/opt/acquireenglish/services/api/.env')
    if env.exists():
        for line in env.read_text().splitlines():
            key, sep, value = line.partition('=')
            if sep and key.strip() in ('DEEPSEEK_API_KEY', 'DEEPSEEK_MODEL'):
                os.environ.setdefault(key.strip(), value.strip().strip('\"\x27'))
    raise SystemExit(run())
