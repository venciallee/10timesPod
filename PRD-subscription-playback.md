# PRD: 订阅浏览、播放队列与知识管理功能

> 10timesPod — 双语字幕播客播放器
> 版本: v2.0 | 作者: Product | 日期: 2026-03-08
> 状态: **Draft** (Phase 1-3 已实现，Phase 4 新增)

---

## 1. 问题陈述

### 1.1 当前状态

10timesPod 已实现 RSS 订阅功能：用户可以通过粘贴 RSS Feed URL 订阅播客，订阅数据存储在 `subscriptions` 表中，`/subscriptions` 页面展示已订阅播客的网格列表。

但**订阅之后的使用链路是断裂的**：

- **浏览断层**: 订阅列表（`/subscriptions`）只展示播客卡片（封面 + 名称 + 描述），没有展示最新单集、未听数量、上次收听进度等关键信息。用户看到的是一个静态目录，而非一个"活的"播客库。
- **播放入口缺失**: 当前唯一的播放入口是 `EpisodeRow` 链接到 `/podcasts/[id]/episodes/[episodeId]` 页面后自动加载播放。但在订阅列表和首页的 Latest Episodes 中，点击 episode 需要先进入播客详情 → 再找到单集 → 再进入播放页，路径太长。
- **无播放队列**: `playerStore` 只维护单个 `currentEpisodeId`，没有 queue/playlist 概念。用户无法连续收听多集内容，每集听完后播放器静默停止。
- **无快速播放按钮**: `EpisodeRow` 组件虽然显示了播放图标，但实际是一个导航链接（Link），不能直接在当前页面触发播放。

### 1.2 用户痛点

| 痛点 | 严重程度 | 场景 |
|------|----------|------|
| 订阅了播客但不知道有什么新内容 | 高 | 打开订阅列表，看不到哪个播客有更新 |
| 想听某集但路径太长 | 高 | 需要点击播客 → 等加载 → 找到单集 → 点击 → 再等加载 |
| 听完一集后自动停止 | 中 | 希望自动播放下一集或自定义的待播列表 |
| 无法在浏览时快速试听 | 中 | 想快速预览某集内容，但必须跳转全屏播放页 |

### 1.3 目标用户画像

**小李 — 英文播客学习者**
28 岁，产品经理，订阅了 Lex Fridman、Huberman Lab 等 5 个英文播客。每天通勤时用电脑浏览器打开 10timesPod，希望快速看到哪些播客更新了，选一集开始听，听完自动播放下一集。他不想每次都点进播客详情页去找最新一集。

---

## 2. 目标与成功指标

### 2.1 产品目标

将 10timesPod 从"能订阅、能播放"提升为"方便浏览、流畅播放"，让订阅→浏览→播放的链路顺滑无断点。

### 2.2 成功指标

| 指标 | 当前基线 | 目标 | 衡量方式 |
|------|----------|------|----------|
| 从订阅列表到开始播放的点击数 | 3-4 次 | 1 次 | 用户操作路径分析 |
| 单次会话平均收听集数 | ~1 集 | ≥2 集 | `playProgress` 表写入频次 |
| 订阅列表页停留时长 | 低（快速跳出） | 提升 50% | 页面停留时间 |
| PlayBar 持续播放时长 | 单集时长 | 跨集连续播放 | 播放器状态追踪 |

### 2.3 非目标（Out of Scope）

- 离线下载与离线播放
- 智能推荐算法
- 社交功能（分享、评论）
- 移动端 App 适配
- 自动刷新 RSS Feed（后台定时任务）
- 多人协作标注（仅单用户知识管理）

---

## 3. 功能需求

### 3.1 F1: 订阅库增强（Subscription Library Redesign）

**参考**: Snipd 的订阅列表——每个播客展示最新集信息、未听标记，让用户一眼看到有什么值得听的。

#### 3.1.1 订阅列表卡片增强

当前 `PodcastCard` 只展示：封面、标题、作者、描述摘要、订阅按钮。

**新增信息**:

