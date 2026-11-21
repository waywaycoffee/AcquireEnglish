"""Generate thin first-party exam packs under data/exam_packs/."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "data" / "exam_packs"


def mcq(pid, prompt, options, answer, explain=""):
    return {
        "id": pid,
        "type": "mcq",
        "prompt": prompt,
        "options": options,
        "answer": answer,
        "explain": explain,
    }


def listening(pid, script, questions, title="Listening"):
    return {
        "id": pid,
        "type": "listening",
        "title": title,
        "script": script,
        "audio_url": "",
        "questions": questions,
    }


def reading(pid, passage, questions, title="Reading"):
    return {
        "id": pid,
        "type": "reading",
        "title": title,
        "passage": passage,
        "questions": questions,
    }


def writing(pid, prompt, rubric, min_words=120):
    return {
        "id": pid,
        "type": "writing",
        "prompt": prompt,
        "rubric": rubric,
        "min_words": min_words,
    }


def speaking(pid, prompt, tips):
    return {
        "id": pid,
        "type": "speaking",
        "prompt": prompt,
        "tips": tips,
    }


def main() -> None:
    ROOT.mkdir(parents=True, exist_ok=True)
    packs: dict[str, dict] = {}

    packs["pack_cet4"] = {
        "family_id": "cet4",
        "title": "大学英语四级备考包",
        "cefr": "B1",
        "version": 1,
        "sections": {
            "vocab": [
                mcq(
                    "c4v1",
                    'The word "abandon" is closest in meaning to ____.',
                    ["give up", "pick up", "look up", "make up"],
                    "give up",
                    "abandon≈放弃",
                ),
                mcq(
                    "c4v2",
                    "She has a strong ____ to succeed.",
                    ["desire", "desert", "design", "device"],
                    "desire",
                ),
                mcq(
                    "c4v3",
                    "Please ____ the form carefully.",
                    ["fill in", "fill out of", "fill up with", "fill on"],
                    "fill in",
                ),
                mcq(
                    "c4v4",
                    "The meeting was ____ until next Monday.",
                    ["put off", "put on", "put up", "put down"],
                    "put off",
                    "put off=推迟",
                ),
                mcq(
                    "c4v5",
                    "He is ____ of his mistakes.",
                    ["aware", "award", "away", "awful"],
                    "aware",
                ),
                mcq(
                    "c4v6",
                    "Environment protection is of great ____.",
                    ["importance", "important", "import", "impose"],
                    "importance",
                ),
                mcq(
                    "c4v7",
                    "We should ____ advantage of every chance.",
                    ["take", "make", "get", "have"],
                    "take",
                    "take advantage of",
                ),
                mcq(
                    "c4v8",
                    "The book is ____ into many languages.",
                    ["translated", "transferred", "transported", "transformed"],
                    "translated",
                ),
            ],
            "listening": [
                listening(
                    "c4l1",
                    "Woman: Did you finish the report for Professor Li?\n"
                    "Man: Not yet. I spent the whole evening in the library looking for references.\n"
                    "Woman: Maybe you can ask Mary. She wrote a similar paper last term.",
                    [
                        mcq(
                            "c4l1q1",
                            "What is the man doing?",
                            [
                                "Writing a report",
                                "Meeting Professor Li",
                                "Helping Mary",
                                "Borrowing a book",
                            ],
                            "Writing a report",
                        ),
                        mcq(
                            "c4l1q2",
                            "Who may help the man?",
                            ["Mary", "Professor Li", "The librarian", "His roommate"],
                            "Mary",
                        ),
                    ],
                    title="Conversation: Report",
                ),
                listening(
                    "c4l2",
                    "Good morning, students. Tomorrow the English club will hold a movie night "
                    "in Room 302 at 7 p.m. Bring your student ID. Snacks will be provided.",
                    [
                        mcq(
                            "c4l2q1",
                            "When is the movie night?",
                            [
                                "7 p.m. tomorrow",
                                "7 a.m. tomorrow",
                                "Tonight",
                                "Next week",
                            ],
                            "7 p.m. tomorrow",
                        ),
                        mcq(
                            "c4l2q2",
                            "What should students bring?",
                            ["Student ID", "Laptop", "Tickets", "Textbooks"],
                            "Student ID",
                        ),
                    ],
                    title="Announcement",
                ),
            ],
            "reading": [
                reading(
                    "c4r1",
                    "Many universities encourage students to join clubs. Clubs help students "
                    "make friends, practice skills, and manage time. However, joining too many "
                    "clubs can hurt academic performance. Experts suggest choosing two "
                    "activities that match long-term goals.",
                    [
                        mcq(
                            "c4r1q1",
                            "What is one benefit of clubs?",
                            [
                                "Making friends",
                                "Higher tuition",
                                "Less homework",
                                "Shorter semesters",
                            ],
                            "Making friends",
                        ),
                        mcq(
                            "c4r1q2",
                            "What do experts suggest?",
                            [
                                "Join two matching activities",
                                "Join every club",
                                "Avoid all clubs",
                                "Only study alone",
                            ],
                            "Join two matching activities",
                        ),
                    ],
                    title="Campus Clubs",
                ),
                reading(
                    "c4r2",
                    "Online learning offers flexibility, but it requires self-discipline. "
                    "Students who set a fixed schedule and take notes usually learn more "
                    "effectively than those who only watch videos casually.",
                    [
                        mcq(
                            "c4r2q1",
                            "What does online learning require?",
                            [
                                "Self-discipline",
                                "A new laptop only",
                                "No notes",
                                "Night classes",
                            ],
                            "Self-discipline",
                        )
                    ],
                    title="Online Learning",
                ),
            ],
            "writing": [
                writing(
                    "c4w1",
                    "Write an essay on the importance of reading English every day. "
                    "Give reasons and examples.",
                    "cet",
                    120,
                ),
                writing(
                    "c4w2",
                    "Some students prefer studying alone; others prefer group study. "
                    "Which do you prefer? Why?",
                    "cet",
                    120,
                ),
            ],
            "speaking": [
                speaking(
                    "c4s1",
                    "Describe a book that influenced you.",
                    "Use past tense; mention title, reason, and result.",
                ),
                speaking(
                    "c4s2",
                    "Talk about your study plan for this month.",
                    "Include goals, schedule, and one challenge.",
                ),
            ],
        },
        "mock": {
            "duration_minutes": 60,
            "sections": ["vocab", "listening", "reading", "writing"],
        },
    }

    packs["pack_cet6"] = {
        "family_id": "cet6",
        "title": "大学英语六级备考包",
        "cefr": "B2",
        "version": 1,
        "sections": {
            "vocab": [
                mcq(
                    "c6v1",
                    "The findings ____ previous assumptions.",
                    ["challenge", "change into", "charge", "chase"],
                    "challenge",
                ),
                mcq(
                    "c6v2",
                    "She spoke with remarkable ____.",
                    ["eloquence", "elegance only", "element", "election"],
                    "eloquence",
                ),
                mcq(
                    "c6v3",
                    "The policy aims to ____ inequality.",
                    ["alleviate", "allocate", "altercate", "alienate only"],
                    "alleviate",
                ),
                mcq(
                    "c6v4",
                    "His argument is not ____ enough.",
                    ["convincing", "convenient", "conventional", "conversing"],
                    "convincing",
                ),
                mcq(
                    "c6v5",
                    "They reached a ____ after long talks.",
                    ["consensus", "consent form", "console", "contest"],
                    "consensus",
                ),
                mcq(
                    "c6v6",
                    "The lecture was too ____ for beginners.",
                    ["abstract", "absorb", "abrupt only", "absent"],
                    "abstract",
                ),
            ],
            "listening": [
                listening(
                    "c6l1",
                    "Man: I am considering a semester abroad, but the cost worries me.\n"
                    "Woman: Have you checked the scholarship board? Several programs cover "
                    "airfare and tuition partially.\n"
                    "Man: That would make a huge difference. I will apply this week.",
                    [
                        mcq(
                            "c6l1q1",
                            "What worries the man?",
                            ["Cost", "Grades", "Language", "Weather"],
                            "Cost",
                        ),
                        mcq(
                            "c6l1q2",
                            "What will he do?",
                            [
                                "Apply for scholarship",
                                "Cancel the trip",
                                "Borrow a book",
                                "Change major",
                            ],
                            "Apply for scholarship",
                        ),
                    ],
                    title="Study Abroad",
                )
            ],
            "reading": [
                reading(
                    "c6r1",
                    "Artificial intelligence can speed up medical diagnosis, yet doctors remain "
                    "responsible for final decisions. Over-reliance on algorithms may hide rare "
                    "cases that models have never seen. Therefore, hospitals train staff to treat "
                    "AI as an assistant, not a replacement.",
                    [
                        mcq(
                            "c6r1q1",
                            "What is AI compared to?",
                            [
                                "An assistant",
                                "A replacement doctor",
                                "A patient",
                                "A hospital",
                            ],
                            "An assistant",
                        ),
                        mcq(
                            "c6r1q2",
                            "What risk is mentioned?",
                            [
                                "Missing rare cases",
                                "Higher salaries",
                                "Slower diagnosis",
                                "No training",
                            ],
                            "Missing rare cases",
                        ),
                    ],
                    title="AI in Medicine",
                )
            ],
            "writing": [
                writing(
                    "c6w1",
                    "Write about whether technology makes people more or less creative. "
                    "Support your view.",
                    "cet",
                    150,
                )
            ],
            "speaking": [
                speaking(
                    "c6s1",
                    "Discuss the advantages and disadvantages of remote work.",
                    "Balance both sides; end with your stance.",
                )
            ],
        },
        "mock": {
            "duration_minutes": 70,
            "sections": ["vocab", "listening", "reading", "writing"],
        },
    }

    packs["pack_ielts_ac"] = {
        "family_id": "ielts_ac",
        "title": "IELTS Academic Prep Pack",
        "cefr": "B2",
        "version": 1,
        "sections": {
            "vocab": [
                mcq(
                    "ilv1",
                    '"Substantial" most nearly means ____.',
                    ["considerable", "tiny", "sudden", "musical"],
                    "considerable",
                ),
                mcq(
                    "ilv2",
                    "A ____ increase was observed.",
                    ["significant", "signify", "signature", "signal"],
                    "significant",
                ),
                mcq(
                    "ilv3",
                    "The data ____ the hypothesis.",
                    ["support", "suppose", "supply", "suppress"],
                    "support",
                ),
                mcq(
                    "ilv4",
                    "Researchers should avoid ____ conclusions.",
                    ["hasty", "haste", "hastily only as noun", "host"],
                    "hasty",
                ),
                mcq(
                    "ilv5",
                    "The chart shows a steady ____.",
                    ["decline", "declare", "decorate", "decide"],
                    "decline",
                ),
            ],
            "listening": [
                listening(
                    "ill1",
                    "Tutor: For your presentation, keep it under ten minutes and leave two "
                    "minutes for questions.\n"
                    "Student: Should I include the survey results?\n"
                    "Tutor: Yes, but summarize them. Use one clear graph rather than three tables.",
                    [
                        mcq(
                            "ill1q1",
                            "How long should the talk be?",
                            [
                                "Under 10 minutes",
                                "30 minutes",
                                "Two hours",
                                "Five seconds",
                            ],
                            "Under 10 minutes",
                        ),
                        mcq(
                            "ill1q2",
                            "What does the tutor prefer?",
                            [
                                "One clear graph",
                                "Three tables",
                                "No data",
                                "A video only",
                            ],
                            "One clear graph",
                        ),
                    ],
                    title="Tutorial",
                )
            ],
            "reading": [
                reading(
                    "ilr1",
                    "Urban green spaces improve mental health and reduce heat in cities. Studies "
                    "in several countries show that people living near parks report lower stress. "
                    "Planners now treat parks as essential infrastructure, similar to roads and "
                    "schools, rather than optional decoration.",
                    [
                        mcq(
                            "ilr1q1",
                            "Parks are compared to ____.",
                            [
                                "essential infrastructure",
                                "optional toys",
                                "private gardens only",
                                "airports",
                            ],
                            "essential infrastructure",
                        ),
                        mcq(
                            "ilr1q2",
                            "What benefit is mentioned?",
                            [
                                "Lower stress",
                                "Higher taxes",
                                "More traffic",
                                "Less sunlight",
                            ],
                            "Lower stress",
                        ),
                    ],
                    title="Urban Parks",
                )
            ],
            "writing": [
                writing(
                    "ilw1",
                    "Task 2: Some people think universities should focus on practical skills; "
                    "others believe theoretical knowledge is more important. Discuss both views "
                    "and give your opinion.",
                    "ielts_task2",
                    250,
                ),
                writing(
                    "ilw2",
                    "Task 1: The chart below shows the percentage of households with internet "
                    "access from 2000 to 2020 in three countries. Summarise the information by "
                    "selecting and reporting the main features.",
                    "ielts_task1",
                    150,
                ),
            ],
            "speaking": [
                speaking(
                    "ils1",
                    "Part 2: Describe a time you learned something new. You should say what it "
                    "was, how you learned it, and how you felt.",
                    "Speak for 1–2 minutes; use past forms.",
                ),
                speaking(
                    "ils2",
                    "Part 3: Do you think schools should teach more digital skills? Why?",
                    "Give reasons and an example.",
                ),
            ],
        },
        "mock": {
            "duration_minutes": 90,
            "sections": ["listening", "reading", "writing"],
        },
    }

    packs["pack_gaokao"] = {
        "family_id": "gaokao",
        "title": "高考英语备考包",
        "cefr": "B2",
        "version": 1,
        "sections": {
            "vocab": [
                mcq(
                    "gkv1",
                    "We ____ the importance of honesty.",
                    ["emphasize", "emperor", "employ", "empty"],
                    "emphasize",
                ),
                mcq(
                    "gkv2",
                    "Hard work leads to ____.",
                    ["success", "succeed", "successful", "successive"],
                    "success",
                ),
                mcq(
                    "gkv3",
                    "She ____ her hand to greet me.",
                    ["raised", "rose", "risen", "arose"],
                    "raised",
                ),
                mcq(
                    "gkv4",
                    "The story is based ____ a true event.",
                    ["on", "in", "at", "with"],
                    "on",
                ),
                mcq(
                    "gkv5",
                    "He is the ____ person for the job.",
                    ["suitable", "suite", "suit", "suitor"],
                    "suitable",
                ),
            ],
            "listening": [
                listening(
                    "gkl1",
                    "Boy: Shall we visit the science museum this Saturday?\n"
                    "Girl: I would love to, but I have a piano lesson in the morning. "
                    "How about Sunday afternoon?\n"
                    "Boy: Sunday works for me.",
                    [
                        mcq(
                            "gkl1q1",
                            "When will they go?",
                            [
                                "Sunday afternoon",
                                "Saturday morning",
                                "Tonight",
                                "Friday",
                            ],
                            "Sunday afternoon",
                        )
                    ],
                    title="Weekend Plan",
                )
            ],
            "reading": [
                reading(
                    "gkr1",
                    "China has been promoting garbage classification in many cities. Citizens "
                    "are asked to separate wet waste, recyclables, and hazardous waste. Although "
                    "the new rules take time to learn, they help recycling and protect the "
                    "environment.",
                    [
                        mcq(
                            "gkr1q1",
                            "What is being promoted?",
                            [
                                "Garbage classification",
                                "Longer holidays",
                                "Free phones",
                                "New airports",
                            ],
                            "Garbage classification",
                        )
                    ],
                    title="Garbage Classification",
                )
            ],
            "writing": [
                writing(
                    "gkw1",
                    "假定你是李华，你的英国朋友 Eric 想了解中国的高中生活。请写一封邮件介绍课程、"
                    "课外活动与考试压力，并给出一条建议。",
                    "k12",
                    100,
                )
            ],
            "speaking": [
                speaking(
                    "gks1",
                    "用英语介绍一次难忘的校园活动。",
                    "包含时间、地点、经过与感受。",
                )
            ],
        },
        "mock": {
            "duration_minutes": 75,
            "sections": ["vocab", "listening", "reading", "writing"],
        },
    }

    packs["pack_zhongkao"] = {
        "family_id": "zhongkao",
        "title": "中考英语备考包",
        "cefr": "A2",
        "version": 1,
        "sections": {
            "vocab": [
                mcq("zkv1", "I ____ a student.", ["am", "is", "are", "be"], "am"),
                mcq(
                    "zkv2",
                    "There ____ a book on the desk.",
                    ["is", "are", "am", "be"],
                    "is",
                ),
                mcq(
                    "zkv3",
                    "She ____ to school by bus.",
                    ["goes", "go", "going", "gone"],
                    "goes",
                ),
                mcq("zkv4", "____ you like apples?", ["Do", "Does", "Are", "Is"], "Do"),
                mcq(
                    "zkv5",
                    "This is ____ interesting story.",
                    ["an", "a", "the", "/"],
                    "an",
                ),
            ],
            "listening": [
                listening(
                    "zkl1",
                    "Tom: What time is it?\nLucy: It is half past seven. Hurry, or we will be "
                    "late for school.",
                    [
                        mcq(
                            "zkl1q1",
                            "What time is it?",
                            ["7:30", "7:00", "8:30", "6:30"],
                            "7:30",
                        )
                    ],
                    title="Time",
                )
            ],
            "reading": [
                reading(
                    "zkr1",
                    "My name is Anna. I have a dog called Bobby. Every morning I walk Bobby in "
                    "the park before school. Bobby likes running and playing with a ball.",
                    [
                        mcq(
                            "zkr1q1",
                            "What is the dog's name?",
                            ["Bobby", "Anna", "Tom", "Park"],
                            "Bobby",
                        )
                    ],
                    title="My Dog",
                )
            ],
            "writing": [
                writing(
                    "zkw1",
                    '以 "My Best Friend" 为题写一篇短文，介绍朋友外貌、性格与一件小事。',
                    "k12",
                    80,
                )
            ],
            "speaking": [
                speaking(
                    "zks1",
                    "Introduce your family in English.",
                    "Name, people, and one hobby.",
                )
            ],
        },
        "mock": {
            "duration_minutes": 50,
            "sections": ["vocab", "listening", "reading", "writing"],
        },
    }

    packs["pack_k12_general"] = dict(packs["pack_zhongkao"])
    packs["pack_k12_general"] = json.loads(json.dumps(packs["pack_zhongkao"]))
    packs["pack_k12_general"]["family_id"] = "k12_j2"
    packs["pack_k12_general"]["title"] = "K12 通用备考包"

    packs["pack_ket"] = {
        "family_id": "ket",
        "title": "KET / A2 Key Prep",
        "cefr": "A2",
        "version": 1,
        "sections": {
            "vocab": [
                mcq("ketv1", "I ____ from China.", ["am", "is", "are", "be"], "am"),
                mcq(
                    "ketv2",
                    "Can you ____ English?",
                    ["speak", "speaking", "spoke", "speech"],
                    "speak",
                ),
                mcq(
                    "ketv3",
                    "This shop ____ at 9 a.m.",
                    ["opens", "open", "opening", "opened always"],
                    "opens",
                ),
            ],
            "listening": [
                listening(
                    "ketl1",
                    "Man: Where is the post office?\nWoman: Go straight and turn left. "
                    "It is next to the bank.",
                    [
                        mcq(
                            "ketl1q1",
                            "Where is the post office?",
                            [
                                "Next to the bank",
                                "Inside the bank",
                                "Far from town",
                                "At school",
                            ],
                            "Next to the bank",
                        )
                    ],
                    title="Directions",
                )
            ],
            "reading": [
                reading(
                    "ketr1",
                    "Hi Sam, Would you like to come to my birthday party on Friday at 6 p.m.? "
                    "Please tell me if you can come. Love, Mia",
                    [
                        mcq(
                            "ketr1q1",
                            "When is the party?",
                            [
                                "Friday 6 p.m.",
                                "Saturday",
                                "Sunday morning",
                                "Monday",
                            ],
                            "Friday 6 p.m.",
                        )
                    ],
                    title="Invitation",
                )
            ],
            "writing": [
                writing(
                    "ketw1",
                    "Write an email to a friend about your favourite sport (40–50 words).",
                    "k12",
                    40,
                )
            ],
            "speaking": [
                speaking(
                    "kets1",
                    "Talk about your daily routine.",
                    "Morning, afternoon, evening.",
                )
            ],
        },
        "mock": {
            "duration_minutes": 45,
            "sections": ["vocab", "listening", "reading", "writing"],
        },
    }

    packs["pack_kaoyan"] = {
        "family_id": "kaoyan",
        "title": "考研英语备考包",
        "cefr": "B2",
        "version": 1,
        "sections": {
            "vocab": [
                mcq(
                    "kyv1",
                    "The theory needs further ____.",
                    ["verification", "verify", "vertical", "version only"],
                    "verification",
                ),
                mcq(
                    "kyv2",
                    "His views are rather ____.",
                    ["controversial", "control", "contribute", "convenient"],
                    "controversial",
                ),
                mcq(
                    "kyv3",
                    "Economic growth remains ____.",
                    ["sluggish", "slug", "slum", "slim only"],
                    "sluggish",
                ),
                mcq(
                    "kyv4",
                    "The author ____ a new framework.",
                    ["proposes", "purposes", "poses", "postures"],
                    "proposes",
                ),
            ],
            "listening": [
                listening(
                    "kyl1",
                    "Professor: Your literature review is solid, but strengthen the methodology "
                    "section with more recent studies from 2022 onward.",
                    [
                        mcq(
                            "kyl1q1",
                            "What should be strengthened?",
                            [
                                "Methodology section",
                                "Title page",
                                "Font size",
                                "Parking",
                            ],
                            "Methodology section",
                        )
                    ],
                    title="Supervision",
                )
            ],
            "reading": [
                reading(
                    "kyr1",
                    "Globalization has intensified competition among universities. Institutions "
                    "compete for talent, funding, and international rankings. Critics argue that "
                    "ranking culture may distort educational priorities, pushing schools to chase "
                    "metrics instead of student learning.",
                    [
                        mcq(
                            "kyr1q1",
                            "What may ranking culture distort?",
                            [
                                "Educational priorities",
                                "Campus trees",
                                "Bus routes",
                                "Lunch menus",
                            ],
                            "Educational priorities",
                        )
                    ],
                    title="University Rankings",
                )
            ],
            "writing": [
                writing(
                    "kyw1",
                    "Write an essay: Is cultural globalization a threat to local traditions? "
                    "Discuss.",
                    "cet",
                    160,
                )
            ],
            "speaking": [
                speaking(
                    "kys1",
                    "Explain your research interest in two minutes.",
                    "Background, question, method.",
                )
            ],
        },
        "mock": {
            "duration_minutes": 80,
            "sections": ["vocab", "reading", "writing"],
        },
    }

    packs["pack_toefl"] = {
        "family_id": "toefl",
        "title": "TOEFL Prep Pack",
        "cefr": "B2",
        "version": 1,
        "sections": {
            "vocab": [
                mcq(
                    "tfv1",
                    '"Mitigate" means ____.',
                    ["make less severe", "make larger", "ignore", "celebrate"],
                    "make less severe",
                ),
                mcq(
                    "tfv2",
                    "The results were ____.",
                    ["inconclusive", "including", "indoor", "induce"],
                    "inconclusive",
                ),
            ],
            "listening": [
                listening(
                    "tfl1",
                    "Professor: Photosynthesis converts light energy into chemical energy. "
                    "Remember, chlorophyll absorbs mainly blue and red wavelengths.",
                    [
                        mcq(
                            "tfl1q1",
                            "What does chlorophyll mainly absorb?",
                            [
                                "Blue and red light",
                                "Only green light",
                                "Ultraviolet only",
                                "Sound waves",
                            ],
                            "Blue and red light",
                        )
                    ],
                    title="Lecture",
                )
            ],
            "reading": [
                reading(
                    "tfr1",
                    "Coral reefs support marine biodiversity but are sensitive to temperature "
                    "rise. Even slight warming can cause bleaching, which weakens coral and "
                    "affects fish populations that depend on reef habitats.",
                    [
                        mcq(
                            "tfr1q1",
                            "What can cause bleaching?",
                            [
                                "Temperature rise",
                                "More tourists only",
                                "Less salt",
                                "Moonlight",
                            ],
                            "Temperature rise",
                        )
                    ],
                    title="Coral Reefs",
                )
            ],
            "writing": [
                writing(
                    "tfw1",
                    "Integrated style: Summarize a lecture claim that disagrees with a reading "
                    "about city bikes, then state which side is stronger.",
                    "cet",
                    180,
                )
            ],
            "speaking": [
                speaking(
                    "tfs1",
                    "Do you prefer studying in a library or at home? Explain.",
                    "Give two reasons.",
                )
            ],
        },
        "mock": {
            "duration_minutes": 80,
            "sections": ["listening", "reading", "writing"],
        },
    }

    for name, data in packs.items():
        path = ROOT / f"{name}.json"
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
        print("wrote", path.name)


if __name__ == "__main__":
    main()
