# claude-code-deepseek-setup

一条命令，把一台 Mac 配成：**Claude Code CLI + DeepSeek API + 「搭工作台」skill**，并在 Obsidian 的 **Claudian** 插件里能正常对话。

不需要你懂命令行。不需要你手动 export 一堆环境变量。

想连带 **飞书 CLI** 和 **ChatCut** 一起装，加一个参数就行：

```bash
npx -y claude-code-deepseek-setup --with-all
```

---

## 快速开始

### 情况 A：你的 Mac 上已经有 Node.js（v18 或更高）

```bash
npx -y claude-code-deepseek-setup          # 默认三样
npx -y claude-code-deepseek-setup --with-all   # 再加飞书 CLI 和 ChatCut
```

不确定有没有？终端里敲 `node -v`，有版本号（v18 以上）就是有。

### 情况 B：全新的 Mac，什么都没有

macOS **不预装 Node.js**，而 `npx` 是 Node 自带的命令 —— 所以第一步必须先装 Node，这一步省不掉。

```bash
curl -fsSL https://raw.githubusercontent.com/ithuangyang-lab/claude-code-deepseek-setup/main/install.sh | bash
```

这个脚本**只干一件事**：装好 nvm + Node.js，然后自动执行上面那条 `npx` 命令。

> **为什么只干这一件事？** 真正的安装逻辑只有一份，在 npm 包里。脚本和包各维护一套实现，早晚会漂移。

> 想先看脚本再跑（推荐）：
> ```bash
> curl -fsSL https://raw.githubusercontent.com/ithuangyang-lab/claude-code-deepseek-setup/main/install.sh -o /tmp/ds-setup.sh
> less /tmp/ds-setup.sh      # 看完按 q 退出
> bash /tmp/ds-setup.sh
> ```

### 备选路线

**直接从 GitHub 跑**（不经过 npm registry）：

```bash
npx -y github:ithuangyang-lab/claude-code-deepseek-setup
```

**装成全局命令**（之后可以反复 `claude-code-deepseek-setup` 重跑）：

```bash
npm install -g claude-code-deepseek-setup
claude-code-deepseek-setup
```

---

## 它做了什么

默认 7 步：

| 步骤 | 内容 |
|---|---|
| 1 | 检测环境（macOS / Node 版本 ≥ 18） |
| 2 | 全局装 **Claude Code CLI**（`npm install -g @anthropic-ai/claude-code`），已装则跳过 |
| 3 | 问你要 **DeepSeek API key** |
| 4 | 打 DeepSeek 的余额接口**验证 key 真的可用** |
| 5 | 把 8 个环境变量写进 `~/.claude/settings.json` 的 `env` 字段（权限 600）；写 `~/.claude.json` 跳过首次登录引导 |
| 6 | **真的调一次 DeepSeek**，确认端到端通了 |
| 7 | 装「搭工作台」skill 到 `~/.claude/skills/ai-workbench-portable/` |

加了 `--with-feishu` / `--with-chatcut` 就多两步（8、9 步）。

> 第 7 步特意放在第 6 步**之后** —— 万一 DeepSeek 没通，脚本会当场停下，
> 不会给你留一个「装了 skill 但 AI 根本连不上」的半成品。

全程**幂等**：重复跑不会坏，改动前一律先备份（`*.bak-<时间戳>`）。

---

## 两个可选模块（默认不装）

```bash
npx -y claude-code-deepseek-setup --with-feishu    # 只加飞书 CLI
npx -y claude-code-deepseek-setup --with-chatcut   # 只加 ChatCut
npx -y claude-code-deepseek-setup --with-all       # 两个都加
```

**为什么默认不装**：这两个装完都**不能立刻用**，各自还差一步必须你本人操作。
无脑装反而容易让人以为坏了，所以做成显式开关。

**两个模块都是「尽力而为」**：装不上只打一行警告然后跳过，不会回滚前面已经装好的部分。

### 飞书 CLI