| 元素 | 说明 |
|------|------|
| 最新单集标题 | 显示该播客最近发布的一集标题（单行截断） |
| 最新单集发布时间 | 相对时间，如"2 天前"、"1 周前" |
| 未听集数 badge | 订阅后未播放过的集数，如 "3 new" |
| 收听进度指示 | 如果最新集正在听，显示微型进度条 |
| 快速播放按钮 | 卡片上的播放按钮，点击直接播放最新一集（不跳转页面） |

**排序规则**: 有新更新的播客排在前面，按最新集发布时间倒序。

#### 3.1.2 订阅列表视图模式

- **网格视图（默认）**: 当前的 grid layout，每张卡片展示增强信息
- **列表视图**: 紧凑的行列表，更像传统播客 app 的"我的节目"，每行展示封面缩略图 + 播客名 + 最新集标题 + 发布时间 + 播放按钮

用户可通过切换按钮在两种视图间切换，偏好保存在 localStorage。

### 3.2 F2: 快速播放（Quick Play）

**核心思想**: 任何能看到单集信息的地方，都应该能一键播放，无需页面跳转。

#### 3.2.1 EpisodeRow 播放按钮

改造 `EpisodeRow` 组件：

- **当前行为**: 整行是 `<Link>`，点击跳转到 `/podcasts/[id]/episodes/[episodeId]`
- **新行为**:
  - 左侧播放图标变为真正的播放按钮，点击调用 `playerStore.loadEpisode()` 直接在 PlayBar 播放
  - 标题区域仍保留为链接，点击进入播放详情页（含字幕面板）
  - 如果该集正在播放中，图标变为暂停按钮（可暂停/恢复）
  - 如果该集有播放进度，显示微型进度指示

**数据需求**: `EpisodeRow` 需要额外获取 `audioUrl`、所属播客的 `title` 和 `imageUrl`，以便调用 `loadEpisode()`。

#### 3.2.2 首页 Latest Episodes 快速播放

首页的 "Latest Episodes" 区域已使用 `EpisodeRow`，应用 3.2.1 的改造后自动获得快速播放能力。

#### 3.2.3 播客详情页单集列表快速播放

`/podcasts/[id]` 页面的 `EpisodeList` 同样应用 3.2.1 改造。

### 3.3 F3: 播放队列（Play Queue）

**参考**: Snipd 的 queue 功能——用户可以将感兴趣的集排入队列，播完一集自动播放下一集。

#### 3.3.1 队列数据模型

扩展 `playerStore`，新增:

```
queue: QueueItem[]        // 有序的待播列表
queueIndex: number        // 当前播放的队列位置
```

其中 `QueueItem` 包含:
```
{
  episodeId: string
  episodeTitle: string
  audioUrl: string
  podcastId: string
  podcastTitle: string
  coverUrl: string
  duration?: number
}
```

#### 3.3.2 队列操作

| 操作 | 说明 |
|------|------|
| 播放单集 | `loadEpisode()` 清空队列，仅播放该集 |
| 添加到队列末尾 | "Add to Queue" 按钮，追加到 `queue` 数组末尾 |
| 播放下一首（Play Next） | 插入到 `queueIndex + 1` 的位置 |
| 从队列移除 | 支持移除指定项 |
| 拖拽排序 | 队列面板中支持拖拽调整顺序 |
| 清空队列 | 一键清空 |

#### 3.3.3 自动连续播放

当前集播放完毕（`ended` 事件）时:

1. 如果队列中还有下一集（`queueIndex + 1 < queue.length`），自动加载并播放
2. 如果队列已播完，停止播放，保持最后一集的信息显示

#### 3.3.4 "播放全部"（Play All）

在播客详情页和订阅列表中提供 "播放全部" 按钮:

- **播客详情页**: 将当前播客的所有已加载单集按发布时间排序加入队列，从第一集开始播放
- **订阅列表最新集**: 将所有订阅播客的最新集加入队列

### 3.4 F4: PlayBar 增强

#### 3.4.1 队列指示器

PlayBar 增加队列信息:

- 显示队列计数（如 "2/5" 表示正在播放第 2 集，共 5 集）
- 上一首/下一首按钮（当队列有多集时显示）

#### 3.4.2 队列面板（Queue Panel）

点击 PlayBar 的队列图标，展开一个侧边面板或弹出层:

- 显示完整队列列表
- 当前播放项高亮
- 支持拖拽排序
- 支持逐项删除
- 支持清空队列

