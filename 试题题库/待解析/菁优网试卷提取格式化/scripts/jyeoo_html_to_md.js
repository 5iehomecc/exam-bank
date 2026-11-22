#!/usr/bin/env node
/**
 * 菁优网试卷 HTML → Markdown 中间稿转换器（确定性后处理）。
 *
 * 输入 JSON:
 * {
 *   "sections": [
 *     { "title": "一．...", "questions": [
 *       { "label": "(出处)", "cate": "9", "reportid": "...", "qid": "...",
 *         "stemHTML": "<div class=\"pt1\">...</div>", "img": "https://..." }
 *     ]}
 *   ]
 * }
 *
 * 输出 JSON:
 * [ { "globalNo": 1, "section": "...", "label": "...", "cate": "9",
 *     "img": "...", "md": "清洗后的 Markdown 题干" } ]
 *
 * 用法: node jyeoo_html_to_md.js <input.json> <output.json>
 *
 * 说明: 本脚本只做结构级清洗（公式分数/上下标/填空线/换行/配图/实体解码），
 * 不负责规则 1.6/1.7 的独立数字空格与独立字母 $ 包裹——那一步由规则
 * （【Rules-数理化试卷】第一章）在人工/规则复核阶段完成。
 */
'use strict';
const fs = require('fs');
const path = require('path');

const [,, inPath, outPath] = process.argv;
if (!inPath || !outPath) {
  console.error('用法: node jyeoo_html_to_md.js <input.json> <output.json>');
  process.exit(1);
}

function decode(s) {
  return s
    .replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'")
    .replace(/&middot;/g, '·');
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

function walkMathJye(node) {
  let out = '';
  for (const c of node.children) {
    if (c.tag === 'text') { out += c.text; continue; }
    if (c.tag === 'div') {
      const cls = c.attrs.class || '';
      if (cls.includes('mfrac')) {
        let zi = '', mu = '';
        for (const d of c.children) {
          const dc = d.attrs ? d.attrs.class || '' : '';
          if (dc.includes('fracZi')) zi = walkMathJye(d);
          if (dc.includes('fracMu')) mu = walkMathJye(d);
        }
        out += `\\frac{${zi}}{${mu}}`;
      } else {
        out += walkMathJye(c);
      }
    } else {
      out += walkMathJye(c);
    }
  }
  return out;
}

function walk(node, ctx) {
  for (const c of node.children) {
    if (c.tag === 'text') { ctx.push(c.text); continue; }
    if (c.tag === 'br') { ctx.push('\n'); continue; }
    if (c.tag === 'img') { ctx.push('\n![Image](' + c.attrs.src + ')\n'); continue; }
    if (c.tag === 'div' && (c.attrs.class || '').includes('quizPutTag')) { ctx.push(' ___ '); continue; }
    if (c.tag === 'div' && (c.attrs.class || '').includes('MathJye')) { ctx.push('$' + walkMathJye(c) + '$'); continue; }
    if (c.tag === 'sub') { const o = []; walk(c, o); ctx.push('_{' + o.join('') + '}'); continue; }
    if (c.tag === 'sup') { const o = []; walk(c, o); ctx.push('^{' + o.join('') + '}'); continue; }
    walk(c, ctx);
  }
}

const data = JSON.parse(fs.readFileSync(inPath, 'utf8'));
const out = [];
let globalNo = 0;
function walkHTML(html) {
  const root = parseHTML(html || '');
  const parts = [];
  walk(root, parts);
  return parts.join('')
    .replace(/[ \t]+/g, ' ')
    .replace(/\n\s*\n/g, '\n')
    .trim();
}
for (const sec of data.sections || []) {
  for (const q of sec.questions || []) {
    globalNo += 1;
    const md = walkHTML(q.stemHTML || '')
      // 去掉题干自带的行首题号（全局题号由遍历顺序重编）
      .replace(/^\d+\.\s*/, '');
    const options = (q.options || []).map(oh => {
      let om = walkHTML(oh);
      const pm = om.match(/^([A-D])[．.、]\s*([\s\S]*)$/);
      if (pm) om = `${pm[1]}. ${pm[2]}`;
      return om;
    });
    out.push({
      globalNo,
      section: sec.title || '',
      label: q.label || '',
      cate: q.cate || '',
      reportid: q.reportid || '',
      qid: q.qid || '',
      img: q.img || '',
      options,
      md,
    });
  }
}

fs.writeFileSync(outPath, JSON.stringify(out, null, 1), 'utf8');
console.log(`已转换 ${out.length} 题 → ${path.resolve(outPath)}`);
