# ffmpeg-static

用于同步并编译最新 FFmpeg 静态版本的项目。默认目标是 Linux x86_64 静态 `ffmpeg` / `ffprobe`，并补充常用能力：

- AAC: FFmpeg 原生 AAC 编码/解码
- H.264: `libx264`
- H.265/HEVC: `libx265`
- RTMP: FFmpeg 原生 RTMP 协议，可选 `librtmp`
- SRT: `libsrt`
- ALSA: `libasound`
- 常用音视频库: `libaom`、`libdav1d`、`libvpx`、`libopus`、`libvorbis`、`libmp3lame`、`libass`、`libfreetype`、`libwebp`、`libzimg`、`libvmaf` 等

截至 2026-04-30，FFmpeg 官方最新稳定版是 `8.1`。本项目默认构建 `n8.1` tag，也可以切换为 `master` 跟随开发分支。

## 快速开始

本机 Debian/Ubuntu 构建：

```bash
sudo ./scripts/install-build-deps.sh
./scripts/build.sh
```

构建产物会输出到：

```text
dist/ffmpeg
dist/ffprobe
dist/bin/
dist/include/
dist/lib/
dist/build-info.txt
```

## 同步最新 FFmpeg

默认构建最新稳定版：

```bash
./scripts/build.sh
```

构建 FFmpeg master 分支：

```bash
FFMPEG_REF=master ./scripts/build.sh
```

构建指定 tag/commit：

```bash
FFMPEG_REF=n8.1 ./scripts/build.sh
FFMPEG_REF=6a1b2c3 ./scripts/build.sh
```

SRT 默认从源码静态编译 `v1.5.5`，确保 `srt://` 在全静态构建中可用：

```bash
SRT_REF=v1.5.5 ./scripts/build.sh
```

## 常用参数

```bash
# 输出目录，默认 ./dist
OUTPUT_DIR=/opt/ffmpeg-static ./scripts/build.sh

# 编译线程数，默认 nproc
JOBS=8 ./scripts/build.sh

# 源码和构建缓存目录，默认 ./work
WORK_DIR=/data/ffmpeg-work ./scripts/build.sh

# 额外 FFmpeg configure 参数
EXTRA_FFMPEG_FLAGS="--enable-nonfree --enable-libfdk-aac" ./scripts/build.sh
```

> 注意：如果启用 `--enable-nonfree` 或 `libfdk-aac`，产物的分发许可会变化。默认配置不启用 nonfree。

## 参考配置

核心配置保存在 [config/ffmpeg.configure](config/ffmpeg.configure)，尽量贴近下面这类静态构建：

```text
--enable-gpl --enable-version3 --enable-static --disable-debug --disable-ffplay
--enable-libx264 --enable-libx265 --enable-libsrt --enable-libvpx
--enable-libaom --enable-libdav1d --enable-libopus --enable-libvorbis
--enable-libmp3lame --enable-libass --enable-libfreetype --enable-fontconfig
--enable-openssl
```

有些库在不同发行版上静态链接支持不一致。默认情况下，脚本会通过 `pkg-config` 自动跳过当前环境缺少的可选库，尽量保证能出包。若要严格要求完整配置，可使用：

```bash
AUTO_SKIP_MISSING_DEPS=0 ./scripts/build.sh
```

## 验证

```bash
./dist/ffmpeg -version
./dist/ffmpeg -protocols | grep -E 'rtmp|srt'
./dist/ffmpeg -encoders | grep -E 'libx264|libx265|aac'
```

## GitHub Actions Release

工作流文件在 [.github/workflows/release.yml](.github/workflows/release.yml)。

- 自动发布：push `v*` tag 时自动构建并上传 Release 资产
- 手动发布：Actions 页面运行 `Build FFmpeg Static Releases`
- 构建环境：不使用 Docker，全部使用 Ubuntu 24.04 runner
- 产物目标：`linux-amd64`、`linux-arm64`

Linux 目标使用完整配置，包含 ALSA，不启用 `h264_vaapi` / `hevc_vaapi`。

Release 包会包含完整安装目录：全静态 `ffmpeg` / `ffprobe`、FFmpeg headers、`libav*.a` 静态库和 pkg-config 文件。构建脚本会用 `readelf` / `ldd` 校验 `ffmpeg` 和 `ffprobe`，如果发现动态解释器或动态 `NEEDED` 依赖会直接失败。

`alsa`、`libsrt`、`libx264` 和 `libx265` 是必选能力，不会被自动跳过。构建结束会检查 `-f alsa`、`srt://`、`libx264`、`libx265` 是否可用，并确认 `h264_vaapi` / `hevc_vaapi` 未启用。