#### 3.4.3 PlayBar 点击展开

点击 PlayBar 中的封面/标题区域，导航到对应的播放详情页（`/podcasts/[podcastId]/episodes/[episodeId]`），方便用户查看字幕。

### 3.5 F5: 最近播放（Recently Played）

#### 3.5.1 最近播放列表

新增 `/recent` 页面或在首页增加"最近播放"区域:

- 从 `playProgress` 表获取最近有播放记录的单集
- 显示单集标题、播客名、播放进度百分比、上次播放时间
- 支持一键继续播放（从断点续播）

**API**: 已有 `GET /api/progress/recent` 端点，需确认返回数据满足展示需求。

### 3.6 F6: 标注系统（Annotation System）

**核心思想**: 用户在收听翻译字幕时，能对感兴趣的内容进行高亮、笔记标注，形成个人知识库。

#### 3.6.1 段落级高亮（Segment Highlight）

在 TranscriptPanel（字幕面板）中，用户可以:

| 操作 | 说明 |
|------|------|
| 点击某段字幕高亮 | 一键高亮整个 segment（双语），支持多种颜色（黄、绿、蓝、紫） |
| 自由文本选中高亮 | 鼠标选中翻译文本的任意片段进行高亮 |
| 添加笔记 | 对高亮段落附加自由文本笔记（支持 Markdown） |
| 取消高亮 | 点击已高亮段落的颜色标记取消 |

**交互流程**:

1. 用户在字幕面板中选中文本或点击段落
2. 弹出浮动工具条：`[🟡 高亮] [📝 笔记] [🎨 颜色]`
3. 点击高亮 → 文本背景变色，标注保存到数据库
4. 点击笔记 → 展开行内输入框，输入后保存

#### 3.6.2 笔记面板（Notes Panel）

在单集播放页面右侧或底部增加笔记面板:

- 展示当前集所有标注和笔记的时间线视图
- 点击某条笔记自动跳转到对应的音频时间点
- 支持编辑和删除已有笔记
- 按时间顺序排列（对应音频时间戳）

#### 3.6.3 高亮回顾

新增 `/highlights` 页面（或在 `/library` 下作为 tab）:

- 按播客/单集分组展示所有高亮和笔记
- 支持搜索高亮内容
- 每条高亮显示：原文（英文）+ 译文（中文）+ 笔记 + 时间戳
- 点击可跳转到对应单集的对应时间点继续收听

### 3.7 F7: 知识导出与同步（Export & Sync）

**核心思想**: 将翻译字幕、高亮和笔记导出到用户已有的知识管理工具中，实现跨平台知识沉淀。

#### 3.7.1 导出内容类型

| 内容 | 说明 |
|------|------|
| 完整双语字幕 | 整集翻译稿（含原文 + 译文），按段落排列 |
| 高亮摘录 | 仅导出用户高亮的段落 + 笔记 |
| 笔记汇总 | 仅导出用户的笔记内容 + 上下文引用 |

#### 3.7.2 导出格式

统一使用 **Markdown** 作为中间格式:

```markdown
# {PodcastTitle} - {EpisodeTitle}

> 发布日期: {publishedAt}
> 时长: {duration}
> 导出时间: {exportedAt}

## 高亮 & 笔记

### [00:12:34] 段落标题或首行内容

> 🇺🇸 Original English text here...
> 🇨🇳 中文翻译文本...

📝 **我的笔记**: 用户写的笔记内容

---

### [00:25:10] 另一个高亮段落

> 🇺🇸 Another highlighted segment...
> 🇨🇳 另一个高亮段落...

---

## 完整字幕

[00:00:00] English text / 中文翻译
[00:00:15] English text / 中文翻译
...
```

#### 3.7.3 导出目标平台

**P0 - Obsidian（本地文件）**:
- 方案 A: 通过 `obsidian://` URI Protocol 直接创建笔记（需用户安装 Obsidian）
- 方案 B: 下载 `.md` 文件，用户手动放入 Vault
- 方案 C: 指定 Vault 路径后自动保存（仅限本地部署场景）
- 自动生成 frontmatter（tags, date, source podcast）

