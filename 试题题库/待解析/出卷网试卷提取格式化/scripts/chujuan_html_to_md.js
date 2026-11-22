#!/usr/bin/env node
/**
 * 出卷网（chujuan.cn，21cnjy 后端）试卷 HTML → Markdown 中间稿转换器（确定性后处理）。
 *
 * 数据来源：页面 JS 中内嵌的 paper_detail JSON（题干 HTML、选项、子题 list、空位
 * {#blank#}N{#/blank#}、题型、出处均结构化保留），比 DOM 切块更稳，且不会带入
 * 页脚二维码/统计脚本/操作条等噪声。
 *
 * 公式：MathML 编码在 <img class="mathml" src=".../mml2svg?mml=..."> 的 mml 参数里，
 * URL 解码后解析 MathML，确定性转 LaTeX，无需视觉转写。
 *
 * 输入：浏览器/直抓保存的试卷页面 HTML（page.html）。
 * 输出 JSON：{ meta, questions: [{ globalNo, section, source, type, options,
 *                                  imgCount, images, md }] }
 *
 * 用法: node chujuan_html_to_md.js <page.html> <output.json>
 *
 * 说明: 本脚本只做结构级清洗与 MathML→LaTeX 转换；规则 1.6/1.7 的独立数字空格、
 * 独立字母包裹、标点前空格等由人工复核阶段按《Rules-数理化试卷》第一章补全。
 */
'use strict';
const fs = require('fs');
const path = require('path');

const [,, inPath, outPath] = process.argv;
if (!inPath || !outPath) {
  console.error('用法: node chujuan_html_to_md.js <page.html> <output.json>');
  process.exit(1);
}

