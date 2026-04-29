#!/usr/bin/env bash
set -euo pipefail

if ! command -v apt-get >/dev/null 2>&1; then
  echo "This helper supports Debian/Ubuntu apt systems only." >&2
  exit 1
fi

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  echo "Run with sudo/root: sudo $0" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

apt-get update

required_packages=(
  autoconf \
  automake \
  bash \
  bison \
  build-essential \
  ca-certificates \
  cmake \
  curl \
  file \
  flex \
  git \
  libasound2-dev \
  libtool \
  meson \
  nasm \
  ninja-build \
  pkg-config \
  texinfo \
  wget \
  yasm \
  zlib1g-dev
)

optional_packages=(
  frei0r-plugins-dev \
  gh \
  libaom-dev \
  libass-dev \
  libdav1d-dev \
  libfontconfig-dev \
  libfreetype-dev \
  libfribidi-dev \
  libgme-dev \
  libgmp-dev \
  libmp3lame-dev \
  libopencore-amrnb-dev \
  libopencore-amrwb-dev \
  libopenjp2-7-dev \
  libopus-dev \
  librtmp-dev \
  librubberband-dev \
  libsoxr-dev \
  libspeex-dev \
  libsrt-openssl-dev \
  libssl-dev \
  libtheora-dev \
  libvidstab-dev \
  libvo-amrwbenc-dev \
  libvorbis-dev \
  libvpx-dev \
  libvmaf-dev \
  libwebp-dev \
  libx264-dev \
  libx265-dev \
  libxml2-dev \
  libxvidcore-dev \
  libzimg-dev \
  libzvbi-dev
)

apt-get install -y --no-install-recommends "${required_packages[@]}"

for package in "${optional_packages[@]}"; do
  if apt-cache show "$package" >/dev/null 2>&1; then
    apt-get install -y --no-install-recommends "$package"
  else
    echo "Skipping unavailable optional package: $package" >&2
  fi
done

apt-get clean
rm -rf /var/lib/apt/lists/*
