#!/bin/sh
# 下载官方 UnRAR 源码并编译为通用（arm64 + x86_64）静态库 Vendor/unrar/libunrar.a。
# UnRAR 许可允许在免费或商业软件中用于解压 RAR，但禁止用来重建 RAR 压缩算法。
set -e
VERSION="${UNRAR_VERSION:-7.1.8}"
cd "$(dirname "$0")/.."
DEST=Vendor/unrar
if [ -f "$DEST/libunrar.a" ]; then exit 0; fi

mkdir -p Vendor
curl -fsSL "https://www.rarlab.com/rar/unrarsrc-$VERSION.tar.gz" -o Vendor/unrarsrc.tar.gz
rm -rf "$DEST"
tar -xzf Vendor/unrarsrc.tar.gz -C Vendor
rm Vendor/unrarsrc.tar.gz

cd "$DEST"
make clean >/dev/null 2>&1 || true
make lib CXX="clang++ -arch arm64 -arch x86_64 -mmacosx-version-min=13.0" \
    CXXFLAGS="-O2 -std=c++11 -fPIC -DRARDLL -Wno-logical-op-parentheses -Wno-switch -Wno-dangling-else" \
    STRIP=true AR=ar
# 部分版本的 makefile 只产出动态库，这里统一打包为静态库
rm -f libunrar.a
ar rcs libunrar.a *.o
rm -f libunrar.so libunrar.dylib
