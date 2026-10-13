# claude-code-deepseek-setup

一条指令，把一台**全新的 Mac** 配成：**Node.js + Claude Code CLI + DeepSeek API**，并在 Obsidian 的 **Claudian** 插件里能正常对话。

不需要你懂命令行。不需要你手动 export 一堆环境变量。

---

## 一行安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/<你的用户名>/<仓库名>/main/install.sh)
```

跑完这一条，命令行部分就全好了。中途它会问你要一次 DeepSeek 的 API key。

> 想先看脚本再跑（推荐）：
> ```bash
> curl -fsSL https://raw.githubusercontent.com/<你的用户名>/<仓库名>/main/install.sh -o /tmp/ds-setup.sh
> less /tmp/ds-setup.sh      # 看完按 q 退出
> bash /tmp/ds-setup.sh
> ```

---

## 它做了什么

| 步骤 | 内容 |
|---|---|
| 1 | 装 **nvm**，再用 nvm 装 **Node.js 22**，把 nvm 初始化写进 `~/.zshrc` |
| 2 | 全局装 **Claude Code CLI**，并输出它的绝对路径 |
| 3 | 问你要 **DeepSeek API key** |
| 4 | 打 DeepSeek 的余额接口**验证 key 真的可用** |
| 5 | 把 8 个环境变量写进 `~/.claude/settings.json` 的 `env` 字段（权限 600）；写 `~/.claude.json` 跳过首次登录引导 |
| 6 | **真的调一次 DeepSeek**，确认端到端通了 |

全程**幂等**：重复跑不会坏，改动前一律先备份（`*.bak-<时间戳>`）。

---

## 为什么环境变量写进 `settings.json` 而不是 `~/.zshrc`

这是这套方案最省事的地方。

Claude Code 官方的 `settings.json` 支持一个 `env` 字段，**它的优先级高于 shell 里 `export` 的同名变量**。所以把 DeepSeek 的配置写在那里，会同时覆盖两个场景：

- 你在终端里直接敲 `claude` → 走 DeepSeek
- Claudian 插件启动 `claude` 子进程 → 也走 DeepSeek

**代价只有一个：Claudian 的设置界面里不用再填那一大坨环境变量了**，只需要填 CLI 路径和模型名。

> ⚠️ 反过来也要知道：如果你哪天想临时用官方 Claude，光在终端 `export` 是**盖不掉** `settings.json` 的。得改文件，或者用 `claude --settings <另一个文件>`。

---

## 装完之后：Obsidian 那两步

这部分**没法纯命令行完成** —— Obsidian 装插件必须在 GUI 里点「安装」和「启用」。但只有两下：

**1. 装插件**

Obsidian → 设置 → 第三方插件 → 浏览 → 搜 `Claudian` → 安装 → 启用

或者直接跳转：

```bash
open "obsidian://show-plugin?id=claudian"
```

> 认准作者 **YishenTu**（`github.com/YishenTu/claudian`）。社区里有同名变体。

**2. 配置**

设置 → Claudian → Provider 选 **Claude**，填三项：

| 设置项 | 填什么 |
|---|---|
| Claude CLI path | 脚本最后打印的那个绝对路径（`which claude` 的输出） |
| Custom models | `deepseek-v4-pro` 和 `deepseek-flash`，**各占一行** |
| Default model | `deepseek-flash` |

**环境变量一栏留空。** 第 5 步已经写进 `~/.claude/settings.json` 了。

**3. 测**

点侧边栏机器人图标 → 模型菜单选 `deepseek-flash` → 发一句话。

---

## 前置要求

- **macOS**（Intel / Apple Silicon 都行）
- 一个 **DeepSeek API key** —— https://platform.deepseek.com/api_keys
- DeepSeek 账户**有余额**（预付费，余额 0 直接报错）
- Obsidian **v1.13.0+**，且是**桌面端**（手机装不了 Claudian）

---

## 模型与计费

脚本默认写这套映射：

| Claude Code 里的档位 | 实际调用 | 说明 |
|---|---|---|
| 默认 / Sonnet / Haiku | `deepseek-flash` | 便宜，日常够用 |
| Opus | `deepseek-v4-pro` | 更强，按 V4 Pro 计费 |

DeepSeek 端点自己的兜底规则：`claude-opus*` → `deepseek-v4-pro`，`claude-sonnet*` / `claude-haiku*` → `deepseek-flash`，不认识的模型名也落 `deepseek-flash`。

**想全走便宜档**：改 `~/.claude/settings.json`，把 `ANTHROPIC_DEFAULT_OPUS_MODEL` 也改成 `deepseek-flash`。

**想换模型**：改 `env.ANTHROPIC_MODEL` 即可，重开终端生效。

---

## 故障排查

| 症状 | 原因 | 解法 |
|---|---|---|
| `[claude-code:unrecognized_model] deepseek-flash` | **无害警告** | 不用管。Claude Code 的静态模型名单里没有 DeepSeek 的名字而已，不影响功能 |
| `401` / `authentication_error` | key 错，或余额为 0 | 去 DeepSeek 后台查余额 |
| 请求卡住 20 秒以上 | 本地代理拦了 | 确认 `NO_PROXY=api.deepseek.com` 生效；或在代理软件里给 `api.deepseek.com` 加直连规则 |
| `spawn claude ENOENT`（在 Claudian 里） | 插件没找到 nvm 装的 CLI | 手填 `cliPath` 绝对路径，即 `which claude` 的输出 |
| 改了配置不生效 | 配置没重载 | 终端重开；Obsidian 要 **Cmd+Q 完全退出**再开（关窗口不算） |
| 首次跑 `claude` 还是弹了登录/主题 | `~/.claude.json` 没生效 | 重开终端再试；实在不行手动过一次引导，之后就不会再弹 |

自查当前用的是不是 DeepSeek：

```bash
claude
# 进去之后输入
/status
```

`~/.claude/settings.json` 里 8 个变量的作用：

| 变量 | 作用 |
|---|---|
| `ANTHROPIC_BASE_URL` | 指向 DeepSeek 的 Anthropic 兼容端点 —— **总开关** |
| `ANTHROPIC_API_KEY` | DeepSeek 的 key |
| `ANTHROPIC_MODEL` | 默认模型 |
| `ANTHROPIC_DEFAULT_OPUS_MODEL` | 选 Opus 时实际调谁 |
| `ANTHROPIC_DEFAULT_SONNET_MODEL` | 选 Sonnet 时实际调谁 |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL` | 选 Haiku 时实际调谁（后台小任务走这档，不设会报错） |
| `NO_PROXY` / `no_proxy` | 绕开本地代理 |

