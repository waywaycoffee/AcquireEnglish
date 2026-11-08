import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { api, type Course } from "../api";
import { useAuth } from "../auth";

export default function HomePage() {
  const { user, logout } = useAuth();
  const [courses, setCourses] = useState<Course[]>([]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api
      .courses()
      .then(setCourses)
      .catch((err) => setError(err instanceof Error ? err.message : "Failed to load courses"));
  }, []);

  return (
    <div className="shell">
      <header className="topbar">
        <div>
          <div className="brand">AcquireEnglish</div>
          <div className="muted">你好，{user?.display_name ?? user?.email}</div>
        </div>
        <button className="btn ghost" type="button" onClick={logout}>
          退出
        </button>
      </header>

      <section>
        <h2 style={{ fontFamily: "var(--font-display)", marginBottom: 8 }}>推荐课程</h2>
        <p className="muted" style={{ marginTop: 0 }}>
          云端课程包 · 与手机 App 共用进度
        </p>
        {error ? <div className="error">{error}</div> : null}
        <div className="grid-courses">
          {courses.map((course) => (
            <Link key={course.id} to={`/courses/${course.id}`} className="card">
              <div className="muted" style={{ fontSize: 12, marginBottom: 8 }}>
                {course.level} · {course.lessons.length} 课段
              </div>
              <div style={{ fontSize: "1.2rem", fontWeight: 700 }}>
                {course.titleZh ?? course.title}
              </div>
              <p className="muted" style={{ marginBottom: 0 }}>
                {course.description}
              </p>
            </Link>
          ))}
        </div>
      </section>
    </div>
  );
}
