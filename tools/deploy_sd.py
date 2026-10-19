"""TF 卡一键部署工具。

把 toSD 里的图片、音频、advertisement.txt 和 .lrc 转成板卡可读格式，
写入 SD 卡并回写扫描常量。

用法:
    python deploy_sd.py --list
    python deploy_sd.py G: --dry-run
    python deploy_sd.py G:
"""

import argparse
import atexit
import ctypes
import glob
import os
import re
import shutil
import struct
import subprocess
import sys
import textwrap
from ctypes import wintypes

try:
    from PIL import Image, ImageOps
    HAS_PIL = True
except ImportError:
    Image = ImageOps = None
    HAS_PIL = False

# 图片转换

TARGET_WIDTH  = 1280
TARGET_HEIGHT = 720

FIT_MODE = "pad"

# 补边颜色，仅 pad 模式生效
PAD_COLOR = (0, 0, 0)

KEEP_SIZE = False

assert (TARGET_WIDTH * 3) % 4 == 0, "行宽必须是 4 字节的倍数，否则 BMP 会产生行填充"
assert FIT_MODE in ("pad", "stretch", "crop"), f"未知的 FIT_MODE: {FIT_MODE}"

def _fit_to_target(img_rgb, target_width, target_height, fit_mode=None):
    """按 FIT_MODE 将图像适配到目标尺寸。"""
    mode = (fit_mode or FIT_MODE).lower()
    size = (target_width, target_height)

    if mode == "stretch":
        return img_rgb.resize(size, Image.Resampling.LANCZOS)
    if mode == "crop":
        return ImageOps.fit(img_rgb, size,
                            method=Image.Resampling.LANCZOS,
                            centering=(0.5, 0.5))
    return ImageOps.pad(img_rgb, size,
                        method=Image.Resampling.LANCZOS,
                        color=PAD_COLOR,
                        centering=(0.5, 0.5))

def _prepare_image(img_rgb, target_width=TARGET_WIDTH, target_height=TARGET_HEIGHT,
                   fit_mode=None, keep_size=None, no_upscale=False):
    """按 keep_size 决定是否缩放，并返回图像与尺寸。"""
    if keep_size is None:
        keep_size = KEEP_SIZE
    if keep_size:
        w, h = img_rgb.size
        if w > BMP_MAX_DIM or h > BMP_MAX_DIM:
            raise ValueError(
                f"原图 {w}x{h} 超出 FPGA 上限 {BMP_MAX_DIM}x{BMP_MAX_DIM}"
                f"（bmp_read.v 的 header_match 限制）")
        return img_rgb, w, h
    w, h = img_rgb.size
    if no_upscale and w <= target_width and h <= target_height:
        return img_rgb, w, h
    out = _fit_to_target(img_rgb, target_width, target_height, fit_mode)
    return out, target_width, target_height

def convert_single_file(input_path, output_path,
                        target_width=TARGET_WIDTH, target_height=TARGET_HEIGHT,
                        fit_mode=None, keep_size=None, no_upscale=False):
    """转换单个图片文件。"""
    if not os.path.exists(input_path):
        print(f"[错误] 找不到输入文件: {input_path}")
        return False

    try:
        with Image.open(input_path) as img:

            img_rgb = img.convert('RGB')

            img_out, ow, oh = _prepare_image(img_rgb, target_width, target_height,
                                             fit_mode, keep_size, no_upscale)

            if not output_path.lower().endswith('.bmp'):
                output_path += '.bmp'

            img_out.save(output_path, 'BMP')

            print(f"[成功] 转换完成: {input_path} -> {output_path}  ({ow}x{oh})")
            return True
    except Exception as e:
        print(f"[失败] 转换 {input_path} 时发生错误: {e}")
        return False

def convert_to_bmp(input_dir, output_dir,
                   target_width=TARGET_WIDTH, target_height=TARGET_HEIGHT,
                   fit_mode=None, keep_size=None):
    """批量转换目录中的图片。"""
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)

    supported_formats = ('.png', '.jpg', '.jpeg', '.bmp', '.webp', '.gif')
    files = [f for f in os.listdir(input_dir) if f.lower().endswith(supported_formats)]

    if not files:
        print(f"在目录 '{input_dir}' 中没有找到支持的图片文件。")
        return

    print(f"找到 {len(files)} 个图片文件，开始转换...")
    success_count = 0

    for filename in files:
        input_path = os.path.join(input_dir, filename)
        base_name = os.path.splitext(filename)[0]

        try:
            with Image.open(input_path) as img:

                img_rgb = img.convert('RGB')

                img_out, ow, oh = _prepare_image(img_rgb, target_width, target_height,
                                                 fit_mode, keep_size)

                output_filename = f"{base_name}_{ow}x{oh}.bmp"
                output_path = os.path.join(output_dir, output_filename)

                img_out.save(output_path, 'BMP')

                print(f"[成功] {filename} -> {output_filename}")
                success_count += 1
        except Exception as e:
            print(f"[失败] 转换 {filename} 时发生错误: {e}")

    print(f"\n转换完成！共成功转换 {success_count} 个文件。")
    print(f"请将 '{output_dir}' 目录下的所有 BMP 文件复制到 TF(SD) 卡的根目录中。")


# 写卡实现

SECTOR_SIZE       = 512
SCAN_MAX_SECTOR   = 131071
DEFAULT_WIPE_MB   = 72                      # 覆盖 64MB 扫描范围 + 余量
SECTOR_ACCESS_US  = 200                     # 单扇区访问耗时估计
SD_INIT_MS        = 150
DEFAULT_CLUSTER_KB = 64                     # FAT32 簇大小（越大 FAT 越小，扫描越快）

BMP_FILE_SIZE     = 54 + 1280 * 720 * 3

BMP_MAX_DIM       = 8191

BMP_HEADER_BYTES  = 54
WAV_OK_RATE = {48000}
WAV_OK_BITS = {16, 24}
WAV_OK_CH   = {1, 2}

IS_WIN = sys.platform.startswith("win")

# 所以：簇越大，FAT 越小，开机越快

def fat32_overhead(vol_bytes, sectors_per_cluster):
    """返回规划阶段的 (overhead_sectors, fat_sectors, n_clusters)。"""
    reserved, nfats = 32, 2
    total_sec = vol_bytes // SECTOR_SIZE
    fatsz = 1
    clusters = 0
    for _ in range(64):
        data_sec = total_sec - reserved - nfats * fatsz
        clusters = max(data_sec // sectors_per_cluster, 1)
        new_fatsz = (clusters * 4 + SECTOR_SIZE - 1) // SECTOR_SIZE
        if new_fatsz == fatsz:
            break
        fatsz = new_fatsz
    return reserved + nfats * fatsz, fatsz, clusters

def read_boot_sector_overhead(letter):
    """读取 FAT32 引导扇区参数，失败返回 None。"""
    try:
        with RawDisk(letter, write=False) as rd:
            d = rd.read(0, SECTOR_SIZE)
    except Exception:
        return None
    if len(d) < 90:
        return None
    bps = struct.unpack_from("<H", d, 11)[0]
    if bps != SECTOR_SIZE:
        return None
    spc = d[13]
    rsvd = struct.unpack_from("<H", d, 14)[0]
    nfat = d[16]
    fsz16 = struct.unpack_from("<H", d, 22)[0]
    fsz32 = struct.unpack_from("<I", d, 36)[0]
    fatsz = fsz16 if fsz16 else fsz32
    fs = d[82:90].decode("latin1", "replace") if len(d) >= 90 else ""
    if spc == 0 or nfat == 0 or fatsz == 0:
        return None
    return {"overhead": rsvd + nfat * fatsz,
            "fatsz": fatsz, "spc": spc,
            "cluster_kb": (spc * bps) // 1024,
            "fs": fs}

# Win32 裸设备访问

if IS_WIN:
    _k32 = ctypes.WinDLL("kernel32", use_last_error=True)

    GENERIC_READ            = 0x80000000
    GENERIC_WRITE           = 0x40000000
    OPEN_EXISTING           = 3
    FILE_SHARE_READ         = 0x00000001
    FILE_SHARE_WRITE        = 0x00000002
    FILE_FLAG_WRITE_THROUGH = 0x80000000
    INVALID_HANDLE_VALUE    = ctypes.c_void_p(-1).value

    FSCTL_LOCK_VOLUME     = 0x00090018
    FSCTL_DISMOUNT_VOLUME = 0x00090020

    _k32.CreateFileW.restype  = wintypes.HANDLE
    _k32.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD,
                                 wintypes.LPVOID, wintypes.DWORD, wintypes.DWORD,
                                 wintypes.HANDLE]
    _k32.DeviceIoControl.restype  = wintypes.BOOL
    _k32.DeviceIoControl.argtypes = [wintypes.HANDLE, wintypes.DWORD, wintypes.LPVOID,
                                     wintypes.DWORD, wintypes.LPVOID, wintypes.DWORD,
                                     ctypes.POINTER(wintypes.DWORD), wintypes.LPVOID]
    _k32.WriteFile.restype  = wintypes.BOOL
    _k32.WriteFile.argtypes = [wintypes.HANDLE, wintypes.LPCVOID, wintypes.DWORD,
                               ctypes.POINTER(wintypes.DWORD), wintypes.LPVOID]
    _k32.SetFilePointerEx.restype  = wintypes.BOOL
    _k32.SetFilePointerEx.argtypes = [wintypes.HANDLE, ctypes.c_longlong,
                                      ctypes.POINTER(ctypes.c_longlong), wintypes.DWORD]
    _k32.CloseHandle.restype  = wintypes.BOOL
    _k32.CloseHandle.argtypes = [wintypes.HANDLE]

    _k32.FlushFileBuffers.restype  = wintypes.BOOL
    _k32.FlushFileBuffers.argtypes = [wintypes.HANDLE]
    _k32.GetDriveTypeW.restype  = wintypes.UINT
    _k32.GetDriveTypeW.argtypes = [wintypes.LPCWSTR]

    DRIVE_REMOVABLE, DRIVE_FIXED, DRIVE_REMOTE = 2, 3, 4
    DRIVE_TYPE_NAME = {0: "未知", 1: "无根目录", 2: "可移动", 3: "固定磁盘",
                       4: "网络", 5: "光驱", 6: "RAM 盘"}

def is_admin():
    if not IS_WIN:
        return os.geteuid() == 0
    try:
        return ctypes.windll.shell32.IsUserAnAdmin() != 0
    except Exception:
        return False

def flush_volume(letter):
    """返回 (ok, 说明)。任何异常都不抛。"""
    if not IS_WIN:
        return False, "非 Windows，跳过"
    path = f"\\\\.\\{letter.upper()}:"
    h = _k32.CreateFileW(path, GENERIC_READ | GENERIC_WRITE,
                         FILE_SHARE_READ | FILE_SHARE_WRITE,
                         None, OPEN_EXISTING, 0, None)
    if h == INVALID_HANDLE_VALUE or h is None:
        return False, f"打不开 {path}（err {ctypes.get_last_error()}）"
    try:
        if not _k32.FlushFileBuffers(h):
            return False, (f"FlushFileBuffers 失败"
                           f"（err {ctypes.get_last_error()}）")
        return True, "写缓存已刷到卡上"
    except Exception as e:
        return False, f"异常: {e}"
    finally:
        try:
            _k32.CloseHandle(h)
        except Exception:
            pass