**P1 - 飞书文档（Feishu/Lark）**:
- 通过飞书开放平台 API 创建文档
- 需要用户授权 OAuth 登录
- 导出为飞书文档格式（支持富文本、高亮）
- 可选择导出到指定知识库或文件夹

**P2 - 钉钉文档（DingTalk）**:
- 通过钉钉开放平台 API 创建文档
- 需要用户授权 OAuth 登录
- 导出为钉钉文档格式

#### 3.7.4 同步设置

在 `/settings` 页面增加"知识导出"配置区:

| 配置项 | 说明 |
|--------|------|
| 默认导出平台 | 选择 Obsidian / 飞书 / 钉钉 / Markdown 下载 |
| Obsidian Vault 路径 | 本地 Vault 目录（可选） |
| 飞书授权 | OAuth 授权连接 + 目标知识库选择 |
| 钉钉授权 | OAuth 授权连接 + 目标空间选择 |
| 自动导出 | 开关：收听完毕后自动导出高亮和笔记 |
| 导出内容范围 | 仅高亮 / 高亮+笔记 / 完整字幕+高亮+笔记 |

---

## 4. 技术设计概要

### 4.1 数据模型变更

#### Phase 1-3: 无需新增数据库表

队列状态为纯客户端状态（存储在 Zustand store + localStorage 持久化），不需要服务端存储。

#### Phase 4: 新增 `annotations` 表

```
annotations:
  id: text (primary key, nanoid)
  userId: text (FK → users)
  episodeId: text (FK → episodes)
  segmentId: text (FK → transcriptSegments, nullable)
  type: text ('highlight' | 'note')
  color: text ('yellow' | 'green' | 'blue' | 'purple')
  startOffset: integer (nullable, 自由选中时的起始偏移)
  endOffset: integer (nullable, 自由选中时的结束偏移)
  noteContent: text (nullable, Markdown 笔记内容)
  createdAt: text (ISO timestamp)
  updatedAt: text (ISO timestamp)
```

#### Phase 4: 新增 `exportConfigs` 表

```
exportConfigs:
  id: text (primary key)
  userId: text (FK → users)
  platform: text ('obsidian' | 'feishu' | 'dingtalk' | 'markdown')
  config: text (JSON, 平台特定配置如 Vault 路径、OAuth token 等)
  isDefault: integer (boolean)
  createdAt: text
  updatedAt: text
```

#### API 增强

| API | 变更 | 阶段 |
|------|------|------|
| `GET /api/podcasts/subscriptions` | 返回 `latestEpisode` 和 `unheardCount` | Phase 3 ✅ |
| `GET /api/podcasts/[id]/episodes` | 返回 `audioUrl` 字段 | Phase 1 ✅ |
| `GET /api/episodes/feed` | 新增：获取订阅播客最新集 | Phase 1 ✅ |
| `GET /api/progress/recent` | 返回完整 episode + podcast 信息 | Phase 3 ✅ |
| `GET/POST/PUT/DELETE /api/annotations` | 新增：标注 CRUD | Phase 4 |
| `GET /api/episodes/[id]/annotations` | 新增：获取单集所有标注 | Phase 4 |
| `POST /api/export` | 新增：导出到目标平台 | Phase 4 |
| `GET/POST /api/export/config` | 新增：导出配置管理 | Phase 4 |

### 4.2 Store 变更

扩展 `stores/playerStore.ts`:

```typescript
// 新增状态
queue: QueueItem[]
queueIndex: number

// 新增 actions
addToQueue: (item: QueueItem) => void
playNext: (item: QueueItem) => void
removeFromQueue: (index: number) => void
clearQueue: () => void
reorderQueue: (from: number, to: number) => void
skipToNext: () => boolean  // 返回是否有下一首
skipToPrevious: () => boolean
playAll: (items: QueueItem[], startIndex?: number) => void
```

### 4.3 组件变更

