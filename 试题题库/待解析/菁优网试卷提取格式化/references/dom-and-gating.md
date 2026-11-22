# 菁优网页面结构、门禁判定与提取要点

> 本文件记录菁优网（jyeoo.com）分享组卷页的 DOM 结构、登录/付费门禁判定、可复用提取片段与已知坑点。页面改版后先按本文件探查，再修正选择器。

## 1. 入口与可达性

- 分享链接形态：`https://www.jyeoo.com/{学科}/paper/share/{uuid}`，学科路径观察到 `math`；物理/化学路径按站点实际命名为准。
- **匿名 HTTP 直抓（`Invoke-WebRequest` / fetch）只返回首页外壳，题目由浏览器端加载**，不要把直抓结果当作试卷内容。
- 必须走 Browser Use（`computer_use_tool`，`plane="bu"`，`import aha_browser_use as bu`）打开页面。
- 匿名访问可能被重定向到登录页（路径含 `/account/loginform`）。命中登录/验证门禁时，按 browser-use-automation 规则调用 `interaction.request_action`（`type="browserControl"`）交接给用户扫码/登录；交回后重新 `bu.snapshot()` 或 `bu.page_info()` 验证门禁已解除，不要凭旧 ref 继续操作。

## 2. 页面分区与选择器

| 用途 | 选择器 / 节点 | 说明 |
|---|---|---|
| 试卷详情容器 | `.zjqPaperDetail` | 子节点交替为 `H4` 分节标题与题目列表 `UL` |
| 分节标题 | 容器内 `H4` 文本 | 如「一．见中点连中线（共3小题）」，写入 MD 的 `### ` 小节 |
| 题目外壳 | `fieldset.quesborder` | 每题一个；题干在 `.pt1` |
| 题干节点 | `.pt1` | 内含文字、`MathJye` 公式块、`<sub>/<sup>`、配图 `<img>`、填空位 `.quizPutTag` |
| 出处标签 | `fieldset` 的 `data-label` 属性 | 如 `（2021秋•松山区期中）`；可能为空（个别题无标签） |
| 题型码 | `fieldset` 的 `data-cate` 属性 | 观察到：`2`=填空题，`9`=解答/证明题；其他码按页面实际题型核对 |
| 题目标识 | `data-reportid`、`id`（qid） | 仅作留痕，不用于拼详情 URL（见第 5 节） |
| 配图 | `.pt1` 内 `<img>` 的 `src` | 静态域名 `img.jyeoo.net`；匿名 HEAD/GET 可访问 |
| 答案/解析节点 | `.pt2` | 公开预览中通常为空；`.ctrl-btn .fleft` 无答案按钮 |

### 2.1 页签

- **组卷详情**：题干、配图、出处、题型码（提取主用）。
- **组卷分析**：难度（较易/中档/较难/难）与知识点映射，供后续解析阶段填 `knowledge`；本阶段只在报告中汇总，不写进源试卷 MD。

## 3. 结构化提取片段（bu.js）

在「组卷详情」页签执行，返回 `{sections, meta}` 落盘为临时 JSON：

```js
(() => {
  const d = document.querySelector('.zjqPaperDetail');
  const sections = [];
  let cur = null;
  [...d.children].forEach(c => {
    if (c.tagName === 'H4') {
      cur = { title: c.innerText.trim(), questions: [] };
      sections.push(cur);
    } else {
      c.querySelectorAll('fieldset.quesborder').forEach(fs => {
        const pt1 = fs.querySelector('.pt1');
        const img = pt1 ? pt1.querySelector('img') : null;
        cur.questions.push({
          label: fs.getAttribute('data-label') || '',
          cate: fs.getAttribute('data-cate') || '',
          reportid: fs.getAttribute('data-reportid') || '',
          qid: fs.id || '',
          stemHTML: pt1 ? pt1.innerHTML : '',
          img: img ? img.src : ''
        });
      });
    }
  });
  return { sections, meta: { url: location.href } };
})()
```

- 全局题号按文档顺序从 1 连续编号；`fieldset` 内局部序号会重置，不要用局部序号。
- 提取后把 JSON 写入临时目录（如 `%TEMP%\jyeoo_paper.json`），再交给 `scripts/jyeoo_html_to_md.js` 转换。

## 4. 门禁判定（答案/解析不可见）

公开预览中以下信号同时成立时，判定答案、解析、考点被门禁（需 VIP 下载或逐题详情权限）：

1. `.pt2` 节点为空；`.ctrl-btn .fleft` 无答案按钮；
2. 整页 HTML / 文本搜索 `【答案】`、`【解析】`、`【考点】` 均 0 命中；
3. 「组卷分析」页签只有难度与知识点统计，无解析正文。

**处置**：本技能只产出题干与配图的格式化 MD，**不得编造答案、解析、考点**；在交付报告中明确标注「答案/解析被门禁，需下载文件或可访问详情后再补解析」。

## 5. 已知坑点

- **详情 URL 猜测无效**：`/math/question/{qid}`、`/math/question/{reportid}` 均 404，不要据此回退抓取。
- **组合配图**：一道题的一张图内可能含「图1/图2/图3」或「备用图1/备用图2」，源试卷阶段保持一题一图，不拆分；拆题阶段再按需处理。
- **公式块结构**：分数在 `.MathJye .mfrac`（`.fracZi` 分子 / `.fracMu` 分母）；圈数 `①②③` 是 `.mo`；字母在 `.math-letter(-i)`。转换器已覆盖，若遇新公式结构先在临时稿目检。
- **填空位**：`.quizPutTag` 是可编辑空 div，两侧带 `<!--BA-->/<!--EA-->` 注释；统一转为 ` ___ `（规则 2.3 两侧空格）。
- **年级常缺省**：页面标题区一般不标年级。依据作者其它卷标题（如「初二上学期…」）与考点章节推断；推断结果必须在报告中提示用户确认，不要写死为既定事实。
- **元信息采集**：试卷标题、发布时间、标签（易错题/拔高题/综合试题/压轴题）、作者名从页面顶部文本读取；作者其它卷列表用于年级推断。
- **配图水印**：站点原图带菁优水印，源试卷阶段保留网络链接；本地化在拆题阶段按规则 4.5 执行。
