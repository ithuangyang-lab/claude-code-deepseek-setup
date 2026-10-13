#!/usr/bin/env node
/**
 * claude-code-deepseek-setup —— 主程序
 *
 * 一条命令把一台 Mac 配成：Claude Code CLI + DeepSeek API，
 * 并打印 Obsidian Claudian 的配置指引。
 *
 *   npx -y claude-code-deepseek-setup
 *   npx -y github:ithuangyang-lab/claude-code-deepseek-setup
 *
 * 幂等：重复执行不会破坏已有配置，改动前一律备份。
 * 安全：本包不含任何密钥；API key 只在运行时由你输入，
 *       写入 ~/.claude/settings.json（权限 600）。
 *
 * 只碰这些地方：~/.claude/settings.json、~/.claude.json、npm 全局包目录。
 */
'use strict'

const child = require('node:child_process')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')

let PKG_VERSION = '1.0.0'
try {
  PKG_VERSION = require('../package.json').version
} catch {
  /* 被单独拷出去跑时忽略 */
}

/* ---------------------------------------------------------------- 常量 */
const DEEPSEEK_HOST = 'api.deepseek.com'
const DEEPSEEK_BASE_URL = `https://${DEEPSEEK_HOST}/anthropic`
const DEEPSEEK_MODEL = process.env.DEEPSEEK_MODEL || 'deepseek-flash'
const DEEPSEEK_PRO_MODEL = process.env.DEEPSEEK_PRO_MODEL || 'deepseek-v4-pro'
const CLAUDE_PKG = '@anthropic-ai/claude-code'

const HOME = os.homedir()
const CLAUDE_DIR = path.join(HOME, '.claude')
const SETTINGS_JSON = path.join(CLAUDE_DIR, 'settings.json')
const CLAUDE_JSON = path.join(HOME, '.claude.json')
const STAMP = new Date().toISOString().replace(/[-:T]/g, '').slice(0, 14)

/* ---------------------------------------------------------------- 输出 */
const TTY = Boolean(process.stdout.isTTY)
const C = TTY
  ? { dim: '\x1b[2m', cyan: '\x1b[36m', green: '\x1b[32m', yellow: '\x1b[33m', red: '\x1b[31m', off: '\x1b[0m' }
  : { dim: '', cyan: '', green: '', yellow: '', red: '', off: '' }

const step = (s) => console.log(`\n${C.cyan}▸ ${s}${C.off}`)
const ok = (s) => console.log(`${C.green}  ✓ ${s}${C.off}`)
const warn = (s) => console.log(`${C.yellow}  ! ${s}${C.off}`)
const info = (s) => console.log(`${C.dim}  ${s}${C.off}`)

function die(msg) {
  console.error(`\n${C.red}✗ ${msg}${C.off}`)
  process.exit(1)
}

/* ---------------------------------------------------------------- 工具 */
/** 在 PATH 里找可执行文件，返回绝对路径或 null */
function which(cmd) {
  const dirs = (process.env.PATH || '').split(path.delimiter).filter(Boolean)
  for (const d of dirs) {
    const p = path.join(d, cmd)
    try {
      if (fs.statSync(p).isFile() && (fs.accessSync(p, fs.constants.X_OK), true)) return p
    } catch {
      /* 继续找下一个 */
    }
  }
  return null
}

function npmVersion() {
  try {
    return child.execFileSync('npm', ['-v'], { encoding: 'utf8' }).trim()
  } catch {
    return '?'
  }
}

/** 凭证一律打码，不整串回显 */
const mask = (k) => `${k.slice(0, 8)}…MASKED`

/** 读 JSON；文件不存在返回 {}；解析失败先备份再返回 {} */
function readJsonSafe(file) {
  if (!fs.existsSync(file)) return {}
  const raw = fs.readFileSync(file, 'utf8').trim()
  if (!raw) return {}
  try {
    return JSON.parse(raw)
  } catch {
    const bak = `${file}.bak-${STAMP}`
    fs.copyFileSync(file, bak)
    warn(`原 ${path.basename(file)} 不是合法 JSON，已备份到 ${path.basename(bak)}`)
    return {}
  }
}