| 组件 | 变更内容 | 阶段 |
|------|----------|------|
| `EpisodeRow` | 分离播放按钮和标题链接，增加 audioUrl / podcastTitle / coverUrl props | Phase 1 ✅ |
| `PodcastCard` | 增加最新集信息展示、快速播放按钮、未听 badge | Phase 3 ✅ |
| `PlayBar` | 增加上一首/下一首按钮、队列计数、队列面板入口、点击导航 | Phase 2 ✅ |
| 新增 `QueuePanel` | 侧边/弹出队列管理面板 | Phase 2 ✅ |
| 新增 `ViewToggle` | 网格/列表视图切换组件 | Phase 3 ✅ |
| `SubscriptionsPage` | 集成增强卡片、视图切换、按更新时间排序 | Phase 3 ✅ |
| 新增 `HighlightToolbar` | 浮动标注工具条（高亮、笔记、颜色选择） | Phase 4 |
| `TranscriptPanel` 增强 | 支持文本选中高亮、段落点击标注、高亮渲染 | Phase 4 |
| 新增 `NotesPanel` | 单集笔记面板（时间线视图） | Phase 4 |
| 新增 `HighlightsPage` | 全局高亮回顾页面 | Phase 4 |
| 新增 `ExportButton` | 导出按钮组件（选择平台 + 内容范围） | Phase 4 |
| 新增 `ExportSettings` | 设置页中的导出配置面板 | Phase 4 |

### 4.4 播放生命周期

```
用户点击播放按钮
  → playerStore.loadEpisode() 或 addToQueue()
  → PlayBar 中 useAudioPlayer hook 响应 audioUrl 变化，创建/更新 Audio 元素
  → 播放开始，usePlayProgress 每 5 秒保存进度
  → audio.ended 事件触发
  → playerStore.skipToNext()
    → 有下一首: loadEpisode(queue[queueIndex + 1])
    → 无下一首: 播放停止
```

---

## 5. 用户故事

### US-1: 浏览订阅库中的最新内容

**作为** 已订阅播客的用户
**我想要** 在订阅列表中看到每个播客的最新单集信息和未听数量
**以便** 快速判断哪个播客有新内容值得收听

**验收标准**:
- Given 用户订阅了 3 个播客
- When 打开 `/subscriptions` 页面
- Then 每张播客卡片显示最新集标题、发布时间（相对时间格式）和未听集数 badge
- And 播客按最新集发布时间倒序排列

### US-2: 一键播放单集

**作为** 浏览单集列表的用户
**我想要** 点击播放按钮直接开始播放，而不需要跳转到新页面
**以便** 减少操作步骤，快速开始收听

**验收标准**:
- Given 用户在任意页面看到 EpisodeRow
- When 点击行左侧的播放按钮
- Then PlayBar 出现并开始播放该集音频
- And 页面不发生跳转
- And 播放按钮变为暂停按钮

### US-3: 将单集添加到播放队列

**作为** 想连续收听多集的用户
**我想要** 将感兴趣的单集加入播放队列
**以便** 听完当前这集后自动播放下一集

**验收标准**:
- Given 用户正在浏览单集列表
- When 点击某集的 "Add to Queue" 选项
- Then 该集被追加到播放队列末尾
- And PlayBar 显示队列计数更新（如 "1/3"）
- And 显示 toast 确认 "已添加到队列"

### US-4: 自动连续播放

**作为** 使用播放队列的用户
**我想要** 当前集播放结束后自动播放队列中的下一集
**以便** 实现免手动操作的连续收听体验

**验收标准**:
- Given 队列中有 3 集，当前播放第 1 集
- When 第 1 集播放完毕
- Then 自动加载并播放第 2 集
- And PlayBar 信息更新为第 2 集
- And 队列计数更新为 "2/3"

### US-5: 管理播放队列

**作为** 使用播放队列的用户
**我想要** 查看、调整和管理队列中的内容
**以便** 控制接下来要听什么

**验收标准**:
- Given PlayBar 可见且队列非空
- When 点击队列图标
- Then 弹出队列面板，展示所有队列项
- And 当前播放项有高亮标识
- And 支持拖拽调整顺序
- And 每项有删除按钮
- And 底部有 "清空队列" 按钮

### US-6: 从断点续播最近收听

**作为** 回到应用的用户
**我想要** 快速找到上次在听的内容并从断点继续
**以便** 无缝恢复之前的收听体验

**验收标准**:
- Given 用户之前收听过某集并退出
- When 打开首页
- Then "最近播放" 区域显示有播放记录的单集
- And 每项显示播放进度百分比
- And 点击 "继续播放" 按钮从断点位置开始播放

