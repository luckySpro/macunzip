#!/bin/sh
# 生成 Xcode 工程。需要先 brew install xcodegen libarchive。
set -e
cd "$(dirname "$0")/.."
xcodegen generate
