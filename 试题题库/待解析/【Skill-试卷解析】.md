---
name: 试卷解析
description: 对已有的 Markdown 试卷进行完整的解析和求解，包括答案、考点、详细解析以及易错点。该技能直接读取用户提供的 Markdown 试卷文件（位于 `12-试卷解析/` 或其他路径），并依据《Rules-试卷解析.md》模板为每道题目生成解析内容。

# Overview
This skill parses an existing Markdown exam file (typically located in `12-试卷解析/` or any user‑specified path) and enriches it with detailed solution sections. It:
1. Reads the provided Markdown exam document.
2. For **each** question (选择题、填空题、解答题) generates the following sections according to `Rules-试卷解析.md`:
   - **【答案】**
   - **【考点】**
   - **【解析】** (step‑by‑step reasoning)
   - **【易错点】** (common pitfalls)
3. Writes the enriched Markdown back to the same location (or a user‑specified output path).

# When to Trigger
- User asks to “解析试卷”, “分析试卷”, “生成答案”, or references a specific exam file under `11-试卷原题/`.
- User wants detailed solutions for *all* questions (default) or a specific range (e.g., `解析第5题`).

# Preconditions
1. The raw exam file (PDF or image) exists in `11-试卷原题/`.
2. Directory `12-试卷解析/` exists (the skill will create it if missing).
3. Original PDF/Image must be preserved.

# Steps
1. **Read the Markdown exam file**
   - The file path is provided by the user (e.g., `12-试卷解析/北京十一实验中学2025-2026学年初一年级第3学段-教与学诊断-数学学科-202604.md`).
2. **Parse and solve**
   - Identify each question (选择题、填空题、解答题) in the markdown.
   - For every question, apply the template from `Rules-试卷解析.md` to produce:
     ```markdown
     #### 第 X 题
     【答案】…
     【考点】…
     【解析】
     - 步骤1 …
     - 步骤2 …
     【易错点】…
     ```
   - Ensure all formulas use LaTeX `$...$` and images are embedded with Obsidian syntax `![[image.png]]`.
   - If the user requests a specific range of questions, only generate those sections.
3. **Write the enriched Markdown**
   - Overwrite the original file (or write to a user‑specified output path).
4. **Confirm completion** – report the file path and a brief summary of the added sections.

# Edge Cases & Error Handling
- **File not found**: List available files and ask the user to select.
- **`数学试卷格式化` fails**: Relay the error and suggest checking the source file.
- **Non‑PDF/Image**: Warn the user that only PDF/Image are supported.
- **User requests specific questions**: Validate the range and generate only those sections.

# Example Usage
User: "请把北京十一实验中学2025-2026数学III试卷全部解析并给出答案。"
Assistant response after running the skill:
```
已在 12-试卷解析/北京十一实验中学2025-2026数学III-202604.md 中生成完整试卷解析。
- 所有题目均包含【答案】、【考点】、【解析】、【易错点】四个子章节。
- 原始 PDF 已通过 [[../11-试卷原题/北京十一实验中学2025-2026数学III-202604.pdf]] 链接返回。
```

# Notes for Maintainers
- The core solving logic resides in this skill; ensure the `数学试卷格式化` skill is up‑to‑date.
- Keep the template in `Rules-试卷解析.md` synchronized with any changes to the output format.
- Periodically review generated files for consistency and correctness.
