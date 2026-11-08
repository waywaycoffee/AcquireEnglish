export type Cue = {
  id: number;
  start: number;
  end: number;
  text: string;
};

function parseTimestamp(value: string): number {
  const cleaned = value.trim().replace(",", ".");
  const parts = cleaned.split(":");
  if (parts.length !== 3) return 0;
  const [h, m, rest] = parts;
  const sec = Number(rest);
  return Number(h) * 3600 + Number(m) * 60 + (Number.isFinite(sec) ? sec : 0);
}

export function parseSrt(content: string): Cue[] {
  const blocks = content.replace(/\r/g, "").split(/\n\n+/);
  const cues: Cue[] = [];
  for (const block of blocks) {
    const lines = block.split("\n").filter(Boolean);
    if (lines.length < 2) continue;
    const timeLine = lines.find((l) => l.includes("-->"));
    if (!timeLine) continue;
    const [startRaw, endRaw] = timeLine.split("-->");
    const textLines = lines.slice(lines.indexOf(timeLine) + 1);
    cues.push({
      id: cues.length + 1,
      start: parseTimestamp(startRaw),
      end: parseTimestamp(endRaw),
      text: textLines.join(" ").trim(),
    });
  }
  return cues;
}

export function formatTime(sec: number): string {
  const s = Math.max(0, Math.floor(sec));
  const m = Math.floor(s / 60);
  const r = s % 60;
  return `${m}:${r.toString().padStart(2, "0")}`;
}

export function findActiveCueIndex(cues: Cue[], t: number): number {
  if (!cues.length) return -1;
  let lo = 0;
  let hi = cues.length - 1;
  let ans = -1;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    const cue = cues[mid];
    if (t < cue.start) hi = mid - 1;
    else if (t > cue.end) lo = mid + 1;
    else return mid;
  }
  // fallback: last cue that started
  for (let i = cues.length - 1; i >= 0; i -= 1) {
    if (t >= cues[i].start) {
      ans = i;
      break;
    }
  }
  return ans;
}
