#!/usr/bin/env bash
# 一键检查与构建脚本
# 用法：
#   bash scripts/run.sh --check-only   仅做无需设备和 DevEco 的检查
#   bash scripts/run.sh                检查后构建（需要 DevEco 命令行工具 devecocli）
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

CHECK_ONLY=0
case "${1:-}" in
  --check-only) CHECK_ONLY=1 ;;
  -h | --help)
    sed -n '2,5p' "$0"
    exit 0
    ;;
  "") ;;
  *)
    echo "未知参数：$1（可用：--check-only、--help）" >&2
    exit 2
    ;;
esac

step() { printf '\n==> %s\n' "$1"; }
fail() {
  printf '错误：%s\n' "$1" >&2
  exit 1
}

step "1/3 检查前置依赖"
command -v node > /dev/null 2>&1 || fail "未找到 Node.js（建议 18 及以上），请先安装：https://nodejs.org"
echo "Node.js $(node -v)"

step "2/3 资源与格式检查（无需设备）"
node scripts/check_strings.mjs
if git rev-parse --git-dir > /dev/null 2>&1; then
  node scripts/check_format.mjs --base HEAD
else
  echo "当前目录不是 git 仓库，已跳过格式检查"
fi

if [ "$CHECK_ONLY" -eq 1 ]; then
  echo
  echo "已完成检查，按 --check-only 跳过构建。"
  exit 0
fi

step "3/3 构建"
if ! command -v devecocli > /dev/null 2>&1; then
  cat << 'EOF'
未找到 DevEco 命令行工具 devecocli，已跳过自动构建。
请改用 DevEco Studio 手动构建运行：
  1. 用 DevEco Studio（5.0 及以上）打开本目录，等待 oh_modules 同步完成
  2. File → Project Structure → Signing Configs → 勾选 Automatically generate signature
  3. 连接真机或启动模拟器，点击 Run
EOF
  exit 0
fi
devecocli build
echo
echo "构建完成。"
