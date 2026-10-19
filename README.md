# 数字广告牌系统

基于安路 EG4S20BG256（EG4HX4S20）的 HDMI 数字广告牌工程。TF 卡读取 BMP 图片与 WAV 音频，
经 SDRAM 缓存后由 HDMI 1.4b 输出 720p60 画面，同时支持字幕、广告文字、Logo、音频频谱、
转场效果、触摸屏与串口控制。

## 目录结构

| 路径 | 内容 |
| --- | --- |
| `src/td_project/` | Tang Dynasty 工程，打开 `HDMI1.4b_Transmitter_v1.0.al` |
| `src/td_project/best_result/` | 已验证的位流 |
| `src/user_source/hdl_source/` | RTL 源码，顶层为 `top_tf_hdmi_audio.v` |
| `src/user_source/constraints_source/` | 引脚约束与时钟约束 |
| `tools/deploy_sd.py` | TF 卡一键部署脚本 |
| `tools/toSD/` | 待部署素材 |

## 环境

- Windows 10/11，Python 3.8 及以上
- `pip install Pillow`
- 可选 `ffmpeg`：音频不是 48 kHz PCM 时用于自动转换

`python` 不可用时，下文命令中的 `python` 换成 `py -3`。

## 部署 TF 卡

1. 把图片、音乐、`advertisement.txt`、`.lrc` 放进 `tools/toSD/`。
2. 插入 TF 卡并确认盘符：

   ```
   python tools/deploy_sd.py --list
   ```

3. 预览（不写卡）：

   ```
   python tools/deploy_sd.py G: --dry-run
   ```

4. 正式写入（会请求管理员权限）：

   ```
   python tools/deploy_sd.py G:
   ```

脚本依次完成：收集素材、转换格式、生成 `TEXT.BIN`、计算卡上布局、擦除格式化、
按序写入、读回校验、回写 `top_tf_hdmi_audio.v` 中的扫描常量。
常量变化后需用 TD 重新综合并烧录。

### 素材要求

| 类型 | 支持格式 | 说明 |
| --- | --- | --- |
| 图片 | jpg / jpeg / png / webp / gif / bmp | 大于 1280x720 的缩到 1280x720（补黑边不裁剪），更小的保持原尺寸 |
| 音频 | wav / mp3 / flac / m4a / aac / ogg | 只使用一个，需为 48 kHz、16 或 24 bit、PCM |
| 广告 | `advertisement.txt` | 每条一行：`序号 广告文案`，`\|` 表示换行 |
| 字幕 | `.lrc` | 只使用一个，与音频配套，仅显示 ASCII 字符 |

广告与字幕由脚本打包成卡上的 `TEXT.BIN`，无需手工生成。两者都可省略，
也可只放其中一个；都没有时只是不显示字幕和广告，其它功能正常。

`advertisement.txt` 示例：

```
01 1280x720|登山客在静谧湖边驻足|凝望云雾缭绕的针叶林
02 2560x1440|晨光柔和中|冲浪者踏浪穿越辽阔大海
```

序号只标记顺序，其后整行都是上屏内容，分辨率也属于文案、会显示在第一行，
所以不要把它当成单独的前缀去掉。序号可以省略，直接写文案。
文案里用到的字符必须已在广告字库中（见
`src/user_source/hdl_source/ad_text_rom.v`），脚本会逐条校验，缺字时报错并指出是第几条。

播放顺序按文件名自然排序（`2.jpg` 在 `10.jpg` 之前），最多 16 张。

### 参数

| 参数 | 作用 |
| --- | --- |
| `-d DIR` | 素材目录，默认 `tools/toSD` |
| `-n N` | 只取前 N 张图 |
| `--keep-size` | 保留图片原始分辨率 |
| `-f pad\|stretch\|crop` | 缩放方式，默认 `pad` |
| `--no-wav` | 不写入音频 |
| `--no-text` | 不生成也不写入 TEXT.BIN |
| `--raw` | 裸扇区模式，开机最快，卡在电脑上不可读 |
| `--no-wipe` | 跳过扇区擦除 |
| `--cluster-kb N` | FAT32 簇大小，默认 64 |
| `--check` | 只读检查卡上现有布局 |
| `--clean` | 删除 `.build` 转换缓存 |
| `--no-elevate` | 不自动请求管理员权限 |

