#!/bin/sh
# 准备依赖并生成 Xcode 工程。需要先 brew install xcodegen libarchive。
set -e
cd "$(dirname "$0")/.."
./scripts/fetch-unrar.sh
xcodegen generate
