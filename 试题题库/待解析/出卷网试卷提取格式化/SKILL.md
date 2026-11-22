---
name: chujuan-paper-extract
description: 从出卷网（chujuan.cn，21cnjy 后端）试卷详情页识别并提取题目，按本地《Rules-数理化试卷》规则格式化为 Markdown 源试卷。当用户给出出卷网试卷链接（如 `/paper/view-5922106.shtml`），或要求"识别出卷网试卷、提取网页试题、把该页面题目转成 Markdown/题库 MD"时使用。覆盖：匿名直抓页面、内嵌 paper_detail JSON 结构化提取、MathML→LaTeX 确定性转换、填空线/选项/表格格式化、配图目检与机械校验。仅做识别与格式化阶段；不生成答案解析、不拆题、不本地化配图（属后续试卷解析阶段）。
---

# 出卷网试卷提取与格式化

## 概述

输入一个出卷网试卷详情 URL，输出一份符合本地规则的源试卷 Markdown：题干、分节、出处标签、题型、配图网络链接齐全；答案/解析在公开预览被门禁时如实标注，不编造。

## 前置依赖

- 规则全文：`D:\【Knowledge Notes】\12-试卷解析\待解析\【Rules-数理化试卷】.md`（第一、二章为格式化依据，落盘前逐条对照）。
- 耦合技能：`C:\Users\LSSTUDIO\.agents\skills\数学试卷格式化\SKILL.md`、`C:\Users\LSSTUDIO\.agents\skills\试卷解析\SKILL.md`。
- 环境：Node v22（`node` 可用）；页面无需浏览器过 JS 挑战，匿名 HTTP 直抓即可拿到正文 HTML（见 `references/dom-and-gating.md` 第 1 节）。

## 与组卷网/菁优网先例的关键差异

1. **直抓即可**：出卷网页面没有组卷网式 JS 挑战壳，`Invoke-WebRequest` / fetch 直存 HTML 即含全部题目正文，不需要 Browser Use 交接。
2. **数据源是内嵌 JSON**：页面 JS 里嵌了一段 `paper_detail` JSON，题干 HTML、选项、子题 `list`、空位标记、题型、出处全部结构化保留；转换器优先解析该 JSON，比逐节点 DOM 切块更稳，且不会带入页脚二维码、统计脚本、操作条等噪声。
3. **公式可确定性转 LaTeX**：公式不是无源码 PNG 碎片，而是 MathML 编码在 `<img class="mathml" src="//math.21cnjy.com/math2svg/mml2svg?mml=...">` 的 `mml=` URL 参数里；URL 解码后按 MathML 树递归渲染为 LaTeX，无需视觉转写。题图/图案在 `//tikupic.21cnjy.com/...png`，始终保留为图片。

## 工作流程

### 步骤 1：直抓页面

1. 用匿名 HTTP GET 保存详情页 HTML 到临时目录（如 `%TEMP%\chujuan_paper1\page.html`）；无需登录、无挑战脚本。
2. 记录页面元信息：试卷标题、年级学期、考试类型、发布日期（`format_examine_time`）、题量。

### 步骤 2：探查结构并判定门禁

- 读 `references/dom-and-gating.md`，确认内嵌 `paper_detail` 可解析、`content[].questions[]` 字段齐全。
- 判定答案/解析是否可见：题目对象 `answer`/`explanation` 为空、`answer_json` 为空数组；整页文本搜索 `【答案】`、`【解析】`、`【考点】` 命中数。不可见则标记「解析门禁」，本阶段只做题干。
- 知识点明细（`knowledge_info`、`t_knowledge`）公开态仅供后续解析阶段参考，本阶段不写进源 MD。

### 步骤 3：运行转换器生成中间稿

```bash
node <skill目录>/scripts/chujuan_html_to_md.js <page.html> <out.json>
```

- 脚本完成：内嵌 JSON 括号配对提取 → 遍历分节与题目；题干/选项/子题 HTML 经栈式解析；MathML 递归渲染 LaTeX；HTML 表格转 Markdown 表；空位 `{#blank#}N{#/blank#}` 转 ` ___ `；选项标签归一；相邻双 `<sub>` 合并；剥离二维码 `/question-sync` 与操作条。
- 脚本**不做**规则 1.6/1.7 的独立数字空格与独立字母包裹；这一步在下一阶段人工复核。

### 步骤 4：按规则复核并撰写最终 MD

- 对照 Rules 第一、二章逐题补全：独立字母/连续表达式整体 `$` 包裹、独立数字前后空格、圈数 `$①$`、标点前不留空格、选项分行、填空线两侧空格。
- 对照用户提供的备选 PDF（图片型扫描件时用 pymupdf 渲染 PNG 后多模态目检）逐页核对题干、公式、坐标、角度、题图；发现误差以 PDF 像素为准回改 MD。
- 按 `references/output-format.md` 第 1–3 节确定落盘路径、文件名、frontmatter 与正文结构。

### 步骤 5：配图目检与机械校验

1. 题图/图案逐张核对：构型与题干一致、无缺图错图；公式已转 LaTeX，不残留公式碎片图。
2. 跑 `references/output-format.md` 第 5 节校验清单：题数=配图数、0 HTML 残留、0 裸圈数、0 非法填空线、无 callout、无本地图引用。

### 步骤 6：落盘与交付报告

- 源试卷 MD 写入 `待解析/` 根目录（路径与命名见 output-format.md 第 1 节）。
- 报告中说明：题量题型、解析门禁状态、年级依据、备选 PDF 对照结论、缺失出处题号；提示用户审核通过后再走拆题解析流程。

## 边界（本技能不做）

- 不生成【答案】【考点】【解析】【易错点】；不写解析 callout。
- 不创建试卷文件夹、不移动源文件、不拆成 Q 文件、不下载本地化配图——属 `/试卷解析` 阶段。
- 不修改既有源试卷文件；本技能产出的是新格式化 MD。
- 门禁不可见时，不推测、不编造答案与解析。

## 环境事实

- Node：本机 Node v22（PATH 中 `node` 可用）。
- Python：PATH 中 `python` 是 Windows 商店占位程序，不可用；PDF 渲染走 `uv run --python 3.12 --with pymupdf python <脚本>.py`。
- 临时文件放 `%TEMP%`，不进 vault；技能目录内不放运行产物。
- 页面选择器/JSON 字段若失效（改版），先在保存的 HTML 中重新定位 `paper_detail` 结构，再回写 `references/dom-and-gating.md`。

## 参考文件

- `references/dom-and-gating.md`：页面可达性、内嵌 JSON 结构、门禁判定、MathML 映射与已知坑点。
- `references/output-format.md`：落盘命名、frontmatter、正文结构、规则对接、校验清单与交付事项。
