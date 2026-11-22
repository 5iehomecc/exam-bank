---
name: jyeoo-paper-extract
description: 从菁优网（jyeoo.com）分享的试卷/组卷页面识别并提取题目，按本地《Rules-数理化试卷》规则格式化为 Markdown 源试卷。当用户给出菁优网试卷链接（/math|physics|chemistry/paper/share/...），或要求"识别菁优网试卷、提取网页试题、把该分享页题目转成 Markdown/题库 MD"时使用。覆盖：浏览器打开与登录交接、DOM 结构化提取、HTML→MD 转换、数学公式/圈数/填空线/选项格式化、配图目检与机械校验。仅做识别与格式化阶段；不生成答案解析、不拆题、不本地化配图（属后续试卷解析阶段）。
---

# 菁优网试卷提取与格式化

## 概述

输入一个菁优网分享试卷 URL，输出一份符合本地规则的源试卷 Markdown：题干、分节、出处标签、题型、配图网络链接齐全；答案/解析在公开预览被门禁时如实标注，不编造。

## 前置依赖

- 规则全文：`D:\【Knowledge Notes】\12-试卷解析\待解析\【Rules-数理化试卷】.md`（第一、二章为格式化依据，落盘前逐条对照）。
- 耦合技能：`C:\Users\LSSTUDIO\.agents\skills\数学试卷格式化\SKILL.md`、`C:\Users\LSSTUDIO\.agents\skills\试卷解析\SKILL.md`。
- 浏览器：Browser Use（`computer_use_tool`，`plane="bu"`）；不得用匿名 HTTP 直抓代替（只返回首页外壳，见 `references/dom-and-gating.md` 第 1 节）。

## 工作流程

### 步骤 1：打开页面，处理登录门禁

1. `bu.navigate(url)`，`bu.wait_for_load()`。
2. 若被重定向登录页或出现验证/登录弹窗：按 browser-use-automation 规则调用 `interaction.request_action`（`type="browserControl"`）交接用户完成登录；交回后重新快照验证门禁解除。
3. 页面为其他学科路径（物理/化学）时，记录学科，后续 tag 与规则对照表按 Rules 文件执行。

### 步骤 2：探查结构并判定门禁

- 读 `references/dom-and-gating.md`，按选择器确认容器、题目外壳、题干、出处/题型属性是否存在。
- 判定答案/解析是否可见：`.pt2` 是否为空、`【答案】/【解析】/【考点】` 命中数。不可见则标记「解析门禁」，本阶段只做题干。
- 切到「组卷分析」页签，采集每题难度与知识点映射（供后续解析阶段用，不写进源 MD）。

### 步骤 3：结构化提取

1. 用 `references/dom-and-gating.md` 第 3 节的 bu.js 片段遍历 `.zjqPaperDetail`：分节标题 + 每题 `label/cate/reportid/qid/stemHTML/img`，写入临时 JSON（`%TEMP%\jyeoo_paper.json`）。
2. 全局题号按文档顺序从 1 连续编号；记录试卷标题、发布时间、标签、作者。

### 步骤 4：运行转换器生成中间稿

```bash
node <skill目录>/scripts/jyeoo_html_to_md.js <输入.json> <输出.json>
```

- 脚本完成：注释剥离、`MathJye` 分数/字母/圈数、`<sub>/<sup>`、填空位 ` ___ `、换行、配图 Markdown、实体解码、行首旧题号剥离。
- 脚本**不做**规则 1.6/1.7 的独立数字空格与独立字母包裹；这一步在下一阶段人工复核。

### 步骤 5：按规则复核并撰写最终 MD

- 对照 Rules 第一、二章逐题补全：独立字母/连续表达式整体 `$` 包裹、独立数字前后空格、圈数 `$①$`、标点前不留空格、选项分行、填空线两侧空格。
- 按 `references/output-format.md` 第 1–3 节确定落盘路径、文件名、frontmatter 与正文结构。
- 年级页面未标注时，依据作者其它卷标题与考点章节推断，并在报告中请用户确认。

### 步骤 6：配图目检与机械校验

1. 下载全部配图到临时目录，逐张 Read 目检：构型与题干一致、无缺图错图、多图组合保持一题一图。
2. 跑 `references/output-format.md` 第 5 节校验清单：题数=配图数、0 HTML 残留、0 裸圈数、0 非法填空线、无 callout、无本地图引用。

### 步骤 7：落盘与交付报告

- 源试卷 MD 写入 `待解析/` 根目录（路径与命名见 output-format.md 第 1 节）。
- 报告中说明：题量题型、难度/知识点对照（来自组卷分析）、解析门禁状态、缺 PDF、年级推断依据、缺失出处题号；提示用户审核通过后再走拆题解析流程。

## 边界（本技能不做）

- 不生成【答案】【考点】【解析】【易错点】；不写解析 callout。
- 不创建试卷文件夹、不移动源文件、不拆成 Q 文件、不下载本地化配图——属 `/试卷解析` 阶段。
- 不修改既有源试卷文件；本技能产出的是新格式化 MD。
- 门禁不可见时，不推测、不编造答案与解析。

## 环境事实

- Node：本机 Node v22（`C:\Users\LSSTUDIO\AppData\Local\Doubao\User Data\sandbox_runtime\bases\fa694f517e5995233c80a9a8db5212c2\node\node.exe`）；若路径失效，用 PATH 中可用的 `node`。
- 临时文件放 `%TEMP%`，不进 vault；技能目录内不放运行产物。
- 页面选择器若失效（改版），先在浏览器快照中重新定位容器与题目外壳，再回写 `references/dom-and-gating.md`。

## 参考文件

- `references/dom-and-gating.md`：DOM 选择器、门禁判定、提取片段、已知坑点与无效 URL。
- `references/output-format.md`：落盘命名、frontmatter、正文结构、规则对接、校验清单与交付事项。
