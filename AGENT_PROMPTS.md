# Claude Code Agent 任务分配方案

## 总体策略

基于文件依赖分析，将技术方案拆为 **2 轮、共 4 个 Agent**：

```
                  Round 1（可并行）
         ┌──────────────────────────────┐
         │                              │
    Agent A                        Agent B
    Store + Hooks 层               Backend API 层
    (0 文件冲突)                   (0 文件冲突)
         │                              │
         └──────────┬───────────────────┘
                    │
                  Round 2（Round 1 完成后）
         ┌──────────┴───────────────────┐
         │                              │
    Agent C                        Agent D
    播放组件层                      页面 + 订阅库层
    (PlayBar/Queue/EpisodeRow)     (首页/订阅页/详情页/PodcastCard)
         │                              │
         └──────────┬───────────────────┘
                    │
               手动验证 + npm run build
```

**为什么这样拆？**

| 维度 | 说明 |
|------|------|
| 文件冲突 | Round 1 的 A/B 零文件重叠（A 改 stores/ + hooks/，B 改 app/api/）；Round 2 的 C/D 零文件重叠（C 改 components/player/ + components/podcast/EpisodeRow+EpisodeList，D 改 app/ 页面 + components/podcast/PodcastCard+ViewToggle） |
| 依赖方向 | 页面层 → 组件层 → Store/Hook 层 → API 层。Round 2 的组件和页面依赖 Round 1 产出的 Store 接口和 API 接口 |
| 粒度合理性 | 每个 Agent 修改 3-6 个文件，任务量适中，单个 prompt 不会超出上下文窗口 |

---

## Round 1: 并行执行

---

### Agent A: Store + Hooks 层改造

**修改文件**: `stores/playerStore.ts`, `hooks/useAudioPlayer.ts`
**新增文件**: 无
**预计耗时**: 10-15 分钟

````
你是一个 Next.js 全栈开发者。你需要改造 10timesPod（双语字幕播客播放器）的 Zustand Store 和 Audio Hook，为应用增加播放队列能力。

## 项目上下文

技术栈: Next.js 16 + React 19 + TypeScript + Zustand 5 + Tailwind CSS v4
项目根目录: 10timespod/

## 任务清单

### 1. 重构 stores/playerStore.ts

当前的 playerStore 只维护单集播放状态，需要扩展为支持播放队列。

**新增类型**:
```typescript
export interface QueueItem {
  episodeId: string;
  episodeTitle: string;
  audioUrl: string;
  podcastId: string;
  podcastTitle: string;
  coverUrl: string;
  duration?: number | null;
}
```

**PlayerState 新增字段**:
- `podcastId: string | null` — 当前播放集所属播客 ID（PlayBar 导航用）
- `queue: QueueItem[]` — 有序播放队列
- `queueIndex: number` — 当前播放位置，-1 表示不在队列中
- `startPosition: number` — 断点续播位置，加载后自动 seek

**LoadEpisodePayload 新增字段**:
- `podcastId: string` — 必填
- `startPosition?: number` — 可选，断点续播

**新增 Actions**:
- `addToQueue(item: QueueItem)` — 追加到队列末尾
- `playNext(item: QueueItem)` — 插入到 queueIndex + 1 位置
- `removeFromQueue(index: number)` — 移除指定位置项，如果移除的是当前播放项之前的项需要调整 queueIndex
- `clearQueue()` — 清空队列，queueIndex 设为 -1
- `reorderQueue(from: number, to: number)` — 拖拽排序，需正确调整 queueIndex
- `skipToNext(): boolean` — 播放队列下一首，返回是否成功
- `skipToPrevious(): boolean` — 播放队列上一首，返回是否成功
- `playAll(items: QueueItem[], startIndex?: number)` — 加载整个队列并从 startIndex 开始播放
- `playFromQueue(index: number)` — 直接播放队列中指定位置的项

**loadEpisode 语义变更**: 调用 loadEpisode 时清空队列（queue: [], queueIndex: -1），表示"直接播放单集，不使用队列"。

**Zustand persist**: 使用 `zustand/middleware` 的 `persist`，storage 为 localStorage，name 为 `'player-store'`。使用 `partialize` 只持久化以下字段: queue, queueIndex, currentEpisodeId, audioUrl, episodeTitle, podcastId, podcastTitle, coverUrl, currentTime, playbackRate, startPosition。**不要持久化** isPlaying, duration, seekTarget, seekVersion（避免页面刷新后自动播放或状态不一致）。

