# -*- coding: utf-8 -*-
"""
geo.py —— 几何图渲染小库 (解耦: 算坐标 / 画图 / 数值自校验)
============================================================
设计目标: 把"几何内核(numpy 算坐标)"和"渲染"分开。
  * 坐标来自你的计算, geo.py 只负责把坐标画出来 -> 几何条件严格成立, 不近似。
  * 渲染默认导出 SVG (矢量, 给 Obsidian/笔记, 放大不糊, 中文符号由查看器字体渲染)。
  * 同时可导 PNG (matplotlib, 给聊天窗口预览)。 换后端不影响正确性。
  * 自带 Report 帮助打印数值自校验 (PASS/FAIL)。

用法:
  from geo import Fig, Report, P
  A = P(0,0); B=P(1,0); ...          # 你的 numpy 坐标 (list/ndarray/tuple 都行)
  fig = Fig(figsize=(11,8))
  fig.line(A,B).line(A,C)...          # 画边
  fig.circle(O,R, color="#9b59b6", dash="9 6")
  fig.fill([O,C,E,G], fill="#d7e6f8", stroke="#5b7fb0")
  fig.right_angle(E,D,C)              # 直角标记
  fig.arc(A,B,C, r=0.26)              # 角弧 ∠BAC
  fig.highlight(B,F, color="#e74c3c", width=4.6)   # 关键线段加粗着色
  fig.label(A,"A").label((B+F)/2,"BF", color="#e74c3c", dy=0.1)
  fig.svg("fig.svg"); fig.png("fig.png")

  rep = Report(); rep.ok("DE=AB", abs(DE-AB)<1e-9); rep.print_all()
"""

import math
import re
import sys
import numpy as np

# Windows 控制台默认 GBK, 打不出 ∠ ⊥ ½ 等符号 -> 强制 UTF-8 (无副作用/失败即忽略)
for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8")
    except Exception:
        pass

def P(x, y):
    """把坐标包成统一的点 (1D ndarray)。"""
    return np.asarray([x, y], dtype=float)


def _unit(a, b):
    d = P(*b) - P(*a)
    n = float(np.linalg.norm(d))
    return d / n if n > 0 else np.array([1.0, 0.0])


def _ra_pts(Pp, q1, q2, size=0.045):
    """直角标记: 顶点 Pp, 沿 Pp->q1 与 Pp->q2 两方向的小方框(两条边)."""
    a = _unit(Pp, q1); b = _unit(Pp, q2)
    Pp = P(*Pp)
    return [Pp + size * a, Pp + size * (a + b), Pp + size * b]


def _arc_pts(Pp, q1, q2, r, n=80):
    """角弧 ∠q1-Pp-q2 (取 <180° 夹角) 的采样折线."""
    Pp = P(*Pp)
    a1 = math.atan2(*_unit(Pp, q1)[::-1])
    a2 = math.atan2(*_unit(Pp, q2)[::-1])
    d = (a2 - a1 + math.pi) % (2 * math.pi) - math.pi
    th = np.linspace(a1, a1 + d, n)
    return [Pp + r * np.array([math.cos(t), math.sin(t)]) for t in th]


def _norm_color(c, for_svg):
    """matplotlib 的灰度串 '0.3' 在 SVG 里无效 -> 转灰度 hex."""
    if isinstance(c, str) and re.fullmatch(r"\d(\.\d+)?", c):
        v = int(round(float(c) * 255))
        return "#%02x%02x%02x" % (v, v, v)
    return c


