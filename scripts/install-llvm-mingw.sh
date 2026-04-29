#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${1:-$PWD/work/toolchains/llvm-mingw}"
LLVM_MINGW_TAG="${LLVM_MINGW_TAG:-latest}"

if [ -x "$INSTALL_DIR/bin/x86_64-w64-mingw32-clang" ] &&
  [ -x "$INSTALL_DIR/bin/aarch64-w64-mingw32-clang" ]; then
  echo "llvm-mingw already installed in $INSTALL_DIR"
  exit 0
fi

mkdir -p "$(dirname "$INSTALL_DIR")"
rm -rf "$INSTALL_DIR"

if [ "$LLVM_MINGW_TAG" = "latest" ]; then
  api_url="https://api.github.com/repos/mstorsjo/llvm-mingw/releases/latest"
else
  api_url="https://api.github.com/repos/mstorsjo/llvm-mingw/releases/tags/$LLVM_MINGW_TAG"
fi

archive_url="$(
  curl -fsSL "$api_url" |
    sed -n 's/.*"browser_download_url": "\(.*ucrt-ubuntu-[0-9.]*-x86_64\.tar\.xz\)".*/\1/p' |
    head -n 1
)"

if [ -z "$archive_url" ]; then
  echo "Unable to find llvm-mingw ubuntu x86_64 archive from $api_url" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

echo "Downloading $archive_url"
curl -fL "$archive_url" -o "$tmp_dir/llvm-mingw.tar.xz"
tar -C "$tmp_dir" -xf "$tmp_dir/llvm-mingw.tar.xz"
mv "$tmp_dir"/llvm-mingw-* "$INSTALL_DIR"

echo "Installed llvm-mingw in $INSTALL_DIR"