**reorderQueue 的 queueIndex 调整逻辑**:
- 如果 queueIndex === from: newIndex = to
- 如果 from < queueIndex && to >= queueIndex: newIndex = queueIndex - 1
- 如果 from > queueIndex && to <= queueIndex: newIndex = queueIndex + 1
- 其他情况不变

**removeFromQueue 的 queueIndex 调整逻辑**:
- 如果移除位置 < queueIndex: queueIndex - 1
- 如果移除位置 === queueIndex: 保持不变（让当前播放继续）
- 如果移除位置 > queueIndex: 不变

**使用 create 的函数签名需要支持 get()**:  因为 skipToNext/skipToPrevious 需要读取当前状态，使用 `(set, get) => ({...})`。

### 2. 修改 hooks/useAudioPlayer.ts

当前的 `onEnded` 回调直接调用 `setPlaying(false)`。需要改为：

```typescript
const onEnded = () => {
  const { skipToNext } = usePlayerStore.getState();
  const hasNext = skipToNext();
  if (!hasNext) {
    setPlaying(false);
  }
};
```

同时，在 `onLoadedMetadata` 回调中增加断点续播逻辑：

```typescript
const onLoadedMetadata = () => {
  setDuration(audio.duration);
  const { startPosition } = usePlayerStore.getState();
  if (startPosition && startPosition > 0) {
    audio.currentTime = startPosition;
    setCurrentTime(startPosition);
    // 清除 startPosition 避免重复 seek
    usePlayerStore.setState({ startPosition: 0 });
  }
};
```

## 注意事项

1. 保持所有现有 action 的 API 签名不变（setPlaying, setCurrentTime, setDuration, setPlaybackRate, seekTo, clearEpisode），只新增字段和方法
2. loadEpisode 的参数类型从 `LoadEpisodePayload` 扩展，需要向后兼容（podcastId 改为必填，startPosition 可选默认 0）
3. 使用 `import { create } from 'zustand'` 和 `import { persist } from 'zustand/middleware'`
4. 确保 TypeScript 类型完整，export QueueItem 和 LoadEpisodePayload
5. 改完后运行 `npx tsc --noEmit` 确认无类型错误
````

---

### Agent B: Backend API 层改造

**修改文件**: `app/api/podcasts/subscriptions/route.ts`
**新增文件**: `app/api/episodes/feed/route.ts`
**预计耗时**: 10-15 分钟

````
你是一个 Next.js 全栈开发者。你需要改造 10timesPod（双语字幕播客播放器）的后端 API，为订阅浏览和快速播放功能提供数据支持。

## 项目上下文

技术栈: Next.js 16 + TypeScript + Drizzle ORM + LibSQL (SQLite)
项目根目录: 10timespod/

数据库 schema 定义在 lib/db/schema.ts，主要表:
- podcasts: id, title, description, author, imageUrl, feedUrl
- episodes: id, podcastId, title, description, audioUrl, duration, publishedAt, guid
- subscriptions: userId, podcastId, subscribedAt (复合主键)
- playProgress: userId, episodeId, position, completed, updatedAt (复合主键)

常量: DEMO_USER_ID = 'demo-user' (from lib/constants.ts)

DB 使用方式:
```typescript
import { db, initPromise } from "@/lib/db";
import { podcasts, episodes, subscriptions, playProgress } from "@/lib/db/schema";
import { eq, desc, sql, and, or, gt, inArray } from "drizzle-orm";
```

## 任务清单

### 1. 新增 app/api/episodes/feed/route.ts

创建一个新的 API 端点，一次性返回用户所有订阅播客的最新 episodes，包含播放所需的完整信息。

**GET /api/episodes/feed**

查询逻辑:
1. 获取用户的所有订阅 podcast IDs
2. JOIN episodes + podcasts 表，WHERE episodes.podcastId IN (订阅 IDs)
3. ORDER BY episodes.publishedAt DESC
4. LIMIT 20

返回字段:
```typescript
{
  id: string;              // episode.id
  podcastId: string;       // episode.podcastId
  title: string;           // episode.title
  audioUrl: string;        // episode.audioUrl
  duration: number | null; // episode.duration
  publishedAt: string | null; // episode.publishedAt
  podcastTitle: string;    // podcasts.title
  podcastImageUrl: string | null; // podcasts.imageUrl
}[]
```