def list_drives():
    """列出所有驱动器（含类型与容量）"""
    rows = []
    for letter in "ABCDEFGHIJKLMNOPQRSTUVWXYZ":
        root = f"{letter}:\\"
        t = _k32.GetDriveTypeW(root)
        if t not in (DRIVE_REMOVABLE, DRIVE_FIXED):
            continue
        try:
            free = ctypes.c_ulonglong(0)
            total = ctypes.c_ulonglong(0)
            _k32.GetDiskFreeSpaceExW(root, None,
                                     ctypes.byref(total), ctypes.byref(free))
            if total.value == 0:
                continue
            rows.append((letter, t, total.value))
        except Exception:
            continue
    return rows

class RawDisk:
    """裸设备读写（Windows \\\\.\\X: 句柄）"""

    def __init__(self, letter, write=True):
        self.letter = letter.upper()
        self.h = None
        access = (GENERIC_READ | GENERIC_WRITE) if write else GENERIC_READ
        path = f"\\\\.\\{self.letter}:"
        self.h = _k32.CreateFileW(path, access,
                                  FILE_SHARE_READ | FILE_SHARE_WRITE,
                                  None, OPEN_EXISTING,
                                  FILE_FLAG_WRITE_THROUGH, None)
        if not self.h or self.h == INVALID_HANDLE_VALUE:
            err = ctypes.get_last_error()
            raise OSError(err,
                          f"无法打开裸设备 {path}。"
                          f"请确认： 以管理员身份运行  盘符正确  盘未被占用")

        br = wintypes.DWORD(0)
        _k32.DeviceIoControl(self.h, FSCTL_LOCK_VOLUME, None, 0, None, 0,
                             ctypes.byref(br), None)
        _k32.DeviceIoControl(self.h, FSCTL_DISMOUNT_VOLUME, None, 0, None, 0,
                             ctypes.byref(br), None)

    def seek(self, offset):
        if not _k32.SetFilePointerEx(self.h, ctypes.c_longlong(offset), None, 0):
            raise OSError(ctypes.get_last_error(), "SetFilePointerEx 失败")

    def write(self, data, offset=None):
        """data 长度必须是 512 的整数倍"""
        if offset is not None:
            self.seek(offset)
        n = len(data)
        buf = ctypes.create_string_buffer(data, n)
        written = wintypes.DWORD(0)
        if not _k32.WriteFile(self.h, buf, n, ctypes.byref(written), None):
            raise OSError(ctypes.get_last_error(), "WriteFile 失败")
        return written.value

    def read(self, offset, nbytes):
        """读取（注意：此处用 buffered 读，够用）"""
        self.seek(offset)
        buf = ctypes.create_string_buffer(nbytes)
        got = wintypes.DWORD(0)
        _k32.ReadFile(self.h, buf, nbytes, ctypes.byref(got), None)
        return buf.raw[:got.value]

    def close(self):
        if self.h and self.h != INVALID_HANDLE_VALUE:
            _k32.CloseHandle(self.h)
            self.h = None

    def __enter__(self):
        return self

    def __exit__(self, *a):
        self.close()

# 输出小工具

def hr(title=None):
    print()
    if title:
        print(f"  {title}")

def norm_drive(d):
    d = d.strip().rstrip("\\/")
    if d.endswith(":"):
        d = d[:-1]
    return d.upper()

def human(n):
    for u, s in (("GB", 1 << 30), ("MB", 1 << 20), ("KB", 1 << 10)):
        if n >= s:
            return f"{n/s:.2f} {u}"
    return f"{n} B"

