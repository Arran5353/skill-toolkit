<div align="center">

<img src="SkillDeck/docs/icon.png" width="120" alt="SkillDeck icon" />

# SkillDeck

### 你的 Claude Code skills 和 commands,终于触手可及。

一款原生 macOS 应用——把你装过的每一个 skill、command、plugin 变成一张可搜索、好看的速查表,
点一下就把命令送进正在用的终端。

[English](README.md) · **简体中文**

[**⬇ 下载 macOS 版**](https://github.com/Arran5353/skill-toolkit/releases/latest) · [反馈问题](https://github.com/Arran5353/skill-toolkit/issues) · [从源码构建](SkillDeck/README.md)

![SkillDeck](SkillDeck/docs/screenshot-detail.png)

</div>

---

## 为什么做 SkillDeck?

只要你装的 Claude Code skill 和 plugin 一多,大概都遇到过这种情况:你*知道*有个 skill 能干这事,
但就是想不起它叫什么、能做什么、怎么调用。于是你停下来翻目录,或者干脆忘了它的存在。

**SkillDeck 就是来解决这个问题的速查表。** 它自动扫描你装过的所有东西,以清晰的层级展示出来,
点一下就能把命令塞进当前终端。装了新东西?自动出现。

## ✨ 功能

- **🗂 一处尽览。** skill、command、你自己的本地 skill、项目专属 skill、Claude Code 内置斜杠命令、
  MCP server——全部自动发现并按来源分组。
- **🌳 清晰层级。** 按 **Marketplace → Plugin → Skill/Command** 浏览,也能按类型筛选。带子命令的
  skill(比如 `/impeccable polish`)可展开显示每一个子命令。
- **⤵️ 点击注入。** 点任意命令,它就通过 ⌘V 输入到你最前面的终端里——随时可执行,绝不自动回车。
  支持 Terminal、iTerm、Ghostty、VS Code 等。
- **🛒 Marketplace 浏览 + 一键安装。** 查看各 marketplace 里所有可用插件、哪些已装,在 app 内
  直接安装新插件——几秒后它的 skill 就出现在树里。
- **📖 漂亮的用法文档。** 每个 skill 的文档以真正的 Markdown 渲染——标题、列表、表格、带语法高亮的
  代码块,而不是一堆原始符号。
- **⭐ 收藏与最近。** 把常用的加星置顶;最近用过的自动浮到前面。
- **🔎 菜单栏快捷。** 菜单栏图标随时可访问收藏和最近使用项。
- **♻️ 永远最新。** 文件监听让目录在你增删 skill/plugin 的瞬间自动同步。
- **🖥 原生轻量。** 纯 Swift / SwiftUI。没有 Electron、没有后台服务,约 700 KB。

## 🚀 开始使用

### 下载(最简单)

1. 到 [**Releases 页面**](https://github.com/Arran5353/skill-toolkit/releases/latest) 下载最新的 **SkillDeck.dmg**。
2. 打开 `.dmg`,把 **SkillDeck** 拖进 **Applications**。
3. **首次打开:** 这个版本没有用付费 Apple 开发者账号签名,所以 macOS Gatekeeper 会拦一下。
   **右键点击 SkillDeck → 打开**,再点**打开**。
   *(macOS 15:系统设置 → 隐私与安全性 → 往下滚 → **仍要打开**。)*
4. 按提示授予**辅助功能(Accessibility)**权限——这是让 SkillDeck 能往终端输入命令的关键。
   不授权也能用,会退化为**仅复制**模式(复制命令,你自己粘贴)。

### 从源码构建

想自己编译(顺便跳过 Gatekeeper 那一步)?

```bash
git clone https://github.com/Arran5353/skill-toolkit.git
cd skill-toolkit/SkillDeck
swift run SkillDeckApp
```

需要 macOS 15+ 和 Swift 6.1 / Xcode 16。打包和贡献细节见 [SkillDeck/README.md](SkillDeck/README.md)。

## 📋 环境要求

- **macOS 15+**
- **`claude` CLI**(仅 marketplace 安装功能需要)——在 `PATH` 中或位于 `~/.local/bin/claude`

## 🙋 常见问题

**安全吗?它会访问什么?**
SkillDeck 只读取你本地的 `~/.claude` 目录(skills、plugins、marketplaces),并把自己的偏好设置写到
`~/Library/Application Support/SkillDeck`,从不改动你的 `~/.claude` 文件。完全开源,每一行都可查。

**为什么需要辅助功能权限?**
仅用于模拟 ⌘V,把命令粘贴进终端。不授权则退化为仅复制模式。

**"身份不明的开发者"警告?**
公开版本未做公证(需付费 Apple 账号)。右键 → 打开一次即可,或从源码构建。

## 🤝 参与贡献

欢迎提 issue 和 PR,详见 [CONTRIBUTING](SkillDeck/CONTRIBUTING.md)。代码量小、测试完整,
拆成纯逻辑核心(`SkillDeckCore`)和一层薄薄的 SwiftUI——很容易加新数据源或功能。

## 📄 许可证

MIT © 2026 Yazhuo Zhou