如果用户没有订阅任何播客，返回空数组 `[]`。

### 2. 增强 app/api/podcasts/subscriptions/route.ts

当前 API 对每个 subscription 单独查询 podcast（N+1 模式），且不返回最新集和未听数信息。

改造为:

1. 使用 JOIN 一次查询所有订阅的 podcast 信息（替代现有的 Promise.all + 逐个查询）
2. 对每个播客获取最新一集（latestEpisode）
3. 对每个播客计算未听集数（unheardCount）

**最新一集查询**:
```typescript
const latestEpisode = await db
  .select({
    id: episodes.id,
    title: episodes.title,
    audioUrl: episodes.audioUrl,
    publishedAt: episodes.publishedAt,
    duration: episodes.duration,
  })
  .from(episodes)
  .where(eq(episodes.podcastId, podcastId))
  .orderBy(desc(episodes.publishedAt))
  .limit(1)
  .get();
```

**未听集数计算**:
- 总集数：该 podcast 下的 episodes count
- 已听集数：playProgress 表中该 podcast 下 (completed = true OR position > 30) 的记录数
- 未听 = 总 - 已听

返回格式：在现有返回对象基础上增加:
```typescript
{
  // ...现有字段 (id, title, author, description, imageUrl, feedUrl, isSubscribed)
  latestEpisode: {
    id: string;
    title: string;
    audioUrl: string;
    publishedAt: string | null;
    duration: number | null;
  } | null;
  unheardCount: number;
}
```

**排序**: 按 latestEpisode.publishedAt 倒序（有新内容的播客排前面）。

## 注意事项

1. 每个 route handler 开头都要 `await initPromise;` 确保数据库初始化
2. 用 try/catch 包裹，错误返回 `{ error: string }` + status 500
3. inArray 从 drizzle-orm 导入
4. 对于 SQLite 的 and/or 条件，使用 drizzle 的 and() 和 or() 函数
5. 确保 podcastIds 为空时直接返回空数组，不要传空数组给 inArray（会生成 IN () 语法错误）
6. 改完后运行 `npx tsc --noEmit` 确认无类型错误
````

---

## Round 2: Round 1 完成后并行执行

---

### Agent C: 播放组件层改造

**修改文件**: `components/podcast/EpisodeRow.tsx`, `components/podcast/EpisodeList.tsx`, `components/player/PlayBar.tsx`
**新增文件**: `components/player/QueuePanel.tsx`, `components/player/QueueButton.tsx`
**预计耗时**: 20-25 分钟

````
你是一个 Next.js + React 前端开发者。你需要改造 10timesPod（双语字幕播客播放器）的播放相关组件，实现"快速播放"和"播放队列"功能。

## 项目上下文

技术栈: Next.js 16 + React 19 + TypeScript + Zustand 5 + Tailwind CSS v4 + shadcn/ui + Lucide React
项目根目录: 10timespod/
深色主题: 背景 zinc-950/900，文字 zinc-50/100/200，强调色 emerald-500/400

## 前置条件（已由其他 Agent 完成）

playerStore 已扩展，可以这样使用:

```typescript
import { usePlayerStore, type QueueItem } from '@/stores/playerStore';

// 获取状态和 actions
const {
  currentEpisodeId, isPlaying, queue, queueIndex,
  setPlaying, loadEpisode, addToQueue, playNext,
  removeFromQueue, clearQueue, reorderQueue,
  skipToNext, skipToPrevious, playAll, playFromQueue,
  podcastId, // 新增：当前播放集所属播客 ID
} = usePlayerStore();

// loadEpisode 新签名（清空队列，直接播放单集）
loadEpisode({
  id: string,
  title: string,
  audioUrl: string,
  podcastId: string,
  podcastTitle: string,
  coverUrl: string,
  startPosition?: number, // 断点续播
});
```

## 任务清单

### 1. 重构 components/podcast/EpisodeRow.tsx

当前整行是 `<Link>`，改为分离播放按钮和导航链接。

**新增 Props**:
```typescript
interface EpisodeRowProps {
  id: string;
  podcastId: string;
  title: string;
  publishedAt: string | null;
  duration: number | null;
  hasTranscript?: boolean;
  transcriptStatus?: string | null;
  // ---- 新增 ----
  audioUrl?: string;
  podcastTitle?: string;
  coverUrl?: string;
}
```

