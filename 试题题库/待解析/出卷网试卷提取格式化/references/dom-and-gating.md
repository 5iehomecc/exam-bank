# 出卷网页面结构、门禁判定与提取要点

> 本文件记录出卷网（chujuan.cn，21cnjy 后端）试卷详情页的可达性、内嵌 JSON 结构、门禁判定、MathML 转换约定与已知坑点。页面改版后先按本文件探查，再修正转换器与选择器。

## 1. 入口与可达性

- 链接形态：`https://www.chujuan.cn/paper/view-{pid}.shtml`（如 `/paper/view-5922106.shtml`）。
- **匿名 HTTP 直抓即可拿到正文 HTML**：页面内没有组卷网式混淆 hash 挑战壳，也不强制登录；`Invoke-WebRequest` / fetch 保存的 HTML 已含全部题目正文。**不需要** Browser Use 交接；浏览器仅在直抓被限流或返回登录壳时才作为兜底。
- 静态资源域名：
  - 公式 SVG：`//math.21cnjy.com/math2svg/mml2svg?mml=<URL 编码的 MathML>`，`mml=` 参数是可解码的 MathML 源码。
  - 题图/图案：`//tikupic.21cnjy.com/yyyy/mm/dd/xx/xx/<hash>.png`。
- 若直抓返回 401/登录弹窗或验证页：按 browser-use-automation 规则交接用户；交回后重新保存 HTML 验证正文到位。

## 2. 内嵌 paper_detail JSON（主数据源）

页面 JS 中 `Application.PaperShowView({ ... paper_detail: {...} ... })` 内嵌一段完整 JSON。转换器按 `paper_detail: ` 起点做**括号配对**提取（字符串内转义须跳过），再 `JSON.parse`，不要用贪婪正则截断。

### 2.1 `_meta` 元信息

| 字段 | 用途 |
|---|---|
| `title` | 试卷全名，写入 MD 标题 |
| `term` | 年级学期（如「八年级上学期」）；`term_id` 对应编码 |
| `paper_type` | 考试类型（如「期末考试」） |
| `format_examine_time` | 发布日期 `YYYY-MM-DD`，落盘文件名日期取此值 |
| `question_num` | 题量；提取后必须与实际题目数一致 |
| `xdName` / `xkName` | 学段 / 学科 |

### 2.2 `content[]` 分节与 `questions[]` 题目

- `content[i].head_title`：分节标题（如「一、选择题（本大题共30分，每小题3分)」），写入 MD 的 `## ` 小节。
- `content[i].questions[]` 题目数组，字段：

| 字段 | 用途 |
|---|---|
| `tihao` | 题号数组（单元素），仅作核对，不直接写入 MD |
| `channel_type_name` | 题型：单选题、填空题、计算题、解答题、证明题、作图题等 |
| `title` / `question_text` | 题干 HTML（含公式 `<img class="mathml">`、题图 `<img>`、`<p>`、`<sub>`、填空 `<span class="filling">`）；转换器以 `question_text` 为准 |
| `options` | 选项对象 `{A: html, B: html, ...}`；值为文字 HTML 或图片 HTML；`null` 表示无选项（填空/解答题） |
| `paper_source.source_text` | 出处标签（如 `2025八上·海淀期末`、`2026·宿迁模拟`） |
| `list[]` | 子题（多小问）：每项 `question_text`，按顺序作为（1）（2）… 拼到题干后 |
| `answer` / `answer_json` / `explanation` | 公开预览为空；门禁信号（见第 4 节） |
| `knowledge_info` / `t_knowledge` / `knowledge` | 知识点标签与考点图，**本阶段不写入源 MD**，留待解析阶段参考 |

### 2.3 空位与标记

- 填空位：`<span class="filling" ></span>`；填空题题干里也可能出现 `{#blank#}1{#/blank#}` 占位串。两类统一转 ` ___ `。
- 下划线填空：`<u>　▲　</u>` 中的三角符号 ▲ 保留，作为作答占位标记。
- 相邻两个 `<sub>`（如 `P<sub>6</sub><sub>0°</sub>`）是站点 HTML 双下标写法，转换器合并为同一个 `_{60°}`。

## 3. MathML → LaTeX 约定

公式 `<img>` 的 `mml=` 参数先 `decodeURIComponent`（`+` 还原为空格），再按 MathML 树递归渲染：