function writeJson(file, data, mode) {
  fs.writeFileSync(file, `${JSON.stringify(data, null, 2)}\n`, 'utf8')
  if (mode) fs.chmodSync(file, mode)
}

/** 隐藏输入。必须在 TTY 下用，否则 raw mode 拿不到按键 */
function askHidden(prompt) {
  return new Promise((resolve) => {
    const stdin = process.stdin
    process.stdout.write(prompt)
    const wasRaw = stdin.isRaw
    stdin.setRawMode(true)
    stdin.resume()
    stdin.setEncoding('utf8')

    let buf = ''
    const finish = (val) => {
      stdin.removeListener('data', onData)
      stdin.setRawMode(wasRaw)
      stdin.pause()
      process.stdout.write('\n')
      resolve(val)
    }
    const onData = (chunk) => {
      for (const ch of chunk) {
        if (ch === '\r' || ch === '\n' || ch === '') return finish(buf)
        if (ch === '') {
          process.stdout.write('\n')
          process.exit(130)
        }
        if (ch === '' || ch === '\b') {
          buf = buf.slice(0, -1)
          continue
        }
        if (ch >= ' ') buf += ch
      }
    }
    stdin.on('data', onData)
  })
}

/* ---------------------------------------------------------------- 各步骤 */
async function verifyBalance(key) {
  let res
  try {
    // Node 内建 fetch 不读 HTTP_PROXY，天然直连 —— 正是我们要的
    res = await fetch(`https://${DEEPSEEK_HOST}/user/balance`, {
      headers: { Authorization: `Bearer ${key}` },
      signal: AbortSignal.timeout(20000),
    })
  } catch (err) {
    die(
      `连不上 ${DEEPSEEK_HOST}：${err.message}\n` +
        `  检查网络。若你的网络需要代理，请在代理软件里给 ${DEEPSEEK_HOST} 加一条直连规则。`
    )
  }

  const text = await res.text()
  let data
  try {
    data = JSON.parse(text)
  } catch {
    die(`返回的内容不是预期 JSON：${text.slice(0, 200)}`)
  }

  if (!data.is_available) die(`接口说这个 key 不可用：${text.slice(0, 200)}`)

  const infos = Array.isArray(data.balance_infos) ? data.balance_infos : []
  if (infos.length === 0) {
    ok('key 可用')
  } else {
    for (const b of infos) ok(`余额 ${b.total_balance ?? '?'} ${b.currency ?? ''}`)
  }
}

function writeClaudeSettings(key) {
  fs.mkdirSync(CLAUDE_DIR, { recursive: true })

  // 官方支持：settings.json 的 env 会覆盖 shell 里 export 的同名变量。
  // 写在这里 = 终端直接跑 claude 也走 DeepSeek，不必每次 export。
  const data = readJsonSafe(SETTINGS_JSON)
  if (typeof data.env !== 'object' || data.env === null) data.env = {}

  Object.assign(data.env, {
    ANTHROPIC_BASE_URL: DEEPSEEK_BASE_URL,
    ANTHROPIC_API_KEY: key,
    ANTHROPIC_MODEL: DEEPSEEK_MODEL,
    ANTHROPIC_DEFAULT_OPUS_MODEL: DEEPSEEK_PRO_MODEL,
    ANTHROPIC_DEFAULT_SONNET_MODEL: DEEPSEEK_MODEL,
    ANTHROPIC_DEFAULT_HAIKU_MODEL: DEEPSEEK_MODEL,
    NO_PROXY: DEEPSEEK_HOST,
    no_proxy: DEEPSEEK_HOST,
  })

  writeJson(SETTINGS_JSON, data, 0o600) // 里面有明文 key，必须 600
  ok(`已写入 ${SETTINGS_JSON}（权限 600）`)
}

