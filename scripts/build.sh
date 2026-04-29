#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${WORK_DIR:-$ROOT_DIR/work}"
SRC_DIR="${SRC_DIR:-$WORK_DIR/ffmpeg}"
BUILD_DIR="${BUILD_DIR:-$WORK_DIR/build}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
FFMPEG_REPO="${FFMPEG_REPO:-https://git.ffmpeg.org/ffmpeg.git}"
FFMPEG_REF="${FFMPEG_REF:-n8.1}"
TARGET="${TARGET:-linux-amd64}"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 2)}"
CONFIG_FILE="${CONFIG_FILE:-$ROOT_DIR/config/ffmpeg.configure}"
PKG_CONFIG_PATH_EXTRA="${PKG_CONFIG_PATH_EXTRA:-}"
EXTRA_FFMPEG_FLAGS="${EXTRA_FFMPEG_FLAGS:-}"
AUTO_SKIP_MISSING_DEPS="${AUTO_SKIP_MISSING_DEPS:-1}"

log() {
  printf '[ffmpeg-static] %s\n' "$*" >&2
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

pkg_for_flag() {
  case "$1" in
    --enable-alsa) echo "alsa" ;;
    --enable-fontconfig) echo "fontconfig" ;;
    --enable-frei0r) echo "frei0r" ;;
    --enable-gmp) echo "gmp" ;;
    --enable-openssl) echo "openssl" ;;
    --enable-libaom) echo "aom" ;;
    --enable-libass) echo "libass" ;;
    --enable-libdav1d) echo "dav1d" ;;
    --enable-libfribidi) echo "fribidi" ;;
    --enable-libfreetype) echo "freetype2" ;;
    --enable-libgme) echo "libgme" ;;
    --enable-libopencore-amrnb) echo "opencore-amrnb" ;;
    --enable-libopencore-amrwb) echo "opencore-amrwb" ;;
    --enable-libopenjpeg) echo "libopenjp2" ;;
    --enable-libopus) echo "opus" ;;
    --enable-librtmp) echo "librtmp" ;;
    --enable-librubberband) echo "rubberband" ;;
    --enable-libsoxr) echo "soxr" ;;
    --enable-libspeex) echo "speex" ;;
    --enable-libsrt) echo "srt" ;;
    --enable-libtheora) echo "theora" ;;
    --enable-libvidstab) echo "vidstab" ;;
    --enable-libvo-amrwbenc) echo "vo-amrwbenc" ;;
    --enable-libvorbis) echo "vorbis" ;;
    --enable-libvmaf) echo "libvmaf" ;;
    --enable-libvpx) echo "vpx" ;;
    --enable-libwebp) echo "libwebp" ;;
    --enable-libx264) echo "x264" ;;
    --enable-libx265) echo "x265" ;;
    --enable-libxml2) echo "libxml-2.0" ;;
    --enable-libzimg) echo "zimg" ;;
    --enable-libzvbi) echo "zvbi-0.2" ;;
  esac
}

static_pkg_usable() {
  local pkg="$1"
  local tmp_dir
  tmp_dir="$(mktemp -d)"

  if ! pkg-config --exists --static "$pkg"; then
    rm -rf "$tmp_dir"
    return 1
  fi

  if ! printf 'int main(void) { return 0; }\n' |
    "${CC:-cc}" -x c - -o "$tmp_dir/probe" -static \
      $(pkg-config --cflags --libs --static "$pkg") >/dev/null 2>&1; then
    rm -rf "$tmp_dir"
    return 1
  fi

  rm -rf "$tmp_dir"
  return 0
}

read_config_flags() {
  local flags=()
  local flag pkg

  while IFS= read -r flag; do
    flag="${flag%%#*}"
    flag="${flag#"${flag%%[![:space:]]*}"}"
    flag="${flag%"${flag##*[![:space:]]}"}"
    [ -n "$flag" ] || continue

    pkg="$(pkg_for_flag "$flag" || true)"
    if [ "$AUTO_SKIP_MISSING_DEPS" = "1" ] && [ -n "$pkg" ] && ! static_pkg_usable "$pkg"; then
      log "Skipping $flag because static pkg-config package '$pkg' was not usable"
      continue
    fi

    flags+=("$flag")
  done <"$CONFIG_FILE"

  printf '%s\n' "${flags[@]}"
}

sync_ffmpeg() {
  mkdir -p "$WORK_DIR"
  if [ ! -d "$SRC_DIR/.git" ]; then
    log "Cloning FFmpeg from $FFMPEG_REPO"
    git clone "$FFMPEG_REPO" "$SRC_DIR"
  fi

  log "Fetching FFmpeg updates"
  git -C "$SRC_DIR" fetch --tags --prune origin

  log "Checking out FFmpeg ref: $FFMPEG_REF"
  git -C "$SRC_DIR" checkout --force "$FFMPEG_REF"
  if [ "$FFMPEG_REF" = "master" ] || [ "$FFMPEG_REF" = "main" ]; then
    git -C "$SRC_DIR" reset --hard "origin/$FFMPEG_REF"
  fi
}

target_configure_flags() {
  case "$TARGET" in
    linux-amd64|linux-arm64)
      return 0
      ;;
    *)
      echo "Unsupported TARGET=$TARGET" >&2
      exit 1
      ;;
  esac
}