### 注意

- 部署会清空整张卡，务必先用 `--dry-run` 核对文件列表。
- 卡容量大于 32 GB 时 Windows 无法格式化为 FAT32，请改用 `--raw`。
- 卡上残留的旧图会被 FPGA 当作有效素材，默认擦除即为此设计。

## 串口命令

串口固定 115200、8N1，空闲高电平。命令以 `\r\n` 结尾，长度为 4 个字符，
数字参数补零到 4 位（如 `B050`）。

**仅模式 8 响应串口命令**：`sw[2:0] = 111`，数码管显示 `8`，其余模式下所有命令返回
`ERR MODE`。

### 命令表

| 命令 | 参数 | 说明 |
| --- | --- | --- |
| `PING` | 无 | 连通性测试，返回 `PONG` |
| `STAT` | 无 | 返回当前状态行 |
| `VERS` | 无 | 返回固件版本，如 `OK VERS=1003` |
| `RSET` | 无 | 全部参数恢复默认值 |
| `RPT0` / `RPT1` | 0/1 | 关闭 / 开启 100 ms 周期状态上报，开启后每帧以 `#` 开头 |
| `Bnnn` | 000-100 | 亮度 |
| `Cnnn` | 050-200 | 对比度 |
| `Snnn` | 000-200 | 饱和度 |
| `Vnnn` | 000-100 | 音量 |
| `Tnnn` | 000-005 | 转场类型 |
| `TEnn` | 00/01 | 转场开关 |
| `NEXT` | 无 | 下一张 |
| `PREV` | 无 | 上一张 |
| `TRNn` | 0/1 | 轮播开关 |
| `PAUS` | 无 | 暂停音频 |
| `RUNN` | 无 | 继续播放音频 |
| `SUBn` | 0-3 | 字幕开关与模式 |
| `SBGn` | 0-2 | 字幕背景：0 无 / 1 半透 / 2 实底 |
| `MONn` | 0/1 | 字幕监视信息开关 |
| `SSZn` | 0/1 | 字幕字号 |
| `LOGn` | 0-2 | Logo 显示方式 |
| `SPEn` | 0/1 | 频谱开关 |
| `SPSn` | 1/2 | 频谱方向 |

### 返回格式

| 情况 | 返回 |
| --- | --- |
| 查询成功 | `PONG` / `OK VERS=xxxx` / `P=n ...` |
| 设置成功 | `OK B=080`，回显命令名与 3 位生效值 |
| 执行成功 | `OK NEXT` 等，仅回显命令名 |
| 出错 | `ERR CMD` 未知命令 / `ERR FMT` 格式或长度错误 / `ERR LONG` 超长 / `ERR TIME` 帧超时 / `ERR MODE` 非模式 8 / `ERR IMPL` 未实现 |

未实现命令为 `SYNC`、`IMG`、`SSP`，返回 `ERR IMPL`。

### STAT 状态行

```
P=008 BRIT=050 CON=100 SATS=100 VOLU=050 TRAN=002 TE=001 IMG=001/009 AUTO=000 SUB=001 ST=OK
```

所有数值固定 3 位十进制。

| 字段 | 含义 |
| --- | --- |
| `P` | 当前模式号 1-8 |
| `BRIT` / `CON` / `SATS` / `VOLU` | 亮度 / 对比度 / 饱和度 / 音量 |
| `TRAN` / `TE` | 转场类型 / 转场开关 |
| `IMG=i/t` | 当前图号 / 卡上总张数 |
| `AUTO` | 轮播开关 |
| `SUB` | 字幕模式 |
| `ST` | 卡状态：`OK` / `SCAN` / `NOIMG` / `NOSD` |

### 示例

```
PING
STAT
B080
T003
NEXT
RPT1
```

串口助手直接发送上面的文本即可，脚本或程序发送时需追加 `\r\n`。