### US-7: 高亮翻译字幕中的关键段落

**作为** 收听翻译播客的用户
**我想要** 在字幕面板中对感兴趣的段落进行高亮标注
**以便** 在收听过程中标记重要内容，便于日后回顾

**验收标准**:
- Given 用户在字幕面板中浏览翻译内容
- When 选中一段文本或点击某个 segment
- Then 弹出浮动工具条，提供高亮和笔记选项
- And 点击高亮后该段文本背景变为选定颜色
- And 高亮标注保存到数据库，刷新后仍存在

### US-8: 对高亮内容添加笔记

**作为** 收听翻译播客的用户
**我想要** 对高亮的段落添加自由文本笔记
**以便** 记录自己的思考和理解

**验收标准**:
- Given 用户已高亮了某段字幕
- When 点击笔记图标
- Then 展开行内输入框
- And 输入笔记内容后自动保存
- And 笔记面板中同步显示新笔记
- And 点击笔记可跳转到对应音频时间点

### US-9: 导出高亮和笔记到 Obsidian

**作为** 使用 Obsidian 做知识管理的用户
**我想要** 将收听中的高亮和笔记一键导出到 Obsidian
**以便** 将播客学习内容整合进个人知识库

**验收标准**:
- Given 用户在某集中有多条高亮和笔记
- When 点击"导出到 Obsidian"按钮
- Then 生成包含双语高亮段落 + 笔记的 Markdown 文档
- And 通过 `obsidian://` URI 打开 Obsidian 并创建笔记（或下载 .md 文件）
- And 文档包含 frontmatter（tags, date, source）
- And 每条高亮保留时间戳，方便回溯

### US-10: 导出翻译字幕到飞书文档

**作为** 在工作中使用飞书的用户
**我想要** 将翻译后的完整双语字幕导出到飞书文档
**以便** 在团队知识库中分享播客笔记

**验收标准**:
- Given 用户已在设置中授权飞书账号
- When 点击"导出到飞书"按钮并选择目标知识库
- Then 在飞书中创建新文档，包含格式化的双语字幕
- And 高亮段落在飞书文档中以彩色背景显示
- And 笔记内容以引用块形式展示
- And 导出成功后显示飞书文档链接

---

## 6. 交互设计

### 6.1 增强后的订阅列表（网格视图）

```
┌──────────────────────────────────────────────┐
│  My Subscriptions            [⊞ Grid] [☰ List] │
│                                                │
│  [RSS Input ...]                               │
│                                                │
│  ┌─────────────────┐  ┌─────────────────┐     │
│  │ 🖼️ Lex Fridman  │  │ 🖼️ Huberman Lab │     │
│  │ by Lex Fridman  │  │ by Andrew       │     │
│  │                 │  │ Huberman        │     │
│  │ ─ ─ ─ ─ ─ ─ ─  │  │ ─ ─ ─ ─ ─ ─ ─  │     │
│  │ ▶ #428 How AI   │  │ ▶ #312 Sleep &  │     │
│  │   Changes...    │  │   Performance   │     │
│  │   2 days ago    │  │   5 days ago    │     │
│  │          ⓷ new  │  │          ⓵ new  │     │
│  └─────────────────┘  └─────────────────┘     │
└──────────────────────────────────────────────┘
```

### 6.2 增强后的 PlayBar（含队列）

```
┌──────────────────────────────────────────────────────┐
│ ━━━━━━━●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  (进度条)    │
│                                                      │
│ 🖼️  #428 How AI Changes...   ⏮ ▶ ⏭  1.0x   📋 2/5  │
│     Lex Fridman Podcast                              │
└──────────────────────────────────────────────────────┘
```

### 6.3 队列面板

```
┌─────────────────────────────────┐
│  Play Queue               Clear │
│  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │
│  ▶ #428 How AI Changes...   ✕  │ ← 当前播放（高亮）
│    Lex Fridman · 1h 23m        │
│                                 │
│  ☰ #312 Sleep & Performance  ✕  │
│    Huberman Lab · 2h 05m       │
│                                 │
│  ☰ #195 Tim on AI Tools     ✕  │
│    Tim Ferriss · 58m           │
│                                 │
│  ☰ #89 Deep Work            ✕  │
│    All-In · 1h 45m             │
│                                 │
│  ☰ #156 Future of Code      ✕  │
│    Lex Fridman · 2h 10m       │
└─────────────────────────────────┘
```

