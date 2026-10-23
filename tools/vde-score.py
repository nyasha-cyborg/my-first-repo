#!/usr/bin/env python3
"""Score tegra-vde block-linear output (<base>.hw) against an I420 reference (<base>.sw).

usage: vde-score.py BASE WIDTH HEIGHT
Prints per-plane mean/min bit-exact share and the first frame where luma drops below 100 %.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from importlib.machinery import SourceFileLoader

detile = SourceFileLoader("vde_detile", os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                                     "vde-detile.py")).load_module()

base, W, H = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
fs = W * H * 3 // 2
hw = np.fromfile(base + ".hw", np.uint8)
sw = np.fromfile(base + ".sw", np.uint8)
n = min(len(hw), len(sw)) // fs
ys, us, vs = [], [], []
for i in range(n):
    Y, U, V = detile.detile_frame(hw[i * fs:(i + 1) * fs], W, H)
    s = sw[i * fs:(i + 1) * fs]
    ys.append(np.mean(Y == s[:W * H].reshape(H, W)))
    us.append(np.mean(U == s[W * H:W * H * 5 // 4].reshape(H // 2, W // 2)))
    vs.append(np.mean(V == s[W * H * 5 // 4:].reshape(H // 2, W // 2)))
if not n:
    print(f"{os.path.basename(base)}: no frames (hw {len(hw)} B, sw {len(sw)} B)")
    sys.exit()
bad = next((i for i, y in enumerate(ys) if y < 1.0), None)
print(f"{os.path.basename(base):10s} {n:3d} fr  Y {np.mean(ys)*100:6.2f}% (min {min(ys)*100:6.2f})"
      f"  U {np.mean(us)*100:6.2f}%  V {np.mean(vs)*100:6.2f}%  first<100: {bad}"
      f"  hw/sw frames {len(hw)//fs}/{len(sw)//fs}")
