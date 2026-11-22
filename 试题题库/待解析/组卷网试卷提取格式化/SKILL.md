---
name: zujuan-paper-extract
description: 从组卷网（zujuan.xkw.com / xkw.com）组卷详情页识别并提取题目，按本地《Rules-数理化试卷》规则格式化为 Markdown 源试卷。当用户给出组卷网试卷链接（如 `/2p3012600.html`），或要求"识别组卷网试卷、提取网页试题、把该页面题目转成 Markdown/题库 MD"时使用。覆盖：浏览器打开与 JS 挑战交接、DOM 结构化提取、HTML→MD 转换、公式碎片图/填空线/选项格式化、配图目检与机械校验。仅做识别与格式化阶段；不生成答案解析、不拆题、不本地化配图（属后续试卷解析阶段）。
---

# 组卷网试卷提取与格式化

## 概述

输入一个组卷网组卷详情 URL，输出一份符合本地规则的源试卷 Markdown：题干、分节、出处标签、题型、配图网络链接齐全；答案/解析在公开预览被门禁时如实标注，不编造。

## 前置依赖

- 规则全文：`D:\【Knowledge Notes】\12-试卷解析\待解析\【Rules-数理化试卷】.md`（第一、二章为格式化依据，落盘前逐条对照）。
- 耦合技能：`C:\Users\LSSTUDIO\.agents\skills\数学试卷格式化\SKILL.md`、`C:\Users\LSSTUDIO\.agents\skills\试卷解析\SKILL.md`。
- 浏览器：Browser Use（`computer_use_tool`，`plane="bu"`）；匿名 HTTP 直抓只返回 JS 挑战壳（见 `references/dom-and-gating.md` 第 1 节），不得用 `Invoke-WebRequest` / fetch 直抓代替。

## 工作流程

### 步骤 1：打开页面，通过 JS 挑战

1. `bu.navigate(url)`，`bu.wait_for_load()`，必要时 `sleep` 1–2 秒等待挑战脚本写 cookie 并自动 reload。
2. 若被重定向登录页或出现验证/登录弹窗：按 browser-use-automation 规则调用 `interaction.request_action`（`type="browserControl"`）交接用户；交回后重新快照验证门禁解除。
3. 记录学科、年级、学期、考试类型、发布日期、难度、考查范围等页面元信息。

### 步骤 2：探查结构并判定门禁

- 读 `references/dom-and-gating.md`，按选择器确认容器、题目外壳、题干、出处/题型属性是否存在。
- 判定答案/解析是否可见：`.item.answer` 是否为空；整页文本搜索 `【答案】`、`【解析】`、`【考点】` 命中数。不可见则标记「解析门禁」，本阶段只做题干。
- 「试卷分析 / 知识点分析」面板多为懒加载，公开态通常只有题型与难度统计；知识点明细供后续解析阶段参考，本阶段不写进源 MD。

### 步骤 3：结构化提取

1. 用 `references/dom-and-gating.md` 第 3 节的 bu.js 片段按文档顺序遍历：分节标题 `h4.sec-title` 与题目 `.tk-quest-item` 合并排序，每题采集 `questionid/source/type/difficulty/tag/stemHTML/options/images`。
2. 全局题号按文档顺序从 1 连续编号；落盘临时 JSON（`%TEMP%\zujuan_paper1\input.json`，目录名按批次递增）。

### 步骤 4：运行转换器生成中间稿

```bash
node <skill目录>/scripts/zujuan_html_to_md.js <输入.json> <输出.json>
```

- 脚本完成：标签剥离、`<br>/<p>` 换行、`<bk>` 填空线、配图 Markdown、实体解码、选项标签归一（`A．`→`A. `）、行首旧题号剥离。
- 脚本**不做**规则 1.6/1.7 的独立数字空格与独立字母包裹；这一步在下一阶段人工复核。

### 步骤 5：按规则复核并撰写最终 MD

- 对照 Rules 第一、二章逐题补全：独立字母/连续表达式整体 `$` 包裹、独立数字前后空格、圈数 `$①$`、标点前不留空格、选项分行、填空线两侧空格。
- 若用户要求把公式碎片图转为 Markdown LaTeX：按 `references/dom-and-gating.md` §5.1 视觉转写流程执行（放大拼图→逐格转写→上下文核对→hash 映射回写）；题图（`img.xkw.com`）始终保留为图片，不参与转写。
- 按 `references/output-format.md` 第 1–3 节确定落盘路径、文件名、frontmatter 与正文结构。
- 年级页面已标注时以页面为准；未标注时依据作者其它卷标题与考点章节推断，并在报告中请用户确认。

### 步骤 6：配图目检与机械校验

1. 下载全部配图到临时目录，逐张 Read 目检：构型与题干一致、无缺图错图；**公式碎片图尺寸很小（常约 40×14px），需放大 4–5 倍后再辨认**。
2. 跑 `references/output-format.md` 第 5 节校验清单：题数=配图数、0 HTML 残留、0 裸圈数、0 非法填空线、无 callout、无本地图引用。

### 步骤 7：落盘与交付报告

- 源试卷 MD 写入 `待解析/` 根目录（路径与命名见 output-format.md 第 1 节）。
- 报告中说明：题量题型、难度分布、解析门禁状态、年级依据、缺 PDF 说明、缺失出处题号；提示用户审核通过后再走拆题解析流程。

## 边界（本技能不做）

- 不生成【答案】【考点】【解析】【易错点】；不写解析 callout。
- 不创建试卷文件夹、不移动源文件、不拆成 Q 文件、不下载本地化配图——属 `/试卷解析` 阶段。
- 不修改既有源试卷文件；本技能产出的是新格式化 MD。
- 门禁不可见时，不推测、不编造答案与解析。

## 环境事实

- Node：本机 Node v22（PATH 中 `node` 可用）；若路径失效，用沙箱运行时内置 node。
- 临时文件放 `%TEMP%`，不进 vault；技能目录内不放运行产物。
- 页面选择器若失效（改版），先在浏览器快照中重新定位容器与题目外壳，再回写 `references/dom-and-gating.md`。

## 参考文件

- `references/dom-and-gating.md`：DOM 选择器、门禁判定、提取片段、已知坑点与无效 URL。
- `references/output-format.md`：落盘命名、frontmatter、正文结构、规则对接、校验清单与交付事项。
