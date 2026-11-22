# 组卷网页面结构、门禁判定与提取要点

> 本文件记录组卷网（zujuan.xkw.com，含 xkw.com 静态域名）组卷详情页的 DOM 结构、登录/付费门禁判定、可复用提取片段与已知坑点。页面改版后先按本文件探查，再修正选择器。

## 1. 入口与可达性

- 链接形态：`https://zujuan.xkw.com/{批次号}.html`（如 `/2p3012600.html`）；题目静态图在 `staticzujuan.xkw.com`、`img.xkw.com` 两个域名。
- **匿名 HTTP 直抓（`Invoke-WebRequest` / fetch）只返回 JS 挑战壳**：页面内是一段混淆的 `hash32` 脚本，读取 `parm_0`/`parm_1` 隐藏域，算哈希后写 cookie 并 `location.reload()`。直抓拿不到题目，不要把直抓结果当作试卷内容。
- 必须走 Browser Use（`computer_use_tool`，`plane="bu"`，`import aha_browser_use as bu`）打开页面；浏览器执行挑战脚本后会自动刷新到正文页。
- 若刷新后仍命中登录/验证门禁（路径含登录注册、出现弹窗），按 browser-use-automation 规则调用 `interaction.request_action`（`type="browserControl"`）交接；交回后重新 `bu.snapshot()` 验证门禁解除。

## 2. 页面分区与选择器

| 用途 | 选择器 / 节点 | 说明 |
|---|---|---|
| 试卷正文容器 | `article.exam-cnt`（内含 `section.exam-list` > `div.sec-item`） | 子节点交替为分节标题 `H4.sec-title` 与题目块 `DIV.sec-list` |
| 分节标题 | 容器内 `H4.sec-title` 文本 | 如「一、单选题」，尾部带「添加题型下试题」按钮文字，提取时剥离；写入 MD 的 `### ` 小节 |
| 题目外壳 | `.tk-quest-item.quesroot` | 属性 `questionid`、`bankid`；外层包一层 `.sec-list` |
| 题干节点 | `.exam-item__cnt` | 内含文字、公式/题图 `<img>`、`<p>` 段落、`<br>`、`<i>` 斜体字母、填空位 `<bk>` |
| 出处标签 | `.ques-src`（`<a>`）文本 | 如 `25-26八年级上·北京西城·期末`；一般每题都有 |
| 题型 | `.left-msg .info-cnt` 第 1 个文本 | 观察到：`单选题`、`填空题`、`解答题-计算题`、`解答题-证明题`、`解答题-作图题`、`解答题-问答题` |
| 难度 | `.left-msg .info-cnt` 第 2 个文本 | 如 `容易 (0.94)`；仅供报告参考，不写进源 MD |
| 标签 | `.right-msg .tag` 文本 | 如 `名校`；留痕用 |
| 选项表 | `table[name=optionsTable] > tbody > tr > td` | 每个 td 一个选项，前缀形如 `A．`；td 内为文字或 `<img>` |
| 配图 | `.exam-item__cnt` 内 `<img src>` | 公式碎片图：`staticzujuan.xkw.com/quesimg/Upload/formula/<hash>.png`；题图/图案：`img.xkw.com/dksih/QBM/editorImg/...png?resizew=64` |
| 答案/解析节点 | `.item.answer` | 公开预览中为空；「详情」「解读」按钮需权限 |

### 2.1 页面元信息（顶部 `h2.exam-title`）

`innerText` 按换行拆分，观察到顺序：试卷全名、地区、年级、考试类型、发布日期（`2026/01/22`）、浏览次数、整体难度、考查范围。年级/学期以页面标注为准；文件名日期取发布日期，格式 `YYYYMMDD`。

## 3. 结构化提取片段（bu.js）

在正文页执行。**注意**：三个分节的外壳相互嵌套，不能用 `h4.parentElement` 圈定题目（会把后续分节全部算入）；正确做法是把 `h4.sec-title` 与 `.tk-quest-item` 合并后按 `compareDocumentPosition` 文档顺序排序，顺序遍历，遇到标题开新节、遇到题目并入当前节。