class Fig:
    def __init__(self, figsize=(11, 8), dpi=100):
        self._prims = []
        self._w_in, self._h_in = figsize
        self._dpi = dpi

    # ---------------- 绘图原语 (链式) ----------------
    def line(self, p, q, color="black", width=1.8, dash=None, z=0, cap="butt"):
        self._prims.append(dict(t="line", p=P(*p), q=P(*q), color=color,
                                width=width, dash=dash, z=z, cap=cap))
        return self

    def circle(self, c, r, color="black", width=1.5, dash=None, z=0, fill=None):
        self._prims.append(dict(t="circle", c=P(*c), r=float(r), color=color,
                                width=width, dash=dash, z=z, fill=fill))
        return self

    def fill(self, pts, fill="#d7e6f8", stroke=None, width=1.2, z=0):
        self._prims.append(dict(t="poly", pts=[P(*p) for p in pts], fill=fill,
                                stroke=stroke, width=width, z=z))
        return self

    def path(self, pts, color="black", width=1.8, dash=None, z=0, closed=False):
        self._prims.append(dict(t="path", pts=[P(*p) for p in pts], color=color,
                                width=width, dash=dash, z=z, closed=closed))
        return self

    def right_angle(self, Pp, q1, q2, size=0.045, color="0.3", width=1.2, z=2):
        self._prims.append(dict(t="path", pts=_ra_pts(Pp, q1, q2, size),
                                color=color, width=width, dash=None, z=z, closed=False))
        return self

    def arc(self, Pp, q1, q2, r, color="dimgray", width=1.7, z=2):
        self._prims.append(dict(t="path", pts=_arc_pts(Pp, q1, q2, r),
                                color=color, width=width, dash=None, z=z, closed=False))
        return self

    def highlight(self, p, q, color="#e74c3c", width=4.6, z=3):
        """关键线段加粗覆盖 (圆头)."""
        return self.line(p, q, color=color, width=width, z=z, cap="round")

    def label(self, p, text, color="black", size=13, dx=0.0, dy=0.0, z=5):
        self._prims.append(dict(t="label", p=P(*p) + np.array([dx, dy]), text=str(text),
                                color=color, size=size, z=z))
        return self

    def seg_label(self, mid, p, q, dist=0.12, side=+1, text="", color="black", size=13, z=5):
        """线段名标签(如 BF/CE/EF): 沿"该线段自身"的法向偏离线, 避免贴在线段上.
        mid: 参考点(一般取线段中点)  p,q: 线段两端  dist: 离线距离  side: 偏到法向哪一侧(±1)."""
        d = _unit(p, q)
        perp = np.array([-d[1], d[0]])
        return self.label(mid, text, color=color, size=size,
                          dx=side*dist*perp[0], dy=side*dist*perp[1], z=z)

    # ---------------- 包围盒 ----------------
    def _bbox(self):
        xs, ys = [], []
        for pr in self._prims:
            if pr["t"] in ("line",):
                xs += [pr["p"][0], pr["q"][0]]; ys += [pr["p"][1], pr["q"][1]]
            elif pr["t"] == "circle":
                xs += [pr["c"][0] - pr["r"], pr["c"][0] + pr["r"]]
                ys += [pr["c"][1] - pr["r"], pr["c"][1] + pr["r"]]
            elif pr["t"] in ("poly", "path", "label"):
                if pr["t"] == "label":
                    xs += [pr["p"][0]]; ys += [pr["p"][1]]
                else:
                    for pt in pr["pts"]:
                        xs += [pt[0]]; ys += [pt[1]]
        if not xs:
            return 0, 1, 0, 1
        return min(xs), max(xs), min(ys), max(ys)

    # ---------------- 导出: SVG (矢量, 给 Obsidian) ----------------
    def svg(self, path, bg="white"):
        xmin, xmax, ymin, ymax = self._bbox()
        pw, ph = self._w_in * self._dpi, self._h_in * self._dpi
        pad = 0.045 * max(xmax - xmin, ymax - ymin, 1e-9)
        pw_in, ph_in = pw, ph
        # 比例与居中 (y 翻转)
        x0, y0 = xmin - pad, ymin - pad
        span_x = (xmax - xmin) + 2 * pad
        span_y = (ymax - ymin) + 2 * pad
        scale = min(pw_in / span_x, ph_in / span_y)
        ox_px = (pw_in - span_x * scale) / 2
        oy_px = (ph_in - span_y * scale) / 2

        def M(p):  # 数学坐标 -> 像素 (y 翻转)
            p = P(*p)
            X = ox_px + (p[0] - x0) * scale
            Y = oy_px + (span_y - (p[1] - y0)) * scale
            return X, Y

        s = []
        s.append('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" '
                 'width="%d" height="%d" font-family="sans-serif, %s">'
                 % (pw_in, ph_in, pw_in, ph_in, "'Microsoft YaHei','SimHei',sans-serif"))
        s.append('<rect x="0" y="0" width="%d" height="%d" fill="%s"/>' % (pw_in, ph_in, bg))
        PT = 1.33  # pt -> px @96dpi

        for pr in sorted(self._prims, key=lambda x: x["z"]):
            c = _norm_color(pr.get("color", "none"), True)
            if pr["t"] == "line":
                x1, y1 = M(pr["p"]); x2, y2 = M(pr["q"])
                da = ' stroke-dasharray="%s"' % pr["dash"] if pr["dash"] else ""
                cap = "round" if pr["cap"] == "round" else "butt"
                s.append('<line x1="%.3f" y1="%.3f" x2="%.3f" y2="%.3f" stroke="%s" '
                         'stroke-width="%.3f"%s stroke-linecap="%s"/>'
                         % (x1, y1, x2, y2, c, pr["width"] * PT, da, cap))
            elif pr["t"] == "circle":
                cx, cy = M(pr["c"]); rr = pr["r"] * scale
                da = ' stroke-dasharray="%s"' % pr["dash"] if pr["dash"] else ""
                f = pr["fill"] or "none"
                s.append('<circle cx="%.3f" cy="%.3f" r="%.3f" stroke="%s" '
                         'stroke-width="%.3f" fill="%s"%s/>'
                         % (cx, cy, rr, c, pr["width"] * PT, f, da))
            elif pr["t"] == "poly":
                pts = " ".join("%.3f,%.3f" % M(pt) for pt in pr["pts"])
                st = pr["stroke"] or "none"
                s.append('<polygon points="%s" fill="%s" stroke="%s" stroke-width="%.3f"/>'
                         % (pts, pr["fill"], st, (pr["width"] or 1) * PT))
            elif pr["t"] == "path":
                d = "M " + " L ".join("%.3f %.3f" % M(pt) for pt in pr["pts"])
                if pr["closed"]:
                    d += " Z"
                da = ' stroke-dasharray="%s"' % pr["dash"] if pr["dash"] else ""
                s.append('<path d="%s" fill="none" stroke="%s" stroke-width="%.3f"%s '
                         'stroke-linejoin="round"/>' % (d, c, pr["width"] * PT, da))
            elif pr["t"] == "label":
                x, y = M(pr["p"])
                fs = pr["size"] * PT
                # 用 paint-order:stroke 画白色光晕, 充当标签底, 无需量测文字宽度
                s.append('<text x="%.3f" y="%.3f" font-size="%.3f" fill="%s" '
                         'text-anchor="middle" dominant-baseline="central" '
                         'style="paint-order:stroke" stroke="%s" stroke-width="%.3f">%s</text>'
                         % (x, y, fs, c, bg, fs * 0.42, _escape(pr["text"])))
        s.append("</svg>")
        with open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(s))
        return path

    # ---------------- 导出: PNG (matplotlib, 给聊天预览) ----------------
    def png(self, path, bg="white"):
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        from matplotlib.patches import Circle, Polygon
        from matplotlib import rcParams
        for f in ["Microsoft YaHei", "SimHei", "Noto Sans CJK SC",
                  "Source Han Sans SC", "PingFang SC", "DejaVu Sans"]:
            rcParams["font.sans-serif"] = [f, "DejaVu Sans"]
        rcParams["axes.unicode_minus"] = False

        xmin, xmax, ymin, ymax = self._bbox()
        pad = 0.045 * max(xmax - xmin, ymax - ymin, 1e-9)
        fig, ax = plt.subplots(figsize=(self._w_in, self._h_in), dpi=self._dpi)
        ax.set_aspect("equal"); ax.axis("off")
        ax.set_facecolor(bg); fig.patch.set_facecolor(bg)

        for pr in sorted(self._prims, key=lambda x: x["z"]):
            c = pr.get("color", "none")
            if pr["t"] == "line":
                ax.plot([pr["p"][0], pr["q"][0]], [pr["p"][1], pr["q"][1]], color=c,
                        lw=pr["width"], zorder=pr["z"],
                        solid_capstyle="round" if pr["cap"] == "round" else "butt",
                        ls="--" if pr["dash"] else "-")
            elif pr["t"] == "circle":
                ax.add_patch(Circle(tuple(pr["c"]), pr["r"], fill=pr["fill"] is not None,
                                    facecolor=pr["fill"] if pr["fill"] else "none",
                                    edgecolor=c, lw=pr["width"],
                                    ls="--" if pr["dash"] else "-", zorder=pr["z"]))
            elif pr["t"] == "poly":
                ax.add_patch(Polygon(pr["pts"], closed=True, facecolor=pr["fill"],
                                     edgecolor=pr["stroke"] or "none",
                                     lw=pr["width"], zorder=pr["z"]))
            elif pr["t"] == "path":
                xs = [pt[0] for pt in pr["pts"]]; ys = [pt[1] for pt in pr["pts"]]
                if pr["closed"]:
                    xs += [xs[0]]; ys += [ys[0]]
                ax.plot(xs, ys, color=c, lw=pr["width"], zorder=pr["z"],
                        ls="--" if pr["dash"] else "-")
            elif pr["t"] == "label":
                ax.text(pr["p"][0], pr["p"][1], pr["text"], ha="center", va="center",
                        fontsize=pr["size"], color=c, zorder=pr["z"],
                        bbox=dict(boxstyle="round,pad=0.14", fc=bg, ec="none", alpha=0.92))
        ax.set_xlim(xmin - pad, xmax + pad); ax.set_ylim(ymin - pad, ymax + pad)
        fig.savefig(path, bbox_inches="tight", facecolor=bg)
        plt.close(fig)
        return path

    def export(self, path, bg="white"):
        return self.svg(path, bg) if path.lower().endswith(".svg") else self.png(path, bg)


def _escape(t):
    return (t.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


class Report:
    """数值自校验小助手: 画完打印 PASS/FAIL, 确认几何条件严格成立."""

    def __init__(self, title=""):
        self.title = title
        self.rows = []
        self._bad = 0

    def ok(self, name, cond):
        self.rows.append((name, bool(cond)))
        self._bad += (not cond)
        return bool(cond)

    def print_all(self):
        if self.title:
            print("\n=== %s ===" % self.title)
        for name, c in self.rows:
            print("  [%s] %s" % ("PASS" if c else "FAIL", name))
        print("  => %s" % ("全部通过 ✓" if self._bad == 0 else "%d 项未通过 ✗" % self._bad))
        return self._bad == 0
