#!/usr/bin/env bash
#
# claude-code-deepseek-setup
# 一条指令把一台新 Mac 配成：Node.js + Claude Code CLI + DeepSeek API (+ Obsidian Claudian)
#
# 用法：
#   bash <(curl -fsSL https://raw.githubusercontent.com/<user>/<repo>/main/install.sh)
#
# 幂等：重复执行不会破坏已有配置。改动前一律先备份。
# 安全：脚本内不含任何密钥；API key 只在运行时由你输入，写入 ~/.claude/settings.json（权限 600）。
#
set -euo pipefail

# ---------------------------------------------------------------- 常量
NVM_VERSION="${NVM_VERSION:-v0.40.1}"
NODE_VERSION="${NODE_VERSION:-22}"
DEEPSEEK_HOST="api.deepseek.com"
DEEPSEEK_BASE_URL="https://${DEEPSEEK_HOST}/anthropic"
DEEPSEEK_MODEL="${DEEPSEEK_MODEL:-deepseek-flash}"
DEEPSEEK_PRO_MODEL="${DEEPSEEK_PRO_MODEL:-deepseek-v4-pro}"

CLAUDE_DIR="$HOME/.claude"
SETTINGS_JSON="$CLAUDE_DIR/settings.json"
CLAUDE_JSON="$HOME/.claude.json"
ZSHRC="$HOME/.zshrc"
STAMP="$(date +%Y%m%d%H%M%S)"

# ---------------------------------------------------------------- 输出
if [ -t 1 ]; then
  C_DIM=$'\033[2m'; C_CYAN=$'\033[36m'; C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_OFF=$'\033[0m'
else
  C_DIM=''; C_CYAN=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_OFF=''
fi

step() { printf '\n%s▸ %s%s\n' "$C_CYAN" "$*" "$C_OFF"; }
ok()   { printf '%s  ✓ %s%s\n' "$C_GREEN" "$*" "$C_OFF"; }
warn() { printf '%s  ! %s%s\n' "$C_YELLOW" "$*" "$C_OFF"; }
die()  { printf '\n%s✗ %s%s\n' "$C_RED" "$*" "$C_OFF" >&2; exit 1; }

# ---------------------------------------------------------------- 交互
# ★ 关键：curl | bash 场景下 stdin 被脚本自身占用，必须显式走 /dev/tty，
#   否则 read 读到的是脚本内容本身，会静默拿到空值。
ask() {
  local prompt="$1" __var="$2" silent="${3:-}"
  if [ -t 0 ]; then
    if [ "$silent" = "silent" ]; then
      read -r -s -p "$prompt" "$__var"; printf '\n'
    else
      read -r -p "$prompt" "$__var"
    fi
  else
    if [ "$silent" = "silent" ]; then
      read -r -s -p "$prompt" "$__var" < /dev/tty; printf '\n'
    else
      read -r -p "$prompt" "$__var" < /dev/tty
    fi
  fi
}

# ---------------------------------------------------------------- 0. 环境检查
[ "$(uname -s)" = "Darwin" ] || die "这个脚本目前只支持 macOS。"
command -v curl >/dev/null 2>&1 || die "找不到 curl。"
command -v python3 >/dev/null 2>&1 || die "找不到 python3（macOS 自带，若被删请先装 Xcode 命令行工具：xcode-select --install）"

printf '%s\n' "${C_DIM}claude-code-deepseek-setup${C_OFF}"
printf '%s\n' "${C_DIM}目标：Node.js + Claude Code CLI + DeepSeek API${C_OFF}"

# ---------------------------------------------------------------- 1. nvm + Node
step "1/6  安装 Node.js"

export NVM_DIR="$HOME/.nvm"

if [ ! -s "$NVM_DIR/nvm.sh" ]; then
  printf '  正在安装 nvm %s ...\n' "$NVM_VERSION"
  curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash
else
  ok "nvm 已存在，跳过"
fi

# ★ nvm.sh 内部引用了未定义变量，必须先关掉 -u 再 source，否则脚本会当场退出
set +u
# shellcheck disable=SC1091
\. "$NVM_DIR/nvm.sh"
set -u

if ! nvm ls "$NODE_VERSION" >/dev/null 2>&1; then
  printf '  正在安装 Node %s ...\n' "$NODE_VERSION"
  nvm install "$NODE_VERSION"
else
  ok "Node $NODE_VERSION 已存在，跳过"
fi

set +u; nvm alias default "$NODE_VERSION" >/dev/null; nvm use default >/dev/null; set -u

NODE_BIN="$(command -v node)"
NODE_DIR="$(dirname "$NODE_BIN")"
ok "node $("$NODE_BIN" -v)   npm $(npm -v)"
ok "bin 目录：$NODE_DIR"