| MathML 节点 | LaTeX 约定 |
|---|---|
| `mi` | 字母原样；`∠`→`\angle`、`π`→`\pi`、`△/▵`→`\triangle` |
| `mo` | `- + = , . ;` 原样；`⋅/·`→`\cdot`、`×`→`\times`、`÷`→`\div`、`≠`→`\neq`、`‖`→`\parallel`、`∘`→`\circ` |
| `msup` | 上标 `^{...}`；上标仅为撇号 `'` 时渲染为主体加撇号（`B'`，不写 `B^{'}`） |
| `msub` | 下标 `_{...}` |
| `msubsup` | `_{...}^{...}` |
| `mfrac` | `\frac{}{}` |
| `mfenced` | `(...)` |
| `msqrt` / `mroot` | `\sqrt{}` / `\sqrt[n]{}` |
| `mtext` / `mspace` | 解包保留内部文本 |

### 3.1 命令后空格

LaTeX 命令（`\frac` `\cdot` `\angle` 等）后紧跟字母时必须补一个空格，否则 `\cdota` 会被解析成未定义命令。转换器用**已知命令白名单**匹配（不能用通用 `[a-zA-Z]+` 贪婪匹配，否则会把命令名自己劈开，如 `\fra c`）。白名单见 `scripts/chujuan_html_to_md.js` `CMD_WHITELIST`，遇到新命令先补进白名单。

## 4. 门禁判定（答案/解析不可见）

公开预览中以下信号同时成立时，判定答案、解析、考点被门禁：

1. 题目 `answer` 为 `""` / `null`，`answer_json` 为空数组，`explanation` 为 `null`；
2. 整页 HTML / 文本搜索 `【答案】`、`【解析】`、`【考点】`、`【易错点】`、`故选`、`故答案为` 均 0 命中；
3. 「试卷分析 / 知识点分析」面板只有题型、难度统计，无解析正文。

**处置**：本技能只产出题干与配图的格式化 MD，**不得编造答案、解析、考点**；交付报告中明确标注「答案/解析被门禁，需下载文件或可访问详情后再补解析」。

## 5. 已知坑点与处置

- **选项内嵌重复标签**：个别选项公式 MathML 首位带了选项字母与句点（如 `B.` 藏在公式里），转换器剥离内嵌标签、保留外层 `A. ` 前缀；纯文本标签与公式内标签两种形态都要处理。
- **坐标内逗号缺失（源 MathML 漏编）**：个别坐标括号内的逗号在 MathML 里被省略（如 `C₃(0,-1/2)` 写成 `0-1/2`），对照 PDF 目检后在人工复核阶段补回逗号；不要凭上下文臆造其它等式。
- **源文印刷瑕疵保留**：题干中个别多余标点/括号（如「相交于点O，.」「（a，b，（c都是整数，且（a<b)」）在原卷 PDF 中即如此印刷，属源文原样，**不做"纠错"**；仅在与 PDF 不一致时以 PDF 为准。
- **页脚噪声**：最后一题块后常跟二维码 `/question-sync/test-qrcode?id=...`、「微信扫码预览」「试题分析/题量分析/难度分析」面板、统计脚本与第三方统计代码；转换器按数据源 JSON 提取天然规避，DOM 兜底切块时必须在这些标记处截断。
- **题图复用**：同一题图 URL 全卷反复出现属正常复用，不是缺图。
- **组合配图**：一道题一张题图内可能含「图1/图2」，源试卷阶段保持一题一图，不拆分；拆题阶段再按需处理。
- **备选 PDF 可能是图片型扫描件**：`pymupdf` 每页 `chars=0`、无文字层（Microsoft Print To PDF 导出常见），不能依赖文本抽取；按 2 倍以上矩阵 `get_pixmap` 渲染 PNG 后逐页多模态视觉核对题干、公式、坐标/角度/单位与题图。核对优先级：可编辑 Word > 官方 PDF 参照 > 在线抓取兜底；发现误差以 PDF 像素为准回改 MD，再复跑机械审计。
- **年级常已标注**：`_meta.term` 一般带「八年级上学期」等字样；学期推断结果须在报告中提示用户确认。
- **配图水印/透明底**：源试卷阶段保留网络链接；本地化在拆题阶段按规则 4.5 执行，本阶段不改链接。
