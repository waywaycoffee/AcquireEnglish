import { useEffect, useMemo, useRef, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { api, type Course, type Lesson } from "../api";
import { useAuth } from "../auth";
import { DEMO_EN_SRT, DEMO_ZH_SRT } from "../data/demoSubtitles";
import { findActiveCueIndex, formatTime, parseSrt, type Cue } from "../lib/srt";

type TabName = "字幕" | "跟读" | "听写" | "练习";

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
  const [loopSentence, setLoopSentence] = useState(false);
  const [pauseAtEnd, setPauseAtEnd] = useState(false);
  const [rate, setRate] = useState(1);
  const [activeIndex, setActiveIndex] = useState(0);
  const [dictation, setDictation] = useState("");
  const [dictationResult, setDictationResult] = useState<boolean | null>(null);
  const [practiceChoice, setPracticeChoice] = useState<string | null>(null);
  const [practiceAnswered, setPracticeAnswered] = useState(false);
  const [generatingSubs, setGeneratingSubs] = useState(false);
  const [generateMsg, setGenerateMsg] = useState<string | null>(null);

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

  const importId = useMemo(() => {
    const m = courseId.match(/^link-(\d+)$/);
    return m ? Number(m[1]) : null;
  }, [courseId]);

  async function generateAiSubtitles() {
    if (!token || importId == null) return;
    setGeneratingSubs(true);
    const durationSec = Math.ceil(lesson?.durationSec ?? 0);
    const maxSeconds =
      durationSec > 0
        ? Math.min(durationSec + 90, 3 * 60 * 60)
        : 60 * 60;
    const minutes = Math.ceil(maxSeconds / 60);
    setGenerateMsg(`正在提取音频并调用阿里云百炼识别（约前 ${minutes} 分钟，可能较久）…`);
    setError(null);
    try {
      const updated = await api.generateSubtitles(token, importId, {
        language: "en",
        max_seconds: maxSeconds,
      });
      setCourse(updated);
      setLesson(updated.lessons[0] ?? null);
      setGenerateMsg("字幕已生成");
    } catch (err) {
      setGenerateMsg(null);
      setError(err instanceof Error ? err.message : "AI 字幕生成失败");
    } finally {
      setGeneratingSubs(false);
    }
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
            {(["字幕", "跟读", "听写", "练习"] as const).map((name) => (
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
              {importId != null ? (
                <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginBottom: 12, alignItems: "center" }}>
                  <button
                    type="button"
                    className="btn"
                    disabled={generatingSubs}
                    onClick={() => void generateAiSubtitles()}
                  >
                    {generatingSubs ? "生成中…" : enCues.length ? "重新 AI 生成字幕" : "AI 生成字幕"}
                  </button>
                  <Link className="muted" to="/" style={{ fontSize: 12 }}>
                    按整课时长识别（最长 3 小时）· 服务器已可使用全局百炼 Key
                  </Link>
                </div>
              ) : null}
              {generateMsg ? <div className="muted" style={{ marginBottom: 10 }}>{generateMsg}</div> : null}
              {enCues.length === 0 ? (
                <div className="cue">
                  <div className="en">暂无字幕</div>
                  <div className="zh" style={{ marginTop: 8 }}>
                    {importId != null
                      ? "可点击上方「AI 生成字幕」用语音识别生成；或先配置 B 站 Cookie 再重新导入以拉取官方字幕。"
                      : "云课程需在媒资中提供字幕文件。"}
                  </div>
                </div>
              ) : (
                enCues.map((cue, index) => (
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
                    <div className="en">{cue.text}</div>
                    {bilingual ? <div className="zh">{zhCues[index]?.text ?? ""}</div> : null}
                  </button>
                ))
              )}
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

          <div className="controls">
            <button type="button" className={`chip ${bilingual ? "on" : ""}`} onClick={() => setBilingual((v) => !v)}>
              双语
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
            <button type="button" className="chip" onClick={() => setTab("字幕")}>
              精读
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