### 6.4 字幕标注交互

```
┌──────────────────────────────────────────────────────────┐
│  TranscriptPanel                          [📝 Notes] [↗ Export] │
│                                                                  │
│  [00:12:30]                                                     │
│  The key insight here is that neural networks               │
│  █████████████████████████████████████████ ← 高亮段落（黄色背景） │
│  关键的洞见在于，神经网络...                                       │
│                                                                  │
│  ┌────────────────────────────┐ ← 浮动工具条                     │
│  │ 🟡 🟢 🔵 🟣 │ 📝 笔记 │ ✕ │                                  │
│  └────────────────────────────┘                                  │
│                                                                  │
│  📝 我的笔记: 这个观点和 Transformer 论文中的...                   │
│                                                                  │
│  [00:12:45]                                                     │
│  But what's really fascinating is the emergent behavior     │
│  但真正令人着迷的是涌现行为...                                     │
│                                                                  │
└──────────────────────────────────────────────────────────┘
```

### 6.5 导出面板

```
┌─────────────────────────────────┐
│  Export to...             Close │
│  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │
│                                 │
│  Content:                       │
│  ○ Highlights only              │
│  ● Highlights + Notes           │
│  ○ Full transcript + All        │
│                                 │
│  Platform:                      │
│  [🟣 Obsidian]  [📘 飞书]       │
│  [📙 钉钉]      [📄 Download]   │
│                                 │
│  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │
│  [    Export Now    ]           │
│                                 │
└─────────────────────────────────┘
```

---

## 7. 实施优先级

采用分阶段交付策略:

### Phase 1: 快速播放 + EpisodeRow 改造（1 周）✅ 已完成

**价值**: 解决最高频的"播放路径太长"问题，投入产出比最高。

- [x] 改造 `EpisodeRow`，分离播放按钮和导航链接
- [x] API 增强：episodes 列表返回 `audioUrl` + 关联的 podcast 信息
- [x] PlayBar 点击导航到播放详情页
- [x] 首页/播客详情页自动获得快速播放能力

### Phase 2: 播放队列（1 周）✅ 已完成

**价值**: 实现连续播放，提升单次使用时长。

- [x] 扩展 `playerStore` 增加队列状态和操作
- [x] audio `ended` 事件自动播放下一首
- [x] PlayBar 增加上一首/下一首按钮和队列计数
- [x] "Add to Queue" 和 "Play Next" 操作入口
- [x] 队列面板 UI（查看、删除、清空）
- [x] 队列持久化到 localStorage

### Phase 3: 订阅库增强（1 周）✅ 已完成

**价值**: 提升浏览体验，让订阅列表真正有用。

- [x] API 增强：subscriptions 返回 `latestEpisode` 和 `unheardCount`
- [x] `PodcastCard` 增强（最新集信息、未听 badge、快速播放）
- [x] 视图切换（网格/列表）
- [x] 按更新时间排序
- [x] "播放全部" 功能
- [x] "最近播放" 区域

### Phase 4: 标注系统（2 周）🆕

**价值**: 将播客从"听过就忘"升级为"可沉淀的知识输入源"，核心差异化功能。

**Phase 4a: 标注基础（1 周）**

- [ ] 新增 `annotations` 数据库表 + Drizzle schema
- [ ] 标注 CRUD API（`/api/annotations`）
- [ ] `HighlightToolbar` 浮动工具条组件
- [ ] `TranscriptPanel` 增加高亮渲染和交互
- [ ] 段落级高亮（点击 segment 高亮）
- [ ] 自由文本选中高亮
- [ ] 行内笔记输入和保存

**Phase 4b: 笔记回顾 + 导出（1 周）**

- [ ] `NotesPanel` 单集笔记面板
- [ ] `/highlights` 全局高亮回顾页面
- [ ] Markdown 导出生成器
- [ ] Obsidian 导出（URI Protocol + 文件下载）
- [ ] `ExportButton` 组件 + 导出面板 UI
- [ ] 导出配置管理（`/settings` 页面）