# 把 nvm 初始化写进 .zshrc（幂等，用哨兵注释包裹便于卸载）
if ! grep -q 'claude-code-deepseek-setup' "$ZSHRC" 2>/dev/null; then
  touch "$ZSHRC"
  cat >>"$ZSHRC" <<'ZSH'

# >>> nvm (added by claude-code-deepseek-setup) >>>
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
# <<< nvm (added by claude-code-deepseek-setup) <<<
ZSH
  ok "已把 nvm 初始化写入 ~/.zshrc"
else
  ok "~/.zshrc 里已有 nvm 初始化，跳过"
fi

# ---------------------------------------------------------------- 2. Claude Code CLI
step "2/6  安装 Claude Code CLI"

if ! command -v claude >/dev/null 2>&1; then
  printf '  正在全局安装 @anthropic-ai/claude-code ...\n'
  npm install -g @anthropic-ai/claude-code
  hash -r 2>/dev/null || true
else
  ok "claude 已存在，跳过安装"
fi

command -v claude >/dev/null 2>&1 || die "安装后仍找不到 claude 命令，请重开终端再跑一次本脚本。"
CLAUDE_BIN="$(command -v claude)"
ok "claude $("$CLAUDE_BIN" --version 2>/dev/null | head -1)"
ok "绝对路径：$CLAUDE_BIN   ${C_DIM}(Claudian 要填这个)${C_OFF}"

# ---------------------------------------------------------------- 3. DeepSeek API key
step "3/6  DeepSeek API key"

DS_KEY="${DEEPSEEK_API_KEY:-}"

if [ -z "$DS_KEY" ]; then
  printf '  到 %shttps://platform.deepseek.com/api_keys%s 创建一个 key（sk- 开头）\n' "$C_CYAN" "$C_OFF"
  printf '  %s注意：DeepSeek 是预付费，余额为 0 会直接报错。%s\n' "$C_DIM" "$C_OFF"
  printf '\n'
  ask "  粘贴你的 DeepSeek API key（输入时不显示）: " DS_KEY silent
fi

case "$DS_KEY" in
  sk-*) ;;
  *) die "key 格式不对，DeepSeek 的 key 应该以 sk- 开头。" ;;
esac
[ "${#DS_KEY}" -ge 20 ] || die "key 太短，看起来不完整。"

# ---------------------------------------------------------------- 4. 验证 key
step "4/6  验证 key 与余额"

BALANCE_JSON="$(curl -s --noproxy '*' --max-time 20 \
  -H "Authorization: Bearer $DS_KEY" \
  "https://${DEEPSEEK_HOST}/user/balance" || true)"

[ -n "$BALANCE_JSON" ] || die "连不上 api.deepseek.com。检查网络，或你所在的网络需要代理时请在代理软件里给 api.deepseek.com 加直连规则。"

BALANCE_JSON="$BALANCE_JSON" python3 - <<'PY' || die "key 验证失败（见上方信息）。"
import json, os, sys
raw = os.environ.get("BALANCE_JSON", "")
try:
    d = json.loads(raw)
except Exception:
    print("  返回内容不是预期 JSON：", raw[:200]); sys.exit(1)
if not d.get("is_available"):
    print("  接口说这个 key 不可用：", raw[:200]); sys.exit(1)
infos = d.get("balance_infos") or []
if infos:
    for b in infos:
        print("  ✓ 余额 %s%s" % (b.get("total_balance", "?"), b.get("currency", "")))
else:
    print("  ✓ key 可用")
PY

# ---------------------------------------------------------------- 5. 写配置
step "5/6  写入 Claude Code 配置"

mkdir -p "$CLAUDE_DIR"

# 5a. ~/.claude/settings.json 的 env 字段
#     官方支持：settings.json 里的 env 会覆盖 shell 里 export 的同名变量。
#     写在这里 = 终端直接跑 claude 也走 DeepSeek，不必每次 export。
export DS_KEY DEEPSEEK_BASE_URL DEEPSEEK_MODEL DEEPSEEK_PRO_MODEL DEEPSEEK_HOST
export SETTINGS_JSON STAMP

python3 - <<'PY'
import json, os, pathlib, shutil, sys

p = pathlib.Path(os.environ["SETTINGS_JSON"])
p.parent.mkdir(parents=True, exist_ok=True)

data = {}
if p.exists():
    raw = p.read_text(encoding="utf-8").strip()
    if raw:
        try:
            data = json.loads(raw)
        except Exception:
            bak = p.with_name(p.name + ".bak-" + os.environ["STAMP"])
            shutil.copy2(p, bak)
            print("  ! 原 settings.json 不是合法 JSON，已备份到 %s" % bak.name)
            data = {}