---

## 卸载 / 回滚

脚本**从不删除任何东西**，只做「写入」和「备份」。要回滚：

```bash
# 1. 恢复配置（挑最近的备份）
ls ~/.claude/settings.json.bak-*
cp ~/.claude/settings.json.bak-<时间戳> ~/.claude/settings.json

# 2. 移除 .zshrc 里那段 nvm 初始化
#    用编辑器删掉 >>> nvm (added by claude-code-deepseek-setup) >>> 到 <<< 之间的内容

# 3. 卸载 CLI
npm uninstall -g @anthropic-ai/claude-code
```

---

## 安全说明

- **脚本里没有任何密钥。** API key 只在运行时由你输入，直接写进 `~/.claude/settings.json`，权限 `600`。
- 你可以随时 `cat ~/.claude/settings.json` 看到完整的配置，没有隐藏动作。
- 脚本只碰这五个地方：`~/.nvm/`、`~/.claude/settings.json`、`~/.claude.json`、`~/.zshrc`、npm 全局包目录。别的一律不动。

---

## 环境变量可调项

跑之前设上可以改默认行为：

```bash
NODE_VERSION=20 bash install.sh              # 换 Node 大版本
DEEPSEEK_MODEL=deepseek-v4-pro bash install.sh   # 换默认模型
NVM_VERSION=v0.40.1 bash install.sh          # 换 nvm 版本
```

---

## 已验证 / 未验证

诚实标注：

- ✅ **已验证**：8 个环境变量的名称与作用、DeepSeek 的 base URL 与模型映射规则、Claudian 的三项设置字段名、`settings.json` 的 `env` 字段、`hasCompletedOnboarding` 跳过引导 —— 都有官方文档或实机依据。
- ⚠️ **未实测**：**「只写 `settings.json`、Claudian 环境变量栏留空」这个组合**。原理上成立（官方文档明确 `env` 覆盖 shell 变量，且 Claudian 不注入同名变量时不会覆盖它），但没在干净的新机器上跑过。**如果 Claudian 里对话不工作，把 8 个变量原样再填进 Claudian 的 Environment 栏即可** —— 那是实机验证过的写法，两者都填不冲突。

---

## License

MIT