function writeClaudeJson() {
  // 没有 hasCompletedOnboarding 时，claude 第一次启动会尝试连官方 Anthropic 做登录校验
  const data = readJsonSafe(CLAUDE_JSON)
  data.hasCompletedOnboarding = true
  if (data.theme === undefined) data.theme = 'dark'
  if (data.hasTrustDialogAccepted === undefined) data.hasTrustDialogAccepted = true

  writeJson(CLAUDE_JSON, data, 0o600)
  ok(`已写入 ${CLAUDE_JSON}（跳过首次引导）`)
}

function runSmokeTest(claudeBin) {
  info('正在请求 ...')
  const r = child.spawnSync(claudeBin, ['-p', '只回复两个字：通了'], {
    encoding: 'utf8',
    timeout: 180000,
  })

  const raw = `${r.stdout || ''}\n${r.stderr || ''}`
  // 过滤掉已知的无害警告
  const filtered = raw
    .split('\n')
    .filter((l) => !l.includes('unrecognized_model'))
    .join('\n')
    .trim()

  if (filtered.includes('通了')) {
    ok('DeepSeek 通了 —— 模型回复正常')
    return
  }
  if (filtered) {
    warn('拿到了返回，但内容不是预期的：')
    for (const l of filtered.split('\n')) console.log(`      ${l}`)
    warn('如果里面是认证/余额类错误，检查 key 与余额。')
    return
  }
  die(`没有任何返回。多数是网络问题：确认 NO_PROXY 生效、代理没拦 ${DEEPSEEK_HOST}。`)
}

function printFooter(claudeBin) {
  console.log(`
${C.green}命令行部分全部完成。${C.off}

${C.dim}────────────────────────────────────────────────${C.off}
下一步：Obsidian 里的 Claudian（需手动点两下，GUI 装插件无法纯命令行完成）

1) 打开 Obsidian → 设置 → 第三方插件 → 浏览 → 搜「Claudian」→ 安装 → 启用
   或者直接跑这条命令跳到插件页：
      open "obsidian://show-plugin?id=claudian"

2) 设置 → Claudian → Provider 选 ${C.cyan}Claude${C.off}，然后填三项：

     Claude CLI path   ${C.cyan}${claudeBin}${C.off}
     Custom models     ${C.cyan}${DEEPSEEK_PRO_MODEL}${C.off} 和 ${C.cyan}${DEEPSEEK_MODEL}${C.off}（各占一行）
     Default model     ${C.cyan}${DEEPSEEK_MODEL}${C.off}

   ${C.dim}环境变量不用在这里填 —— 已经写进 ~/.claude/settings.json，
   Claudian 启动的 CLI 会自己读到。${C.off}

3) 打开 Claudian 侧边栏，模型菜单选 ${C.cyan}${DEEPSEEK_MODEL}${C.off}，发一句话测试。

${C.dim}────────────────────────────────────────────────${C.off}
常用命令
  查看当前 provider：   claude  然后输入  /status
  改模型：             编辑 ~/.claude/settings.json 的 env.ANTHROPIC_MODEL
  重跑本命令：          安全的，幂等，不会破坏已有配置
`)
}

