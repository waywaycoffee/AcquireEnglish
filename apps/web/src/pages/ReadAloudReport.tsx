import { useEffect, useState } from "react";
import { api, type ReadAloudAttempt } from "../api";

function localDay(date: Date) {
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return [date.getFullYear(), month, day].join("-");
}

export default function ReadAloudReport({ token }: { token: string }) {
  const now = new Date();
  const today = localDay(now);
  const since = localDay(new Date(now.getFullYear(), now.getMonth(), now.getDate() - 29));
  const [day, setDay] = useState(today);
  const [attempts, setAttempts] = useState<ReadAloudAttempt[] | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let request: AbortController | undefined;
    async function refresh() {
      request?.abort();
      const controller = new AbortController();
      request = controller;
      try {
        const rows = await api.readAloud(token, since, controller.signal);
        if (!controller.signal.aborted) {
          setAttempts(rows);
          setFailed(false);
        }
      } catch {
        if (!controller.signal.aborted) setFailed(true);
      }
    }
    void refresh();
    window.addEventListener("focus", refresh);
    return () => {
      request?.abort();
      window.removeEventListener("focus", refresh);
    };
  }, [token, since]);

  const daily = attempts?.filter((attempt) => attempt.day === day) ?? [];
  const seconds = Math.round(daily.reduce((sum, attempt) => sum + attempt.durationMs, 0) / 1000);
  const counts = new Map<string, number>();
  for (const attempt of daily) {
    for (const word of new Set(attempt.weakWords)) {
      counts.set(word, (counts.get(word) ?? 0) + 1);
    }
  }
  const weakWords = [...counts].sort(([a, countA], [b, countB]) =>
    countB - countA || a.localeCompare(b),
  ).slice(0, 8);

  return (
    <section className="card" style={{ marginBottom: 24 }}>
      <h2>每日朗读报告</h2>
      <label>
        报告日期{" "}
        <input type="date" value={day} min={since} max={today}
          onChange={(event) => setDay(event.currentTarget.value || today)} />
      </label>
      {failed && <p role="status">报告暂时无法同步，切回本页时会重试。</p>}
      {attempts === null && !failed && <p role="status">正在加载报告…</p>}
      {attempts !== null && (
        <>
          <p>{Math.floor(seconds / 60)} 分 {seconds % 60} 秒 · {daily.length} 次录音</p>
          {weakWords.length > 0 && (
            <>
              <h3>发音薄弱词</h3>
              <ul>{weakWords.map(([word, count]) => <li key={word}>{word} · {count} 次</li>)}</ul>
            </>
          )}
        </>
      )}
    </section>
  );
}