/* ---------- 实体与编码 ---------- */
function decodeEntities(s) {
  return s
    .replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'")
    .replace(/&#160;/g, ' ').replace(/&#8800;/g, '≠').replace(/&#183;/g, '·')
    .replace(/&#8230;/g, '…').replace(/&middot;/g, '·');
}

function decodeMml(src) {
  try { return decodeURIComponent(src.replace(/\+/g, ' ')); }
  catch { return src; }
}

/* ---------- 通用 HTML 栈解析 ---------- */
function parseHTML(html) {
  const root = { tag: 'root', children: [] };
  const stack = [root];
  const re = /<!--[\s\S]*?-->|<\/?[a-zA-Z][^>]*>|([^<]+)/g;
  let m;
  while ((m = re.exec(html))) {
    const tok = m[0];
    if (tok.startsWith('<!--')) continue;
    if (tok.startsWith('</')) { if (stack.length > 1) stack.pop(); continue; }
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
      stack[stack.length - 1].children.push({ tag: 'text', text: decodeEntities(m[1]) });
    }
  }
  return root;
}

/* ---------- MathML → LaTeX ---------- */
const MO_MAP = {
  '-': '-', '+': '+', '=': '=', ',': ',', '.': '.', ';': ';',
  '⋅': '\\cdot', '·': '\\cdot', '×': '\\times', '÷': '\\div',
  '≠': '\\neq', '‖': '\\parallel', '∘': '\\circ',
  '∠': '\\angle', 'π': '\\pi', '△': '\\triangle', '▵': '\\triangle',
};
const MI_MAP = { '∠': '\\angle', 'π': '\\pi', '△': '\\triangle', '▵': '\\triangle' };

function renderMathml(node) {
  if (node.tag === 'text') return node.text || '';
  const children = node.children || [];
  const kids = () => children.map(renderMathml).join('');
  switch (node.tag) {
    case 'math': return kids();
    case 'mrow': return kids().trim();
    case 'mi': {
      const t = (node.children[0] && node.children[0].text) || '';
      return MI_MAP[t] || t;
    }
    case 'mn': return kids();
    case 'mo': {
      const t = (node.children[0] && node.children[0].text) || '';
      return MO_MAP[t] !== undefined ? MO_MAP[t] : t;
    }
    case 'msup': {
      const [b, s] = node.children.map(renderMathml);
      if (s === "'") return `${b}'`; // 撇号上标：B' 而非 B^{'}
      return `${b}^{${s}}`;
    }
    case 'msub': {
      const [b, s] = node.children.map(renderMathml);
      return `${b}_{${s}}`;
    }
    case 'msubsup': {
      const [b, sub, sup] = node.children.map(renderMathml);
      return `${b}_{${sub}}^{${sup}}`;
    }
    case 'mfrac': {
      const [n, d] = node.children.map(renderMathml);
      return `\\frac{${n}}{${d}}`;
    }
    case 'mfenced': return `(${kids()})`;
    case 'msqrt': return `\\sqrt{${kids()}}`;
    case 'mroot': {
      const [x, n] = node.children.map(renderMathml);
      return `\\sqrt[${n}]{${x}}`;
    }
    case 'mtext': case 'mspace': return kids();
    default: return kids();
  }
}

// 已知 LaTeX 命令白名单（本站 MathML 实际会出现的集合）；
// 命令后若紧跟字母，补一个空格，避免 \cdota 被解析成未定义命令
const CMD_WHITELIST = [
  'frac', 'cdot', 'times', 'div', 'neq', 'parallel', 'angle', 'pi', 'triangle',
  'circ', 'sqrt', 'overline', 'widehat', 'overrightarrow', 'left', 'right',
  'cdots', 'ldots', 'pm', 'le', 'ge', 'infty', 'alpha', 'beta', 'gamma',
  'delta', 'theta', 'lambda', 'mu', 'sigma', 'phi', 'omega', 'Gamma', 'Delta',
  'Theta', 'Sigma', 'Phi', 'Omega', 'mathrm', 'mathbb', 'mathcal', 'text',
  'vec', 'hat', 'bar', 'tilde', 'overline', 'underline',
].join('|');
const CMD_RE = new RegExp('\\\\(' + CMD_WHITELIST + ')', 'g');
function padCommands(latex) {
  return latex.replace(CMD_RE, (match, _g, off, str) =>
    /[a-zA-Z]/.test(str[off + match.length] || '') ? match + ' ' : match);
}

function mathmlToLatex(mmlSrc) {
  const xml = decodeMml(mmlSrc);
  const root = parseHTML(xml);
  return padCommands(renderMathml(root).trim());
}

/* ---------- 题干 HTML → Markdown ---------- */
function walkHTML(node, ctx) {
  for (const c of node.children) {
    if (c.tag === 'text') { ctx.push(c.text); continue; }
    if (c.tag === 'br') { ctx.push('\n'); continue; }
    if (c.tag === 'img') {
      const src = c.attrs.src || '';
      if (c.attrs.class === 'mathml' || src.includes('mml2svg')) {
        const mm = src.match(/mml=([^&]+(?:&[^&]+)*)/);
        if (mm) ctx.push('$' + mathmlToLatex(mm[1]) + '$');
      } else if (!src.includes('/question-sync')) {
        const url = src.startsWith('//') ? 'https:' + src : src;
        ctx.push('![Image](' + url + ')');
      }
      continue;
    }
    if (c.tag === 'span' && /filling/.test(c.attrs.class || '')) {
      ctx.push(' ___ '); continue;
    }
    if (c.tag === 'p') {
      const o = []; walkHTML(c, o);
      const t = o.join('').trim();
      if (t) ctx.push('\n\n' + t + '\n\n');
      continue;
    }
    if (c.tag === 'table') { ctx.push('\n' + tableToMd(c) + '\n'); continue; }
    if (c.tag === 'sub') { const o = []; walkHTML(c, o); ctx.push('_{' + o.join('') + '}'); continue; }
    if (c.tag === 'sup') { const o = []; walkHTML(c, o); ctx.push('^{' + o.join('') + '}'); continue; }
    walkHTML(c, ctx);
  }
}

function tableToMd(table) {
  const rows = [];
  for (const tr of table.children.flatMap(r => r.tag === 'tbody' ? r.children : [r])) {
    if (tr.tag !== 'tr') continue;
    const cells = tr.children.filter(td => ['td', 'th'].includes(td.tag)).map(td => {
      const o = []; walkHTML(td, o);
      return o.join('').replace(/\s+/g, ' ').trim();
    });
    rows.push(cells);
  }
  if (!rows.length) return '';
  const width = Math.max(...rows.map(r => r.length));
  const pad = r => Array.from({ length: width }, (_, i) => r[i] || '');
  const lines = [pad(rows[0]).join(' | '), pad(rows[0]).map(() => '---').join(' | ')];
  for (const r of rows.slice(1)) lines.push(pad(r).join(' | '));
  return '\n' + lines.join('\n') + '\n';
}

function htmlToMd(html) {
  const root = parseHTML(html || '');
  const parts = [];
  walkHTML(root, parts);
  return parts.join('')
    .replace(/\{#blank#\}\d+\{#\/blank#\}/g, ' ___ ') // 空位标记
    .replace(/[ \t]+/g, ' ')
    .replace(/\n[ \t]+/g, '\n')
    .replace(/\n{3,}/g, '\n\n')
    .replace(/_{2,}/g, ' ___ ')
    // 相邻两个 <sub>（如 P<sub>6</sub><sub>0°</sub>）合并为同一个下标
    .replace(/_{([^{}]*)}_{([^{}]*)}/g, '_{$1$2}')
    .trim();
}

/* ---------- 提取内嵌 paper_detail JSON（括号配对） ---------- */
function extractPaperDetail(html) {
  const key = 'paper_detail: ';
  const i = html.indexOf(key);
  if (i < 0) throw new Error('页面中未找到 paper_detail');
  let j = i + key.length, depth = 0, inStr = false, esc = false;
  while (j < html.length) {
    const c = html[j];
    if (inStr) {
      if (esc) esc = false;
      else if (c === '\\') esc = true;
      else if (c === '"') inStr = false;
    } else {
      if (c === '"') inStr = true;
      else if (c === '{') depth += 1;
      else if (c === '}') { depth -= 1; if (depth === 0) break; }
    }
    j += 1;
  }
  return JSON.parse(html.slice(i + key.length, j + 1));
}

const html = fs.readFileSync(inPath, 'utf8');
const detail = extractPaperDetail(html);

const meta = {
  title: detail._meta.title || '',
  addtime: String(detail._meta.addtime || ''),
  term: detail._meta.term || '',
  paperType: detail._meta.paper_type || '',
  formatTime: detail._meta.format_examine_time || '',
};

const CN_NUM = ['一', '二', '三', '四', '五'];
const out = [];
let globalNo = 0;

for (const sec of detail.content) {
  const secTitle = sec.head_title || '';
  for (const q of sec.questions) {
    globalNo += 1;
    const stemHTML = q.question_text || q.title || '';
    const source = (q.paper_source && q.paper_source.source_text) || '';
    const type = q.channel_type_name || '';

    // 选项（JSON 选项值即为含图 HTML；null 表示无选项）
    const options = [];
    if (q.options) {
      for (const L of ['A', 'B', 'C', 'D']) {
        const oh = q.options[L];
        if (!oh) continue;
        let meatMd = htmlToMd(oh);
        // 去除内嵌重复标签：藏在公式首位的 $B. 只删标签、保留包裹 $；纯文本 B. 整段删
        meatMd = meatMd.replace(/^\$[A-D]\s*[．.、]/, '$')
          .replace(/^\s*[A-D]\s*[．.、]\s*/, '');
        options.push(`${L}. ${meatMd}`.trim());
      }
    }

    // 子题（list）：（1）（2）… 依次拼接到题干后
    const subs = (q.list || []).map((sub, idx) => {
      const subMd = htmlToMd(sub.question_text || '');
      return `（${idx + 1}）${subMd}`;
    });

    const stemMd = htmlToMd(stemHTML);
    const md = [stemMd, ...subs].filter(Boolean).join('\n\n');

    // 配图清单（题干 + 选项 + 子题）
    const imgs = [];
    for (const frag of [stemHTML, ...Object.values(q.options || {}), ...(q.list || []).map(s => s.question_text || '')]) {
      for (const x of frag.matchAll(/<img[^>]*src="([^"]+)"/g)) {
        const src = x[1];
        if (src.includes('mml2svg') || src.includes('tikupic.21cnjy.com')) imgs.push(src);
      }
    }

    out.push({
      globalNo,
      section: secTitle,
      source,
      type,
      options,
      imgCount: imgs.length,
      images: imgs,
      md,
    });
  }
}

fs.writeFileSync(outPath, JSON.stringify({ meta, questions: out }, null, 1), 'utf8');
console.log(`已提取 ${out.length} 题 → ${path.resolve(outPath)}`);