**新 DOM 结构**:
```
<div className="flex items-center gap-4 px-4 py-3 rounded-lg hover:bg-zinc-800/50 transition-colors group">
  <button onClick={handlePlay}>  ← 播放/暂停按钮
    如果 currentEpisodeId === id && isPlaying → Pause 图标
    如果 currentEpisodeId === id && !isPlaying → Play 图标（有 ring 高亮表示"暂停中"）
    否则 → Play 图标
  </button>
  <Link href={`/podcasts/${podcastId}/episodes/${id}`} className="flex-1 min-w-0">
    <p className="text-sm font-medium text-zinc-200 truncate">{title}</p>
    <div className="flex items-center gap-2 mt-0.5">
      <span className="text-xs text-zinc-500">{formatDate(publishedAt)}</span>
      {duration && <span className="text-xs text-zinc-500">{formatDuration(duration)}</span>}
    </div>
  </Link>
  {/* 右侧：转录 badge + 更多操作 */}
  <div className="flex items-center gap-2">
    {hasTranscript && <badge>...</badge>}
    {audioUrl && (
      <DropdownMenu>  ← 使用 shadcn/ui dropdown-menu
        <DropdownMenuTrigger>
          <MoreHorizontal className="size-4" />  ← 从 lucide-react 导入
        </DropdownMenuTrigger>
        <DropdownMenuContent>
          <DropdownMenuItem onClick={() => playNext(...)}>Play Next</DropdownMenuItem>
          <DropdownMenuItem onClick={() => addToQueue(...)}>Add to Queue</DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
    )}
  </div>
</div>
```

**播放按钮逻辑**:
```typescript
import { usePlayerStore, type QueueItem } from '@/stores/playerStore';
import { useRouter } from 'next/navigation';

const handlePlay = () => {
  const { currentEpisodeId, isPlaying, setPlaying, loadEpisode } = usePlayerStore.getState();
  if (currentEpisodeId === id) {
    setPlaying(!isPlaying);
    return;
  }
  if (!audioUrl) {
    router.push(`/podcasts/${podcastId}/episodes/${id}`);
    return;
  }
  loadEpisode({ id, title, audioUrl, podcastId, podcastTitle: podcastTitle || '', coverUrl: coverUrl || '' });
};
```

**addToQueue / playNext 的 item 构造**:
```typescript
const queueItem: QueueItem = {
  episodeId: id, episodeTitle: title, audioUrl: audioUrl!,
  podcastId, podcastTitle: podcastTitle || '', coverUrl: coverUrl || '', duration,
};
```

点击 "Add to Queue" 和 "Play Next" 后显示 toast（使用 sonner）:
```typescript
import { toast } from 'sonner';
toast.success('Added to queue');
```

### 2. 更新 components/podcast/EpisodeList.tsx

Episode interface 新增可选字段：`audioUrl?: string`, `podcastTitle?: string`, `podcastImageUrl?: string`。

将新字段透传给 EpisodeRow:
```tsx
<EpisodeRow
  key={ep.id}
  {...ep}
  audioUrl={ep.audioUrl}
  podcastTitle={ep.podcastTitle}
  coverUrl={ep.podcastImageUrl}
/>
```

### 3. 增强 components/player/PlayBar.tsx

在现有布局基础上增加:

**左侧封面+标题区域**: 包裹在 Link 中，导航到 `/podcasts/${podcastId}/episodes/${currentEpisodeId}`。podcastId 从 usePlayerStore 获取。

**右侧控件区域新增**（在 SpeedControl 和 Play/Pause 按钮之间或之后）:
- 上一首按钮 `<SkipBack>`: 仅 queue.length > 0 时显示，disabled 当 queueIndex <= 0，onClick → skipToPrevious()
- 下一首按钮 `<SkipForward>`: 仅 queue.length > 0 时显示，disabled 当 queueIndex >= queue.length - 1，onClick → skipToNext()
- 队列按钮 `<QueueButton>`: 显示队列计数，点击展开 QueuePanel

从 lucide-react 导入: `SkipBack, SkipForward, ListMusic`。
从 next/link 导入: `Link`。

### 4. 新增 components/player/QueueButton.tsx

```typescript
interface QueueButtonProps {
  count: number;       // queue.length
  currentIndex: number; // queueIndex + 1（显示用，从 1 开始）
  onClick: () => void;
}
```

渲染: 一个小按钮，显示 ListMusic 图标 + 文本 `{currentIndex}/{count}`（如 "2/5"）。仅 count > 0 时渲染。

