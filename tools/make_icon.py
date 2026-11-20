#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""墨阅图标生成器 - 纯标准库，几何矢量风格，超采样抗锯齿。

生成:
  - Android 各 density 的 ic_launcher.png
  - Windows 多尺寸 app_icon.ico (PNG-in-ICO)
  - assets/icon_source.png (1024px 主图)
"""
import math
import os
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ANDROID_RES = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res')
WIN_RES = os.path.join(ROOT, 'windows', 'runner', 'resources')
ASSETS = os.path.join(ROOT, 'assets')

# ---------- PNG 编码 ----------
def write_png(path, w, h, pixels):
    def chunk(tag, data):
        return (struct.pack('>I', len(data)) + tag + data +
                struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff))
    raw = bytearray()
    for y in range(h):
        raw.append(0)  # filter: none
        raw.extend(pixels[y * w * 4:(y + 1) * w * 4])
    png = (b'\x89PNG\r\n\x1a\n' +
           chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)) +
           chunk(b'IDAT', zlib.compress(bytes(raw), 9)) +
           chunk(b'IEND', b''))
    with open(path, 'wb') as f:
        f.write(png)

# ---------- 几何 ----------
def sd_round_rect(px, py, x0, y0, x1, y1, r):
    cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
    hx, hy = (x1 - x0) / 2.0 - r, (y1 - y0) / 2.0 - r
    qx, qy = abs(px - cx) - hx, abs(py - cy) - hy
    return math.hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - r

def in_poly(x, y, pts):
    inside = False
    j = len(pts) - 1
    for i in range(len(pts)):
        xi, yi = pts[i]
        xj, yj = pts[j]
        if ((yi > y) != (yj > y)) and (x < (xj - xi) * (y - yi) / (yj - yi) + xi):
            inside = not inside
        j = i
    return inside

def dseg(px, py, x1, y1, x2, y2):
    dx, dy = x2 - x1, y2 - y1
    L = dx * dx + dy * dy
    if L == 0:
        return math.hypot(px - x1, py - y1)
    t = max(0.0, min(1.0, ((px - x1) * dx + (py - y1) * dy) / L))
    return math.hypot(px - (x1 + t * dx), py - (y1 + t * dy))

# 书本几何
PAGE_L = [(0.12, 0.60), (0.485, 0.545), (0.485, 0.325), (0.12, 0.38)]
PAGE_R = [(0.515, 0.545), (0.88, 0.60), (0.88, 0.38), (0.515, 0.325)]
SHADOW_L = [(x + 0.012, y + 0.020) for x, y in PAGE_L]
SHADOW_R = [(x + 0.012, y + 0.020) for x, y in PAGE_R]

# 文字线（模拟书页上的行）
LINES = []
SLOPE = -0.1507
for y0 in (0.435, 0.495, 0.555):
    y1 = y0 + SLOPE * (0.45 - 0.12)
    LINES.append((0.165, y0, 0.445, y1))
for y0 in (0.375, 0.435, 0.495):
    y1 = y0 + (-SLOPE) * (0.84 - 0.515)
    LINES.append((0.555, y0, 0.835, y1))

def sample(x, y):
    # 圆角背景
    if sd_round_rect(x, y, 0.025, 0.025, 0.975, 0.975, 0.19) > 0:
        return (0, 0, 0, 0)
    # 墨绿渐变
    t = y
    col = [int(38 + (14 - 38) * t), int(96 + (48 - 96) * t),
           int(72 + (38 - 72) * t), 255]
    # 书本投影
    if in_poly(x, y, SHADOW_L) or in_poly(x, y, SHADOW_R):
        col = [8, 28, 22, 255]
    # 书页
    if in_poly(x, y, PAGE_L) or in_poly(x, y, PAGE_R):
        shade = min(1.0, abs(x - 0.5) / 0.36)
        col = [int(233 + 22 * shade), int(228 + 23 * shade),
               int(212 + 26 * shade), 255]
        # 页面文字线
        for (x1, y1, x2, y2) in LINES:
            if dseg(x, y, x1, y1, x2, y2) < 0.0055:
                col = [148, 176, 156, 255]
                break
    # 书脊
    if dseg(x, y, 0.5, 0.328, 0.5, 0.548) < 0.005:
        col = [198, 188, 164, 255]
    # 墨滴（水滴形：圆 + 尖）
    in_drop = (math.hypot(x - 0.5, y - 0.258) < 0.040 or
               in_poly(x, y, [(0.5, 0.158), (0.465, 0.258), (0.535, 0.258)]))
    if in_drop:
        col = [216, 172, 92, 255]
    return tuple(col)

def render(size, ss=4):
    px = bytearray(size * size * 4)
    step = 1.0 / (size * ss)
    for j in range(size):
        for i in range(size):
            r = g = b = a = 0
            for sy in range(ss):
                y = (j * ss + sy + 0.5) * step
                for sx in range(ss):
                    x = (i * ss + sx + 0.5) * step
                    c = sample(x, y)
                    r += c[0]; g += c[1]; b += c[2]; a += c[3]
            n = ss * ss
            o = (j * size + i) * 4
            px[o] = r // n; px[o+1] = g // n
            px[o+2] = b // n; px[o+3] = a // n
    return px

def write_ico(path, sizes_png):
    """sizes_png: list of (size, png_bytes)"""
    header = struct.pack('<HHH', 0, 1, len(sizes_png))
    offset = 6 + 16 * len(sizes_png)
    entries = b''
    data = b''
    for size, png in sizes_png:
        s = 0 if size >= 256 else size
        entries += struct.pack('<BBBBHHII', s, s, 0, 0, 1, 32, len(png), offset)
        offset += len(png)
        data += png
    with open(path, 'wb') as f:
        f.write(header + entries + data)

def main():
    os.makedirs(ASSETS, exist_ok=True)
    os.makedirs(WIN_RES, exist_ok=True)

    # 主图
    main_px = render(1024)
    write_png(os.path.join(ASSETS, 'icon_source.png'), 1024, 1024, main_px)
    print('generated assets/icon_source.png')

    # Android
    densities = [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96),
                 ('xxhdpi', 144), ('xxxhdpi', 192)]
    for name, size in densities:
        d = os.path.join(ANDROID_RES, 'mipmap-' + name)
        os.makedirs(d, exist_ok=True)
        write_png(os.path.join(d, 'ic_launcher.png'), size, size, render(size))
        print('generated android mipmap-' + name)

    # Windows ICO（PNG-in-ICO，多尺寸）
    ico_entries = []
    for size in (16, 24, 32, 48, 64, 128, 256):
        tmp = os.path.join(ASSETS, '_icon_%d.png' % size)
        write_png(tmp, size, size, render(size))
        with open(tmp, 'rb') as f:
            ico_entries.append((size, f.read()))
        os.remove(tmp)
    write_ico(os.path.join(WIN_RES, 'app_icon.ico'), ico_entries)
    print('generated windows app_icon.ico (7 sizes)')

if __name__ == '__main__':
    main()
