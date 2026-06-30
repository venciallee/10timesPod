# 10timesPod - 双语字幕播客播放器

<div align="center">

**听英文播客，看中文字幕**

让每一个中文用户都能无障碍享受英文播客内容

[查看 Demo](./demo/index.html) • [产品文档](./PRD.md) • [技术设计](./TECH_DESIGN.md) • [项目结构](./PROJECT_STRUCTURE.md)

</div>

---

## 📖 项目简介

**10timesPod** 是一个专为中文用户打造的英文播客 Web 播放器，核心功能是为英文播客提供 **AI 驱动的双语字幕**（英文原文 + 中文翻译），让用户像看带字幕的视频一样听播客。

### 核心特性

- 🎙️ **RSS 订阅**: 支持任意英文播客 RSS Feed
- 🤖 **AI 转录**: 使用 Whisper 将音频转为精准的英文文本
- 🌐 **智能翻译**: LLM 驱动的中文翻译，专业术语准确
- 📝 **双语字幕**: 英中逐句对照，实时高亮跟随播放
- ⚙️ **灵活配置**: 支持多种 AI 服务商（OpenRouter / OpenAI / 自定义）
- 🎵 **流畅播放**: 变速播放、进度记忆、播放队列

## 🎯 目标用户

- 英文播客爱好者，但听力能力有限，需要文字辅助
- 想通过播客内容学习英文的用户
- 希望快速获取英文播客核心内容的中文读者

## 🚀 快速体验

### 查看交互式原型

```bash
# 克隆仓库
git clone https://github.com/venciallee/10timesPod.git
cd 10timesPod

# 启动 HTML Demo
./start-demo.sh

# 或手动打开
open demo/index.html
```

Demo 包含完整的交互式界面：
- ✅ 播客发现与订阅
- ✅ 播放器与双语字幕
- ✅ 模型设置页面
- ✅ 底部常驻播放栏

## 📐 技术架构

### 技术栈

| 层级 | 技术 | 说明 |
|------|------|------|
| **框架** | Next.js 14 | App Router，SSR/SSG，API Routes |
| **语言** | TypeScript | 类型安全 |
| **UI** | Tailwind CSS + shadcn/ui | 快速构建现代 UI |
| **状态** | Zustand | 轻量状态管理 |
| **数据库** | SQLite / PostgreSQL | Turso 或 Supabase |
| **ORM** | Drizzle ORM | 类型安全的数据库访问 |
| **认证** | NextAuth.js | Google OAuth + 邮箱登录 |
| **AI** | OpenAI / OpenRouter | Whisper 转录 + LLM 翻译 |
| **部署** | Vercel / Docker | 零配置部署或私有化 |

### 系统架构图

```
┌─────────────────┐
│   用户浏览器     │
│  (Next.js App)  │
└────────┬────────┘
         │
┌────────┴────────┐
│  Next.js Server │
│   API Routes    │
├─────────────────┤
│  RSS Service    │
│  AI Service     │
│  DB (SQLite)    │
└────────┬────────┘
         │
    ┌────┴────┐
    │ External│
    │ AI APIs │
    └─────────┘
```

### 核心设计

- **AI Provider 抽象层**: 统一接口适配多个模型服务商
- **转录缓存**: 同一单集转录结果全局共享
- **预生成翻译**: 订阅后后台自动翻译，实时兜底
- **二分查找同步**: 高性能字幕时间轴匹配

## 📂 项目结构