### 5. 新增 components/player/QueuePanel.tsx

从 PlayBar 上方弹出的面板（绝对定位 bottom-full，固定在右下角）。

```typescript
interface QueuePanelProps {
  open: boolean;
  onClose: () => void;
}
```

**布局**:
```
<div className="fixed bottom-16 right-4 w-80 max-h-[60vh] bg-zinc-900 border border-zinc-800 rounded-xl shadow-2xl overflow-hidden z-50">
  {/* Header */}
  <div className="flex items-center justify-between px-4 py-3 border-b border-zinc-800">
    <h3 className="text-sm font-semibold text-zinc-200">Play Queue</h3>
    <button onClick={clearQueue} className="text-xs text-zinc-500 hover:text-zinc-300">Clear</button>
  </div>

  {/* Queue List */}
  <ScrollArea className="max-h-[calc(60vh-3rem)]">
    {queue.map((item, index) => (
      <div key={`${item.episodeId}-${index}`}
        className={cn("flex items-center gap-3 px-4 py-2 hover:bg-zinc-800/50",
          index === queueIndex && "bg-emerald-900/20 border-l-2 border-emerald-500"
        )}
      >
        <button onClick={() => playFromQueue(index)}>
          {index === queueIndex && isPlaying ? <Pause size={14}/> : <Play size={14}/>}
        </button>
        <div className="flex-1 min-w-0">
          <p className="text-sm text-zinc-200 truncate">{item.episodeTitle}</p>
          <p className="text-xs text-zinc-500 truncate">{item.podcastTitle}{item.duration ? ` · ${formatDuration(item.duration)}` : ''}</p>
        </div>
        <button onClick={() => removeFromQueue(index)} className="text-zinc-600 hover:text-zinc-400">
          <X size={14}/>
        </button>
      </div>
    ))}
  </ScrollArea>
</div>
```

点击面板外部关闭: 在 PlayBar 中管理 open state，QueuePanel 外层加一个透明 overlay div（onClick → onClose）。

使用 shadcn 的 ScrollArea: `import { ScrollArea } from '@/components/ui/scroll-area'`。

## 样式指南

- 按钮 hover: `hover:bg-zinc-800/50` 或 `hover:text-zinc-200`
- 当前播放项高亮: `bg-emerald-900/20 border-l-2 border-emerald-500`
- 禁用状态: `opacity-40 cursor-not-allowed`
- 播放按钮圆形: `w-8 h-8 rounded-full bg-zinc-800 flex items-center justify-center`
- 图标大小统一: PlayBar 用 size={16}，EpisodeRow 用 `w-3.5 h-3.5`

## 注意事项

1. 所有组件都是 'use client'
2. 使用 shadcn/ui 已有组件: dropdown-menu, scroll-area, button, badge
3. 从 lucide-react 导入图标: Play, Pause, SkipBack, SkipForward, ListMusic, X, MoreHorizontal
4. toast 使用 sonner: `import { toast } from 'sonner'`
5. 工具函数: `import { formatDuration, formatDate, cn } from '@/lib/utils'`
6. 改完后运行 `npx tsc --noEmit` 确认无类型错误
````

---

### Agent D: 页面层 + 订阅库增强

**修改文件**: `app/page.tsx`, `app/subscriptions/page.tsx`, `app/podcasts/[id]/page.tsx`, `components/podcast/PodcastCard.tsx`
**新增文件**: `components/podcast/ViewToggle.tsx`
**预计耗时**: 20-25 分钟

````
你是一个 Next.js + React 前端开发者。你需要改造 10timesPod（双语字幕播客播放器）的页面层，连接增强后的 API 和组件，实现订阅库浏览增强和快速播放入口。

## 项目上下文

技术栈: Next.js 16 + React 19 + TypeScript + Zustand 5 + Tailwind CSS v4 + shadcn/ui + Lucide React
项目根目录: 10timespod/
深色主题: 背景 zinc-950/900，文字 zinc-50/100/200，强调色 emerald-500/400

## 前置条件（已由其他 Agent 完成）

1. **新增 API**: `GET /api/episodes/feed` 返回:
```typescript
{ id, podcastId, title, audioUrl, duration, publishedAt, podcastTitle, podcastImageUrl }[]
```