```js
(() => {
  const markers = [...document.querySelectorAll('h4.sec-title, .tk-quest-item')]
    .sort((a,b)=> (a.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING) ? -1 : 1);
  const sections = []; let cur = null;
  markers.forEach(m => {
    if (m.matches('h4.sec-title')) {
      cur = { title: m.innerText.trim().replace(/\s+/g,' ').replace(/添加题型下试题/,'').trim(), questions: [] };
      sections.push(cur); return;
    }
    if (!cur) return;
    const item = m;
    const cnt = item.querySelector('.exam-item__cnt');
    const srcA = item.querySelector('.ques-src');
    const infos = [...item.querySelectorAll('.left-msg .info-cnt')].map(e=>e.innerText.trim());
    const tag = item.querySelector('.right-msg .tag')?.innerText.trim() || '';
    const optsTable = cnt.querySelector('table[name=optionsTable]');
    const options = optsTable ? [...optsTable.querySelectorAll('td')].map(td=>td.innerHTML.trim()) : [];
    const stemClone = cnt.cloneNode(true);
    stemClone.querySelectorAll('table[name=optionsTable]').forEach(t=>t.remove());
    item.querySelectorAll('[data-inspector-id]').forEach(n=>n.removeAttribute('data-inspector-id'));
    const imgs = [...cnt.querySelectorAll('img')].map(im=>({
      src: im.src, kind: im.src.includes('img.xkw.com') ? 'editor' : 'formula', alt: im.alt || ''
    }));
    cur.questions.push({
      questionid: item.getAttribute('questionid') || '',
      source: srcA ? srcA.innerText.trim() : '',
      type: infos[0] || '', difficulty: infos[1] || '', tag,
      stemHTML: stemClone.innerHTML.trim(), options, images: imgs
    });
  });
  const titleText = document.querySelector('h2.exam-title')?.innerText.trim() || '';
  const lines = titleText.split('\n').map(s=>s.trim()).filter(Boolean);
  return { sections, meta: { url: location.href, lines } };
})()
```

- 全局题号按文档顺序从 1 连续编号；题目外壳内局部序号会重置，不要用局部序号。
- 提取后把 JSON 写入临时目录（如 `%TEMP%\zujuan_paper1\input.json`），再交给 `scripts/zujuan_html_to_md.js` 转换。

## 4. 门禁判定（答案/解析不可见）

公开预览中以下信号同时成立时，判定答案、解析、考点被门禁（需登录/会员或逐题详情权限）：

1. `.item.answer` 节点为空；题目区无答案正文；
2. 整页 HTML / 文本搜索 `【答案】`、`【解析】`、`【考点】` 均 0 命中；
3. 「试卷分析 / 知识点分析」面板只有题型、难度统计，无解析正文与知识点明细。

**处置**：本技能只产出题干与配图的格式化 MD，**不得编造答案、解析、考点**；在交付报告中明确标注「答案/解析被门禁，需下载文件或可访问详情后再补解析」。

## 5. 已知坑点

- **公式无 LaTeX 源码**：公式碎片 `<img>` 的 `latex`、`mathml` 属性为空，站点只给渲染好的 PNG；下载 SVG/PNG 源码确认内部是纯矢量 `<path>` 路径、0 个 `<text>` 节点、无 MathML/annotation；内联 `paperJson` 脚本只含题目 id/知识点/难度元数据；试题接口（`/zujuan-api/paper/getpaper`、`/zujuan-api/question/batch`）对匿名会话返回 401（GET 则 405），即使带 `RequestVerification` token 仍 401。公开渠道拿不到可编辑 LaTeX 原文，只能图片视觉识别转写。

### 5.1 公式碎片视觉转写工作流（可选）

当用户要求把公式图转为 Markdown LaTeX 时，按下列步骤执行（无需登录导出）：