```
10timesPod/
├── demo/                    # HTML 交互式原型
│   ├── index.html          # 完整的单页应用 Demo
│   └── README.md           # Demo 使用说明
│
├── 10timespod/             # Next.js 项目（待开发）
│   ├── app/                # Next.js App Router 页面
│   ├── components/         # React 组件
│   ├── services/           # 后端服务层
│   ├── hooks/              # 自定义 Hooks
│   ├── stores/             # Zustand 状态管理
│   └── lib/                # 工具函数
│
├── PRD.md                  # 产品需求文档（MVP）
├── TECH_DESIGN.md          # 技术设计文档
├── PRD-subscription-playback.md              # Phase 2-4 需求
├── TECH_DESIGN_subscription_playback.md      # Phase 2-4 技术设计
├── BRAINSTORM-podcast-insights.md            # AI 智能洞察功能
├── AGENT_PROMPTS.md        # AI Agent 开发提示词
├── start-demo.sh           # Demo 启动脚本
└── README.md               # 本文件
```

详见 [项目结构文档](./PROJECT_STRUCTURE.md)

## 🗺️ 开发路线图

### Phase 1: MVP 核心功能（Week 1-4）

- [ ] 项目初始化与数据库设计
- [ ] RSS 订阅与解析
- [ ] 音频播放器组件
- [ ] AI 转录集成（Whisper）
- [ ] AI 翻译集成（LLM）
- [ ] 双语字幕展示与同步
- [ ] 模型设置页面

### Phase 2: 体验优化（Week 5-6）

- [ ] 用户认证系统
- [ ] 播放进度持久化
- [ ] 订阅库增强（未听标记、快速播放）
- [ ] 底部常驻播放栏
- [ ] UI/UX 打磨

### Phase 3: 高级功能（Week 7-9）

- [ ] 播放队列管理
- [ ] AI 单集摘要
- [ ] 自动章节识别
- [ ] 搜索与发现
- [ ] 学习功能（生词标记、跟读）

### Phase 4: 未来规划

- [ ] 移动端 App
- [ ] 离线下载
- [ ] 社区功能
- [ ] 笔记导出

## 📚 文档索引

| 文档 | 说明 | 受众 |
|------|------|------|
| [PRD.md](./PRD.md) | 产品需求文档 | 产品经理、开发者 |
| [TECH_DESIGN.md](./TECH_DESIGN.md) | 技术架构设计 | 开发者、架构师 |
| [demo/README.md](./demo/README.md) | HTML 原型说明 | 设计师、测试人员 |
| [PROJECT_STRUCTURE.md](./PROJECT_STRUCTURE.md) | 项目结构总览 | 所有人 |
| [PRD-subscription-playback.md](./PRD-subscription-playback.md) | Phase 2-4 需求 | 产品经理 |
| [TECH_DESIGN_subscription_playback.md](./TECH_DESIGN_subscription_playback.md) | Phase 2-4 设计 | 开发者 |

## 🤝 贡献指南

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 创建 Pull Request

## 📊 差异化优势

| 竞品 | 10timesPod |
|------|-----------|
| **Snipd**: 有 AI 转录但无中文逐句翻译 | ✅ 逐句双语对照，专门优化学习体验 |
| **Apple Podcasts**: 转录功能无翻译 | ✅ AI 翻译 + 多模型支持 |
| **小宇宙**: 中文播客为主 | ✅ 专注英文播客垂直场景 |

## 🎓 学习资源

- [Next.js 14 文档](https://nextjs.org/docs)
- [Tailwind CSS](https://tailwindcss.com)
- [Drizzle ORM](https://orm.drizzle.team)
- [OpenRouter API](https://openrouter.ai/docs)
- [Whisper API](https://platform.openai.com/docs/guides/speech-to-text)

## 📄 许可证

待定

## 🙏 致谢

- [Lex Fridman Podcast](https://lexfridman.com/podcast/) - 产品灵感来源
- [Snipd](https://www.snipd.com/) - 竞品参考
- [OpenAI Whisper](https://openai.com/research/whisper) - 转录技术
- [shadcn/ui](https://ui.shadcn.com/) - UI 组件库

---

<div align="center">

**Built with ❤️ for English podcast learners**

[⭐ Star this repo](https://github.com/venciallee/10timesPod) if you find it helpful!

</div>