2. **增强 API**: `GET /api/podcasts/subscriptions` 返回:
```typescript
{
  id, title, author, description, imageUrl, feedUrl, isSubscribed,
  latestEpisode: { id, title, audioUrl, publishedAt, duration } | null,
  unheardCount: number
}[]
```

3. **EpisodeRow** 已支持新 props: `audioUrl?: string`, `podcastTitle?: string`, `coverUrl?: string`（传入后可直接在列表中播放，无需跳转）

4. **EpisodeList** 已支持新 Episode 字段: `audioUrl`, `podcastTitle`, `podcastImageUrl`

5. **playerStore** 已支持: `loadEpisode({ id, title, audioUrl, podcastId, podcastTitle, coverUrl, startPosition? })`

## 任务清单

### 1. 重构 app/page.tsx（首页）

**当前问题**: 首页用 N+1 循环获取每个订阅播客的 episodes，缺少 audioUrl 和 podcast 信息。

**改造方案**: 使用新的 `/api/episodes/feed` API 替换现有的循环获取逻辑。

```typescript
// 替换现有的 recentEpisodes fetch 逻辑
const feedRes = await fetch('/api/episodes/feed');
const feedData = await feedRes.json();
setRecentEpisodes(Array.isArray(feedData) ? feedData : []);
```

recentEpisodes 的 interface 更新为:
```typescript
interface EpisodeData {
  id: string;
  podcastId: string;
  title: string;
  audioUrl: string;      // 新增
  publishedAt: string | null;
  duration: number | null;
  podcastTitle: string;    // 新增
  podcastImageUrl: string | null; // 新增
}
```

在渲染 EpisodeRow 时传递新 props:
```tsx
<EpisodeRow
  key={ep.id}
  id={ep.id}
  podcastId={ep.podcastId}
  title={ep.title}
  publishedAt={ep.publishedAt}
  duration={ep.duration}
  audioUrl={ep.audioUrl}
  podcastTitle={ep.podcastTitle}
  coverUrl={ep.podcastImageUrl}
/>
```

**新增"最近播放"区域**: 在 Latest Episodes 之后，增加 "Recently Played" section:

```typescript
const [recentPlayed, setRecentPlayed] = useState([]);

// fetch 最近播放（在 fetchData 中增加）
const recentRes = await fetch('/api/progress/recent');
const recentData = await recentRes.json();
setRecentPlayed(Array.isArray(recentData) ? recentData : []);
```

`/api/progress/recent` 已有，返回格式:
```typescript
{
  episodeId, position, completed, updatedAt,
  episodeTitle, audioUrl, duration, podcastId, podcastTitle, podcastImageUrl
}[]
```

渲染为 EpisodeRow 列表，传入所有新 props（注意字段名映射：episodeId → id, episodeTitle → title 等）。仅当 recentPlayed.length > 0 且有未完成的项时显示该 section。

### 2. 改造 app/podcasts/[id]/page.tsx（播客详情页）

**当前问题**: EpisodeData interface 没有声明 audioUrl 字段，也没有传递 podcast 信息给 EpisodeRow/EpisodeList。

改造:

1. EpisodeData interface 新增: `audioUrl: string`（API 已返回该字段，只是 interface 没声明）

2. 在传递给 EpisodeList 的 episodes 数组中，每项补充 podcast 信息:
```typescript
const enrichedEpisodes = episodes.map(ep => ({
  ...ep,
  podcastTitle: podcast?.title,
  podcastImageUrl: podcast?.imageUrl,
}));
```

3. 在 Episodes header 右侧增加 "Play All" 按钮:
```tsx
import { usePlayerStore, type QueueItem } from '@/stores/playerStore';
import { Play } from 'lucide-react';

const handlePlayAll = () => {
  const items: QueueItem[] = episodes.map(ep => ({
    episodeId: ep.id,
    episodeTitle: ep.title,
    audioUrl: ep.audioUrl,
    podcastId: id,
    podcastTitle: podcast?.title || '',
    coverUrl: podcast?.imageUrl || '',
    duration: ep.duration,
  }));
  usePlayerStore.getState().playAll(items, 0);
};

// 渲染
<div className="flex items-center justify-between mb-4">
  <h2 className="text-lg font-semibold text-zinc-200">Episodes</h2>
  {episodes.length > 0 && (
    <button onClick={handlePlayAll}
      className="text-sm text-emerald-500 hover:text-emerald-400 flex items-center gap-1">
      <Play size={14} /> Play All
    </button>
  )}
</div>
```