def bmp_header_at(data, i):
    """解析指定偏移处的 BMP 头，失败返回 None。"""
    if data[i:i+2] != b"BM":
        return None

    if len(data) - i < BMP_HEADER_BYTES:
        return None
    file_size    = struct.unpack_from("<I", data, i + 2)[0]
    pixel_offset = struct.unpack_from("<I", data, i + 10)[0]
    width        = struct.unpack_from("<i", data, i + 18)[0]
    height       = struct.unpack_from("<i", data, i + 22)[0]
    bit_count    = struct.unpack_from("<H", data, i + 28)[0]
    compression  = struct.unpack_from("<I", data, i + 30)[0]

    if not (1 <= width <= BMP_MAX_DIM) or not (1 <= height <= BMP_MAX_DIM):
        return None
    if bit_count != 24 or compression != 0:
        return None
    if pixel_offset < BMP_HEADER_BYTES:
        return None

    row_stride = ((width * 3 + 3) // 4) * 4
    if file_size != pixel_offset + row_stride * height:
        return None
    return {"file_size": file_size, "width": width, "height": height,
            "row_stride": row_stride, "pixel_offset": pixel_offset}

# 素材收集

def collect_bmps(folder, limit):
    if not folder or not os.path.isdir(folder):
        return []
    files = sorted(glob.glob(os.path.join(folder, "*.bmp")))
    files += sorted(glob.glob(os.path.join(folder, "*.BMP")))
    seen, out = set(), []
    for f in files:
        rp = os.path.realpath(f)
        if rp not in seen:
            seen.add(rp); out.append(f)
    return out[:limit] if limit > 0 else out

def collect_wavs(folder):
    if not folder or not os.path.isdir(folder):
        return []
    files = sorted(glob.glob(os.path.join(folder, "*.wav")))
    files += sorted(glob.glob(os.path.join(folder, "*.WAV")))
    seen, out = set(), []
    for f in files:
        rp = os.path.realpath(f)
        if rp not in seen:
            seen.add(rp); out.append(f)
    return out

def parse_wav(path):
    size = os.path.getsize(path)
    with open(path, "rb") as f:
        head = f.read(12)
        if len(head) < 12 or head[0:4] != b"RIFF" or head[8:12] != b"WAVE":
            raise ValueError("不是 RIFF/WAVE")
        info = {"path": path, "file_size": size, "data_off": None, "data_size": None}
        pos = 12
        while pos + 8 <= size:
            f.seek(pos)
            hdr = f.read(8)
            if len(hdr) < 8:
                break
            cid = hdr[0:4]
            csz = struct.unpack("<I", hdr[4:8])[0]
            body = pos + 8
            if cid == b"fmt ":
                f.seek(body)
                raw = f.read(min(csz, 40))
                if len(raw) >= 16:
                    af, nch, sr, br, ba, bits = struct.unpack("<HHIIHH", raw[:16])
                    info.update(dict(audio_format=af, channels=nch, sample_rate=sr,
                                     byte_rate=br, block_align=ba, bits=bits))
            elif cid == b"data":
                info["data_off"] = body
                info["data_size"] = csz
                break
            pos = body + csz + (csz & 1)
        if info.get("sample_rate") is None or info.get("data_off") is None:
            raise ValueError("缺少 fmt / data chunk")
        return info

def validate_wav(info):
    probs, fixes = [], []
    if info.get("audio_format") != 1:
        probs.append(f"编码非 PCM (audioFormat={info.get('audio_format')})")
        fixes.append("ffmpeg -i in.wav -acodec pcm_s16le out.wav")
    if info.get("sample_rate") not in WAV_OK_RATE:
        sr = info.get("sample_rate")
        probs.append(f"采样率 {sr} Hz ≠ 48000（FPGA 按 48k 取帧，"
                     f"会播成{'快放' if sr and sr > 48000 else '慢放'}）")
        fixes.append("ffmpeg -i in.wav -ar 48000 -acodec pcm_s16le out.wav")
    if info.get("bits") not in WAV_OK_BITS:
        probs.append(f"位深 {info.get('bits')} bit 不为 16/24")
        fixes.append("ffmpeg -i in.wav -sample_fmt s16 -ar 48000 out.wav")
    if info.get("channels") not in WAV_OK_CH:
        probs.append(f"声道数 {info.get('channels')} 不为 1/2")
        fixes.append("ffmpeg -i in.wav -ac 2 -ar 48000 out.wav")
    return (not probs), probs, fixes

# 布局规划

def plan(bmps, wav_path, wav_info, overhead_sectors, cluster_sectors=0):
    """计算文件写入顺序与起始扇区。"""
    cur = overhead_sectors
    rows = []

    def round_up(n):
        """按簇向上取整；cluster_sectors==0 时退化为按扇区"""
        if cluster_sectors <= 0:
            return n
        return ((n + cluster_sectors - 1) // cluster_sectors) * cluster_sectors

    for i, p in enumerate(bmps):
        sz = os.path.getsize(p)
        raw_sec = (sz + SECTOR_SIZE - 1) // SECTOR_SIZE
        sec = round_up(raw_sec)
        rows.append(("BMP", f"{i:02d}_{os.path.basename(p)}", sz, cur, sec))
        cur += sec
    wav_start = cur
    if wav_info:
        sz = wav_info["file_size"]
        raw_sec = (sz + SECTOR_SIZE - 1) // SECTOR_SIZE
        sec = round_up(raw_sec)
        rows.append(("WAV", os.path.basename(wav_path), sz, cur, sec))
        cur += sec
    return rows, wav_start, cur

def report_plan(rows, wav_start, total_sec, mode, wipe_mb, overhead, cluster_kb=None):
    hr("布局规划")
    if overhead > 0:
        print(f"  文件系统开销 : {overhead:,} 扇区 = {human(overhead*SECTOR_SIZE)}"
              f"  ({'簇 '+str(cluster_kb)+'KB' if cluster_kb else ''})")
        print(f"                 [!] bmp_read 会[逐扇区爬过]这整个 FAT 区"
              f" = {overhead*SECTOR_ACCESS_US/1e6:.1f} s 启动延迟")
    print()
    print(f"  {'类型':<5}{'文件':<32}{'大小':>10}{'起始扇区':>12}{'扇区数':>10}")
    print(f"  {'-'*5}{'-'*32}{'-'*10}{'-'*12}{'-'*10}")
    for k, name, sz, st, sec in rows:
        print(f"  {k:<5}{name:<32}{sz/1048576:>8.2f}MB{st:>12,}{sec:>10,}")
    print(f"\n  合计 {total_sec:,} 扇区 = {human(total_sec*SECTOR_SIZE)}")
    print(f"  模式 {mode}    擦除前 {wipe_mb} MB ({wipe_mb*1024*1024//SECTOR_SIZE:,} 扇区)")

    hr("FPGA 上电预估")
    n_bmp = sum(1 for k, *_ in rows if k == "BMP")

    bmp_scan = (overhead + n_bmp * 2 + 2) * SECTOR_ACCESS_US / 1e6

    first_bmp_sz = next((r[2] for r in rows if r[0] == "BMP"), BMP_FILE_SIZE)
    img_load = first_bmp_sz / (25e6 / 8)
    t_img = SD_INIT_MS / 1000 + bmp_scan + img_load
    t_wav = SD_INIT_MS / 1000 + wav_start * SECTOR_ACCESS_US / 1e6
    print(f"  图片出现 : 约 {t_img:.1f} s")
    print(f"             = 初始化 {SD_INIT_MS/1000:.1f}s"
          f" + 扫描 {bmp_scan:.2f}s"
          f"{f'（含爬 FAT {overhead:,} 扇区）' if overhead else '（BMP 命中后快进）'}"
          f" + 载入首图 {img_load:.2f}s")
    print(f"  音频开始 : 约 {t_wav:.1f} s")
    print(f"             = 初始化 {SD_INIT_MS/1000:.1f}s"
          f" + 逐扇区扫描 {wav_start:,}×{SECTOR_ACCESS_US}µs")
    print(f"             [!] wav_read 逐扇区爬（无 BMP 那种快进）")

    if overhead > 5000:
        print(f"\n  [提示] FAT 开销偏大（{overhead:,} 扇区）-> 图片要等 {t_img:.1f}s")
        print(f"     改善方案（按推荐度）：")
        print(f"        --raw            裸扇区，开销 0，图片 ≈1.0s（卡在 PC 不可读）")
        print(f"        --cluster-kb 64  FAT32 + 64KB 簇，开销 ~3.8k，图片 ≈1.8s（卡可读）")

    bad = False
    if wav_start > SCAN_MAX_SECTOR:
        print(f"\n  [错误] WAV 起始扇区 {wav_start:,} > SCAN_MAX_SECTOR "
              f"({SCAN_MAX_SECTOR:,}) -> 音频扫不到！")
        bad = True
    if total_sec > SCAN_MAX_SECTOR:
        print(f"\n  [信息]  总占用 {total_sec:,} 扇区 > SCAN_MAX_SECTOR，属正常：")
        print(f"     扫描上限只约束「找魔数」；找到后流式读取不受限。")
        print(f"     [!] 但 WAV 的起始位置必须在 {SCAN_MAX_SECTOR:,} 以内")
    return not bad

# 步骤 1：扇区级擦除

def wipe_sectors(letter, mb):
    """裸写 0x00 擦除前 mb MB（只擦 FPGA 会扫描的范围）"""
    nbytes = mb * 1024 * 1024
    nbytes = (nbytes // SECTOR_SIZE) * SECTOR_SIZE
    chunk = 1024 * 1024                        # 1 MB/次
    assert chunk % SECTOR_SIZE == 0
    zeros = b"\x00" * chunk

    print(f"\n[擦除] 裸写 0x00 到 {letter}: 前 {mb} MB ...")
    print(f"       （只需覆盖 FPGA 扫描范围 {SCAN_MAX_SECTOR*SECTOR_SIZE//1024//1024} MB）")
    with RawDisk(letter, write=True) as rd:
        done = 0
        while done < nbytes:
            n = min(chunk, nbytes - done)
            rd.write(zeros[:n], offset=done)
            done += n
            pct = done * 100 // nbytes
            bar = "" * (pct // 4) + "-" * (25 - pct // 4)
            print(f"\r       [{bar}] {pct:3d}%  {done//1024//1024:3d}/{mb} MB",
                  end="", flush=True)
        print()
    print(f"       [OK] 擦除完成（{mb} MB）")

# 步骤 2a：FAT32 格式化

def format_fat32(letter, cluster_kb=64, label="FPGA"):
    """格式化 FAT32，优先使用 diskpart。"""
    print(f"\n[格式化] FAT32 /A:{cluster_kb}K on {letter}: ...")

    if _format_via_diskpart(letter, cluster_kb, label):
        return True
    print(f"       [!] diskpart 失败，改用 format.com ...")

    exe = shutil.which("format") or shutil.which("format.com")
    if not exe:
        print(f"       [错误] 找不到 format 命令")
        return False
    print(f"       (format.com 路径: {exe})")
    cmd = [exe, f"{letter}:", "/FS:FAT32", f"/A:{cluster_kb}K",
           "/Q", "/Y", f"/V:{label}"]
    try:
        p = subprocess.run(cmd, capture_output=True, text=True,
                           timeout=300, input="Y\n")
        out = (p.stdout or "") + (p.stderr or "")
        if p.returncode != 0 or "rror" in out or "失败" in out:
            print(f"       [错误] format 失败 (rc={p.returncode}):\n{out[-600:]}")
            return False
        print(f"       [OK] 格式化完成（format.com）")
        return True
    except subprocess.TimeoutExpired:
        print(f"       [错误] format 超时")
        return False
    except Exception as e:
        print(f"       [错误] format 异常: {e}")
        return False

def _format_via_diskpart(letter, cluster_kb, label):
    """用 diskpart 格式化目标卷。"""
    dp = shutil.which("diskpart") or \
         os.path.join(os.environ.get("SystemRoot", r"C:\Windows"),
                      "System32", "diskpart.exe")
    if not dp or not os.path.isfile(dp):
        return False

    vol_idx, why = _find_volume_index(letter)
    if vol_idx is None:
        print(f"       [!] 无法定位卷: {why}")
        if "管理员" in why or "权限" in why:
            print(f"       -> 请用[管理员 PowerShell]重跑本脚本")
        return False
    print(f"       (diskpart select volume {vol_idx}  - {why})")

    script_lines = [
        f"select volume {vol_idx}",
        f"format fs=fat32 unit={cluster_kb}K label={label} quick noerr",
        "exit",
    ]
    script = "\r\n".join(script_lines) + "\r\n"

    tmp = os.path.join(os.environ.get("TEMP", "."), "_sd_fmt.txt")
    try:
        with open(tmp, "w", encoding="ascii", newline="") as f:
            f.write(script)
        p = subprocess.run([dp, "/s", tmp], capture_output=True, text=True,
                           timeout=300)
        out = (p.stdout or "") + (p.stderr or "")
        low = out.lower()
        ok = (p.returncode == 0) and ("successfully" in low
                                      or "100 percent" in low
                                      or "格式化" in out)
        if not ok:
            errs = [ln.strip() for ln in out.splitlines()
                    if any(k in ln.lower() for k in
                           ("error", "virtual disk", "不是", "无效",
                            "失敗", "失败", "没有", "no volume"))]
            print(f"       diskpart 未成功 (rc={p.returncode})")
            for e in errs[:5]:
                print(f"         {e}")
            return False
        print(f"       [OK] 格式化完成（diskpart, volume {vol_idx}, "
              f"{cluster_kb}KB/簇）")
        return True
    except subprocess.TimeoutExpired:
        print(f"       diskpart 超时")
        return False
    except Exception as e:
        print(f"       diskpart 异常: {e}")
        return False
    finally:
        try:
            os.remove(tmp)
        except Exception:
            pass

def _diskpart_list(args):
    """跑 `diskpart /s` 执行 list 命令，返回输出文本"""
    dp = shutil.which("diskpart") or \
         os.path.join(os.environ.get("SystemRoot", r"C:\Windows"),
                      "System32", "diskpart.exe")
    tmp = os.path.join(os.environ.get("TEMP", "."), "_sd_lst.txt")
    try:
        with open(tmp, "w", encoding="ascii", newline="") as f:
            f.write("\r\n".join(list(args) + ["exit"]) + "\r\n")
        p = subprocess.run([dp, "/s", tmp], capture_output=True, text=True,
                           timeout=120)
        return (p.stdout or "") + (p.stderr or "")
    except OSError as e:

        if getattr(e, "winerror", None) == 740:
            return "__NOADMIN__"
        return f"__ERR__ {e}"
    except Exception as e:
        return f"__ERR__ {e}"
    finally:
        try:
            os.remove(tmp)
        except Exception:
            pass

def _find_volume_index(prefer_letter):
    """返回目标卷的 diskpart 卷号与说明。"""
    if os.path.exists(f"{prefer_letter}:\\"):
        return prefer_letter, f"盘符 {prefer_letter}: 仍有效"

    out = _diskpart_list([f"list volume"])
    if out == "__NOADMIN__":
        return None, "diskpart 需要管理员权限（WinError 740）"
    if out.startswith("__ERR__"):
        return None, out

    rows = []
    for ln in out.splitlines():
        s = ln.strip()
        if not s:
            continue
        m = re.match(r"^(?:卷|Volume)\s+(\d+)\s*(.*)$", s, re.IGNORECASE)
        if not m:
            continue
        idx = int(m.group(1))
        rest = m.group(2)
        parts = [p for p in re.split(r"\s{1,}", rest.strip()) if p]
        if not parts:
            continue

        letter_field = ""

        if parts and len(parts[0]) == 1 and parts[0].isalpha():
            letter_field = parts[0].upper()
        fs_field = ""
        for p in parts:
            if p.upper() in ("FAT32", "FAT", "NTFS", "EXFAT", "RAW", ""):
                fs_field = p.upper()
                break

        cap_mb, cap_pos = None, -1
        for k, p in enumerate(parts):
            if re.fullmatch(r"\d+(?:\.\d+)?", p) and k + 1 < len(parts):
                u = parts[k+1].upper()
                if u in ("GB", "MB", "TB", "KB"):
                    v = float(p)
                    cap_mb = v * {"KB": 1/1024, "MB": 1, "GB": 1024, "TB": 1024*1024}[u]
                    cap_pos = k
                    break
        rows.append(dict(idx=idx, letter=letter_field, fs=fs_field,
                         cap_mb=cap_mb, raw=s))

    if not rows:
        return None, f"list volume 未解析出任何卷（输出前 200 字: {out[:200]!r}）"

    cands = [r for r in rows if not r["letter"]
             and r["fs"] in ("RAW", "", "FAT", "FAT32")]
    if len(cands) == 1:
        return cands[0]["idx"], (f"找到无盘符的裸卷（{cands[0]['fs'] or '空'}）"
                                 f" 容量≈{cands[0]['cap_mb']:.0f}MB"
                                 if cands[0]['cap_mb'] else "找到无盘符的裸卷")
    if len(cands) > 1:

        c = min(cands, key=lambda r: (r["cap_mb"] is None, r["cap_mb"] or 1e9))
        return c["idx"], f"多个裸卷中选最小容量者（≈{c['cap_mb']:.0f}MB）"

    for r in rows:
        if r["letter"] == prefer_letter.upper():
            return r["idx"], f"按盘符 {prefer_letter}: 匹配"

    return None, ("未找到候选卷。list volume 摘要: " +
                  "; ".join(f"vol{r['idx']}(ltr={r['letter'] or '-'},"
                            f"fs={r['fs'] or '-'},cap={r['cap_mb']})"
                            for r in rows[:8]))

def copy_ordered(letter, bmps, wav_path, text_path=None):

    print(f"\n[写入] 按 TEXT -> BMP -> WAV 顺序拷贝 ...")
    root = f"{letter}:\\"
    n = 0
    if text_path:
        name = "TEXT.BIN"
        try:
            shutil.copy2(text_path, os.path.join(root, name))
            print(f"        {name}  ({human(os.path.getsize(text_path))})  [字幕/广告]")
            n += 1
        except Exception as e:
            print(f"        {name}: {e}")
    for i, p in enumerate(bmps):
        name = f"{i:02d}_{os.path.basename(p)}"
        try:
            shutil.copy2(p, os.path.join(root, name))
            print(f"        {name}  ({human(os.path.getsize(p))})")
            n += 1
        except Exception as e:
            print(f"        {name}: {e}")
    if wav_path:
        name = "zz_" + os.path.basename(wav_path)
        try:
            sz = os.path.getsize(wav_path)
            print(f"       ... {name}  ({human(sz)}，可能需十几秒)")
            shutil.copy2(wav_path, os.path.join(root, name))
            print(f"        {name}")
            n += 1
        except Exception as e:
            print(f"        {name}: {e}")
    return n

# 步骤 2c/3b：裸扇区直写（不建文件系统）

def raw_write_all(letter, bmps, wav_path, rows):
    """按规划扇区直接写入文件。"""
    print(f"\n[写入] 裸扇区直写（无文件系统）...")
    with RawDisk(letter, write=True) as rd:
        for (kind, name, sz, start, sec), path in zip(rows,
                                                      bmps + ([wav_path] if wav_path else [])):
            off = start * SECTOR_SIZE
            print(f"       ... {name}  -> 扇区 {start:,}  ({human(sz)})")
            with open(path, "rb") as f:
                written = 0
                while written < sz:
                    blk = f.read(4 * 1024 * 1024)       # 4 MB/次
                    if not blk:
                        break
                    pad = (-len(blk)) % SECTOR_SIZE
                    if pad:
                        blk += b"\x00" * pad
                    rd.write(blk, offset=off + written)
                    written += len(blk)
            pct = 100
            print(f"        完成")
    return len(rows)

# 步骤 4：校验（读回扇区确认魔数）

def verify_raw(letter, rows, bmps, wav_path, wav_info):
    """裸模式下读回每个文件的起始扇区，确认魔数正确"""
    print(f"\n[校验] 读回扇区确认魔数 ...")
    ok = True
    paths = bmps + ([wav_path] if wav_path else [])
    with RawDisk(letter, write=False) as rd:
        for (kind, name, sz, start, sec), path in zip(rows, paths):
            head = rd.read(start * SECTOR_SIZE, 16)
            if kind == "BMP":
                good = head[0:2] == b"BM"
                exp = "BM"
            else:
                good = head[0:4] == b"RIFF" and head[8:12] == b"WAVE"
                exp = "RIFF..WAVE"
            print(f"       {'' if good else ''} 扇区 {start:>7,}  "
                  f"{name:<30} 头={head[:4]!r}  (期望 {exp})")
            ok &= good
        if wav_path:
            ws = rows[-1][3]
            inr = ws <= SCAN_MAX_SECTOR
            print(f"       {'' if inr else ''} WAV 起始扇区 {ws:,} "
                  f"{'≤' if inr else '>'} SCAN_MAX_SECTOR({SCAN_MAX_SECTOR:,})")
            ok &= inr
    return ok

def verify_fat(letter, n_expect, bmps, wav_path):
    """校验 FAT32 布局与扇区魔数。"""
    print(f"\n[校验] 根目录 + 扇区魔数 ...")
    root = f"{letter}:\\"
    bmp_hits, wav_hit = [], None
    try:
        files = sorted(os.listdir(root))
    except Exception as e:
        print(f"       [错误] 无法读取: {e}")
        return dict(ok=False, bmp_hits=[], wav_hit=None)

    n_bmp_exp = len(bmps)
    for f in files:
        p = os.path.join(root, f)
        if os.path.isfile(p):
            print(f"       {f:<34} {human(os.path.getsize(p)):>12}")
    ok_fs = len(files) >= n_expect

    print(f"\n       裸扇区魔数扫描（FPGA 视角）...")
    ok_raw = True
    try:
        with RawDisk(letter, write=False) as rd:

            limit = min(SCAN_MAX_SECTOR + 4096, 240000)
            BATCH = 2048                      # 1MB/批
            off = 0
            wav_rest = None
            while off // SECTOR_SIZE < limit:
                data = rd.read(off, min(BATCH * SECTOR_SIZE,
                                        (limit - off // SECTOR_SIZE) * SECTOR_SIZE))
                if not data:
                    break
                for i in range(0, len(data) - SECTOR_SIZE + 1, SECTOR_SIZE):
                    sec = (off + i) // SECTOR_SIZE
                    if sec > limit:
                        break

                    if bmp_header_at(data, i) is not None:
                        bmp_hits.append(sec)
                    if wav_hit is None and data[i:i+4] == b"RIFF" and \
                            data[i+8:i+12] == b"WAVE":
                        wav_hit = sec
                        wav_rest = data[i+4:i+8]          # 供下面核对长度
                if len(bmp_hits) >= n_bmp_exp and wav_hit is not None:
                    break
                off += len(data)

            print(f"       找到 BMP 'BM' 起始扇区: {bmp_hits if bmp_hits else '[错误] 无'}")
            if wav_hit is not None:
                in_range = wav_hit <= SCAN_MAX_SECTOR
                print(f"       找到 WAV 'RIFF' 起始扇区: {wav_hit:,}"
                      f"  {'≤' if in_range else '>'} SCAN_MAX_SECTOR OK" if in_range
                      else f"       找到 WAV 'RIFF' 起始扇区: {wav_hit:,}"
                           f"  [错误] 超出 {SCAN_MAX_SECTOR:,}！音频扫不到")
                ok_raw &= in_range
            else:
                print(f"       [错误] 未找到 WAV 'RIFF'（扫到 {limit:,} 扇区）")
                ok_raw = False
            ok_raw &= (len(bmp_hits) >= 1)
            if not bmp_hits:
                print(f"       [错误] 未找到任何 BMP 'BM'！")

            if len(bmp_hits) != n_bmp_exp:
                print(f"       [!]  BMP 魔数个数 {len(bmp_hits)} ≠ 写入张数 {n_bmp_exp}"
                      f"   （多出 -> 卡上有残留旧图，建议加 --wipe-mb 重装）")
            else:
                print(f"        BMP 魔数个数 == 写入张数（{n_bmp_exp}）")
            if len(bmp_hits) > 1:
                if all(bmp_hits[i] < bmp_hits[i+1] for i in range(len(bmp_hits)-1)):
                    print(f"        BMP 顺序单调递增")
                else:
                    print(f"       [错误] BMP 顺序异常（乱序）")
                    ok_raw = False

                diffs = [bmp_hits[i+1] - bmp_hits[i] for i in range(len(bmp_hits)-1)]
                if len(set(diffs)) > 1:
                    print(f"       [信息]  BMP 间隔不完全等距（{sorted(set(diffs))}）-"
                          f" 不影响 FPGA（逐扇区扫描），只要单调递增即可")
            if bmp_hits and wav_hit is not None:
                if max(bmp_hits) < wav_hit:
                    print(f"        BMP 在 WAV 之前（符合硬约束）")
                else:
                    print(f"       [错误] WAV 在 BMP 之前！图片会扫不到")
                    ok_raw = False
    except Exception as e:
        print(f"       [!] 扇区验证出错: {e}")
        ok_raw = False

    ok = ok_fs and ok_raw
    print(f"\n       {'[OK]' if ok else '[!] '} 文件数 {len(files)}/{n_expect}"
          f"   扇区校验 {'通过' if ok_raw else '失败'}")
    if bmp_hits:
        print(f"        实测 BMP 起始扇区（可信）: {bmp_hits}")
    if wav_hit is not None:
        print(f"        实测 WAV 起始扇区（可信）: {wav_hit:,}")
    return dict(ok=ok, bmp_hits=bmp_hits, wav_hit=wav_hit)

RTL_REL = os.path.join("..", "src", "user_source", "hdl_source",
                       "top_tf_hdmi_audio.v")

def fix_rtl_constants(script_dir, bmp_start, wav_start, bmp_count):
    """把扫描常量写回 top_tf_hdmi_audio.v。"""
    path = os.path.normpath(os.path.join(script_dir, RTL_REL))
    if not os.path.isfile(path):
        return False, f"未找到 RTL 文件: {path}"

    try:
        with open(path, "r", encoding="utf-8", newline="") as f:
            text = f.read()
    except Exception as e:
        return False, f"读取失败: {e}"

    nl = "\r\n" if "\r\n" in text else "\n"

    spec = [
        (r"([ \t]*parameter[ \t]+)SCAN_BMP_START([ \t]*=[ \t]*)32'd\d+([ \t]*;)",
         rf"\g<1>SCAN_BMP_START\g<2>32'd{bmp_start}\g<3>"),
        (r"([ \t]*parameter[ \t]+)SCAN_WAV_START([ \t]*=[ \t]*)32'd\d+([ \t]*;)",
         rf"\g<1>SCAN_WAV_START\g<2>32'd{wav_start}\g<3>"),
        (r"([ \t]*parameter[ \t]+)SCAN_BMP_COUNT([ \t]*=[ \t]*)5'd\d+([ \t]*;)",
         rf"\g<1>SCAN_BMP_COUNT\g<2>5'd{bmp_count}\g<3>"),
    ]

    new_text = text
    hits = []
    for pat, rep in spec:
        new_text, n = re.subn(pat, rep, new_text)
        hits.append(n)

    if any(n != 1 for n in hits):
        return False, (f"匹配数异常 {hits}（期望每个 1）-> 未修改，请手动核对")

    if new_text == text:
        return True, "常量已是目标值（无需修改）"

    try:
        with open(path + ".bak", "w", encoding="utf-8", newline="") as f:
            f.write(text)
    except Exception as e:
        return False, f"备份失败（为安全起见不修改）: {e}"

    try:
        with open(path, "w", encoding="utf-8", newline="") as f:
            f.write(new_text)
    except Exception as e:
        return False, f"写入失败: {e}"

    return True, (f"已写回 {os.path.basename(path)}："
                  f"BMP_START={bmp_start}, WAV_START={wav_start}, "
                  f"COUNT={bmp_count}   （备份: {os.path.basename(path)}.bak）")

def check_card(letter):
    """只读检查卡上的 BMP/WAV 布局。"""
    zf = dict(ok=False, n_bmp=0, bmp_hits=[], bm_false=[], wav_hit=None)

    hr(f"只读体检  {letter}:")
    root = f"{letter}:\\"

    fs_ok = os.path.exists(root)
    if fs_ok:
        try:
            items = sorted(os.listdir(root))
            bmpf = [f for f in items if f.lower().endswith(".bmp")]
            wavf = [f for f in items if f.lower().endswith(".wav")]
            print(f"  [OK] 文件系统可读，根目录 {len(items)} 项")
            print(f"     BMP {len(bmpf)} 个" + (f"  {bmpf[:6]}" if bmpf else "  [错误]"))
            print(f"     WAV {len(wavf)} 个" + (f"  {wavf}" if wavf else "  [错误]"))
        except Exception as e:
            print(f"  [!] 文件系统可读但列目录失败: {e}")
    else:
        print(f"  [!] 盘符 {letter}: 不可见（无文件系统 / 已被擦除）")
        print(f"     -> 这正是板卡黑屏的典型原因之一！")

    print(f"\n  裸扇区扫描（FPGA 实际看到的）...")
    try:
        with RawDisk(letter, write=False) as rd:
            bs_bytes = rd.read(0, SECTOR_SIZE)
            if not bs_bytes or len(bs_bytes) < SECTOR_SIZE:
                print(f"  [错误] 读不到扇区 0（卡不在位？）")
                return zf

            is_fat = bs_bytes[510:512] == b"\x55\xAA"
            oem = bs_bytes[3:11].decode("ascii", "replace").strip()
            if is_fat:
                print(f"  [OK] 扇区 0 有 FAT 引导记录（OEM='{oem}'）")
            else:
                head = bs_bytes[:16]
                print(f"  [错误] 扇区 0 无引导记录！前 16 字节 = "
                      f"{head.hex(' ')}")
                if head.strip(b"\x00") == b"":
                    print(f"     -> 整片被擦成 0：卡是空的（上次擦除后没格式化成功）")

            limit = min(SCAN_MAX_SECTOR + 4096, 240000)
            BATCH = 2048
            off = 0
            while off // SECTOR_SIZE < limit:
                n_byte = min(BATCH * SECTOR_SIZE,
                             (limit - off // SECTOR_SIZE) * SECTOR_SIZE)
                data = rd.read(off, n_byte)
                if not data:
                    break
                for i in range(0, len(data) - SECTOR_SIZE + 1, SECTOR_SIZE):
                    sec = (off + i) // SECTOR_SIZE
                    if sec > limit:
                        break
                    if data[i:i+2] == b"BM":

                        if bmp_header_at(data, i) is not None:
                            zf["bmp_hits"].append(sec)
                        else:
                            zf["bm_false"].append(sec)
                    if zf["wav_hit"] is None and data[i:i+4] == b"RIFF" \
                            and data[i+8:i+12] == b"WAVE":
                        zf["wav_hit"] = sec
                off += len(data)

            zf["n_bmp"] = len(zf["bmp_hits"])

            print(f"\n  扫描结果（0 ~ {limit:,} 扇区）：")
            if zf["bmp_hits"]:
                print(f"  [OK] BMP 'BM' 发现 {zf['n_bmp']} 处，起始扇区：")
                print(f"     {zf['bmp_hits'][:20]}")
                print(f"     -> 请填 parameter SCAN_BMP_COUNT = 5'd{zf['n_bmp']};")
                print(f"        parameter SCAN_BMP_START = 32'd{zf['bmp_hits'][0]};")
            else:
                print(f"  [错误] 一个 BMP 都没有 -> 这就是板卡黑屏的原因！")
            if zf["bm_false"]:

                print(f"  [信息]  另有 {len(zf['bm_false'])} 处 'BM' 假阳性，已忽略："
                      f" {zf['bm_false'][:10]}")
                print(f"      （WAV/像素数据里的偶然字节对，FPGA 会跳过，无害）")

            if zf["wav_hit"] is not None:
                in_r = zf["wav_hit"] <= SCAN_MAX_SECTOR
                print(f"  {'[OK]' if in_r else '[错误]'} WAV 'RIFF' 起始扇区 "
                      f"{zf['wav_hit']:,}"
                      f"{'' if in_r else f'  超出 {SCAN_MAX_SECTOR:,}！音频读不到'}")
                if in_r:
                    print(f"     -> 请填 parameter SCAN_WAV_START = "
                          f"32'd{zf['wav_hit']};")
            else:
                print(f"  [错误] 没有 WAV -> 音频不会响")

            if zf["bmp_hits"] and zf["wav_hit"] is not None:
                if max(zf["bmp_hits"]) < zf["wav_hit"]:
                    print(f"  [OK] BMP 全部在 WAV 之前（符合硬约束）")
                else:
                    print(f"  [错误] WAV 在 BMP 之前！图片会扫不到")

            zf["ok"] = (zf["n_bmp"] > 0 and zf["wav_hit"] is not None
                        and max(zf["bmp_hits"] or [0]) < (zf["wav_hit"] or 1e18)
                        and zf["wav_hit"] <= SCAN_MAX_SECTOR)
    except Exception as e:
        print(f"  [错误] 裸设备访问失败: {e}")
        print(f"     请确认： 卡插好了  盘符正确（--list） 是否被占用")
        return zf

    print()
    if zf["ok"]:
        print(f"   卡已正确部署：{zf['n_bmp']} 张 BMP + 1 个 WAV")
        print(f"     可放心编译上板。")
    else:
        print(f"  [!] 卡未正确部署 -> 板卡必然黑屏。请先跑部署：")

        print(f"     python deploy_sd.py {letter}: -n {zf['n_bmp']} --cluster-kb 64")
    return zf

# main


def deploy_main(argv=None):
    ap = argparse.ArgumentParser(
        description="FPGA SD 卡一键部署（清扇区 + 按序写入 BMP/WAV）",
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("drive", nargs="?", help="SD 卡盘符，如 G: 或 G:\\")
    ap.add_argument("--list", action="store_true", help="列出候选驱动器")
    ap.add_argument("-d", "--dir", default=None,
                    help="素材文件夹（默认：脚本同级的 assets/，再退回 output_bmp+output_wav）")
    ap.add_argument("-n", "--num", type=int, default=0,
                    help="最多几张 BMP（0 = 全部，上限 16）")
    ap.add_argument("--raw", action="store_true",
                    help="裸扇区模式（布局确定、开机最快；卡在 PC 不可读）")
    ap.add_argument("--cluster-kb", type=int, default=DEFAULT_CLUSTER_KB,
                    choices=[4, 8, 16, 32, 64],
                    help=f"FAT32 簇大小 KB（默认 {DEFAULT_CLUSTER_KB}；越大 FAT 越小、"
                         f"开机越快）")
    ap.add_argument("--no-wav", action="store_true", help="不装 WAV")

    ap.add_argument("--text", default=None,
                    help="TEXT.BIN 路径（默认 toSD/TEXT.BIN，存在则自动安装）")
    ap.add_argument("--no-wipe", action="store_true", help="跳过扇区擦除（快，但可能有残留）")
    ap.add_argument("--wipe-mb", type=int, default=DEFAULT_WIPE_MB,
                    help=f"擦除前多少 MB（默认 {DEFAULT_WIPE_MB}）")
    ap.add_argument("--check", action="store_true",
                    help="[只读体检]不改任何东西，直接判断卡是否已正确部署")
    ap.add_argument("--no-fix-rtl", action="store_true",
                    help="不改写 top_tf_hdmi_audio.v 的扫描常量（默认会自动写回）")
    ap.add_argument("--dry-run", action="store_true", help="只预览，不碰盘")
    ap.add_argument("--yes", action="store_true", help="跳过交互确认")
    args = ap.parse_args(argv)

    script_dir = os.path.dirname(os.path.abspath(__file__))

    if args.list or not args.drive:
        hr("候选驱动器")
        for letter, t, total in list_drives():
            print(f"  {letter}:\\  {DRIVE_TYPE_NAME.get(t,'?'):<8}  {human(total):>10}")
        print(f"\n  [提示] 建议用[可移动]类型、容量与你 SD 卡相符的那个")
        print(f"  用法: python deploy_sd.py G:\\")
        if not args.drive:
            return 0

    letter = norm_drive(args.drive)
    if letter == "C":
        print("[错误] 拒绝操作系统盘 C:")
        return 2
    if not IS_WIN:
        print("[错误] 本脚本依赖 Windows 裸设备 API")
        return 2

    root = f"{letter}:\\"
    drive_letter_live = os.path.exists(root)

    if not drive_letter_live:
        print(f"[!]  盘符 {letter}: 当前不可见（可能已被擦除/无文件系统）")
        print(f"    -> 尝试裸设备访问 + diskpart 按卷号定位 ...")
        raw_ok = False
        try:
            with RawDisk(letter, write=False) as _rd:
                _rd.read(0, SECTOR_SIZE)
            raw_ok = True
            print(f"    [OK] 裸设备 \\\\.\\{letter}: 可访问 -> 卡在位，继续")
        except Exception as e:
            print(f"    [错误] 裸设备也不可访问: {e}")
            print(f"       请检查： 卡插好了吗  盘符对不对（跑 --list）")
            return 2

    dt = _k32.GetDriveTypeW(root)
    free = ctypes.c_ulonglong(0); total = ctypes.c_ulonglong(0)
    _k32.GetDiskFreeSpaceExW(root, None, ctypes.byref(total), ctypes.byref(free))
    if total.value == 0:

        total = ctypes.c_ulonglong(16 * 1024**3)
        print(f"    [信息]  无文件系统 -> 容量取不到，用 16GB 占位估算")

    if args.check:
        zf = check_card(letter)
        return 0 if zf["ok"] else 1

    need_admin = not args.dry_run
    if need_admin and not is_admin():
        print("[错误] 需要[管理员权限]（擦除/裸写要访问裸设备）")
        print("   请右键 PowerShell -> 以管理员身份运行，再执行本脚本")
        return 2

    hr("素材收集")
    if args.dir:
        cand_dirs = [args.dir]
    else:
        cand_dirs = [os.path.join(script_dir, "toSD"),
                     os.path.join(script_dir, "assets"),
                     os.path.join(script_dir, "output_bmp")]

    bmp_dir = next((d for d in cand_dirs
                    if glob.glob(os.path.join(d, "*.bmp"))), None)

    if args.dir:
        wav_dirs = [args.dir]
    else:
        wav_dirs = [os.path.join(script_dir, "toSD"),
                    os.path.join(script_dir, "assets"),
                    os.path.join(script_dir, "output_wav")]
    wav_dir = next((d for d in wav_dirs
                    if glob.glob(os.path.join(d, "*.wav"))), None)

    bmps = collect_bmps(bmp_dir, args.num)
    wavs = [] if args.no_wav else collect_wavs(wav_dir)
    wav_path = wavs[0] if wavs else None

    text_path = args.text
    if text_path is None:
        cand = os.path.join(bmp_dir, "TEXT.BIN")
        if os.path.isfile(cand):
            text_path = cand
    if text_path and not os.path.isfile(text_path):
        print(f"[!] --text 指定的文件不存在，跳过：{text_path}")
        text_path = None
    if text_path:
        print(f"  字幕/广告文本 : {os.path.basename(text_path)} "
              f"({human(os.path.getsize(text_path))})")

    print(f"  目标卡   : {letter}:\\   ({DRIVE_TYPE_NAME.get(dt,'?')}, {human(total.value)})")
    print(f"  BMP 目录 : {bmp_dir or '(未找到)'}   -> {len(bmps)} 张")
    print(f"  WAV 目录 : {wav_dir or '(未找到)'}   -> {len(wavs)} 个")
    if not bmps and not wav_path:
        print("\n[错误] 没有找到任何素材（.bmp / .wav）")
        print(f"   [提示] 请把要写入的素材放进 {os.path.join(script_dir,'toSD')}\\")
        return 2

    wav_info = None
    if wav_path:
        try:
            wav_info = parse_wav(wav_path)
        except Exception as e:
            print(f"\n[错误] WAV 解析失败: {e}")
            return 2
        ok, probs, fixes = validate_wav(wav_info)
        print(f"\n  WAV 格式 : {wav_info['sample_rate']} Hz / {wav_info['bits']} bit"
              f" / {wav_info['channels']} ch / {human(wav_info['data_size'])} PCM")
        if ok:
            print(f"  [OK] 符合要求（48 kHz，可直接播放）")
        else:
            print(f"\n  [错误] WAV 不符合要求：")
            for p in probs:
                print(f"     - {p}")
            print(f"  修复命令：")
            for f in fixes:
                print(f"     {f}")
            if not args.yes and input("\n  仍要继续？(y/N): ").strip().lower() != "y":
                return 2

    spc_used = max(args.cluster_kb * 1024 // SECTOR_SIZE, 1)
    bs = None if args.raw else read_boot_sector_overhead(letter)
    if bs:
        overhead = bs["overhead"]
        src = (f"实测（读引导扇区：{bs['cluster_kb']}KB/簇，"
               f"FAT {bs['fatsz']:,} 扇区）")
        print(f"\n  [信息]  卡当前文件系统 : {bs['fs']}   {bs['cluster_kb']} KB/簇")
        print(f"      文件区起点 {overhead:,} 扇区 = {human(overhead*SECTOR_SIZE)}")
        print(f"      -> [{src}]（FAT 区不含 BM，bmp_read 要爬过去）")

        spc_used = max(args.cluster_kb * 1024 // SECTOR_SIZE, 1)
    elif args.raw:
        overhead = 0
        spc_used = 0            # 裸写无需簇对齐
        print(f"\n  [信息]  裸扇区模式：无文件系统开销，文件从扇区 0 开始")
    else:
        spc = max(args.cluster_kb * 1024 // SECTOR_SIZE, 1)
        overhead, fat_sec, _ = fat32_overhead(total.value, spc)
        spc_used = spc
        print(f"\n  [!]  无法读引导扇区 -> 用理论估算")
        print(f"      FAT32/{args.cluster_kb}KB簇 -> 开销 {overhead:,} 扇区")
        print(f"      [!] 格式化后实际值可能不同，跑完看校验输出")

    rows, wav_start, total_sec = plan(bmps, wav_path, wav_info, overhead,
                                     cluster_sectors=spc_used)
    fatal = report_plan(rows, wav_start, total_sec,
                        "裸扇区" if args.raw else "FAT32",
                        args.wipe_mb, overhead,
                        bs["cluster_kb"] if bs else
                        (None if args.raw else args.cluster_kb))
    if not fatal:
        print(f"\n  [错误] 布局不可行，请减少图片数量或换用更小的 WAV")
        return 2

    if args.dry_run:
        print("\n  [--dry-run] 未做任何修改。")
        return 0

    if not args.yes:
        warn = "[!] 会[物理擦除]卡上的数据！" if not args.no_wipe else ""
        print(f"\n  {warn}")
        print(f"  即将对 {letter}:\\ 执行："
              f"{'扇区擦除 -> ' if not args.no_wipe else ''}"
              f"{'裸扇区直写' if args.raw else 'FAT32 格式化 -> 顺序拷贝'}")
        if input(f"  请输入盘符 {letter} 确认（其它输入=取消）: ").strip().upper() != letter:
            print("  已取消。")
            return 0

    t0 = __import__("time").time()

    if not args.no_wipe:
        try:
            wipe_sectors(letter, args.wipe_mb)
        except OSError as e:
            print(f"\n[错误] 擦除失败: {e}")
            return 3

    if args.raw:
        n = raw_write_all(letter, bmps, wav_path, rows)
        ok = verify_raw(letter, rows, bmps, wav_path, wav_info)
        vres = dict(bmp_hits=[], wav_hit=None)
    else:
        if not format_fat32(letter, cluster_kb=args.cluster_kb):
            print("\n[错误] FAT32 格式化失败。")
            print("   若卡容量 >32GB，Windows 不支持 FAT32 -> 请改用 --raw 模式")
            return 3

        bs2 = read_boot_sector_overhead(letter)
        if bs2:
            ov2 = bs2["overhead"]
            if ov2 != overhead:
                print(f"\n  [!]  格式化后布局与规划不同：")
                print(f"      规划开销 {overhead:,} -> 实测 {ov2:,} 扇区"
                      f"  （差 {ov2-overhead:+,}）")
            else:
                print(f"\n  [信息]  格式化后开销与规划一致（{ov2:,} 扇区）")
            print(f"      实测：{bs2['cluster_kb']} KB/簇, "
                  f"FAT {bs2['fatsz']:,} 扇区, "
                  f"文件区起点 {ov2:,} 扇区")
            overhead = ov2
            spc_used = max(bs2['cluster_kb'] * 1024 // SECTOR_SIZE, 1)
            rows, wav_start, total_sec = plan(bmps, wav_path, wav_info, ov2,
                                             cluster_sectors=spc_used)
            if wav_path and wav_start > SCAN_MAX_SECTOR:
                print(f"\n[错误] 格式化后 WAV 起点 {wav_start:,} 超出扫描上限 "
                      f"{SCAN_MAX_SECTOR:,}，写卡后音频无法读取。")
                print("   请减少图片数量或缩短音频后重试。")
                return 2

        n = copy_ordered(letter, bmps, wav_path, text_path)
        vres = verify_fat(letter, len(rows), bmps, wav_path)
        ok = vres["ok"]

    dt_s = __import__("time").time() - t0

    hr("完成")
    print(f"  耗时 {dt_s:.1f} s    写入 {n} 个文件    校验 {'通过 [OK]' if ok else '有问题 [!]'}")

    n_bmp_rows = 0
    wavs = []
    bmp1 = overhead
    wav1 = None
    measured = False
    if rows:
        n_bmp_rows = sum(1 for r in rows if r[0] == "BMP")
        bmp1 = rows[0][3]
        wavs = [r for r in rows if r[0] == "WAV"]
        if wavs:
            wav1 = wavs[0][3]

    bmp_rows      = [r for r in rows if r[0] == "BMP"]
    bmp_sec_total = sum(r[4] for r in bmp_rows)
    meas_bmp1 = vres.get("bmp_hits")[0] if vres.get("bmp_hits") else None
    meas_wav1 = vres.get("wav_hit")
    if rows and n_bmp_rows:
        bmp1 = overhead
        wav1 = overhead + bmp_sec_total
        measured = True
        print(f"\n   扫描常量（保守下界，不是精确值）：")
        print(f"      数据区起点 {overhead:,} 扇区（= 保留 + 2×FAT）")
        print(f"      {n_bmp_rows} 张 BMP 共占 {bmp_sec_total:,} 扇区"
              f"（逐张按 {spc_used} 扇区/簇取整后求和）")
        if len({r[4] for r in bmp_rows}) > 1:
            print(f"       各图尺寸不同 -> 单张占用不等："
                  f"{min(r[4] for r in bmp_rows):,} ~ "
                  f"{max(r[4] for r in bmp_rows):,} 扇区/张"
                  f"（旧版按 720p 单张值 × 张数会算错）")
        if meas_bmp1 is not None:
            print(f"      BMP 实测 {meas_bmp1:,} -> 下界 {bmp1:,}"
                  f"（多爬 {meas_bmp1-bmp1:,} 扇区 ≈ "
                  f"{(meas_bmp1-bmp1)*SECTOR_ACCESS_US/1e6:.2f}s）")
        if meas_wav1 is not None:
            print(f"      WAV 实测 {meas_wav1:,} -> 下界 {wav1:,}"
                  f"（多爬 {max(meas_wav1-wav1,0):,} 扇区 ≈ "
                  f"{max(meas_wav1-wav1,0)*SECTOR_ACCESS_US/1e6:.2f}s）")
            if meas_wav1 < wav1:
                print(f"      [!] 实测 WAV 比下界还小（{meas_wav1:,} < {wav1:,}）"
                      f"-> 布局异常，请人工核对！")
    elif wavs:
        wav1 = wavs[0][3]
        measured = False

    if rows:
        hr(" 请把这 3 个常量填进 top_tf_hdmi_audio.v（否则黑屏/启动慢）")
        print(f"      {'[OK] 以下数值为[保守下界]（单向扫描，早起点无害、晚起点致命）' if measured else '[!] 以下为推算值（未能实测，可能与实际有偏差）'}")
        print("      // top_tf_hdmi_audio.v 的 parameter 段")
        print(f"      parameter SCAN_BMP_COUNT = 5'd{n_bmp_rows};"
              f"        // [!] 必须=卡上实际张数！填大了会黑屏")
        print(f"      parameter SCAN_BMP_START = 32'd{bmp1};"
              f"    // = 数据区起点（任何文件都不可能更早）")
        if wav1 is not None:
            print(f"      parameter SCAN_WAV_START = 32'd{wav1};"
                  f"   // = 数据区起点 + 张数×每张占扇区")
        print(f"")
        print(f"      [!] 三个常量填错的后果：")
        print(f"         - SCAN_BMP_COUNT 填大 -> bmp_read 爬满 64MB"
              f" -> 最长 {(SCAN_MAX_SECTOR-bmp1)*SECTOR_ACCESS_US/1e6:.0f}s 黑屏")
        print(f"         - SCAN_BMP_START 偏小 -> 多爬几帧（本下界只多爬 "
              f"{(meas_bmp1-bmp1) if meas_bmp1 is not None else 0:,} 扇区）- 无害")
        print(f"         - SCAN_WAV_START 偏大 -> 单向扫描永远碰不到 ->"
              f" 位4 恒显 'F'、没声音（且无任何报错）")
        print(f"         - SCAN_WAV_START 偏差超过 WAV_SCAN_SPAN(8000) -> 同样扫不到")

        if args.no_fix_rtl:
            print(f"\n      [--no-fix-rtl] 已跳过自动写回，请手动填上面 3 个值")
        elif wav1 is None:
            print(f"\n      [!] 未算出 WAV 起点 -> 不自动写回（WAV_START 未知）")
            print(f"         请手动填 SCAN_BMP_COUNT={n_bmp_rows}, "
                  f"SCAN_BMP_START={bmp1}")
        elif not ok:
            print(f"\n      [!] 卡上校验未通过 -> 不自动写回（避免把错的值写进 RTL）")
        elif not measured:
            print(f"\n      [!] 常量来自推算（非实测）-> 不自动写回（偏差可能几百扇区）")
        else:
            print(f"\n[自动写回] 正在更新 top_tf_hdmi_audio.v ...")
            okw, msg = fix_rtl_constants(script_dir, bmp1, wav1, n_bmp_rows)
            print(f"      {'[OK]' if okw else '[!] '} {msg}")
            if okw:
                print(f"      -> 现在可直接在 TD 里编译（无需手抄常量）")

    print(f"\n  FPGA 上电预期（填了上面常量后）：")
    print(f"     图片 ~{SD_INIT_MS/1000 + 0.89:.1f}s"
          f"   音频 ~{SD_INIT_MS/1000 + (wav1 or 0)*SECTOR_ACCESS_US/1e6:.1f}s")
    print(f"  （不填常量则为：图片 ~{SD_INIT_MS/1000 + overhead*SECTOR_ACCESS_US/1e6 + 0.89:.1f}s"
          f"   音频 ~{SD_INIT_MS/1000 + wav_start*SECTOR_ACCESS_US/1e6:.1f}s）")

    if not args.raw:
        hrok, hmsg = flush_volume(letter)
        print(f"\n[刷缓存] {'[OK]' if hrok else '[!] '} {hmsg}" +
              ("" if hrok else "   -> 请务必先用『安全弹出』再拔卡"))

    if args.raw:
        print(f"\n  [!] 裸扇区模式：Windows 会提示「需要格式化」-")
        print(f"     千万不要点格式化，那会毁掉布局。直接用即可。")
    else:
        print(f"\n  [OK] 可以安全弹出 SD 卡了。")
    return 0 if ok else 1


# 文本打包

TEXT_MAGIC = b"FTXT"
TEXT_VERSION = 1
TEXT_CUE_N = 64
TEXT_SCH_N = 1024
TEXT_LN_N = 64
TEXT_ACH_N = 1024
TEXT_OFF_CUE = 16
TEXT_OFF_SCH = TEXT_OFF_CUE + 512
TEXT_OFF_LN = TEXT_OFF_SCH + 1024
TEXT_OFF_ACH = TEXT_OFF_LN + 128
TEXT_OFF_END = TEXT_OFF_ACH + 1024
TEXT_RATE = 48000
TEXT_SAMPLES_PER_FRAME = 792
TEXT_ASCII_FIRST, TEXT_ASCII_LAST = 0x20, 0x7E
TEXT_AD_LINES = 4
TEXT_AD_COLS = 64

# 广告字库收录的字符，顺序必须与 ad_cn_font_lo/hi.mif 一致（索引即字形槽位）
TEXT_AD_CHARSET = (
    " 1280x7"
    "登山客在静谧湖边驻足凝望云雾缭绕的针叶林564晨光柔和中冲浪者踏穿越辽阔大海"
    "3旧金门桥橙色暮空下映出雄伟剪影阳洒沙滩成排茅草伞与躺椅上透着悠闲假期气息"
    "晴朗蓝天孤零木屋立黄麦田9茂密冷杉笼罩浓重白里深邃而神秘壮硕狗戴属链项圈"
    "警觉地守围栏后院黑暗披床单幽缓走发楼梯这间多彩复古厅因梵高名画点缀洋溢艺术温馨"
)


def parse_lrc(path):
    out = []
    for raw in open(path, encoding="utf-8-sig", errors="replace"):
        line = raw.strip()
        if not line:
            continue
        stamps = re.findall(r"\[(\d+):(\d+(?:\.\d+)?)\]", line)
        if not stamps:
            continue
        text = re.sub(r"\[(\d+):(\d+(?:\.\d+)?)\]", "", line).strip()
        if not text:
            continue
        for mm, ss in stamps:
            out.append((int(mm) * 60 + float(ss), text))
    out.sort(key=lambda item: item[0])
    return out


def subtitle_tables(lrc_path, wav_info):
    cues, stream, dropped = [], [], {}
    for sec, text in parse_lrc(lrc_path):
        keep = []
        for ch in text:
            if TEXT_ASCII_FIRST <= ord(ch) <= TEXT_ASCII_LAST:
                keep.append(ch)
            else:
                dropped[ch] = dropped.get(ch, 0) + 1
        if not keep:
            continue
        frame = int(round(sec * TEXT_RATE)) // TEXT_SAMPLES_PER_FRAME
        cues.append((frame, len(stream), len(keep)))
        stream.extend(keep)

    if not cues:
        raise ValueError("LRC 里没有可显示的句子（字幕字库只支持 ASCII）")
    if len(cues) > TEXT_CUE_N - 1:
        raise ValueError(f"句子 {len(cues)} 条，超过上限 {TEXT_CUE_N - 1} 条")
    if len(stream) > TEXT_SCH_N:
        raise ValueError(f"字幕字符 {len(stream)} 个，超过上限 {TEXT_SCH_N}")
    if max(c[0] for c in cues) > 0xFFFF:
        raise ValueError("时间戳超出可表示范围（约 18 分钟）")

    if wav_info and wav_info.get("block_align"):
        samples = wav_info["data_size"] // wav_info["block_align"]
        end = max(0, samples - 1) // TEXT_SAMPLES_PER_FRAME
    else:
        end = cues[-1][0] + 300
    durs = []
    for i, (frame, _off, _len) in enumerate(cues):
        nxt = cues[i + 1][0] if i + 1 < len(cues) else end
        durs.append(max(1, min(nxt - frame, 0xFFFF)))

    chars = "".join(stream)
    return cues, chars, durs, dropped


def parse_ad_lines(path):
    texts = []
    for raw in open(path, encoding="utf-8-sig", errors="replace"):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        # 序号只是顺序标记；其后整行都是广告内容，分辨率也属于文案
        body = re.sub(r"^\d{1,3}\s+", "", line)
        if not body:
            continue
        texts.append(body.replace("|", "\n"))
    return texts


def wrap_ad(text):
    lines = []
    for seg in text.split("\n"):
        seg = " ".join(seg.split())
        if not seg:
            continue
        lines.extend(textwrap.wrap(seg, width=TEXT_AD_COLS,
                                   break_long_words=True,
                                   break_on_hyphens=False))
    return lines or [""]


def ad_tables(ad_path):
    texts = parse_ad_lines(ad_path)
    if not texts:
        raise ValueError("advertisement.txt 里没有有效行")
    if len(texts) > TEXT_LN_N // TEXT_AD_LINES:
        raise ValueError(f"广告文案 {len(texts)} 条，最多 "
                         f"{TEXT_LN_N // TEXT_AD_LINES} 条（每条对应一张图）")

    missing = {}
    for idx, text in enumerate(texts, 1):
        for ch in text:
            if ch != "\n" and ch not in TEXT_AD_CHARSET:
                missing.setdefault(ch, idx)
    if missing:
        chars = " ".join(f"'{c}'" for c in list(missing)[:20])
        raise ValueError(f"字库没有这些字符：{chars}（首见于第 "
                         f"{min(missing.values())} 条）")

    entries, stream = [], []
    for idx, text in enumerate(texts):
        lines = wrap_ad(text)
        if len(lines) > TEXT_AD_LINES:
            raise ValueError(f"第 {idx + 1} 条折行后 {len(lines)} 行，"
                             f"最多 {TEXT_AD_LINES} 行")
        for ln in range(TEXT_AD_LINES):
            if ln < len(lines):
                entries.append((len(stream), len(lines[ln])))
                stream.extend(TEXT_AD_CHARSET.index(c) for c in lines[ln])
            else:
                entries.append((len(stream), 0))

    if len(stream) > TEXT_ACH_N:
        raise ValueError(f"广告字符 {len(stream)} 个，超过上限 {TEXT_ACH_N}")
    for off, ln in entries:
        if off > 0x3FF or ln > 0x3F:
            raise ValueError(f"广告行偏移或长度越界（{off}, {ln}）")
    return entries, stream, texts


def build_text_blob(ad_path, lrc_path, wav_info):
    cues, chars, durs, dropped = ([], "", [], {})
    entries, stream, texts = ([], [], [])
    if lrc_path:
        cues, chars, durs, dropped = subtitle_tables(lrc_path, wav_info)
    if ad_path:
        entries, stream, texts = ad_tables(ad_path)

    buf = bytearray(TEXT_OFF_END)
    buf[0:4] = TEXT_MAGIC
    buf[4] = TEXT_VERSION

    for i in range(TEXT_CUE_N):
        pos = TEXT_OFF_CUE + i * 8
        if i < len(cues):
            frame, off, ln = cues[i]
            buf[pos:pos + 8] = struct.pack("<HHHH", frame, off, ln, durs[i])
        else:
            buf[pos:pos + 8] = b"\xff" * 8

    buf[TEXT_OFF_SCH:TEXT_OFF_SCH + TEXT_SCH_N] = b"\x20" * TEXT_SCH_N
    buf[TEXT_OFF_SCH:TEXT_OFF_SCH + len(chars)] = chars.encode("ascii")

    for i in range(TEXT_LN_N):
        val = (entries[i][1] << 10) | entries[i][0] if i < len(entries) else 0
        pos = TEXT_OFF_LN + i * 2
        buf[pos:pos + 2] = struct.pack("<H", val)

    for i, code in enumerate(stream):
        buf[TEXT_OFF_ACH + i] = code

    note = f"字幕 {len(cues)} 句 / 广告 {len(texts)} 条"
    return bytes(buf), note, dropped


# 一键流程

HERE = os.path.dirname(os.path.abspath(__file__))

IMAGE_EXT = {".bmp", ".jpg", ".jpeg", ".png", ".webp", ".gif"}
AUDIO_EXT = {".wav", ".mp3", ".flac", ".m4a", ".aac", ".ogg"}
MAX_IMAGES = 16
TARGET_SIZE = (1280, 720)


def natural(name):
    return [int(t) if t.isdigit() else t.lower()
            for t in re.split(r"(\d+)", name)]


def copy_into(src, dst):
    if os.path.exists(dst):
        os.remove(dst)
    shutil.copy2(src, dst)


def bmp_ok(path):
    """返回 (宽, 高) 表示可直接使用，否则 None。"""
    try:
        with open(path, "rb") as fh:
            head = fh.read(54)
    except OSError:
        return None
    if len(head) < 54 or head[:2] != b"BM":
        return None
    if struct.unpack_from("<I", head, 14)[0] < 40:
        return None
    width = abs(struct.unpack_from("<i", head, 18)[0])
    height = abs(struct.unpack_from("<i", head, 22)[0])
    bits = struct.unpack_from("<H", head, 28)[0]
    compress = struct.unpack_from("<I", head, 30)[0]
    if bits != 24 or compress != 0:
        return None
    if not (1 <= width <= BMP_MAX_DIM and 1 <= height <= BMP_MAX_DIM):
        return None
    return width, height


def list_sources(folder):
    images, audios, text = [], [], None
    ad_path = lrc_path = None
    for name in sorted(os.listdir(folder), key=natural):
        path = os.path.join(folder, name)
        if not os.path.isfile(path):
            continue
        ext = os.path.splitext(name)[1].lower()
        if ext in IMAGE_EXT:
            images.append(path)
        elif ext in AUDIO_EXT:
            audios.append(path)
        elif ext == ".lrc":
            if lrc_path is None:
                lrc_path = path
        elif name.lower() == "advertisement.txt":
            ad_path = path
        elif name.upper() == "TEXT.BIN":
            text = path
    return images, audios, ad_path, lrc_path, text


def prepare_images(images, keep_size, fit):
    out = []
    for idx, src in enumerate(images, 1):
        dst = os.path.join(BUILD, f"{idx:02d}.bmp")
        size = bmp_ok(src)
        small_enough = size and size[0] <= TARGET_SIZE[0] and size[1] <= TARGET_SIZE[1]
        if size and (keep_size or small_enough):
            copy_into(src, dst)
            note = "直接使用"
        else:
            if not HAS_PIL:
                raise SystemExit("[错误] 需要 Pillow 转换图片: pip install Pillow")
            if os.path.exists(dst):
                os.remove(dst)
            if not convert_single_file(src, dst, fit_mode=fit,
                                            keep_size=keep_size,
                                            no_upscale=True):
                raise SystemExit(f"[错误] 转换失败: {src}")
            note = "已转换"
        out.append((dst, os.path.basename(src), note))
    return out


def prepare_audio(audios):
    if not audios:
        print("  音频: 未提供（上板后无声）")
        return None
    if len(audios) > 1:
        print(f"  [!] 发现 {len(audios)} 个音频，只使用 {os.path.basename(audios[0])}")
    src = audios[0]
    dst = os.path.join(BUILD, "music.wav")

    if src.lower().endswith(".wav"):
        try:
            info = parse_wav(src)
        except Exception:
            info = None
        if info and validate_wav(info)[0]:
            copy_into(src, dst)
            print(f"  音频: {os.path.basename(src)}  {info['sample_rate']} Hz / "
                  f"{info['bits']} bit / {info['channels']} ch  直接使用")
            return dst

    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise SystemExit("[错误] 音频需转成 48 kHz PCM，但未找到 ffmpeg\n"
                         "        安装后重试，或先用 48 kHz/16/24 bit WAV")
    print(f"  音频转换: {os.path.basename(src)} -> 48 kHz / 16 bit / 2 ch")
    subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
                    "-i", src, "-vn", "-ac", "2", "-ar", "48000",
                    "-c:a", "pcm_s16le", dst], check=False)
    if not os.path.isfile(dst):
        raise SystemExit("[错误] ffmpeg 转换失败")
    info = parse_wav(dst)
    ok, probs, _ = validate_wav(info)
    if not ok:
        raise SystemExit("[错误] 转换后的音频仍不符合要求: " + "; ".join(probs))
    return dst


def drive_size(letter):
    try:
        total = ctypes.c_ulonglong(0)
        free = ctypes.c_ulonglong(0)
        root = f"{norm_drive(letter)}:\\"
        ctypes.windll.kernel32.GetDiskFreeSpaceExW(
            root, None, ctypes.byref(total), ctypes.byref(free))
        return total.value or 16 * 1024**3
    except Exception:
        return 16 * 1024**3


def preflight(cluster_kb, raw, no_wipe, letter):
    bmps = [os.path.join(BUILD, n) for n in sorted(os.listdir(BUILD))
            if n.lower().endswith(".bmp")]
    wav = os.path.join(BUILD, "music.wav")
    wav = wav if os.path.isfile(wav) else None
    info = parse_wav(wav) if wav else None
    sectors = 0 if raw else max(cluster_kb * 1024 // SECTOR_SIZE, 1)
    overhead = 0
    note = "格式化后估算"
    if not raw:
        bs = read_boot_sector_overhead(norm_drive(letter)) if no_wipe else None
        if bs:
            overhead = bs["overhead"]
            sectors = max(bs["cluster_kb"] * 1024 // SECTOR_SIZE, 1)
            note = f"当前文件系统 {bs['fs']} / {bs['cluster_kb']} KB 簇"
        else:
            overhead = fat32_overhead(drive_size(letter), sectors)[0]
    rows, wav_start, total = plan(bmps, wav, info, overhead, sectors)

    print(f"\n  卡上顺序（BMP 按文件名排序，{note}）:")
    for kind, name, size, start, sec in rows:
        print(f"    {kind:<4}{name:<20}{size / 1048576:>8.2f} MB"
              f"{start:>10,} 扇区起")
    print(f"  预计占用 {total * SECTOR_SIZE / 1048576:.1f} MB"
          f"    WAV 起始 {wav_start:,} 扇区（上限 {SCAN_MAX_SECTOR:,}）")
    if wav_start > SCAN_MAX_SECTOR:
        print("\n[错误] 素材超出扫描范围，请减少图片数量或缩短音频"
              "（默认已缩放到 1280x720，去掉 --keep-size）")
        return False
    return True


def deploy_args(args):
    out = ["-d", BUILD, "-n", "0"]
    if args.raw:
        out.append("--raw")
    if args.no_wipe:
        out.append("--no-wipe")
    if args.cluster_kb != DEFAULT_CLUSTER_KB:
        out += ["--cluster-kb", str(args.cluster_kb)]
    if args.wipe_mb is not None:
        out += ["--wipe-mb", str(args.wipe_mb)]
    if args.no_fix_rtl:
        out.append("--no-fix-rtl")
    if args.dry_run:
        out.append("--dry-run")
    out.append("--yes")
    return out


def needs_admin(args):
    return (not args.dry_run) and (not args.check)


def pause_before_close():
    try:
        input("\n按回车键关闭窗口 ...")
    except (EOFError, KeyboardInterrupt):
        pass


def elevate():
    params = subprocess.list2cmdline(
        [os.path.abspath(sys.argv[0])] + sys.argv[1:] + ["--elevated"])
    rc = ctypes.windll.shell32.ShellExecuteW(None, "runas", sys.executable,
                                             params, HERE, 1)
    if rc <= 32:
        print("[!] 未获得管理员权限，已取消")
        return 2
    print("[信息] 已在新窗口以管理员权限继续")
    return 0


BUILD = os.path.join(HERE, ".build")
DEFAULT_SRC = os.path.join(HERE, "toSD")


def main():
    try:
        sys.stdout.reconfigure(line_buffering=True)
    except Exception:
        pass
    ap = argparse.ArgumentParser(
        description="TF 卡一键部署（转换图片/音频 + 写入 SD 卡）",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="示例:\n"
               "  python deploy_sd.py --list\n"
               "  python deploy_sd.py G: --dry-run\n"
               "  python deploy_sd.py G:\n")
    ap.add_argument("drive", nargs="?", help="SD 卡盘符，如 G: 或 G:\\")
    ap.add_argument("--list", action="store_true", help="列出候选驱动器")
    ap.add_argument("-d", "--dir", default=DEFAULT_SRC, help="素材目录（默认 toSD）")
    ap.add_argument("-n", "--num", type=int, default=0, help="只取前 N 张图（默认全部）")
    ap.add_argument("--keep-size", action="store_true",
                    help="保留图片原始分辨率（默认缩放到 1280x720）")
    ap.add_argument("-f", "--fit", choices=["pad", "stretch", "crop"],
                    default="pad", help="缩放方式：pad 补边 / stretch 拉伸 / crop 裁剪")
    ap.add_argument("--no-text", action="store_true", help="不写入 TEXT.BIN")
    ap.add_argument("--no-wav", action="store_true", help="不写入音频")
    ap.add_argument("--raw", action="store_true", help="裸扇区模式（开机最快）")
    ap.add_argument("--no-wipe", action="store_true", help="跳过扇区擦除")
    ap.add_argument("--wipe-mb", type=int, default=None, help="擦除前多少 MB")
    ap.add_argument("--cluster-kb", type=int, default=DEFAULT_CLUSTER_KB,
                    choices=[4, 8, 16, 32, 64], help="FAT32 簇大小")
    ap.add_argument("--no-fix-rtl", action="store_true", help="不改写 RTL 扫描常量")
    ap.add_argument("--check", action="store_true", help="只读检查卡上布局")
    ap.add_argument("--dry-run", action="store_true", help="只转换和预览，不写卡")
    ap.add_argument("--no-elevate", action="store_true", help="不自动请求管理员权限")
    ap.add_argument("--clean", action="store_true", help="清空 .build 转换缓存")
    ap.add_argument("--elevated", action="store_true", help=argparse.SUPPRESS)
    args = ap.parse_args()

    if args.elevated:
        atexit.register(pause_before_close)

    if args.clean:
        shutil.rmtree(BUILD, ignore_errors=True)
        print("已清空 .build")
        return 0

    common = deploy_args(args)

    if args.list or not args.drive:
        return deploy_main(["--list"])

    if args.check:
        return deploy_main([args.drive, "--check"])

    if not os.path.isdir(args.dir):
        print(f"[错误] 素材目录不存在: {args.dir}")
        return 2
    images, audios, ad_path, lrc_path, text = list_sources(args.dir)
    if args.num > 0:
        images = images[:args.num]
    if not images:
        print(f"[错误] {args.dir} 里没有图片（支持 jpg/png/webp/gif/bmp）")
        return 2
    if len(images) > MAX_IMAGES:
        print(f"[错误] 图片 {len(images)} 张，超过上限 {MAX_IMAGES}")
        return 2

    if needs_admin(args) and IS_WIN and not is_admin():
        if args.no_elevate:
            print("[错误] 该操作需要管理员权限，请用管理员 PowerShell 运行")
            return 2
        return elevate()

    print("素材转换")
    shutil.rmtree(BUILD, ignore_errors=True)
    os.makedirs(BUILD, exist_ok=True)

    prepared = prepare_images(images, args.keep_size, args.fit)
    for dst, src_name, note in prepared:
        size = bmp_ok(dst)
        print(f"  {os.path.basename(dst)} <- {src_name}  "
              f"{size[0]}x{size[1]}  {os.path.getsize(dst) / 1048576:.2f} MB  {note}")

    if args.no_wav:
        print("  音频: 已跳过")
    else:
        prepare_audio(audios)

    if args.no_text:
        print("  文本: 已跳过（无字幕/广告）")
    elif ad_path or lrc_path:
        if not ad_path:
            print("  [!] 未找到 advertisement.txt，只生成字幕")
        if not lrc_path:
            print("  [!] 未找到 .lrc，只生成广告文字")
        wav_path = os.path.join(BUILD, "music.wav")
        wav_info = None
        if os.path.isfile(wav_path):
            try:
                wav_info = parse_wav(wav_path)
            except Exception:
                wav_info = None
        try:
            blob, note, dropped = build_text_blob(ad_path, lrc_path, wav_info)
        except ValueError as exc:
            print(f"[错误] 无法生成 TEXT.BIN：{exc}")
            return 2
        with open(os.path.join(BUILD, "TEXT.BIN"), "wb") as fh:
            fh.write(blob)
        sources = " + ".join(os.path.basename(p) for p in (ad_path, lrc_path) if p)
        print(f"  TEXT.BIN <- {sources}  {len(blob)} 字节  {note}")
        if dropped:
            sample = " ".join(repr(c) for c in list(dropped)[:8])
            print(f"  [!] 字幕丢弃 {sum(dropped.values())} 个非 ASCII 字符：{sample}")
    elif text:
        shutil.copy2(text, os.path.join(BUILD, "TEXT.BIN"))
        print(f"  TEXT.BIN <- {os.path.basename(text)}")
    else:
        print("  文本: 未提供 advertisement.txt / .lrc / TEXT.BIN"
              "（无字幕与广告，其余功能正常）")

    if not preflight(args.cluster_kb, args.raw, args.no_wipe, args.drive):
        return 2

    print("\n部署")
    return deploy_main([args.drive] + common)


if __name__ == "__main__":
    sys.exit(main())