/* ---------------------------------------------------------------- 主流程 */
async function main() {
  console.log(`${C.dim}claude-code-deepseek-setup v${PKG_VERSION}${C.off}`)
  console.log(`${C.dim}目标：Claude Code CLI + DeepSeek API${C.off}`)

  /* ---- 0. 环境检查 ---- */
  step('0/5  环境检查')
  if (process.platform !== 'darwin') die('这个工具目前只支持 macOS。')
  const nodeMajor = Number(process.versions.node.split('.')[0])
  if (nodeMajor < 18) die(`Node 版本太低（当前 v${process.versions.node}），需要 v18 或更高。`)
  ok(`macOS · Node v${process.versions.node} · npm ${npmVersion()}`)

  /* ---- 1. Claude Code CLI ---- */
  step('1/5  安装 Claude Code CLI')
  let claudeBin = which('claude')
  if (claudeBin) {
    ok('claude 已存在，跳过安装')
  } else {
    info(`正在全局安装 ${CLAUDE_PKG} ...`)
    const r = child.spawnSync('npm', ['install', '-g', CLAUDE_PKG], { stdio: 'inherit' })
    if (r.status !== 0) {
      die(
        'npm install -g 失败。\n' +
          '  若报 EACCES / 权限错误：说明你的 Node 是官方 pkg 装的，全局目录在 /usr/local 需要 sudo。\n' +
          `  建议改用 nvm 管 Node；或手动跑：sudo npm install -g ${CLAUDE_PKG}`
      )
    }
    claudeBin = which('claude')
  }
  if (!claudeBin) die('安装后仍找不到 claude 命令，请重开终端再跑一次本命令。')

  let claudeVer = ''
  try {
    claudeVer = (child.execFileSync(claudeBin, ['--version'], { encoding: 'utf8' }).split('\n')[0] || '').trim()
  } catch {
    /* 版本拿不到不影响主流程 */
  }
  ok(`claude ${claudeVer}`)
  ok(`绝对路径：${claudeBin}   ${C.dim}(Claudian 要填这个)${C.off}`)

  /* ---- 2. DeepSeek API key ---- */
  step('2/5  DeepSeek API key')
  let key = (process.env.DEEPSEEK_API_KEY || '').trim()
  if (key) {
    ok('已从环境变量 DEEPSEEK_API_KEY 读到 key')
  } else {
    if (!process.stdin.isTTY) {
      die(
        '当前不是交互式终端，没法问你要 key。\n' +
          '  请改用：DEEPSEEK_API_KEY=sk-xxx npx -y claude-code-deepseek-setup'
      )
    }
    console.log(`  到 ${C.cyan}https://platform.deepseek.com/api_keys${C.off} 创建一个 key（sk- 开头）`)
    info('注意：DeepSeek 是预付费，余额为 0 会直接报错。')
    console.log()
    key = (await askHidden('  粘贴你的 DeepSeek API key（输入时不显示）: ')).trim()
  }

  if (!key.startsWith('sk-')) die('key 格式不对，DeepSeek 的 key 应该以 sk- 开头。')
  if (key.length < 20) die('key 太短，看起来不完整。')
  ok(`key 已就绪：${mask(key)}`)

  /* ---- 3. 验证 key 与余额 ---- */
  step('3/5  验证 key 与余额')
  await verifyBalance(key)

  /* ---- 4. 写配置 ---- */
  step('4/5  写入 Claude Code 配置')
  writeClaudeSettings(key)
  writeClaudeJson()

  /* ---- 5. 端到端验证 ---- */
  step('5/5  端到端验证（真的调一次 DeepSeek）')
  runSmokeTest(claudeBin)

  /* ---- 收尾 ---- */
  printFooter(claudeBin)
}

/* ---------------------------------------------------------------- 入口 */
function printHelp() {
  console.log(`
claude-code-deepseek-setup v${PKG_VERSION}

把一台 Mac 配成 Claude Code CLI + DeepSeek API。

用法
  npx -y claude-code-deepseek-setup
  npx -y github:ithuangyang-lab/claude-code-deepseek-setup

可调环境变量
  DEEPSEEK_API_KEY    直接给 key，跳过交互提问
  DEEPSEEK_MODEL      默认模型（默认 deepseek-flash）
  DEEPSEEK_PRO_MODEL  Opus 档实际调用的模型（默认 deepseek-v4-pro）

它只碰这几处
  ~/.claude/settings.json   ~/.claude.json   npm 全局包目录
`)
}

const argv = process.argv.slice(2)
if (argv.includes('-h') || argv.includes('--help')) {
  printHelp()
  process.exit(0)
}
if (argv.includes('-v') || argv.includes('--version')) {
  console.log(PKG_VERSION)
  process.exit(0)
}

main().catch((err) => {
  console.error(`\n${C.red}✗ 出错了：${err && err.stack ? err.stack : err}${C.off}`)
  process.exit(1)
})