### 3. 增强 components/podcast/PodcastCard.tsx

**新增 Props**:
```typescript
interface PodcastCardProps {
  // ...现有 props...
  latestEpisode?: {
    id: string;
    title: string;
    audioUrl: string;
    publishedAt: string | null;
    duration: number | null;
  } | null;
  unheardCount?: number;
}
```

**新增渲染**: 在现有卡片底部（subscribe 按钮上方）增加最新集信息区域:

```tsx
{latestEpisode && (
  <div className="mt-3 pt-3 border-t border-zinc-800/50">
    <div className="flex items-center gap-2">
      <button
        onClick={(e) => {
          e.preventDefault();
          e.stopPropagation();
          usePlayerStore.getState().loadEpisode({
            id: latestEpisode.id,
            title: latestEpisode.title,
            audioUrl: latestEpisode.audioUrl,
            podcastId: id,
            podcastTitle: title,
            coverUrl: imageUrl || '',
          });
        }}
        className="w-6 h-6 rounded-full bg-emerald-600 hover:bg-emerald-500 flex items-center justify-center shrink-0"
      >
        <Play size={12} className="text-white ml-0.5" />
      </button>
      <div className="flex-1 min-w-0">
        <p className="text-xs text-zinc-300 truncate">{latestEpisode.title}</p>
        <p className="text-xs text-zinc-500">{formatDate(latestEpisode.publishedAt)}</p>
      </div>
      {unheardCount != null && unheardCount > 0 && (
        <span className="text-xs bg-emerald-900/50 text-emerald-400 px-1.5 py-0.5 rounded-full shrink-0">
          {unheardCount} new
        </span>
      )}
    </div>
  </div>
)}
```

需要导入: `import { usePlayerStore } from '@/stores/playerStore'`, `import { Play } from 'lucide-react'`, `import { formatDate } from '@/lib/utils'`。

### 4. 重构 app/subscriptions/page.tsx

**改造内容**:

1. 使用增强后的 subscriptions API 数据:
```typescript
interface PodcastData {
  id: string;
  title: string;
  author: string | null;
  description: string | null;
  imageUrl: string | null;
  feedUrl: string;
  isSubscribed: boolean;
  latestEpisode: { id: string; title: string; audioUrl: string; publishedAt: string | null; duration: number | null; } | null;
  unheardCount: number;
}
```

2. 传递新 props 给 PodcastCard:
```tsx
<PodcastCard
  key={podcast.id}
  {...podcast}
  latestEpisode={podcast.latestEpisode}
  unheardCount={podcast.unheardCount}
  onSubscriptionChange={...}
/>
```

3. 增加视图切换（网格/列表）:
```tsx
import { ViewToggle } from '@/components/podcast/ViewToggle';

const [viewMode, setViewMode] = useState<'grid' | 'list'>(() => {
  if (typeof window !== 'undefined') {
    return (localStorage.getItem('subscription-view-mode') as 'grid' | 'list') || 'grid';
  }
  return 'grid';
});

useEffect(() => {
  localStorage.setItem('subscription-view-mode', viewMode);
}, [viewMode]);
```

4. 页面标题区域增加视图切换:
```tsx
<div className="flex items-center justify-between">
  <h1 className="text-2xl font-bold text-zinc-50">My Subscriptions</h1>
  <ViewToggle value={viewMode} onChange={setViewMode} />
</div>
```

5. 列表视图渲染（viewMode === 'list' 时）:
```tsx
<div className="space-y-1 bg-zinc-900 border border-zinc-800 rounded-xl overflow-hidden">
  {podcasts.map(podcast => (
    <div key={podcast.id} className="flex items-center gap-4 px-4 py-3 hover:bg-zinc-800/50 transition-colors">
      {podcast.imageUrl ? (
        <img src={podcast.imageUrl} alt={podcast.title} className="w-12 h-12 rounded-lg object-cover shrink-0" />
      ) : (
        <div className="w-12 h-12 rounded-lg bg-zinc-800 shrink-0" />
      )}
      <Link href={`/podcasts/${podcast.id}`} className="flex-1 min-w-0">
        <p className="text-sm font-medium text-zinc-200 truncate">{podcast.title}</p>
        <p className="text-xs text-zinc-500 truncate">
          {podcast.latestEpisode?.title || 'No episodes yet'}
        </p>
      </Link>
      {podcast.latestEpisode && (
        <>
          <span className="text-xs text-zinc-500 shrink-0">
            {formatDate(podcast.latestEpisode.publishedAt)}
          </span>
          <button
            onClick={() => usePlayerStore.getState().loadEpisode({
              id: podcast.latestEpisode!.id,
              title: podcast.latestEpisode!.title,
              audioUrl: podcast.latestEpisode!.audioUrl,
              podcastId: podcast.id,
              podcastTitle: podcast.title,
              coverUrl: podcast.imageUrl || '',
            })}
            className="w-8 h-8 rounded-full bg-zinc-800 hover:bg-zinc-700 flex items-center justify-center shrink-0"
          >
            <Play size={14} className="text-zinc-300 ml-0.5" />
          </button>
        </>
      )}
      {podcast.unheardCount > 0 && (
        <span className="text-xs bg-emerald-900/50 text-emerald-400 px-1.5 py-0.5 rounded-full shrink-0">
          {podcast.unheardCount}
        </span>
      )}
    </div>
  ))}
</div>
```

