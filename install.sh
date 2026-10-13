#!/usr/bin/env bash
#
# claude-code-deepseek-setup —— 引导脚本（bootstrap）
#
# 只干一件事：给「还没有 Node 的 Mac」装好 nvm + Node.js，
# 然后把剩下的活全部交给 npm 包：
#
#     npx -y claude-code-deepseek-setup
#
# 为什么只干这一件事：真正的安装逻辑只有一份（在 npm 包里）。
# 脚本和包各维护一套实现，早晚会漂移。
#
# 用法：
#   curl -fsSL https://raw.githubusercontent.com/ithuangyang-lab/claude-code-deepseek-setup/main/install.sh | bash
#
# 已经有 Node（v18+）的话别用这个，直接跑：
#   npx -y claude-code-deepseek-setup
#
# 幂等：nvm / Node / .zshrc 哨兵块已存在就跳过。
# 安全：本脚本不含任何密钥；API key 由 npm 包在运行时问你。
#
set -euo pipefail

# ---------------------------------------------------------------- 常量
NVM_VERSION="${NVM_VERSION:-v0.40.1}"
NODE_VERSION="${NODE_VERSION:-22}"
PKG="${PKG:-claude-code-deepseek-setup}"
PKG_FALLBACK="${PKG_FALLBACK:-github:ithuangyang-lab/claude-code-deepseek-setup}"

NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
ZSHRC="$HOME/.zshrc"

# ---------------------------------------------------------------- 输出
if [ -t 1 ]; then
  C_DIM=$'\033[2m'; C_CYAN=$'\033[36m'; C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_OFF=$'\033[0m'
else
  C_DIM=''; C_CYAN=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_OFF=''
fi
step() { printf '\n%s▸ %s%s\n' "$C_CYAN" "$1" "$C_OFF"; }
ok()   { printf '%s  ✓ %s%s\n' "$C_GREEN" "$1" "$C_OFF"; }
warn() { printf '%s  ! %s%s\n' "$C_YELLOW" "$1" "$C_OFF"; }
die()  { printf '\n%s✗ %s%s\n' "$C_RED" "$1" "$C_OFF" >&2; exit 1; }

# ---------------------------------------------------------------- 0. 环境检查
step "0/2  环境检查"
[ "$(uname -s)" = "Darwin" ] || die "这个脚本目前只支持 macOS。"
command -v curl >/dev/null 2>&1 || die "找不到 curl，无法继续。"
ok "macOS $(sw_vers -productVersion)"

# ---------------------------------------------------------------- 1. nvm + Node
step "1/2  Node.js 运行时"

if [ -s "$NVM_DIR/nvm.sh" ]; then
  ok "nvm 已存在，跳过安装"
else
  echo "  正在安装 nvm ${NVM_VERSION} ..."
  curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash
fi

# ★ nvm.sh 内部引用了未定义变量，必须先关掉 -u 再 source，否则 set -euo pipefail 下直接退出
set +u
# shellcheck disable=SC1091
. "$NVM_DIR/nvm.sh"
set -u

if command -v node >/dev/null 2>&1; then
  ok "Node 已存在：$(node -v)，跳过安装"
else
  echo "  正在安装 Node ${NODE_VERSION} ..."
  nvm install "$NODE_VERSION"
  nvm alias default "$NODE_VERSION" >/dev/null
fi
ok "Node $(node -v) · npm $(npm -v)"

# 把 nvm 初始化写进 .zshrc（哨兵块，幂等）
MARK_BEGIN="# >>> nvm (added by claude-code-deepseek-setup) >>>"
MARK_END="# <<< nvm (added by claude-code-deepseek-setup) <<<"

if [ -f "$ZSHRC" ] && grep -qF "$MARK_BEGIN" "$ZSHRC"; then
  ok "~/.zshrc 里的 nvm 初始化已存在，跳过"
else
  {
    printf '\n%s\n' "$MARK_BEGIN"
    printf 'export NVM_DIR="%s"\n' "$NVM_DIR"
    printf '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"\n'
    printf '[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"\n'
    printf '%s\n' "$MARK_END"
  } >> "$ZSHRC"
  ok "已把 nvm 初始化写进 ~/.zshrc"
fi

# ---------------------------------------------------------------- 2. 交给 npm 包
step "2/2  运行安装程序"
printf '%s  %s\n\n' "$C_DIM" "npx -y ${PKG}" >&2

# 先走 npm registry；拉不到（包还没发布 / 网络问题）就回退到 GitHub 源
if npx -y "$PKG" "$@"; then
  exit 0
fi

warn "从 npm registry 拉包失败，改用 GitHub 源重试 ..."
printf '%s  %s%s\n\n' "$C_DIM" "npx -y ${PKG_FALLBACK}" "$C_OFF" >&2
npx -y "$PKG_FALLBACK" "$@"
