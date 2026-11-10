import { useEffect, useMemo, useRef, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { api, type Course, type Lesson } from "../api";
import { useAuth } from "../auth";
import { DEMO_EN_SRT, DEMO_ZH_SRT } from "../data/demoSubtitles";
import { findActiveCueIndex, formatTime, parseSrt, type Cue } from "../lib/srt";

type TabName = "字幕" | "跟读" | "听写" | "练习" | "词卡";

type WordCardKind = "单词" | "短语" | "短句";

type EpisodeWordCard = {
  id: string;
  text: string;
  kind: WordCardKind;
  exampleEn: string;
  exampleZh: string;
  start: number;
  favorited: boolean;
};

const STOP_WORDS = new Set([
  "a",
  "an",
  "the",
  "and",
  "or",
  "but",
  "to",
  "of",
  "in",
  "on",
  "at",
  "for",
  "with",
  "is",
  "are",
  "was",
  "were",
  "be",
  "i",
  "you",
  "he",
  "she",
  "it",
  "we",
  "they",
  "this",
  "that",
  "my",
  "your",
  "his",
  "her",
  "our",
  "their",
  "as",
  "by",
  "from",
  "so",
  "if",
  "not",
  "do",
  "does",
  "did",
  "have",
  "has",
  "had",
  "just",
  "now",
  "can",
  "will",
  "would",
  "should",
]);

function kindForText(text: string): WordCardKind {
  const tokens = text.match(/[A-Za-z']+/g) ?? [];
  if (tokens.length >= 5) return "短句";
  if (tokens.length >= 2) return "短语";
  return "单词";
}

function buildEpisodeWordCards(enCues: Cue[], zhCues: Cue[]): EpisodeWordCard[] {
  const map = new Map<string, EpisodeWordCard>();
  for (const cue of enCues) {
    const tokens = (cue.text.match(/[A-Za-z']+/g) ?? [])
      .map((t) => t.toLowerCase())
      .filter((t) => t.length >= 4 && !STOP_WORDS.has(t));
    for (let i = 0; i < tokens.length; i++) {
      const token = tokens[i];
      if (!map.has(token)) {
        map.set(token, {
          id: `w:${token}:${cue.start}`,
          text: token,
          kind: "单词",
          exampleEn: cue.text,
          exampleZh: zhCues.find((z) => Math.abs(z.start - cue.start) < 0.4)?.text ?? "",
          start: cue.start,
          favorited: false,
        });
      }
      if (i + 1 < tokens.length) {
        const phrase = `${token} ${tokens[i + 1]}`;
        if (!map.has(phrase)) {
          map.set(phrase, {
            id: `p:${phrase}:${cue.start}`,
            text: phrase,
            kind: "短语",
            exampleEn: cue.text,
            exampleZh: zhCues.find((z) => Math.abs(z.start - cue.start) < 0.4)?.text ?? "",
            start: cue.start,
            favorited: false,
          });
        }
      }
    }
    if (/^(this is|we (do )?say|we don'?t say|it'?s called)/i.test(cue.text.trim())) {
      const key = cue.text.trim().toLowerCase();
      if (!map.has(key)) {
        map.set(key, {
          id: `s:${cue.start}`,
          text: cue.text.trim(),
          kind: "短句",
          exampleEn: cue.text,
          exampleZh: zhCues.find((z) => Math.abs(z.start - cue.start) < 0.4)?.text ?? "",
          start: cue.start,
          favorited: false,
        });
      }
    }
  }
  return [...map.values()]
    .sort((a, b) => a.start - b.start)
    .slice(0, 24)
    .map((card) => ({ ...card, kind: kindForText(card.text) }));
}

function normalize(value: string) {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9\s']/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function youtubeIdFromUrl(url: string): string | null {
  const m = url.match(
    /(?:youtu\.be\/|youtube\.com\/(?:watch\?v=|embed\/|shorts\/|live\/))([A-Za-z0-9_-]{6,})/i,
  );
  return m?.[1] ?? null;
}

function biliBvidFromUrl(url: string): string | null {
  const m = url.match(/bilibili\.com\/video\/(BV[0-9A-Za-z]+)/i);
  return m?.[1] ?? null;
}

export default function StudyPage() {
  const { courseId = "" } = useParams();
  const { token } = useAuth();
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const listRef = useRef<HTMLDivElement | null>(null);

  const [course, setCourse] = useState<Course | null>(null);
  const [lesson, setLesson] = useState<Lesson | null>(null);
  const [tab, setTab] = useState<TabName>("字幕");
  const [error, setError] = useState<string | null>(null);
  const [enCues, setEnCues] = useState<Cue[]>([]);
  const [zhCues, setZhCues] = useState<Cue[]>([]);
  const [currentTime, setCurrentTime] = useState(0);
  const [playing, setPlaying] = useState(false);
  const [bilingual, setBilingual] = useState(true);
  const [blindListening, setBlindListening] = useState(false);
  const [wordCardFilter, setWordCardFilter] = useState<"全部" | WordCardKind>("全部");
  const [loopSentence, setLoopSentence] = useState(false);
  const [pauseAtEnd, setPauseAtEnd] = useState(false);
  const [rate, setRate] = useState(1);
  const [activeIndex, setActiveIndex] = useState(0);
  const [dictation, setDictation] = useState("");
  const [dictationResult, setDictationResult] = useState<boolean | null>(null);
  const [practiceChoice, setPracticeChoice] = useState<string | null>(null);
  const [practiceAnswered, setPracticeAnswered] = useState(false);

  useEffect(() => {
    api
      .course(courseId, token)
      .then((c) => {
        setCourse(c);
        setLesson(c.lessons[0] ?? null);
      })
      .catch((err) => setError(err instanceof Error ? err.message : "Failed to load course"));
  }, [courseId, token]);

  useEffect(() => {
    let cancelled = false;
    async function loadSubs() {
      setDictation("");
      setDictationResult(null);
      setPracticeChoice(null);
      setPracticeAnswered(false);
      if (!lesson) return;
      try {
        const enPath = lesson.subtitles?.en;
        const zhPath = lesson.subtitles?.zh;
        if (enPath?.startsWith("/api/")) {
          const enText = await api.fetchText(enPath, token);
          if (!cancelled) setEnCues(parseSrt(enText));
        } else if (enPath?.startsWith("http") && !enPath.includes("cdn.example.com")) {
          const res = await fetch(enPath);
          const enText = await res.text();
          if (!cancelled) setEnCues(parseSrt(enText));
        } else if (!enPath) {
          if (!cancelled) setEnCues([]);
        } else {
          if (!cancelled) setEnCues(parseSrt(DEMO_EN_SRT));
        }
        if (zhPath?.startsWith("/api/")) {
          const zhText = await api.fetchText(zhPath, token);
          if (!cancelled) setZhCues(parseSrt(zhText));
        } else if (zhPath?.startsWith("http") && !zhPath.includes("cdn.example.com")) {
          const res = await fetch(zhPath);
          const zhText = await res.text();
          if (!cancelled) setZhCues(parseSrt(zhText));
        } else if (!zhPath) {
          if (!cancelled) setZhCues([]);
        } else {
          if (!cancelled) setZhCues(parseSrt(DEMO_ZH_SRT));
        }
      } catch {
        if (!cancelled) {
          setEnCues(parseSrt(DEMO_EN_SRT));
          setZhCues(parseSrt(DEMO_ZH_SRT));
        }
      }
    }
    void loadSubs();
    return () => {
      cancelled = true;
    };
  }, [lesson?.id, lesson?.subtitles?.en, lesson?.subtitles?.zh, token]);

  useEffect(() => {
    if (videoRef.current) videoRef.current.playbackRate = rate;
  }, [rate]);

  useEffect(() => {
    const idx = findActiveCueIndex(enCues, currentTime);
    if (idx >= 0 && idx !== activeIndex) setActiveIndex(idx);
  }, [currentTime, enCues, activeIndex]);

  useEffect(() => {
    const el = listRef.current?.querySelector(`[data-cue="${activeIndex}"]`);
    el?.scrollIntoView({ block: "nearest", behavior: "smooth" });
  }, [activeIndex]);

  useEffect(() => {
    if (!playing) return;
    const cue = enCues[activeIndex];
    if (!cue) return;
    if (loopSentence && currentTime >= cue.end - 0.05) {
      if (videoRef.current) {
        videoRef.current.currentTime = cue.start;
        void videoRef.current.play();
      } else {
        setCurrentTime(cue.start);
      }
      return;
    }
    if (pauseAtEnd && !loopSentence && currentTime >= cue.end - 0.05) {
      if (videoRef.current) videoRef.current.pause();
      setPlaying(false);
      setCurrentTime(cue.end);
    }
  }, [currentTime, loopSentence, pauseAtEnd, playing, enCues, activeIndex]);

  const ytId = lesson?.videoUrl ? youtubeIdFromUrl(lesson.videoUrl) : null;
  const biliId = lesson?.videoUrl ? biliBvidFromUrl(lesson.videoUrl) : null;
  const isEmbed = !!ytId || !!biliId;
  const hasRealVideo =
    !!lesson?.videoUrl?.startsWith("http") &&
    !lesson.videoUrl.includes("cdn.example.com") &&
    !isEmbed;

  useEffect(() => {
    if (!token || !course || !lesson) return;
    const timer = window.setTimeout(() => {
      void api.upsertProgress(
        {
          course_id: course.id,
          lesson_id: lesson.id,
          position_sec: currentTime,
          completed: false,
        },
        token,
      );
    }, 1500);
    return () => window.clearTimeout(timer);
  }, [token, course, lesson, currentTime]);

  useEffect(() => {
    if (!token || !lesson) return;
    void api.listProgress(token).then((rows) => {
      const row = rows.find((r) => r.lesson_id === lesson.id);
      if (row && row.position_sec > 1) {
        setCurrentTime(row.position_sec);
        if (videoRef.current) videoRef.current.currentTime = row.position_sec;
      }
    });
  }, [token, lesson?.id]);

  useEffect(() => {
    if ((hasRealVideo && !isEmbed) || !playing) return;
    const id = window.setInterval(() => {
      setCurrentTime((t) => {
        const next = t + 0.25 * rate;
        const last = enCues[enCues.length - 1];
        if (last && next > last.end + 0.5) {
          setPlaying(false);
          return last.end;
        }
        return next;
      });
    }, 250);
    return () => window.clearInterval(id);
  }, [hasRealVideo, isEmbed, playing, rate, enCues]);

  const lessonLabel = useMemo(() => {
    if (!course || !lesson) return "";
    return `${lesson.index}/${course.lessons.length}`;
  }, [course, lesson]);

  const practice = useMemo(() => {
    const line = enCues[activeIndex]?.text ?? "";
    const words = line
      .split(/\s+/)
      .map((w) => w.replace(/[^A-Za-z']/g, ""))
      .filter((w) => w.length > 3);
    if (!words.length) {
      return { masked: line, answer: "", options: [] as string[] };
    }
    const answer = words[activeIndex % words.length];
    const masked = line.replace(new RegExp(`\\b${answer}\\b`, "i"), "______");
    const distractors = words.filter((w) => w.toLowerCase() !== answer.toLowerCase()).slice(0, 2);
    const options = [answer, ...distractors].sort();
    return { masked, answer, options };
  }, [enCues, activeIndex]);

  const episodeCards = useMemo(
    () => buildEpisodeWordCards(enCues, zhCues),
    [enCues, zhCues],
  );
  const filteredCards = useMemo(
    () =>
      wordCardFilter === "全部"
        ? episodeCards
        : episodeCards.filter((card) => card.kind === wordCardFilter),
    [episodeCards, wordCardFilter],
  );

  function seekToCue(index: number) {
    const cue = enCues[index];
    if (!cue) return;
    setActiveIndex(index);
    setDictation("");
    setDictationResult(null);
    setPracticeChoice(null);
    setPracticeAnswered(false);
    if (videoRef.current) {
      videoRef.current.currentTime = cue.start;
      void videoRef.current.play();
      setPlaying(true);
    } else {
      setCurrentTime(cue.start);
    }
  }

  function togglePlay() {
    const v = videoRef.current;
    if (!v) {
      setPlaying((p) => !p);
      return;
    }
    if (v.paused) {
      void v.play();
      setPlaying(true);
    } else {
      v.pause();
      setPlaying(false);
    }
  }

  function checkDictation() {
    const expected = normalize(enCues[activeIndex]?.text ?? "");
    setDictationResult(normalize(dictation) === expected);
  }

  async function collectWord(word: string) {
    if (!token || !word) return;
    await api.upsertVocab(token, {
      word: word.toLowerCase(),
      context: enCues[activeIndex]?.text,
      mastery: "new",
    });
  }

  const activeEn = enCues[activeIndex]?.text ?? "";
  const activeZh = zhCues[activeIndex]?.text ?? "";

  return (
    <div className="shell">
      <header className="topbar">
        <div>
          <Link className="muted" to="/">
            ← 返回课程
          </Link>
          <div className="brand" style={{ marginTop: 8 }}>
            {course?.titleZh ?? course?.title ?? "学习中"}
          </div>
        </div>
        <div className="muted">{lessonLabel}</div>
      </header>

      {error ? <div className="error">{error}</div> : null}

      <div className="study-layout">
        <section className="card">
          <div className="video-frame">
            {ytId ? (
              <iframe
                title={lesson?.title ?? "YouTube"}
                src={`https://www.youtube.com/embed/${ytId}?rel=0`}
                allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
                allowFullScreen
                style={{ width: "100%", aspectRatio: "16 / 9", border: 0, borderRadius: 12 }}
              />
            ) : biliId ? (
              <iframe
                title={lesson?.title ?? "Bilibili"}
                src={`https://player.bilibili.com/player.html?bvid=${biliId}&high_quality=1&danmaku=0`}
                allowFullScreen
                style={{ width: "100%", aspectRatio: "16 / 9", border: 0, borderRadius: 12 }}
              />
            ) : hasRealVideo ? (
              <video
                ref={videoRef}
                src={lesson!.videoUrl}
                onTimeUpdate={(e) => setCurrentTime(e.currentTarget.currentTime)}
                onPlay={() => setPlaying(true)}
                onPause={() => setPlaying(false)}
              />
            ) : (
              <div style={{ textAlign: "center", padding: 24 }}>
                <div style={{ fontSize: 18, color: "#dbeafe", marginBottom: 8 }}>
                  {lesson?.title ?? "课段预览"}
                </div>
                <div className="muted">演示课视频待替换 CDN；字幕卡片与控制已可用</div>
                <div className="muted" style={{ marginTop: 8 }}>
                  {formatTime(currentTime)}
                </div>
              </div>
            )}
            {isEmbed ? (
              <div className="muted" style={{ marginTop: 8, fontSize: 12 }}>
                外链嵌入播放 · 字幕轴用下方控制同步精听（循环/听写/练习）
              </div>
            ) : null}
          </div>

          <div className="tabs">
            {(["字幕", "跟读", "听写", "练习", "词卡"] as const).map((name) => (
              <button
                key={name}
                type="button"
                className={`tab ${tab === name ? "active" : ""}`}
                onClick={() => setTab(name)}
              >
                {name}
              </button>
            ))}
          </div>

          {tab === "字幕" ? (
            <div ref={listRef} style={{ maxHeight: 360, overflow: "auto" }}>
              {enCues.map((cue, index) => (
                <button
                  key={cue.id}
                  type="button"
                  data-cue={index}
                  className={`cue ${index === activeIndex ? "active" : ""}`}
                  style={{ width: "100%", textAlign: "left", cursor: "pointer" }}
                  onClick={() => seekToCue(index)}
                >
                  <div className="muted" style={{ fontSize: 12, marginBottom: 6 }}>
                    {formatTime(cue.start)}
                  </div>
                  <div className="en">
                    {blindListening && index === activeIndex ? "（盲听中）" : cue.text}
                  </div>
                  {bilingual && !(blindListening && index === activeIndex) ? (
                    <div className="zh">{zhCues[index]?.text ?? ""}</div>
                  ) : null}
                </button>
              ))}
            </div>
          ) : null}

          {tab === "跟读" ? (
            <div>
              <div className="cue active">
                <div className="en">{activeEn}</div>
                {bilingual ? <div className="zh">{activeZh}</div> : null}
              </div>
              <label className="muted" style={{ display: "flex", gap: 8, marginTop: 12, alignItems: "center" }}>
                <input
                  type="checkbox"
                  checked={pauseAtEnd}
                  onChange={(e) => {
                    setPauseAtEnd(e.target.checked);
                    if (e.target.checked) setLoopSentence(false);
                  }}
                />
                句末暂停（Echo）
              </label>
              <p className="muted">播完当前句自动暂停，便于跟读。PC 可用系统麦克风录音（完整评测在 App）。</p>
            </div>
          ) : null}

          {tab === "听写" ? (
            <div>
              <button type="button" className="chip" onClick={() => seekToCue(activeIndex)}>
                重播本句
              </button>
              <textarea
                value={dictation}
                onChange={(e) => {
                  setDictation(e.target.value);
                  setDictationResult(null);
                }}
                placeholder="听写英文句子…"
                rows={3}
                style={{ width: "100%", marginTop: 12, borderRadius: 12, padding: 12 }}
              />
              <div style={{ display: "flex", gap: 8, marginTop: 8 }}>
                <button type="button" className="btn" onClick={checkDictation}>
                  核对
                </button>
                <button type="button" className="chip" onClick={() => seekToCue(Math.max(0, activeIndex - 1))}>
                  上一句
                </button>
                <button
                  type="button"
                  className="chip"
                  onClick={() => seekToCue(Math.min(enCues.length - 1, activeIndex + 1))}
                >
                  下一句
                </button>
              </div>
              {dictationResult !== null ? (
                <div style={{ marginTop: 10 }}>
                  <div className={dictationResult ? "muted" : "error"}>
                    {dictationResult ? "正确" : "再听一遍"}
                  </div>
                  <div className="en" style={{ marginTop: 6 }}>
                    {activeEn}
                  </div>
                </div>
              ) : null}
            </div>
          ) : null}

          {tab === "练习" ? (
            <div>
              <div className="en">{practice.masked || "本句暂无可挖空词"}</div>
              <div style={{ display: "grid", gap: 8, marginTop: 12 }}>
                {practice.options.map((option) => (
                  <button
                    key={option}
                    type="button"
                    className={`chip ${practiceAnswered && option === practice.answer ? "on" : ""}`}
                    onClick={() => {
                      setPracticeChoice(option);
                      setPracticeAnswered(true);
                      void collectWord(option === practice.answer ? option : practice.answer);
                    }}
                  >
                    {option}
                  </button>
                ))}
              </div>
              {practiceAnswered ? (
                <p className="muted" style={{ marginTop: 10 }}>
                  {practiceChoice === practice.answer ? "答对了" : `答案：${practice.answer}`}
                </p>
              ) : null}
            </div>
          ) : null}

          {tab === "词卡" ? (
            <div>
              <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginBottom: 12 }}>
                {(["全部", "单词", "短语", "短句"] as const).map((name) => (
                  <button
                    key={name}
                    type="button"
                    className={`chip ${wordCardFilter === name ? "on" : ""}`}
                    onClick={() => setWordCardFilter(name)}
                  >
                    {name}
                    {name === "全部"
                      ? ` ${episodeCards.length}`
                      : ` ${episodeCards.filter((c) => c.kind === name).length}`}
                  </button>
                ))}
              </div>
              <div style={{ maxHeight: 360, overflow: "auto", display: "grid", gap: 8 }}>
                {filteredCards.length === 0 ? (
                  <p className="muted">本集暂无推荐词卡</p>
                ) : (
                  filteredCards.map((card, index) => (
                    <button
                      key={card.id}
                      type="button"
                      className="cue"
                      style={{ width: "100%", textAlign: "left", cursor: "pointer" }}
                      onClick={() => {
                        const idx = enCues.findIndex((c) => Math.abs(c.start - card.start) < 0.35);
                        seekToCue(idx >= 0 ? idx : activeIndex);
                        setTab("字幕");
                        void collectWord(card.text);
                      }}
                    >
                      <div className="muted" style={{ fontSize: 12, marginBottom: 4 }}>
                        {index + 1} · {card.kind} · {formatTime(card.start)}
                      </div>
                      <div className="en">{card.text}</div>
                      <div className="zh">{card.exampleEn}</div>
                      {card.exampleZh ? <div className="muted">{card.exampleZh}</div> : null}
                    </button>
                  ))
                )}
              </div>
            </div>
          ) : null}

          <div className="controls">
            <button type="button" className={`chip ${bilingual ? "on" : ""}`} onClick={() => setBilingual((v) => !v)}>
              双语
            </button>
            <button
              type="button"
              className={`chip ${blindListening ? "on" : ""}`}
              onClick={() => setBlindListening((v) => !v)}
            >
              盲听
            </button>
            <button
              type="button"
              className="chip"
              onClick={() => setRate((r) => (r >= 1.5 ? 0.75 : Number((r + 0.25).toFixed(2))))}
            >
              {rate}x
            </button>
            <button type="button" className="play" onClick={togglePlay}>
              {playing ? "暂停" : "播放"}
            </button>
            <button
              type="button"
              className={`chip ${loopSentence ? "on" : ""}`}
              onClick={() => {
                setLoopSentence((v) => !v);
                setPauseAtEnd(false);
              }}
            >
              循环
            </button>
            <button type="button" className="chip" onClick={() => setTab("词卡")}>
              词卡
            </button>
          </div>
        </section>

        <aside className="card">
          <h3 style={{ marginTop: 0, fontFamily: "var(--font-display)" }}>课段列表</h3>
          <div className="muted" style={{ marginBottom: 12 }}>
            与 App 共用 course-schema · 进度自动同步
          </div>
          {(course?.lessons ?? []).map((item) => (
            <button
              key={item.id}
              type="button"
              className={`cue ${lesson?.id === item.id ? "active" : ""}`}
              style={{ width: "100%", textAlign: "left", cursor: "pointer" }}
              onClick={() => setLesson(item)}
            >
              <div className="muted" style={{ fontSize: 12 }}>
                {item.index}/{course?.lessons.length}
              </div>
              <div className="en">{item.title}</div>
            </button>
          ))}
        </aside>
      </div>
    </div>
  );
}
