/**
 * Render reading_bookshelf.pen boards → PNGs (+ combined preview SVG/PNG).
 * Uses @resvg/resvg-js at 2× (~780×1688 phone frames).
 */
import { Resvg } from '@resvg/resvg-js';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const designDir = path.resolve(__dirname, '../..');
const outDir = __dirname;
const pen = JSON.parse(
  fs.readFileSync(path.join(designDir, 'reading_bookshelf.pen'), 'utf8'),
);

function esc(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function renderNode(node, ox, oy) {
  const x = (node.x ?? 0) + ox;
  const y = (node.y ?? 0) + oy;
  const parts = [];

  if (node.type === 'frame') {
    const w = node.width ?? 0;
    const h = node.height ?? 0;
    const r = node.cornerRadius ?? 0;
    if (node.fill) {
      parts.push(
        `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${r}" ry="${r}" fill="${esc(node.fill)}"/>`,
      );
    }
    for (const child of node.children ?? []) {
      parts.push(renderNode(child, x, y));
    }
  } else if (node.type === 'text') {
    const size = node.fontSize ?? 14;
    const family = node.fontFamily ?? 'Georgia';
    const fill = node.fill ?? '#000';
    // CJK fallbacks so Windows resvg can paint 中文 labels
    const fontStack = `${esc(family)}, 'Microsoft YaHei', 'PingFang SC', 'Noto Sans SC', sans-serif`;
    const lines = String(node.content ?? '').split('\n');
    const lineH = Math.round(size * 1.25);
    lines.forEach((line, i) => {
      const ty = y + i * lineH;
      parts.push(
        `<text x="${x}" y="${ty}" fill="${esc(fill)}" font-family="${fontStack}" font-size="${size}" dominant-baseline="hanging">${esc(line)}</text>`,
      );
    });
  }
  return parts.join('\n');
}

function boardSvg(frame, { pad = 0, bg = null, label = null } = {}) {
  const w = frame.width + pad * 2;
  const h = frame.height + pad * 2 + (label ? 36 : 0);
  const oy = pad + (label ? 36 : 0);
  const body = renderNode(
    { ...frame, x: pad, y: 0 },
    0,
    oy,
  );
  const labelEl = label
    ? `<text x="${pad}" y="22" fill="#5C3D2E" font-family="Georgia,serif" font-size="14" font-weight="700">${esc(label)}</text>`
    : '';
  const bgRect = bg
    ? `<rect width="${w}" height="${h}" fill="${esc(bg)}"/>`
    : '';
  return {
    width: w,
    height: h,
    svg:
      `<?xml version="1.0" encoding="UTF-8"?>\n` +
      `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">\n` +
      `${bgRect}${labelEl}${body}\n</svg>\n`,
  };
}

function combinedPreview(frames) {
  const gap = 36;
  const left = 24;
  const top = 48;
  const phoneW = 390;
  const phoneH = 844;
  const width = left * 2 + phoneW * 3 + gap * 2;
  const height = top + phoneH + 48;
  const labels = [
    '01 浅橡木 · 封面朝外',
    '02 深胡桃 · 暖色书脊',
    '03 空书架 · 冷启动',
  ];
  const parts = [
    `<rect width="${width}" height="${height}" fill="#E5D9C6"/>`,
    `<text x="28" y="30" font-family="Georgia,serif" font-size="16" font-weight="700" fill="#3D2A1F">Pencil 书架稿 / reading_bookshelf</text>`,
  ];
  frames.forEach((frame, i) => {
    const ox = left + i * (phoneW + gap);
    const shifted = { ...frame, x: ox, y: top };
    parts.push(renderNode(shifted, 0, 0));
    parts.push(
      `<text x="${ox}" y="${top + phoneH + 28}" class="label" fill="#5C3D2E" font-family="Georgia,serif" font-size="14">${esc(labels[i])}</text>`,
    );
  });
  return {
    width,
    height,
    svg:
      `<?xml version="1.0" encoding="UTF-8"?>\n` +
      `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">\n` +
      `${parts.join('\n')}\n</svg>\n`,
  };
}

function writePng(svgText, outName, widthPx) {
  const resvg = new Resvg(svgText, {
    fitTo: { mode: 'width', value: widthPx },
    font: {
      loadSystemFonts: true,
      defaultFontFamily: 'Georgia',
    },
  });
  const png = resvg.render().asPng();
  const outPath = path.join(outDir, outName);
  fs.writeFileSync(outPath, png);
  console.log(`${outName}: ${png.length} bytes → ${outPath}`);
  return outPath;
}

const frames = pen.children.filter((c) => c.type === 'frame');
const map = {
  'bs-light': 'shelf-light.png',
  'bs-dark': 'shelf-dark.png',
  'bs-empty': 'shelf-empty.png',
};

const paths = [];
for (const frame of frames) {
  const name = map[frame.id];
  if (!name) continue;
  const { svg } = boardSvg(frame);
  // keep a per-board SVG for debugging
  fs.writeFileSync(path.join(outDir, name.replace('.png', '.svg')), svg, 'utf8');
  paths.push(writePng(svg, name, frame.width * 2));
}

const preview = combinedPreview(frames);
const previewSvgPath = path.join(designDir, 'reading_bookshelf_preview.svg');
fs.writeFileSync(previewSvgPath, preview.svg, 'utf8');
console.log(`updated preview SVG → ${previewSvgPath}`);
paths.push(writePng(preview.svg, 'reading_bookshelf_preview.png', preview.width * 2));

console.log(JSON.stringify(paths, null, 2));
