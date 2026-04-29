#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${WORK_DIR:-$ROOT_DIR/work}"
SRC_DIR="${SRC_DIR:-$WORK_DIR/ffmpeg}"
BUILD_DIR="${BUILD_DIR:-$WORK_DIR/build}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
FFMPEG_REPO="${FFMPEG_REPO:-https://git.ffmpeg.org/ffmpeg.git}"
FFMPEG_REF="${FFMPEG_REF:-n8.1}"
SRT_REPO="${SRT_REPO:-https://github.com/Haivision/srt.git}"
SRT_REF="${SRT_REF:-v1.5.5}"
ALSA_REPO="${ALSA_REPO:-https://github.com/alsa-project/alsa-lib.git}"
ALSA_REF="${ALSA_REF:-v1.2.14}"
X265_REPO="${X265_REPO:-https://bitbucket.org/multicoreware/x265_git.git}"
X265_REF="${X265_REF:-4.1}"
TARGET="${TARGET:-linux-amd64}"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 2)}"
CONFIG_FILE="${CONFIG_FILE:-$ROOT_DIR/config/ffmpeg.configure}"
PKG_CONFIG_PATH_EXTRA="${PKG_CONFIG_PATH_EXTRA:-}"
EXTRA_FFMPEG_FLAGS="${EXTRA_FFMPEG_FLAGS:-}"
AUTO_SKIP_MISSING_DEPS="${AUTO_SKIP_MISSING_DEPS:-1}"
REQUIRED_CONFIG_FLAGS=(
  --enable-alsa
  --enable-libsrt
  --enable-libx264
  --enable-libx265
)

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