### 5. 新增 components/podcast/ViewToggle.tsx

```typescript
'use client';
import { LayoutGrid, List } from 'lucide-react';
import { cn } from '@/lib/utils';

type ViewMode = 'grid' | 'list';

interface ViewToggleProps {
  value: ViewMode;
  onChange: (mode: ViewMode) => void;
}

export function ViewToggle({ value, onChange }: ViewToggleProps) {
  return (
    <div className="flex items-center border border-zinc-800 rounded-lg overflow-hidden">
      <button
        onClick={() => onChange('grid')}
        className={cn(
          'p-1.5 transition-colors',
          value === 'grid' ? 'bg-zinc-800 text-zinc-200' : 'text-zinc-500 hover:text-zinc-300'
        )}
        title="Grid view"
      >
        <LayoutGrid size={16} />
      </button>
      <button
        onClick={() => onChange('list')}
        className={cn(
          'p-1.5 transition-colors',
          value === 'list' ? 'bg-zinc-800 text-zinc-200' : 'text-zinc-500 hover:text-zinc-300'
        )}
        title="List view"
      >
        <List size={16} />
      </button>
    </div>
  );
}
```

## 注意事项

1. 所有页面和组件都是 'use client'
2. app/podcasts/[id]/page.tsx 使用 `use(params)` 获取路由参数（React 19 方式）
3. PodcastCard 内部的快速播放按钮需要 `e.preventDefault(); e.stopPropagation()` 阻止 Link 导航
4. 列表视图中的图片用 `<img>` 标签（动态外部 src）
5. 从 next/link 导入 Link 用于导航
6. 改完后运行 `npx tsc --noEmit` 确认无类型错误，再运行 `npm run build` 确认编译通过
````

---

## 执行步骤总结

```
Step 1: 同时启动 Agent A 和 Agent B（并行，约 15 分钟）
   ↓
Step 2: 两个都完成后，运行 npx tsc --noEmit 验证 Round 1 无类型错误
   ↓
Step 3: 同时启动 Agent C 和 Agent D（并行，约 25 分钟）
   ↓
Step 4: 两个都完成后，运行:
   - npx tsc --noEmit  （类型检查）
   - npm run build     （全量编译）
   - npm run dev → 手动测试核心流程
```

### 手动测试清单（Step 4）

- [ ] 首页 Latest Episodes → 点击播放按钮 → PlayBar 出现并播放（不跳转页面）
- [ ] 首页 EpisodeRow → 点击标题 → 导航到详情页
- [ ] 首页 Recently Played → 显示有进度的集 → 点击继续播放
- [ ] 播客详情页 → Play All → 队列加载所有集 → 连续播放
- [ ] EpisodeRow → 更多菜单 → Add to Queue → toast 确认 → PlayBar 队列计数更新
- [ ] PlayBar → 下一首/上一首 → 切换正常
- [ ] PlayBar → 队列图标 → QueuePanel 弹出 → 删除/清空/点击播放
- [ ] PlayBar → 点击封面/标题 → 导航到详情页
- [ ] 订阅列表 → 显示最新集 + 未听 badge
- [ ] 订阅列表 → 快速播放按钮 → 播放最新集
- [ ] 订阅列表 → 网格/列表视图切换 → 刷新后偏好保留
- [ ] 播完一集 → 自动播放队列下一集
- [ ] 页面刷新 → 队列恢复 → 手动点击播放 → 从断点续播
