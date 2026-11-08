import { useEffect, useMemo, useRef, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { api, type Course, type Lesson } from "../api";
import { useAuth } from "../auth";
import { DEMO_EN_SRT, DEMO_ZH_SRT } from "../data/demoSubtitles";
import { findActiveCueIndex, formatTime, parseSrt, type Cue } from "../lib/srt";

type TabName = "字幕" | "跟读" | "听写" | "练习";

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
  const [rate, setRate] = useState(1);
  const [activeIndex, setActiveIndex] = useState(0);

  useEffect(() => {
    api
      .course(courseId)
      .then((c) => {
        setCourse(c);
        setLesson(c.lessons[0] ?? null);
      })
      .catch((err) => setError(err instanceof Error ? err.message : "Failed to load course"));
  }, [courseId]);

  useEffect(() => {
    setEnCues(parseSrt(DEMO_EN_SRT));
    setZhCues(parseSrt(DEMO_ZH_SRT));
  }, [lesson?.id]);

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
    if (!loopSentence || !playing) return;
    const cue = enCues[activeIndex];
    if (!cue || !videoRef.current) return;
    if (currentTime >= cue.end - 0.05) {
      videoRef.current.currentTime = cue.start;
      void videoRef.current.play();
    }
  }, [currentTime, loopSentence, playing, enCues, activeIndex]);

  const hasRealVideo =
    !!lesson?.videoUrl?.startsWith("http") && !lesson.videoUrl.includes("cdn.example.com");

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

  // Demo clock when CDN video is not available yet.
  useEffect(() => {
    if (hasRealVideo || !playing) return;
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
  }, [hasRealVideo, playing, rate, enCues]);

  const lessonLabel = useMemo(() => {
    if (!course || !lesson) return "";
    return `${lesson.index}/${course.lessons.length}`;
  }, [course, lesson]);

  function seekToCue(index: number) {
    const cue = enCues[index];
    if (!cue) return;
    setActiveIndex(index);
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
            {hasRealVideo ? (
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
                  <div className="en">{cue.text}</div>
                  {bilingual ? (
                    <div className="zh">{zhCues[index]?.text ?? ""}</div>
                  ) : null}
                </button>
              ))}
            </div>
          ) : (
            <div className="muted">{tab} 模式将在 P2 接入完整能力；当前为占位。</div>
          )}

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
              onClick={() => setLoopSentence((v) => !v)}
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