is_required_config_flag() {
  local flag="$1"
  local required

  for required in "${REQUIRED_CONFIG_FLAGS[@]}"; do
    if [ "$flag" = "$required" ]; then
      return 0
    fi
  done

  return 1
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
    if [ "$AUTO_SKIP_MISSING_DEPS" = "1" ] && [ -n "$pkg" ] && ! is_required_config_flag "$flag" && ! static_pkg_usable "$pkg"; then
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

sync_srt() {
  local srt_src_dir="$WORK_DIR/srt"

  mkdir -p "$WORK_DIR"
  if [ ! -d "$srt_src_dir/.git" ]; then
    log "Cloning SRT from $SRT_REPO"
    git clone "$SRT_REPO" "$srt_src_dir"
  fi

  log "Fetching SRT updates"
  git -C "$srt_src_dir" fetch --tags --prune origin

  log "Checking out SRT ref: $SRT_REF"
  git -C "$srt_src_dir" checkout --force "$SRT_REF"
}

sync_alsa() {
  local alsa_src_dir="$WORK_DIR/alsa-lib"

  mkdir -p "$WORK_DIR"
  if [ ! -d "$alsa_src_dir/.git" ]; then
    log "Cloning ALSA from $ALSA_REPO"
    git clone "$ALSA_REPO" "$alsa_src_dir"
  fi

  log "Fetching ALSA updates"
  git -C "$alsa_src_dir" fetch --tags --prune origin

  log "Checking out ALSA ref: $ALSA_REF"
  git -C "$alsa_src_dir" checkout --force "$ALSA_REF"
}

build_alsa() {
  local alsa_src_dir="$WORK_DIR/alsa-lib"
  local alsa_build_dir="$WORK_DIR/build-alsa"

  sync_alsa

  rm -rf "$alsa_build_dir"
  mkdir -p "$alsa_build_dir" "$OUTPUT_DIR"

  log "Preparing static ALSA"
  (
    cd "$alsa_src_dir"
    if [ ! -x ./configure ]; then
      autoreconf -fi
    fi
  )

  log "Configuring static ALSA"
  (
    cd "$alsa_build_dir"
    "$alsa_src_dir/configure" \
      --prefix="$OUTPUT_DIR" \
      --disable-shared \
      --enable-static
  )

  log "Compiling static ALSA with $JOBS jobs"
  make -C "$alsa_build_dir" -j "$JOBS"

  log "Installing static ALSA into $OUTPUT_DIR"
  make -C "$alsa_build_dir" install
}

sync_x265() {
  local x265_src_dir="$WORK_DIR/x265"

  mkdir -p "$WORK_DIR"
  if [ ! -d "$x265_src_dir/.git" ]; then
    log "Cloning x265 from $X265_REPO"
    git clone "$X265_REPO" "$x265_src_dir"
  fi

  log "Fetching x265 updates"
  git -C "$x265_src_dir" fetch --tags --prune origin

  log "Checking out x265 ref: $X265_REF"
  git -C "$x265_src_dir" checkout --force "$X265_REF"
}

patch_x265_pkg_config() {
  local pc_file="$OUTPUT_DIR/lib/pkgconfig/x265.pc"
  local private_libs="-lstdc++ -lpthread -ldl"

  [ -f "$pc_file" ] || return 0

  log "Patching pkg-config metadata: $pc_file"
  if grep -q '^Libs\.private:' "$pc_file"; then
    perl -0pi -e 's/^Libs\.private:\s*.*$/Libs.private: -lstdc++ -lpthread -ldl/m' "$pc_file"
  else
    printf '\nLibs.private: %s\n' "$private_libs" >>"$pc_file"
  fi
}

build_x265() {
  local x265_src_dir="$WORK_DIR/x265"
  local x265_build_dir="$WORK_DIR/build-x265"

  sync_x265

  rm -rf "$x265_build_dir"
  mkdir -p "$x265_build_dir" "$OUTPUT_DIR"

  log "Configuring static x265"
  cmake -S "$x265_src_dir/source" -B "$x265_build_dir" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$OUTPUT_DIR" \
    -DENABLE_SHARED=OFF \
    -DENABLE_CLI=OFF \
    -DENABLE_PIC=ON \
    -DENABLE_LIBNUMA=OFF \
    -DHIGH_BIT_DEPTH=OFF \
    -DMAIN12=OFF

  log "Compiling static x265 with $JOBS jobs"
  cmake --build "$x265_build_dir" --parallel "$JOBS"

  log "Installing static x265 into $OUTPUT_DIR"
  cmake --install "$x265_build_dir"

  patch_x265_pkg_config
}

build_srt() {
  local srt_src_dir="$WORK_DIR/srt"
  local srt_build_dir="$WORK_DIR/build-srt"

  sync_srt

  rm -rf "$srt_build_dir"
  mkdir -p "$srt_build_dir" "$OUTPUT_DIR"

  log "Configuring static SRT"
  cmake -S "$srt_src_dir" -B "$srt_build_dir" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$OUTPUT_DIR" \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -DENABLE_SHARED=OFF \
    -DENABLE_STATIC=ON \
    -DENABLE_APPS=OFF \
    -DENABLE_TESTING=OFF \
    -DENABLE_UNITTESTS=OFF \
    -DENABLE_C_DEPS=ON \
    -DUSE_ENCLIB=openssl

  log "Compiling static SRT with $JOBS jobs"
  cmake --build "$srt_build_dir" --parallel "$JOBS"

  log "Installing static SRT into $OUTPUT_DIR"
  cmake --install "$srt_build_dir"

  patch_srt_pkg_config
}

patch_srt_pkg_config() {
  local pc_file
  local private_libs="-lstdc++ -lssl -lcrypto -latomic -lpthread -lm -ldl"

  for pc_file in "$OUTPUT_DIR/lib/pkgconfig/srt.pc" "$OUTPUT_DIR/lib/pkgconfig/haisrt.pc"; do
    [ -f "$pc_file" ] || continue

    log "Patching pkg-config metadata: $pc_file"
    if grep -q '^Libs\.private:' "$pc_file"; then
      perl -0pi -e 's/^Libs\.private:\s*.*$/Libs.private: -lstdc++ -lssl -lcrypto -latomic -lpthread -lm -ldl/m' "$pc_file"
    else
      printf '\nLibs.private: %s\n' "$private_libs" >>"$pc_file"
    fi
  done
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

  build_alsa
  build_srt
  build_x265

  export PKG_CONFIG_PATH="$OUTPUT_DIR/lib/pkgconfig:$OUTPUT_DIR/lib64/pkgconfig:$PKG_CONFIG_PATH_EXTRA${PKG_CONFIG_PATH_EXTRA:+:}${PKG_CONFIG_PATH:-}"

  local -a config_flags
  local -a target_flags
  local extra_ldflags="-L$OUTPUT_DIR/lib -static ${EXTRA_LDFLAGS:-}"
  local extra_libs="-lpthread -lm -ldl -lstdc++ -lssl -lcrypto -latomic ${EXTRA_LIBS:-}"

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
    echo "srt_ref=$SRT_REF"
    echo "srt_commit=$(git -C "$WORK_DIR/srt" rev-parse HEAD)"
    echo "srt_describe=$(git -C "$WORK_DIR/srt" describe --tags --always --dirty 2>/dev/null || true)"
    echo "alsa_ref=$ALSA_REF"
    echo "alsa_commit=$(git -C "$WORK_DIR/alsa-lib" rev-parse HEAD)"
    echo "alsa_describe=$(git -C "$WORK_DIR/alsa-lib" describe --tags --always --dirty 2>/dev/null || true)"
    echo "x265_ref=$X265_REF"
    echo "x265_commit=$(git -C "$WORK_DIR/x265" rev-parse HEAD)"
    echo "x265_describe=$(git -C "$WORK_DIR/x265" describe --tags --always --dirty 2>/dev/null || true)"
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

  log "Verifying required FFmpeg features"
  "$OUTPUT_DIR/ffmpeg" -hide_banner -devices | grep -Eq '^[[:space:]]*D[ E.]*[[:space:]]+alsa([[:space:]]|$)' || {
    echo "Missing required ALSA input format; expected '-f alsa' to be available." >&2
    exit 1
  }
  "$OUTPUT_DIR/ffmpeg" -hide_banner -protocols | grep -Eq '^[[:space:]]*srt$' || {
    echo "Missing required SRT protocol; expected 'srt://' to be available." >&2
    exit 1
  }
  "$OUTPUT_DIR/ffmpeg" -hide_banner -encoders | grep -Eq '^[[:space:]]*V.*libx264[[:space:]]' || {
    echo "Missing required libx264 encoder." >&2
    exit 1
  }
  "$OUTPUT_DIR/ffmpeg" -hide_banner -encoders | grep -Eq '^[[:space:]]*V.*libx265[[:space:]]' || {
    echo "Missing required libx265 encoder." >&2
    exit 1
  }
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
