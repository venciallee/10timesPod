# 10timesPod 项目结构

```
10timesPod/
├── demo/                          # 📱 HTML 交互式原型
│   ├── index.html                 # 完整单页应用原型
│   └── README.md                  # Demo 使用说明
│
├── docs/                          # 📚 项目文档
│   ├── PRD.md                     # 产品需求文档（MVP）
│   ├── TECH_DESIGN.md             # 技术设计文档
│   ├── PRD-subscription-playback.md              # Phase 2-4 需求
│   ├── TECH_DESIGN_subscription_playback.md      # Phase 2-4 技术设计
│   ├── BRAINSTORM-podcast-insights.md            # AI 智能洞察功能头脑风暴
│   ├── AGENT_PROMPTS.md           # AI Agent 开发提示词
│   └── AGENT_PROMPTS_PHASE4.md    # Phase 4 开发提示词
│
├── 10timespod/                    # 🚀 Next.js 项目（待开发）
│   ├── app/                       # Next.js App Router
│   ├── components/                # React 组件
│   ├── services/                  # 后端服务层
│   ├── hooks/                     # 自定义 Hooks
│   ├── stores/                    # Zustand 状态管理
│   └── lib/                       # 工具函数
│
├── podscript/                     # 📜 辅助脚本
│
├── start-demo.sh                  # 🎬 快速启动 Demo 脚本
└── README.md                      # 项目总览
```

## 🎯 快速开始

### 查看 HTML 原型

```bash
# 方式 1: 使用启动脚本（推荐）
./start-demo.sh

# 方式 2: 手动启动
cd demo
python3 -m http.server 8000
# 访问 http://localhost:8000

# 方式 3: 直接打开
open demo/index.html
```

### 开发 Next.js 应用

```bash
# TODO: 待 Next.js 项目初始化后更新
cd 10timespod
npm install
npm run dev
```

## 📖 文档导航

| 文档 | 说明 | 阅读顺序 |
|------|------|----------|
| [PRD.md](PRD.md) | 产品需求文档，定义核心功能与用户价值 | ① 必读 |
| [TECH_DESIGN.md](TECH_DESIGN.md) | 技术架构设计，技术栈选型与系统设计 | ② 必读 |
| [demo/README.md](demo/README.md) | HTML 原型使用说明 | ③ 快速体验 |
| [PRD-subscription-playback.md](PRD-subscription-playback.md) | Phase 2-4 功能需求 | ④ 进阶功能 |
| [TECH_DESIGN_subscription_playback.md](TECH_DESIGN_subscription_playback.md) | Phase 2-4 技术设计 | ⑤ 进阶实现 |
| [BRAINSTORM-podcast-insights.md](BRAINSTORM-podcast-insights.md) | AI 智能洞察功能头脑风暴 | ⑥ 未来规划 |

## 🎨 当前状态

- ✅ **产品设计**: 完整的 PRD 与技术设计文档
- ✅ **交互原型**: 可交互的 HTML Demo
- ⏳ **开发实现**: 等待开始
- ⏳ **部署上线**: 等待实现

## 💡 项目特点

1. **文档驱动**: 详细的 PRD 和技术设计先行
2. **原型先行**: 交互式 HTML 原型验证设计
3. **模块化架构**: AI Provider 抽象层，支持多模型
4. **用户导向**: 专注英文播客 + 中文字幕垂直场景
5. **技术现代**: Next.js 14 + TypeScript + Tailwind CSS

## 📊 开发路线图

### Phase 1: MVP 核心功能
- [ ] 项目初始化（Next.js + 数据库）
- [ ] RSS 订阅与播放器
- [ ] AI 转录（Whisper）
- [ ] AI 翻译（LLM）
- [ ] 双语字幕展示
- [ ] 模型设置页

### Phase 2-3: 体验优化
- [ ] 用户认证系统
- [ ] 播放进度记忆
- [ ] 订阅库增强
- [ ] 播放队列功能
- [ ] UI/UX 打磨

### Phase 4: AI 增强
- [ ] 单集摘要
- [ ] 自动章节识别
- [ ] 关键词高亮
- [ ] 搜索与发现

## 🤝 参与开发

1. 克隆仓库
2. 查看 HTML Demo 了解产品形态
3. 阅读 PRD 和技术设计文档
4. 选择一个模块开始开发

## 📄 许可

待定