data.setdefault("env", {}).update({
    "ANTHROPIC_BASE_URL":            os.environ["DEEPSEEK_BASE_URL"],
    "ANTHROPIC_API_KEY":             os.environ["DS_KEY"],
    "ANTHROPIC_MODEL":               os.environ["DEEPSEEK_MODEL"],
    "ANTHROPIC_DEFAULT_OPUS_MODEL":  os.environ["DEEPSEEK_PRO_MODEL"],
    "ANTHROPIC_DEFAULT_SONNET_MODEL": os.environ["DEEPSEEK_MODEL"],
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": os.environ["DEEPSEEK_MODEL"],
    "NO_PROXY":  os.environ["DEEPSEEK_HOST"],
    "no_proxy":  os.environ["DEEPSEEK_HOST"],
})

p.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
os.chmod(p, 0o600)   # 里面有明文 key，必须 600
print("  ✓ 已写入 %s（权限 600）" % p)
PY

# 5b. ~/.claude.json —— 跳过首次运行的登录/引导
#     没有 hasCompletedOnboarding 时，claude 第一次启动会尝试连官方 Anthropic 做登录校验。
export CLAUDE_JSON
python3 - <<'PY'
import json, os, pathlib, shutil

p = pathlib.Path(os.environ["CLAUDE_JSON"])
data = {}
if p.exists():
    raw = p.read_text(encoding="utf-8").strip()
    if raw:
        try:
            data = json.loads(raw)
        except Exception:
            bak = p.with_name(p.name + ".bak-" + os.environ["STAMP"])
            shutil.copy2(p, bak)
            print("  ! 原 .claude.json 不是合法 JSON，已备份到 %s" % bak.name)
            data = {}

data["hasCompletedOnboarding"] = True
data.setdefault("theme", "dark")
data.setdefault("hasTrustDialogAccepted", True)

p.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("  ✓ 已写入 %s（跳过首次引导）" % p)
PY

# ---------------------------------------------------------------- 6. 端到端验证
step "6/6  端到端验证（真的调一次 DeepSeek）"

printf '  正在请求 ...\n'
REPLY="$(claude -p "只回复两个字：通了" 2>&1 || true)"

# 过滤掉已知的无害警告
FILTERED="$(printf '%s' "$REPLY" | grep -v 'unrecognized_model' || true)"

if printf '%s' "$FILTERED" | grep -q '通了'; then
  ok "DeepSeek 通了 —— 模型回复正常"
elif [ -n "$FILTERED" ]; then
  warn "拿到了返回，但内容不是预期的："
  printf '%s\n' "$FILTERED" | sed 's/^/      /'
  warn "如果里面是认证/余额类错误，检查 key 与余额。"
else
  die "没有任何返回。多数是网络问题：确认 NO_PROXY 生效、代理没拦 api.deepseek.com。"
fi

# ---------------------------------------------------------------- 收尾
cat <<EOF

${C_GREEN}命令行部分全部完成。${C_OFF}

${C_DIM}────────────────────────────────────────────────${C_OFF}
下一步：Obsidian 里的 Claudian（需手动点两下，GUI 装插件无法纯命令行完成）

1) 打开 Obsidian → 设置 → 第三方插件 → 浏览 → 搜「Claudian」→ 安装 → 启用
   或者直接跑这条命令跳到插件页：
      open "obsidian://show-plugin?id=claudian"

2) 设置 → Claudian → Provider 选 ${C_CYAN}Claude${C_OFF}，然后填三项：

     Claude CLI path   ${C_CYAN}${CLAUDE_BIN}${C_OFF}
     Custom models     ${C_CYAN}${DEEPSEEK_PRO_MODEL}${C_OFF} 和 ${C_CYAN}${DEEPSEEK_MODEL}${C_OFF}（各占一行）
     Default model     ${C_CYAN}${DEEPSEEK_MODEL}${C_OFF}

   ${C_DIM}环境变量不用在这里填 —— 第 5 步已经写进 ~/.claude/settings.json，
   Claudian 启动的 CLI 会自己读到。${C_OFF}

3) 打开 Claudian 侧边栏，模型菜单选 ${C_CYAN}${DEEPSEEK_MODEL}${C_OFF}，发一句话测试。

${C_DIM}────────────────────────────────────────────────${C_OFF}
常用命令
  查看当前 provider：   claude  然后输入  /status
  改模型：             编辑 ~/.claude/settings.json 的 env.ANTHROPIC_MODEL
  重跑本脚本：          安全的，幂等，不会破坏已有配置

EOF