装的是 npm 包 [`@larksuite/cli`](https://www.npmjs.com/package/@larksuite/cli)，命令名 `lark-cli`。

> ⚠️ **装完还不能用，还差两步，命令行代替不了：**
>
> ```bash
> lark-cli config init    # 填你自己飞书自建应用的 app-id / app-secret
> lark-cli auth login     # 给你一个链接/二维码，在手机或浏览器上点授权
> ```
>
> `app-id` / `app-secret` 要在 [open.feishu.cn](https://open.feishu.cn) 建一个**自建应用**，
> 并按你要用的功能开通对应权限。**这一步没有任何脚本能替你做** —— 它绑的是你的账号。

### ChatCut

> ⚠️ **ChatCut 不是一个命令**，它是 Claude Code 的插件（`chatcut@chatcut-inc`）。
> 装完**必须重开一个 Claude Code 会话**才生效 —— 当前窗口里不会出现那些工具。
> 首次调用时会弹一次授权，登录 ChatCut 账号即可。

装的过程要连 GitHub 拉插件市场，**国内网络通常需要代理**。装不上时脚本会打印手动命令：

```bash
claude plugin marketplace add https://github.com/ChatCut-Inc/agent-plugin.git
claude plugin install chatcut@chatcut-inc -y
```

> 装好后 `~/.claude/skills/` 里会多出一批 `chatcut-*` 目录 —— 那是插件自带的，
> 插件安装时自动铺进去，不用你单独装。

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

## 顺手装好的：「搭工作台」skill

装完在上面那个 Claude Code 里（终端或 Claudian 都行）说一句：

> **搭工作台**

它会带你走四步：

1. 问你知识库放哪个文件夹，**建好目录骨架**（`01-收件箱` / `02-在做的` / `03-知识` / `04-素材` / `05-归档`）
2. **一次一题问你 15 个问题** —— 你是谁、你的尺子是什么、什么会让你一眼 pass、AI 不许碰什么
3. 按你的回答**生成四个文件**：`README.md` / `user.md` / `CLAUDE.md` / `HANDOFF.md`
4. **点火验证** —— 故意写一句不像你的话，让你纠正，当场把这条纠正写成一条永久记忆

**约 30 分钟，其中 20 分钟是你在回答问题。**

> 它的价值不在那四个文件（那部分只占 31%），在于**「你纠正它 → 它记下来」这个机制**（占 69%）。
> 用满两周、攒到 10 条记忆之后，你就不想再换回一个什么都不记得的 AI 了。

源文件在 `skills/ai-workbench-portable/SKILL.md`，**单文件、自包含**，
你也可以把它直接发给别人的 AI，不需要装任何东西。

---

## 前置要求

- **macOS**（Intel / Apple Silicon 都行）
- **Node.js ≥ 18**（走 install.sh 引导的话，脚本会替你装）
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
| `npm install -g` 报 `EACCES` | Node 是官方 pkg 装的，全局目录要 sudo | 改用 nvm 管 Node，或手动 `sudo npm install -g @anthropic-ai/claude-code` |
| `npx` 提示找不到包 | 包没发到 registry，或网络问题 | 换 `npx -y github:ithuangyang-lab/claude-code-deepseek-setup` |
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

**从不删除任何东西**，只做「写入」和「备份」。要回滚：

```bash
# 1. 恢复配置（挑最近的备份）
ls ~/.claude/settings.json.bak-*
cp ~/.claude/settings.json.bak-<时间戳> ~/.claude/settings.json

# 2. 移除 .zshrc 里那段 nvm 初始化
#    用编辑器删掉 >>> nvm (added by claude-code-deepseek-setup) >>> 到 <<< 之间的内容

# 3. 卸载 CLI
npm uninstall -g @anthropic-ai/claude-code

# 4. 如果装过全局命令
npm uninstall -g claude-code-deepseek-setup
```

**装了可选模块的，额外三步：**

```bash
# 5. 移除「搭工作台」skill
rm -rf ~/.claude/skills/ai-workbench-portable

# 6. 卸飞书 CLI（如果装过）
npm uninstall -g @larksuite/cli

# 7. 卸 ChatCut 插件（如果装过）
claude plugin uninstall chatcut@chatcut-inc
```

> ⚠️ 第 6 步**不会清掉你的飞书应用凭证** —— 那个在系统钥匙串里，要自己去「钥匙串访问」搜 `lark` 删。

---

## 安全说明

- **包里没有任何密钥。** API key 只在运行时由你输入，直接写进 `~/.claude/settings.json`，权限 `600`。
- 你可以随时 `cat ~/.claude/settings.json` 看到完整的配置，没有隐藏动作。
**默认只碰这四处：**

`~/.claude/settings.json` · `~/.claude.json` · `~/.claude/skills/ai-workbench-portable/` · npm 全局包目录

**加 `--with-feishu` 多碰一处**：npm 全局包目录（装 `@larksuite/cli`）。

**加 `--with-chatcut` 多碰一处**：`~/.claude/plugins/`（Claude Code 的插件目录，写之前会调官方 `claude plugin` 命令，不是自己乱写）。

**`install.sh` 引导脚本额外碰**：`~/.nvm/`、`~/.zshrc`（只往末尾追加一个带哨兵注释的块）。

> 除了上面这些，**不碰你的任何文档、任何配置**。

---

## 可调项

### 环境变量

```bash
DEEPSEEK_API_KEY=sk-xxx npx -y claude-code-deepseek-setup   # 非交互，直接给 key
DEEPSEEK_MODEL=deepseek-v4-pro npx -y claude-code-deepseek-setup
NODE_VERSION=20 bash install.sh          # 引导脚本：换 Node 大版本
NVM_VERSION=v0.40.1 bash install.sh      # 引导脚本：换 nvm 版本
PKG=github:ithuangyang-lab/claude-code-deepseek-setup bash install.sh   # 引导脚本：换包来源
```

### 命令行参数

```bash
npx -y claude-code-deepseek-setup --help           # 看全部参数
npx -y claude-code-deepseek-setup --version        # 看版本

npx -y claude-code-deepseek-setup --with-feishu    # 加装飞书 CLI
npx -y claude-code-deepseek-setup --with-chatcut   # 加装 ChatCut
npx -y claude-code-deepseek-setup --with-all       # 两个都加
```

> `--with-feishu` / `--with-chatcut` 可以一起写，效果同 `--with-all`。

---

## 已验证 / 未验证

诚实标注：

- ✅ **已验证**：8 个环境变量的名称与作用、DeepSeek 的 base URL 与模型映射规则、Claudian 的三项设置字段名、`settings.json` 的 `env` 字段、`hasCompletedOnboarding` 跳过引导 —— 都有官方文档或实机依据。
- ⚠️ **未实测**：**「只写 `settings.json`、Claudian 环境变量栏留空」这个组合**。原理上成立（官方文档明确 `env` 覆盖 shell 变量，且 Claudian 不注入同名变量时不会覆盖它），但没在干净的新机器上跑过。**如果 Claudian 里对话不工作，把 8 个变量原样再填进 Claudian 的 Environment 栏即可** —— 那是实机验证过的写法，两者都填不冲突。
- ⚠️ **未实测**：npm 包形态（`bin/cli.js`）与 bash 版逻辑等价，但**尚未在一台干净的新 Mac 上端到端跑过**。
- ✅ **已实测**：「装『搭工作台』skill」这一步（第 7 步）**三条分支全跑过** —— 空目录能装上、原样重跑会跳过、目标文件被改过会先备份再覆盖。用真代码 + 假 `HOME` 跑的，没碰真环境。
- ⚠️ **未实测**：`--with-feishu` 和 `--with-chatcut` 这两条安装命令**没有在干净机器上跑过** —— 只核对过包名、命令语法和 `--help` 输出。你本机这两个都已装好，跑也只会「已存在跳过」，验不出真东西。**要真验得找一台没装过的机器。**
- ⚠️ **未实测**：`--with-chatcut` 依赖 GitHub 连通性。国内网络下 `github.com` 直连会超时，**通常需要代理**；脚本装不上时只警告不中断，会打印手动命令。

---

## License

MIT