build_ffmpeg() {
  mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"
  rm -rf "$BUILD_DIR"
  mkdir -p "$BUILD_DIR"

  export PKG_CONFIG_PATH="$PKG_CONFIG_PATH_EXTRA${PKG_CONFIG_PATH_EXTRA:+:}${PKG_CONFIG_PATH:-}"

  local -a config_flags
  local -a target_flags
  local extra_ldflags="-L$OUTPUT_DIR/lib -static ${EXTRA_LDFLAGS:-}"
  local extra_libs="-lpthread -lm -ldl ${EXTRA_LIBS:-}"

  mapfile -t config_flags < <(read_config_flags)
  mapfile -t target_flags < <(target_configure_flags)

  log "Configuring FFmpeg"
  (
    cd "$BUILD_DIR"
    "$SRC_DIR/configure" \
      --prefix="$OUTPUT_DIR" \
      --pkg-config-flags="--static" \
      --extra-cflags="-I$OUTPUT_DIR/include ${EXTRA_CFLAGS:-}" \
      --extra-ldflags="$extra_ldflags" \
      --extra-libs="$extra_libs" \
      "${target_flags[@]}" \
      "${config_flags[@]}" \
      $EXTRA_FFMPEG_FLAGS
  )

  log "Compiling FFmpeg with $JOBS jobs"
  make -C "$BUILD_DIR" -j "$JOBS"

  log "Installing into $OUTPUT_DIR"
  make -C "$BUILD_DIR" install
}

write_build_info() {
  {
    echo "ffmpeg_ref=$FFMPEG_REF"
    echo "ffmpeg_commit=$(git -C "$SRC_DIR" rev-parse HEAD)"
    echo "ffmpeg_describe=$(git -C "$SRC_DIR" describe --tags --always --dirty 2>/dev/null || true)"
    echo "target=$TARGET"
    echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "configure_file=$CONFIG_FILE"
    echo "auto_skip_missing_deps=$AUTO_SKIP_MISSING_DEPS"
    echo "extra_ffmpeg_flags=$EXTRA_FFMPEG_FLAGS"
  } >"$OUTPUT_DIR/build-info.txt"
}

verify_binary() {
  if [ ! -x "$OUTPUT_DIR/bin/ffmpeg" ]; then
    echo "Build finished but $OUTPUT_DIR/bin/ffmpeg was not found." >&2
    exit 1
  fi

  cp -f "$OUTPUT_DIR/bin/ffmpeg" "$OUTPUT_DIR/ffmpeg"
  cp -f "$OUTPUT_DIR/bin/ffprobe" "$OUTPUT_DIR/ffprobe"

  log "Built binary:"
  "$OUTPUT_DIR/ffmpeg" -hide_banner -version | sed -n '1,4p'

  require_cmd readelf

  for binary in "$OUTPUT_DIR/ffmpeg" "$OUTPUT_DIR/ffprobe"; do
    log "Verifying fully static ELF: $binary"
    if readelf -l "$binary" | grep -Eq 'INTERP|Requesting program interpreter'; then
      echo "$binary has a dynamic loader/interpreter; expected a fully static binary." >&2
      exit 1
    fi

    if readelf -d "$binary" 2>/dev/null | grep -q 'NEEDED'; then
      echo "$binary has dynamic NEEDED libraries; expected a fully static binary." >&2
      exit 1
    fi

    if command -v ldd >/dev/null 2>&1; then
      local ldd_output
      ldd_output="$(ldd "$binary" 2>&1 || true)"
      grep -q 'not a dynamic executable' <<<"$ldd_output" || {
        echo "$binary is not reported as fully static by ldd." >&2
        printf '%s\n' "$ldd_output" >&2
        exit 1
      }
    fi
  done
}

main() {
  require_cmd git
  require_cmd make
  require_cmd pkg-config
  require_cmd file

  sync_ffmpeg
  build_ffmpeg
  write_build_info
  verify_binary

  log "Done. Binaries are in $OUTPUT_DIR"
}

main "$@"