### Phase 5: 第三方平台同步（2 周）🆕

**价值**: 打通飞书/钉钉生态，覆盖企业用户的知识管理场景。

- [ ] ExportAdapter 抽象接口设计
- [ ] 飞书 OAuth 授权 + 文档创建 API 集成
- [ ] 钉钉 OAuth 授权 + 文档创建 API 集成
- [ ] 自动导出功能（收听完毕后自动导出）
- [ ] 导出历史记录

---

## 8. 风险与缓解

| 风险 | 影响 | 缓解方案 |
|------|------|----------|
| EpisodeRow 需要更多数据（audioUrl, podcast info），影响现有 API 和数据加载性能 | 中 | ✅ 已解决：通过 JOIN 查询一次性返回 |
| 队列状态丢失（页面刷新） | 中 | ✅ 已解决：Zustand persist middleware |
| 快速播放与字幕页播放器冲突 | 高 | ✅ 已解决：全局单一 PlayerStore 实例 |
| subscriptions API 返回增强数据导致查询变慢 | 低 | ✅ 已解决：单次 JOIN + 子查询 |
| 标注数据量大导致字幕面板渲染卡顿 | 中 | 使用虚拟滚动（只渲染可见区域的高亮），标注数据按需加载 |
| 文本选中交互在不同浏览器中表现不一致 | 中 | 使用 `window.getSelection()` API + 统一的偏移量计算逻辑；提供段落级一键高亮作为后备方案 |
| 飞书/钉钉 OAuth Token 过期 | 中 | 实现 refresh token 自动续期；过期时提示用户重新授权 |
| Obsidian URI Protocol 兼容性 | 低 | 提供 .md 文件下载作为通用后备方案 |
| 标注与字幕翻译更新后的一致性 | 中 | 标注绑定 segmentId（不可变），翻译更新不影响已有标注；自由选中标注存储偏移量，翻译变更时标记为"需要确认" |

### 反模式警示

- **不要把队列存到服务端数据库**: 队列是短暂的会话状态，不是持久化数据。
- **不要在 EpisodeRow 中 fetch audioUrl**: 应在父组件/页面级别获取完整数据，通过 props 传递。
- **不要在标注中存储完整文本内容**: 标注应存储 segmentId + offset 引用，而非复制字幕文本。避免数据冗余和一致性问题。
- **不要在前端存储 OAuth Token**: 飞书/钉钉的 OAuth Token 应存储在服务端，前端只保存 userId 和配置 ID。

---

## 9. 开放问题

| # | 问题 | 建议 | 状态 |
|---|------|------|------|
| 1 | 队列拖拽排序用什么库？ | 推荐 `@dnd-kit/core`，轻量且支持 React 19 | ✅ 已决定 |
| 2 | "未听集数"如何定义？ | `playProgress` 中无记录或 `completed = false` 且 `position < 30s` | ✅ 已决定 |
| 3 | 队列是否需要跨设备同步？ | MVP 阶段不需要，存 localStorage | ✅ 已决定 |
| 4 | 播放完毕是否自动标记为"已听"？ | 播放进度 > 90% 自动标记 `completed = true` | ✅ 已决定 |
| 5 | 列表视图是否需要展示播放进度？ | Phase 3 实现，显示微型进度条 | ✅ 已决定 |
| 6 | 高亮颜色数量和默认色？ | 4 色（黄、绿、蓝、紫），默认黄色 | 待定 |
| 7 | 自由文本选中高亮如何处理跨 segment 选择？ | 建议拆分为多个标注记录，每个 segment 一条；或限制为同一 segment 内选中 | 待定 |
| 8 | 飞书/钉钉应用需要申请哪种权限？ | 飞书需 `docs:doc:create` + `wiki:wiki:create`；钉钉需文档写入权限 | 待定 |
| 9 | 导出 Markdown 模板是否可自定义？ | MVP 阶段使用固定模板；后续支持 Handlebars 模板自定义 | 待定 |
| 10 | 标注是否需要跨设备同步？ | 标注存储在服务端数据库，天然支持同一用户跨设备访问 | ✅ 已决定 |