1. 从源 MD 正则抽取 `staticzujuan.xkw.com/quesimg/Upload/formula/<hash>.png` 链接，按出现顺序编号并去重；题图域名 `img.xkw.com` 不参与转写，保留图片不动。
2. 碎片原图下载到临时目录；Pillow 放大 4–6 倍，按 20 张/页拼成带红色编号 `#idx hash6` 的拼图；裁切/粘连条目再单独 6–10 倍放大分张复核。
3. 逐格视觉转写 LaTeX，并结合题干上下文（点/线/角名、单位、坐标、等式两端）交叉核对；模糊或被裁断的碎片单列待复核，不得凭上下文臆造等式结果。
4. 写 `hash → LaTeX` 映射 JSON，按 URL 把 `![Image](url)` 整体替换为 `$latex$`；同一 hash 全卷复用同一转写。
5. 回写后机械审计：公式图残留 0、题图数量不变、`$` 配对为偶数、题号连续、无 HTML 标签/实体/本地图链。
6. 转写写法约定（对齐 Rules 第一章）：三角形 `\triangle ABC`、角 `\angle ABC`、平行 `\parallel`、垂直 `\perp`、全等 `\cong`、分式 `\frac{}{}`、上标 `^{2}`、度 `^{\circ}`、单位 `\mathrm{}`；连续表达式整体 `$` 包裹，选项标签 A./B./C./D. 不包裹。
7. 确不可辨的碎片在交付报告标注题号与待核位置；若用户后续提供登录导出的 Word/PDF，可用高保真源重转。
8. **撇号（对称点）归属易错**：对称点撇号随主体字母（如 C′、A′）；若角顶点是对称点，写作 `\angle MC'N=\alpha`，撇号紧跟 C′，不能误落到后一点 N 上写成 `\angle MCN'`。视觉转写后必须放大原图/PDF 逐字母确认撇号归属。
- **公式碎片图很小**：常见约 40×14px，Read 直读会被尺寸阈值过滤；目检前用 Pillow 放大 4–5 倍（`uv run --python 3.12 --with Pillow`）再看。
- **填空位**：`<bk size="6" index="1" type="underline">______</bk>`，转换器统一转 ` ___ `；裸下划线串残留也会归一。
- **选项表**：选择题选项在独立 `table[name=optionsTable]` 内，提取题干时需整表剥离，选项单独收集；选项前缀 `A．`（全角句点）由转换器归一为 `A. `。
- **段落与换行**：题干正文可能在 `<p>` 内（题图常独占一段），`<br>` 为段内换行；转换器按段落输出空行。
- **斜体字母**：`<i style="font-family: Times New Roman">A</i>` 是点/线字母，转换器解包保留文本；规则 1.7 的 `$` 包裹在人工复核阶段补。
- **复用图片**：同一公式碎片 URL 在全卷反复出现（如三角形记号、线段记号），属正常复用，不是缺图。
- **组合配图**：一道题的一张题图内可能含「图1/图2/图3」或备用图，源试卷阶段保持一题一图，不拆分；拆题阶段再按需处理。
- **年级常已标注**：顶部元信息一般带「八年级」等字样；学期（上/下）结合学年标题判断，推断结果必须在报告中提示用户确认。
- **元信息采集**：试卷标题、地区、年级、考试类型、发布日期、浏览次数、整体难度、考查范围从 `h2.exam-title` 读取；知识点标签在公开面板不可见，不要留空编造。
- **配图水印**：站点原图可能带水印，源试卷阶段保留网络链接；本地化在拆题阶段按规则 4.5 执行。
- **透明底题图在深色主题下发黑**：部分题图为 RGBA 透明底深线图（四角 alpha=0，透明占比常 80%–95%），深色主题下透明区渲染成黑底、深色线条贴黑底看不清，并非后缀错误。校验格式时以下载魔数（PNG `89 50 4E 47`）与 `Content-Type: image/png` 为准；`?resizew=` 只是缩放查询参数。拆题本地化时把这类图统一合成白底（`RGBA` 铺 `(255,255,255,255)` 再转 `RGB`）后存本地；源试卷阶段不改链接。
- **无效回退**：不要猜测题目详情 URL 逐题抓取；详情内容在门禁后，回退抓取同样拿不到解析。
- **用户提供的 PDF 可能是图片型扫描件**：`pymupdf` 每页 `chars=0`、无文字层（常见 Microsoft Print To PDF 导出），不能依赖文本抽取；按 3 倍矩阵 `get_pixmap` 渲染成 PNG 后逐页多模态视觉核对题干、公式、坐标/角度/单位与题图。核对优先级：可编辑 Word > 官方 PDF 参照 > 在线抓取兜底；发现误差以 PDF 像素为准回改 MD，再复跑机械审计。
