#!/usr/bin/env node
/**
 * 组卷网（zujuan.xkw.com / xkw.com）试卷 HTML → Markdown 中间稿转换器（确定性后处理）。
 *
 * 输入 JSON（由浏览器 DOM 提取片段产出）:
 * {
 *   "meta": { "url": "...", "lines": [...] },
 *   "sections": [
 *     { "title": "一、单选题", "questions": [
 *       { "questionid": "...", "source": "(出处)", "type": "单选题",
 *         "difficulty": "容易 (0.94)", "tag": "名校",
 *         "stemHTML": "<div class=\"exam-item__cnt\">...</div>",
 *         "options": ["A．<img ...>", ...],
 *         "images": [{ "src": "...", "kind": "formula|editor", "alt": "" }] }
 *     ]}
 *   ]
 * }
 *
 * 输出 JSON:
 * [ { "globalNo": 1, "section": "...", "source": "...", "type": "...",
 *     "difficulty": "...", "tag": "...", "qid": "...",
 *     "options": ["A. ...", ...], "imgCount": n, "md": "清洗后的题干" } ]
 *
 * 用法: node zujuan_html_to_md.js <input.json> <output.json>
 *
 * 说明: 本脚本只做结构级清洗（标签剥离、填空线、换行、配图 Markdown、实体解码、
 * 选项标签归一、行首旧题号剥离）；不负责规则 1.6/1.7 的独立数字空格与独立字母
 * `$` 包裹——那一步由规则（【Rules-数理化试卷】第一章）在人工复核阶段完成。
 *
 * 组卷网已知结构事实:
 * - 公式与题图多为 PNG 图片（staticzujuan.xkw.com / img.xkw.com），img 的
 *   latex / mathml 属性为空，无 LaTeX 源码，图片在源卷阶段保留网络链接；
 * - 填空位为 `<bk type="underline">______</bk>`；
 * - 选择题选项在 `table[name=optionsTable]` 的 td 内，前缀形如 `A．`；
 * - 题干含 `<p>` 段落、`<br>`、`<i>` 斜体字母、`<span>` 空格占位。
 */
'use strict';
const fs = require('fs');
const path = require('path');

const [,, inPath, outPath] = process.argv;
if (!inPath || !outPath) {
  console.error('用法: node zujuan_html_to_md.js <input.json> <output.json>');
  process.exit(1);
}

function decode(s) {
  return s
    .replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'")
    .replace(/&middot;/g, '·').replace(/&#160;/g, ' ');
}

function parseHTML(html) {
  const root = { tag: 'root', children: [] };
  const stack = [root];
  const re = /<!--[\s\S]*?-->|<\/?[a-zA-Z][^>]*>|([^<]+)/g;
  let m;
  while ((m = re.exec(html))) {
    const tok = m[0];
    if (tok.startsWith('<!--')) continue;
    if (tok.startsWith('</')) { stack.pop(); continue; }
    if (tok.startsWith('<')) {
      const tagM = tok.match(/^<([a-zA-Z0-9]+)/);
      const tag = tagM ? tagM[1].toLowerCase() : '';
      const attrs = {};
      const am = /([a-zA-Z-]+)="([^"]*)"/g; let a;
      while ((a = am.exec(tok))) attrs[a[1]] = a[2];
      const node = { tag, attrs, children: [] };
      stack[stack.length - 1].children.push(node);
      if (!/\/>$/.test(tok) && !['br', 'img', 'hr', 'input'].includes(tag)) stack.push(node);
    } else if (m[1] !== undefined) {
      stack[stack.length - 1].children.push({ tag: 'text', text: decode(m[1]) });
    }
  }
  return root;
}

function walk(node, ctx) {
  for (const c of node.children) {
    if (c.tag === 'text') { ctx.push(c.text); continue; }
    if (c.tag === 'br') { ctx.push('\n'); continue; }
    if (c.tag === 'img') {
      ctx.push('![Image](' + c.attrs.src + ')');
      continue;
    }
    if (c.tag === 'bk') { ctx.push(' ___ '); continue; }
    if (c.tag === 'p') {
      const o = []; walk(c, o);
      const t = o.join('').trim();
      if (t) ctx.push('\n\n' + t + '\n\n');
      continue;
    }
    if (c.tag === 'sub') { const o = []; walk(c, o); ctx.push('_{' + o.join('') + '}'); continue; }
    if (c.tag === 'sup') { const o = []; walk(c, o); ctx.push('^{' + o.join('') + '}'); continue; }
    // i / span / b / div / 其他包裹标签：解包，保留内部文本与图片
    walk(c, ctx);
  }
}

function walkHTML(html) {
  const root = parseHTML(html || '');
  const parts = [];
  walk(root, parts);
  return parts.join('')
    .replace(/[ \t]+/g, ' ')
    .replace(/\n[ \t]+/g, '\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

const data = JSON.parse(fs.readFileSync(inPath, 'utf8'));
const out = [];
let globalNo = 0;

function normalizeOption(om) {
  let md = walkHTML(om);
  // 选项标签归一：A． / A. / A、 → A.
  const pm = md.match(/^\s*([A-D])[．.、]\s*([\s\S]*)$/);
  if (pm) md = `${pm[1]}. ${pm[2]}`;
  return md.trim();
}

for (const sec of data.sections || []) {
  for (const q of sec.questions || []) {
    globalNo += 1;
    let md = walkHTML(q.stemHTML || '')
      // 去掉题干自带的行首题号（全局题号由遍历顺序重编）
      .replace(/^\d+\s*[．.、]\s*/, '');
    // 裸下划线串（未被 bk 包裹的残留）统一为填空线
    md = md.replace(/_{2,}/g, ' ___ ');
    const options = (q.options || []).map(normalizeOption);
    out.push({
      globalNo,
      section: sec.title || '',
      source: q.source || '',
      type: q.type || '',
      difficulty: q.difficulty || '',
      tag: q.tag || '',
      qid: q.questionid || '',
      options,
      imgCount: (q.images || []).length,
      images: (q.images || []).map(im => ({ src: im.src, kind: im.kind || '' })),
      md,
    });
  }
}

fs.writeFileSync(outPath, JSON.stringify(out, null, 1), 'utf8');
console.log(`已转换 ${out.length} 题 → ${path.resolve(outPath)}`);
