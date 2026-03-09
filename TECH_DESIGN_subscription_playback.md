# 技术方案：订阅浏览、播放队列与知识管理

> 对应 PRD: `PRD-subscription-playback.md`
> 项目: 10timesPod
> 日期: 2026-03-08 | 状态: Draft (Phase 1-3 已实现，Phase 4-5 新增)

---

## 1. 现有架构分析

### 1.1 技术栈现状

| 层级 | 技术 | 版本 |
|------|------|------|
| 框架 | Next.js (App Router) | 16.1.6 |
| 语言 | TypeScript + React | React 19.2.3 |
| 状态管理 | Zustand | 5.0.11 |
| 数据库 | LibSQL (本地 SQLite) | Drizzle ORM |
| UI | Tailwind CSS v4 + shadcn/ui | - |
| 图标 | Lucide React | - |

### 1.2 当前数据流分析

```
订阅流程（已实现）:
  RSSInput → POST /api/podcasts/subscribe → rss-parser 解析 → 写入 podcasts + episodes 表
                                         → 写入 subscriptions 表

播放流程（已实现但路径过长）:
  EpisodeRow <Link> → /podcasts/[id]/episodes/[episodeId] 页面
                    → fetch /api/episodes/[id]
                    → playerStore.loadEpisode()
                    → useAudioPlayer hook 创建 Audio 元素
                    → PlayBar 渲染播放控件

断裂点:
  1. EpisodeRow 是纯 <Link>，无法直接触发播放
  2. playerStore 无 queue 概念，ended 事件直接 setPlaying(false)
  3. subscriptions API 只返回 podcast 基本信息，无最新集/未听数
  4. episodes API 的返回数据不含 audioUrl（EpisodeRow 未传递）
```

### 1.3 需要变更的文件清单

```
=== Phase 1-3（已实现） ===

stores/
  playerStore.ts              ← ✅ 核心重构：增加 queue + persist

hooks/
  useAudioPlayer.ts           ← ✅ 修改 onEnded 回调
  usePlayProgress.ts          ← 不变

components/
  player/
    PlayBar.tsx               ← ✅ 增加导航、上下首、队列入口
    QueuePanel.tsx            ← ✅ 新增
    QueueButton.tsx           ← ✅ 新增
  podcast/
    EpisodeRow.tsx            ← ✅ 核心重构：分离播放按钮
    EpisodeList.tsx           ← ✅ 传递新 props
    PodcastCard.tsx           ← ✅ 增加最新集信息
    ViewToggle.tsx            ← ✅ 新增

app/
  page.tsx                    ← ✅ 首页数据获取调整
  subscriptions/page.tsx      ← ✅ 增强布局
  podcasts/[id]/page.tsx      ← ✅ 传递 audioUrl + podcast 信息
  api/
    podcasts/subscriptions/route.ts  ← ✅ 增强返回数据
    podcasts/[id]/episodes/route.ts  ← ✅ 返回 audioUrl

=== Phase 4-5（待实现） ===

lib/
  db/schema.ts                ← 新增 annotations + exportConfigs 表
  export/
    types.ts                  ← ExportAdapter 接口
    registry.ts               ← Adapter 注册
    markdown-generator.ts     ← Markdown 生成
    adapters/*.ts             ← 各平台适配器

stores/
  annotationStore.ts          ← 新增标注状态管理

hooks/
  useTextSelection.ts         ← 新增文本选中检测

components/
  transcript/
    HighlightedSegment.tsx    ← 新增高亮段落
    HighlightToolbar.tsx      ← 新增浮动工具条
    NotesPanel.tsx            ← 新增笔记面板
  export/
    ExportButton.tsx          ← 新增导出按钮
    ExportSettings.tsx        ← 新增导出配置

app/
  highlights/page.tsx         ← 新增高亮回顾页
  api/annotations/            ← 新增标注 CRUD API
  api/export/                 ← 新增导出 API
  api/auth/feishu/            ← 新增飞书 OAuth
  api/auth/dingtalk/          ← 新增钉钉 OAuth
```

---

## 2. Phase 1: 快速播放（EpisodeRow 改造）✅ 已实现

### 2.1 EpisodeRow 组件重构

**当前问题**: 整个 `EpisodeRow` 是一个 `<Link>`，播放图标是装饰性的 SVG，无法直接触发播放。

**方案**: 将组件拆分为"播放按钮"和"导航链接"两个独立交互区域。

```typescript
// components/podcast/EpisodeRow.tsx — 重构后

interface EpisodeRowProps {
  id: string;
  podcastId: string;
  title: string;
  publishedAt: string | null;
  duration: number | null;
  hasTranscript?: boolean;
  transcriptStatus?: string | null;
  // ---- 新增 props ----
  audioUrl?: string;              // 直接播放所需
  podcastTitle?: string;          // loadEpisode 所需
  coverUrl?: string;              // loadEpisode 所需
  onAddToQueue?: (item: QueueItem) => void;  // Phase 2
}
```

**关键设计决策**:

1. **事件冒泡隔离**: 播放按钮使用 `e.stopPropagation()` + `e.preventDefault()` 阻止触发外层 Link 的导航。但实际上我们不再用 Link 包裹整行，而是只在标题区域放 Link。

2. **播放状态判断**: 通过 `usePlayerStore` 的 `currentEpisodeId` 判断当前行是否正在播放，决定显示 Play 还是 Pause 图标。

3. **无 audioUrl 的降级**: 如果父组件没有传递 `audioUrl`（如旧代码路径），播放按钮点击时 fallback 为导航到详情页。

**改造后的 DOM 结构**:

```
<div className="flex items-center gap-4 ...">      ← 外层容器（非 Link）
  <button onClick={handlePlay}>                     ← 播放/暂停按钮
    <PlayIcon /> 或 <PauseIcon />
  </button>
  <Link href={`/podcasts/${podcastId}/episodes/${id}`}>  ← 仅标题可导航
    <p>{title}</p>
    <span>{date} · {duration}</span>
  </Link>
  <div>                                             ← 右侧操作区（Phase 2: 更多菜单）
    {transcriptBadge}
  </div>
</div>
```

**播放逻辑伪代码**:

```typescript
const handlePlay = (e: React.MouseEvent) => {
  e.stopPropagation();

  const { currentEpisodeId, isPlaying, setPlaying, loadEpisode } = usePlayerStore.getState();

  if (currentEpisodeId === id) {
    // 当前集：切换播放/暂停
    setPlaying(!isPlaying);
    return;
  }

  if (!audioUrl) {
    // 无 audioUrl，降级为导航
    router.push(`/podcasts/${podcastId}/episodes/${id}`);
    return;
  }

  // 加载并播放新集
  loadEpisode({
    id,
    title,
    audioUrl,
    podcastTitle: podcastTitle || '',
    coverUrl: coverUrl || '',
  });
};
```

### 2.2 Episodes API 增强

**当前问题**: `GET /api/podcasts/[id]/episodes` 的返回数据虽然包含 `audioUrl`（因为 `select()` 是全字段），但 `EpisodeRow` 组件的 `EpisodeRowProps` 接口没有声明 `audioUrl` prop，父组件也没有传递它。

**方案**: 确认 API 已返回 `audioUrl`，在父组件层面传递给 `EpisodeRow`。

**文件变更**:

```
app/podcasts/[id]/page.tsx     — 传递 ep.audioUrl, podcast.title, podcast.imageUrl
app/page.tsx                   — 首页 recentEpisodes 需要补充 audioUrl + podcast info
components/podcast/EpisodeList.tsx — Episode interface 增加 audioUrl 等字段
```

#### 首页数据获取优化

当前首页通过 N+1 方式逐个获取每个订阅播客的 episodes。需要确保返回的 episode 包含 audioUrl 和所属 podcast 的 title/imageUrl。

**方案 A（推荐）**: 新增一个 `/api/episodes/feed` API，一次性返回用户所有订阅播客的最新 episodes，包含 podcast 信息：

```typescript
// app/api/episodes/feed/route.ts — 新增

export async function GET() {
  const userId = DEMO_USER_ID;

  // 获取用户订阅的所有 podcast IDs
  const subs = await db
    .select({ podcastId: subscriptions.podcastId })
    .from(subscriptions)
    .where(eq(subscriptions.userId, userId));

  const podcastIds = subs.map(s => s.podcastId);
  if (podcastIds.length === 0) return NextResponse.json([]);

  // 一次 JOIN 查询获取最新 episodes + podcast 信息
  const results = await db
    .select({
      id: episodes.id,
      podcastId: episodes.podcastId,
      title: episodes.title,
      audioUrl: episodes.audioUrl,
      duration: episodes.duration,
      publishedAt: episodes.publishedAt,
      podcastTitle: podcasts.title,
      podcastImageUrl: podcasts.imageUrl,
    })
    .from(episodes)
    .innerJoin(podcasts, eq(episodes.podcastId, podcasts.id))
    .where(inArray(episodes.podcastId, podcastIds))
    .orderBy(desc(episodes.publishedAt))
    .limit(20);

  return NextResponse.json(results);
}
```

**方案 B**: 在现有的 N+1 循环中，每个 episode 响应里附带 podcast 信息。但这不够优雅，且查询效率差。

**选择**: 方案 A，新增 `/api/episodes/feed` 端点。

### 2.3 PlayBar 点击导航

当前 PlayBar 的封面和标题区域没有交互性。增加 Link 包裹：

```typescript
// components/player/PlayBar.tsx

import Link from 'next/link';

// 在 "Left: cover + title" 区域
<Link
  href={currentEpisodeId
    ? `/podcasts/${podcastId}/episodes/${currentEpisodeId}`
    : '#'}
  className="flex items-center gap-3 flex-1 min-w-0"
>
  {/* coverUrl + title + podcastTitle */}
</Link>
```

**问题**: playerStore 当前不存储 `podcastId`，PlayBar 无法构造导航 URL。

**方案**: 在 `LoadEpisodePayload` 和 `PlayerState` 中增加 `podcastId` 字段：

```typescript
// stores/playerStore.ts 变更

export interface LoadEpisodePayload {
  id: string;
  title: string;
  audioUrl: string;
  podcastId: string;      // ← 新增
  podcastTitle: string;
  coverUrl: string;
}

interface PlayerState {
  // ...existing fields...
  podcastId: string | null;  // ← 新增
}
```

这个变更影响所有调用 `loadEpisode` 的地方（EpisodePage、EpisodeRow、未来的 QueuePanel），需要传入 `podcastId`。

---

## 3. Phase 2: 播放队列 ✅ 已实现

### 3.1 PlayerStore 队列扩展

这是本次改造最核心的变更。

```typescript
// stores/playerStore.ts — 完整类型定义

export interface QueueItem {
  episodeId: string;
  episodeTitle: string;
  audioUrl: string;
  podcastId: string;
  podcastTitle: string;
  coverUrl: string;
  duration?: number | null;
}

interface PlayerState {
  // ===== 现有状态（不变） =====
  currentEpisodeId: string | null;
  isPlaying: boolean;
  currentTime: number;
  duration: number;
  playbackRate: number;
  audioUrl: string | null;
  episodeTitle: string;
  podcastId: string | null;       // ← Phase 1 新增
  podcastTitle: string;
  coverUrl: string;
  seekTarget: number | null;
  seekVersion: number;

  // ===== 队列状态（新增） =====
  queue: QueueItem[];
  queueIndex: number;             // -1 表示当前播放项不在队列中

  // ===== 现有 Actions（不变） =====
  setPlaying: (playing: boolean) => void;
  setCurrentTime: (time: number) => void;
  setDuration: (duration: number) => void;
  setPlaybackRate: (rate: number) => void;
  seekTo: (time: number) => void;
  clearEpisode: () => void;

  // ===== loadEpisode 语义变更 =====
  loadEpisode: (episode: LoadEpisodePayload) => void;
  // 行为变更：清空队列，只播放该集

  // ===== 队列 Actions（新增） =====
  addToQueue: (item: QueueItem) => void;
  playNext: (item: QueueItem) => void;
  removeFromQueue: (index: number) => void;
  clearQueue: () => void;
  reorderQueue: (from: number, to: number) => void;
  skipToNext: () => boolean;      // 返回值：是否有下一首
  skipToPrevious: () => boolean;
  playAll: (items: QueueItem[], startIndex?: number) => void;
  playFromQueue: (index: number) => void;  // 直接播放队列中的某项
}
```

### 3.2 队列操作实现细节

#### loadEpisode（语义变更）

```typescript
loadEpisode: (episode) => set({
  currentEpisodeId: episode.id,
  audioUrl: episode.audioUrl,
  episodeTitle: episode.title,
  podcastId: episode.podcastId,
  podcastTitle: episode.podcastTitle,
  coverUrl: episode.coverUrl,
  currentTime: 0,
  duration: 0,
  isPlaying: true,
  // 清空队列
  queue: [],
  queueIndex: -1,
}),
```

#### addToQueue

```typescript
addToQueue: (item) => set((state) => ({
  queue: [...state.queue, item],
})),
```

#### playNext（插入到当前播放位置的下一个）

```typescript
playNext: (item) => set((state) => {
  const insertAt = state.queueIndex >= 0
    ? state.queueIndex + 1
    : 0;
  const newQueue = [...state.queue];
  newQueue.splice(insertAt, 0, item);
  return { queue: newQueue };
}),
```

#### skipToNext（核心：自动连续播放的触发点）

```typescript
skipToNext: () => {
  const state = get();
  const nextIndex = state.queueIndex + 1;

  if (nextIndex >= state.queue.length) {
    // 队列已播完
    return false;
  }

  const next = state.queue[nextIndex];
  set({
    currentEpisodeId: next.episodeId,
    audioUrl: next.audioUrl,
    episodeTitle: next.episodeTitle,
    podcastId: next.podcastId,
    podcastTitle: next.podcastTitle,
    coverUrl: next.coverUrl,
    currentTime: 0,
    duration: 0,
    isPlaying: true,
    queueIndex: nextIndex,
  });
  return true;
},
```

#### playAll

```typescript
playAll: (items, startIndex = 0) => {
  if (items.length === 0) return;
  const first = items[startIndex];
  set({
    currentEpisodeId: first.episodeId,
    audioUrl: first.audioUrl,
    episodeTitle: first.episodeTitle,
    podcastId: first.podcastId,
    podcastTitle: first.podcastTitle,
    coverUrl: first.coverUrl,
    currentTime: 0,
    duration: 0,
    isPlaying: true,
    queue: items,
    queueIndex: startIndex,
  });
},
```

#### reorderQueue（拖拽排序）

```typescript
reorderQueue: (from, to) => set((state) => {
  const newQueue = [...state.queue];
  const [moved] = newQueue.splice(from, 1);
  newQueue.splice(to, 0, moved);

  // 调整 queueIndex
  let newIndex = state.queueIndex;
  if (state.queueIndex === from) {
    newIndex = to;
  } else if (from < state.queueIndex && to >= state.queueIndex) {
    newIndex = state.queueIndex - 1;
  } else if (from > state.queueIndex && to <= state.queueIndex) {
    newIndex = state.queueIndex + 1;
  }

  return { queue: newQueue, queueIndex: newIndex };
}),
```

### 3.3 Zustand Persist Middleware

队列状态需要在页面刷新后恢复。使用 Zustand 内置的 `persist` middleware：

```typescript
import { create } from 'zustand';
import { persist } from 'zustand/middleware';

export const usePlayerStore = create<PlayerState>()(
  persist(
    (set, get) => ({
      // ...所有状态和 actions
    }),
    {
      name: 'player-store',
      // 只持久化部分字段，排除运行时状态
      partialize: (state) => ({
        queue: state.queue,
        queueIndex: state.queueIndex,
        currentEpisodeId: state.currentEpisodeId,
        audioUrl: state.audioUrl,
        episodeTitle: state.episodeTitle,
        podcastId: state.podcastId,
        podcastTitle: state.podcastTitle,
        coverUrl: state.coverUrl,
        currentTime: state.currentTime,
        playbackRate: state.playbackRate,
        // 不持久化: isPlaying, duration, seekTarget, seekVersion
      }),
    }
  )
);
```

**注意**: 恢复时 `isPlaying` 默认 false，不会自动恢复播放。用户需要手动点击播放。这是有意为之——避免页面刷新后突然出声。

### 3.4 useAudioPlayer Hook 变更

**核心变更点**: `onEnded` 回调从 `setPlaying(false)` 改为尝试 `skipToNext()`。

```typescript
// hooks/useAudioPlayer.ts

const onEnded = () => {
  const { skipToNext } = usePlayerStore.getState();
  const hasNext = skipToNext();
  if (!hasNext) {
    setPlaying(false);
  }
  // 如果 skipToNext 成功，会自动 set isPlaying: true
  // 并更新 audioUrl，触发下方的 audioUrl 变更 effect
};
```

**audioUrl 变更 effect 调整**: 当 `skipToNext` 更新 audioUrl 时，需要确保 Audio 元素加载新 src 并开始播放：

```typescript
// 当前已有的 effect，无需修改
useEffect(() => {
  const audio = audioRef.current;
  if (!audio || !audioUrl) return;
  audio.src = audioUrl;
  audio.load();
}, [audioUrl]);
```

这个 effect 会因为 audioUrl 变化而触发，自动加载新音频。配合 `isPlaying` 为 true 的 effect，音频会自动开始播放。

### 3.5 PlayBar 增强

#### 新增控件布局

```
┌──────────────────────────────────────────────────────────┐
│ ━━━━●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  (ProgressBar)     │
│                                                          │
│ [封面+标题 Link]       [1.0x] [⏮] [▶] [⏭]  [📋 2/5]   │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

**条件渲染逻辑**:

- 上一首 `⏮` / 下一首 `⏭`: 仅当 `queue.length > 0` 时显示
- 队列计数 `📋 2/5`: 仅当 `queue.length > 0` 时显示，点击展开 QueuePanel
- 上一首灰色禁用：当 `queueIndex <= 0` 时
- 下一首灰色禁用：当 `queueIndex >= queue.length - 1` 时

#### QueuePanel 组件

**位置**: 从 PlayBar 上方弹出的面板，使用绝对定位 + 动画。

**文件**: `components/player/QueuePanel.tsx`

```typescript
interface QueuePanelProps {
  open: boolean;
  onClose: () => void;
}
```

**功能**:

- 展示 `queue` 数组，当前播放项（`queueIndex`）高亮
- 每项显示：封面缩略图、单集标题、播客名、时长、删除按钮
- 点击某项直接播放（`playFromQueue(index)`）
- 拖拽排序（Phase 3 引入 `@dnd-kit/core`，初始版本不实现）
- 底部"清空队列"按钮

**交互**:

- 点击 PlayBar 的队列图标打开，再次点击或点击外部关闭
- 最大高度 `max-h-[60vh]`，内容超出时 scroll
- 使用 shadcn 的 `scroll-area` 组件

### 3.6 EpisodeRow "更多操作"菜单

在 EpisodeRow 右侧增加一个 `...` 菜单（使用 shadcn `DropdownMenu`）：

```
┌─────────────────────┐
│ ▶ Play Next          │
│ ＋ Add to Queue      │
│ ─────────────────── │
│ → Go to Episode     │
└─────────────────────┘
```

Phase 1 不实现菜单，只在播放按钮旁增加一个小的"添加到队列"按钮（`+` 图标）。Phase 2 实现完整的下拉菜单。

---

## 4. Phase 3: 订阅库增强 ✅ 已实现

### 4.1 Subscriptions API 增强

**当前 API**（`GET /api/podcasts/subscriptions`）的问题：对每个 subscription 执行单独的 podcast 查询（N+1），且不返回最新集和未听数信息。

**增强方案**:

```typescript
// app/api/podcasts/subscriptions/route.ts — 重写

export async function GET() {
  const userId = DEMO_USER_ID;
  await initPromise;

  // 1. 获取订阅列表 + podcast 信息（单次 JOIN）
  const subs = await db
    .select({
      podcastId: subscriptions.podcastId,
      subscribedAt: subscriptions.subscribedAt,
      title: podcasts.title,
      author: podcasts.author,
      description: podcasts.description,
      imageUrl: podcasts.imageUrl,
      feedUrl: podcasts.feedUrl,
    })
    .from(subscriptions)
    .innerJoin(podcasts, eq(subscriptions.podcastId, podcasts.id))
    .where(eq(subscriptions.userId, userId));

  // 2. 对每个播客获取最新集 + 未听数
  const enriched = await Promise.all(
    subs.map(async (sub) => {
      // 最新一集
      const latestEpisode = await db
        .select({
          id: episodes.id,
          title: episodes.title,
          audioUrl: episodes.audioUrl,
          publishedAt: episodes.publishedAt,
          duration: episodes.duration,
        })
        .from(episodes)
        .where(eq(episodes.podcastId, sub.podcastId))
        .orderBy(desc(episodes.publishedAt))
        .limit(1)
        .get();

      // 未听集数：该播客的 episodes 中，不在 playProgress 中或 completed=false 且 position<30 的
      const totalEpisodes = await db
        .select({ count: sql<number>`count(*)` })
        .from(episodes)
        .where(eq(episodes.podcastId, sub.podcastId))
        .get();

      const heardEpisodes = await db
        .select({ count: sql<number>`count(*)` })
        .from(playProgress)
        .innerJoin(episodes, eq(playProgress.episodeId, episodes.id))
        .where(
          and(
            eq(playProgress.userId, userId),
            eq(episodes.podcastId, sub.podcastId),
            or(
              eq(playProgress.completed, true),
              gt(playProgress.position, 30)
            )
          )
        )
        .get();

      const unheardCount = (totalEpisodes?.count ?? 0) - (heardEpisodes?.count ?? 0);

      return {
        id: sub.podcastId,
        title: sub.title,
        author: sub.author,
        description: sub.description,
        imageUrl: sub.imageUrl,
        feedUrl: sub.feedUrl,
        isSubscribed: true,
        latestEpisode: latestEpisode || null,
        unheardCount: Math.max(0, unheardCount),
      };
    })
  );

  // 3. 按最新集发布时间倒序排列
  enriched.sort((a, b) => {
    const aTime = a.latestEpisode?.publishedAt
      ? new Date(a.latestEpisode.publishedAt).getTime()
      : 0;
    const bTime = b.latestEpisode?.publishedAt
      ? new Date(b.latestEpisode.publishedAt).getTime()
      : 0;
    return bTime - aTime;
  });

  return NextResponse.json(enriched);
}
```

**性能考虑**: 上述实现仍然存在 N+1（每个播客两个额外查询）。对于 MVP 阶段（订阅数 <20），这是可以接受的。如果后期需要优化，可以使用 SQLite 的窗口函数一次性获取所有播客的最新集：

```sql
-- 一次查询获取所有订阅播客的最新集（优化版）
SELECT DISTINCT ON (e.podcast_id)
  e.id, e.title, e.audio_url, e.published_at, e.duration, e.podcast_id
FROM episodes e
WHERE e.podcast_id IN (SELECT podcast_id FROM subscriptions WHERE user_id = ?)
ORDER BY e.podcast_id, e.published_at DESC
```

SQLite 不支持 `DISTINCT ON`，替代方案是用子查询：

```sql
SELECT e.*
FROM episodes e
INNER JOIN (
  SELECT podcast_id, MAX(published_at) AS max_pub
  FROM episodes
  WHERE podcast_id IN (SELECT podcast_id FROM subscriptions WHERE user_id = ?)
  GROUP BY podcast_id
) latest ON e.podcast_id = latest.podcast_id AND e.published_at = latest.max_pub
```

### 4.2 PodcastCard 增强

新增 props:

```typescript
interface PodcastCardProps {
  // ...existing props...
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

新增渲染元素:

```
[封面] [标题/作者/描述]      ← 现有（Link 到 podcast 详情页）
─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
▶ Episode Title...            ← 最新集：点击直接播放
  3 days ago                  ← 相对时间
                    ③ new     ← 未听 badge
```

**快速播放按钮**调用逻辑与 EpisodeRow 相同：`playerStore.loadEpisode()`。

**相对时间**: 使用轻量 helper，不引入新依赖：

```typescript
function timeAgo(dateStr: string): string {
  const now = Date.now();
  const then = new Date(dateStr).getTime();
  const diff = now - then;
  const minutes = Math.floor(diff / 60000);
  const hours = Math.floor(diff / 3600000);
  const days = Math.floor(diff / 86400000);

  if (minutes < 60) return `${minutes}m ago`;
  if (hours < 24) return `${hours}h ago`;
  if (days < 7) return `${days}d ago`;
  if (days < 30) return `${Math.floor(days / 7)}w ago`;
  return new Date(dateStr).toLocaleDateString('zh-CN');
}
```

### 4.3 视图切换（ViewToggle）

```typescript
// components/podcast/ViewToggle.tsx

type ViewMode = 'grid' | 'list';

interface ViewToggleProps {
  value: ViewMode;
  onChange: (mode: ViewMode) => void;
}
```

偏好存储在 localStorage（`subscription-view-mode`），不需要 Zustand。

### 4.4 最近播放区域

利用已有的 `GET /api/progress/recent` API。该 API 已经返回完整的 episode + podcast 信息（包含 audioUrl、podcastTitle、podcastImageUrl），数据模型满足需求。

在首页底部增加 "Recently Played" section，使用 `EpisodeRow` 渲染。由于 `recent` API 返回了 audioUrl 和 podcast info，可以直接传递给 EpisodeRow 的新 props，支持快速播放和断点续播。

**续播逻辑**: 点击播放按钮时，通过 `loadProgress(episodeId)` 获取上次播放位置，传递给 `loadEpisode` 后调用 `seekTo(position)`。

```typescript
const handleResume = async (item: RecentItem) => {
  loadEpisode({
    id: item.episodeId,
    title: item.episodeTitle,
    audioUrl: item.audioUrl,
    podcastId: item.podcastId,
    podcastTitle: item.podcastTitle,
    coverUrl: item.podcastImageUrl || '',
  });
  // 等待 audio 加载后 seek 到断点
  if (item.position > 0) {
    // 短暂延时等 audio load
    setTimeout(() => seekTo(item.position), 300);
  }
};
```

**更优雅的方案**: 在 `loadEpisode` 的 payload 中增加可选的 `startPosition` 字段，在 useAudioPlayer 的 `loadedmetadata` 事件中自动 seek：

```typescript
// stores/playerStore.ts
interface LoadEpisodePayload {
  // ...existing fields...
  startPosition?: number;  // 断点续播位置
}

// hooks/useAudioPlayer.ts
const onLoadedMetadata = () => {
  setDuration(audio.duration);
  const { startPosition } = usePlayerStore.getState();
  if (startPosition && startPosition > 0) {
    audio.currentTime = startPosition;
    setCurrentTime(startPosition);
  }
};
```

---

## 5. 状态管理全景

### 5.1 改造后的 PlayerStore 状态流

```
                          ┌──────────────────────────────┐
                          │         PlayerStore          │
                          │                              │
  EpisodeRow ──────────→ │  loadEpisode()               │
    (点击播放)             │    → set currentEpisodeId    │
                          │    → set audioUrl            │
  QueuePanel ─────────→  │    → set queue: []           │
    (点击队列项)           │                              │
                          │  addToQueue()                │
  "Add to Queue" ──────→ │    → queue.push(item)        │
                          │                              │
  "Play Next" ─────────→ │  playNext()                  │
                          │    → queue.splice(idx, item) │
                          │                              │
  Audio ended ─────────→ │  skipToNext()                │
    (useAudioPlayer)      │    → queueIndex++            │
                          │    → load queue[newIndex]    │
                          │                              │
  PlayBar ⏮ ──────────→  │  skipToPrevious()            │
  PlayBar ⏭ ──────────→  │  skipToNext()                │
                          │                              │
  "Play All" ──────────→ │  playAll(items)              │
                          │    → set queue: items        │
                          │    → load items[0]           │
                          └──────────────┬───────────────┘
                                         │
                              localStorage persist
                                (via zustand/persist)
```

### 5.2 不需要 Zustand 管理的状态

| 状态 | 存储位置 | 原因 |
|------|----------|------|
| 视图模式 (grid/list) | localStorage 直接读写 | 单页面使用，不涉及跨组件共享 |
| 订阅列表数据 | React useState + fetch | 页面级数据，不需要全局状态 |
| 队列面板 open/close | React useState | 纯 UI 状态 |

---

## 6. 组件依赖关系

```
PlayBar
  ├── useAudioPlayer (hook)     ← 管理 HTMLAudioElement
  ├── usePlayProgress (hook)    ← 自动保存进度
  ├── ProgressBar               ← 进度条
  ├── SpeedControl              ← 倍速
  ├── QueueButton (新增)        ← 队列图标 + 计数
  └── QueuePanel (新增)         ← 队列管理面板

EpisodeRow (重构)
  ├── usePlayerStore            ← 判断当前播放状态
  └── useRouter (next/navigation) ← audioUrl 缺失时降级导航

PodcastCard (增强)
  └── usePlayerStore            ← 快速播放最新集

SubscriptionsPage (增强)
  ├── PodcastCard (增强)
  ├── ViewToggle (新增)
  └── RSSInput (不变)

HomePage (增强)
  ├── PodcastCard (不变)
  ├── EpisodeRow (重构)
  └── RecentlyPlayed Section (新增)
```

---

## 7. API 变更汇总

| API | 变更类型 | 变更说明 |
|-----|----------|----------|
| `GET /api/podcasts/subscriptions` | 增强 | 返回 `latestEpisode` 对象和 `unheardCount` |
| `GET /api/podcasts/[id]/episodes` | 微调 | 确保返回 `audioUrl` 字段（已有，需确认前端消费） |
| `GET /api/episodes/feed` | **新增** | 获取用户所有订阅播客的最新 episodes，含 podcast 信息 |
| `GET /api/progress/recent` | 不变 | 已满足需求（含 audioUrl、podcastTitle 等） |

---

## 8. 新增依赖

| 包名 | 用途 | 阶段 | 大小 |
|------|------|------|------|
| `zustand/middleware` | persist 中间件 | Phase 2 | 内置 |
| `@dnd-kit/core` | 队列拖拽排序 | Phase 3 | ~30KB |
| `@dnd-kit/sortable` | 排序预设 | Phase 3 | ~15KB |

Phase 1 和 Phase 2 不引入任何新依赖。Phase 3 的拖拽排序可以延后实现。

---

## 9. 测试策略

### 9.1 单元测试重点

| 模块 | 测试重点 |
|------|----------|
| `playerStore` queue actions | addToQueue / playNext / removeFromQueue / reorderQueue 的索引正确性 |
| `skipToNext` / `skipToPrevious` | 边界条件：空队列、队列末尾、队列开头 |
| `reorderQueue` | queueIndex 在拖拽后的正确调整 |
| `persist` partialize | 确认持久化字段正确，恢复后状态一致 |

### 9.2 集成测试场景

| 场景 | 预期行为 |
|------|----------|
| 快速播放 → 暂停 → 切换另一集 | 旧集停止，新集播放 |
| 添加 3 集到队列 → 播放到结束 | 自动连续播放 3 集 |
| 页面刷新后恢复 | 队列和播放信息恢复，不自动播放 |
| 删除队列中正在播放的项 | 自动跳到下一首，或停止（如果是最后一首） |

### 9.3 手动测试清单

- [ ] EpisodeRow 播放按钮：首页、播客详情页、订阅库各页面
- [ ] 播放/暂停状态图标切换
- [ ] PlayBar 封面/标题点击导航到详情页
- [ ] 队列添加 → 队列面板查看
- [ ] 自动连续播放：集结束后无缝播放下一集
- [ ] 断点续播：最近播放 → 点击继续 → 从上次位置开始
- [ ] 订阅列表增强信息展示
- [ ] 视图切换持久化

---

## 10. 实施计划

### Phase 1: 快速播放（预估 3-4 天）

```
Day 1:
  [x] playerStore 增加 podcastId 字段
  [x] EpisodeRow 重构：分离播放按钮和导航链接
  [x] EpisodeRow 播放逻辑实现

Day 2:
  [x] 新增 /api/episodes/feed 端点
  [x] 首页数据获取重构（使用新 API）
  [x] 播客详情页传递 audioUrl + podcast info 给 EpisodeRow

Day 3:
  [x] PlayBar 增加 Link 导航
  [x] EpisodeList 组件 props 扩展
  [x] 端到端测试 + bug 修复
```

### Phase 2: 播放队列（预估 4-5 天）

```
Day 4-5:
  [x] playerStore 队列状态 + 全部 queue actions
  [x] zustand persist 配置
  [x] useAudioPlayer onEnded → skipToNext 联动

Day 6:
  [x] PlayBar 上下首按钮 + 队列计数
  [x] QueuePanel 组件（列表、删除、清空）
  [x] EpisodeRow 更多操作菜单（Add to Queue / Play Next）

Day 7-8:
  [x] playAll 功能（播客详情页 + 订阅列表）
  [x] 测试：连续播放、队列操作、persist 恢复
```

### Phase 3: 订阅库增强（预估 4-5 天）

```
Day 9-10:
  [x] subscriptions API 增强（latestEpisode + unheardCount）
  [x] PodcastCard 增强（最新集 + 未听 badge + 快速播放）
  [x] ViewToggle 组件 + 列表视图

Day 11:
  [x] 首页 "最近播放" 区域
  [x] 断点续播（loadEpisode startPosition）

Day 12-13:
  [x] QueuePanel 拖拽排序（@dnd-kit）
  [x] 全功能端到端测试
  [x] 性能检查 + 代码清理
```

---

## 11. 风险与应对

| 风险 | 概率 | 影响 | 应对 |
|------|------|------|------|
| Zustand persist hydration 不一致 | 中 | 页面刷新后状态异常 | 使用 `onRehydrateStorage` 回调验证状态完整性；不持久化 `isPlaying` 避免自动播放 |
| Audio 元素在 skipToNext 时不加载 | 中 | 连续播放中断 | 在 useAudioPlayer 中监听 audioUrl 变化，确保 `audio.src` 更新后调用 `audio.load()` |
| EpisodeRow 重构影响范围大 | 低 | 多处使用的组件修改可能引入 bug | 增加 `audioUrl` 为可选 prop，无 audioUrl 时降级为原有 Link 行为 |
| subscriptions API N+1 查询性能 | 低 | 订阅数多时响应慢 | MVP 阶段可接受（<20 订阅）；预留 SQL 窗口函数优化方案 |
| @dnd-kit 与 React 19 兼容性 | 低 | 拖拽排序不工作 | Phase 3 才引入，有充足时间评估；备选方案为按钮上移/下移 |

---

## 12. Phase 4: 标注系统（Annotation System）

### 12.1 数据库 Schema

新增两张表：`annotations` 和 `exportConfigs`。

```typescript
// lib/db/schema.ts — 新增

export const annotations = sqliteTable('annotations', {
  id: text('id').primaryKey(),
  userId: text('user_id').notNull().references(() => users.id),
  episodeId: text('episode_id').notNull().references(() => episodes.id),
  segmentId: text('segment_id').references(() => transcriptSegments.id),
  type: text('type').notNull(), // 'highlight' | 'note'
  color: text('color').notNull().default('yellow'), // 'yellow' | 'green' | 'blue' | 'purple'
  startOffset: integer('start_offset'), // 自由选中：字符起始偏移
  endOffset: integer('end_offset'),     // 自由选中：字符结束偏移
  noteContent: text('note_content'),    // Markdown 笔记
  createdAt: text('created_at').notNull().default(sql`(datetime('now'))`),
  updatedAt: text('updated_at').notNull().default(sql`(datetime('now'))`),
});

export const exportConfigs = sqliteTable('export_configs', {
  id: text('id').primaryKey(),
  userId: text('user_id').notNull().references(() => users.id),
  platform: text('platform').notNull(), // 'obsidian' | 'feishu' | 'dingtalk' | 'markdown'
  config: text('config').notNull().default('{}'), // JSON: 平台特定配置
  isDefault: integer('is_default').notNull().default(0),
  createdAt: text('created_at').notNull().default(sql`(datetime('now'))`),
  updatedAt: text('updated_at').notNull().default(sql`(datetime('now'))`),
});
```

**索引设计**:

```typescript
// 按 episodeId 快速查询某集的所有标注
export const annotationsByEpisode = index('idx_annotations_episode')
  .on(annotations.episodeId);

// 按 userId 查询用户所有标注（高亮回顾页面）
export const annotationsByUser = index('idx_annotations_user')
  .on(annotations.userId, annotations.createdAt);

// 按 userId + episodeId 复合查询
export const annotationsByUserEpisode = index('idx_annotations_user_episode')
  .on(annotations.userId, annotations.episodeId);
```

### 12.2 标注 API

#### GET /api/episodes/[id]/annotations

获取某集的所有标注：

```typescript
// app/api/episodes/[id]/annotations/route.ts

export async function GET(
  request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const userId = DEMO_USER_ID;

  const results = await db
    .select()
    .from(annotations)
    .where(
      and(
        eq(annotations.episodeId, id),
        eq(annotations.userId, userId)
      )
    )
    .orderBy(asc(annotations.createdAt));

  return NextResponse.json(results);
}
```

#### POST /api/annotations

创建标注：

```typescript
// app/api/annotations/route.ts

interface CreateAnnotationBody {
  episodeId: string;
  segmentId?: string;
  type: 'highlight' | 'note';
  color?: string;
  startOffset?: number;
  endOffset?: number;
  noteContent?: string;
}

export async function POST(request: Request) {
  const body: CreateAnnotationBody = await request.json();
  const userId = DEMO_USER_ID;

  const id = nanoid();
  const now = new Date().toISOString();

  await db.insert(annotations).values({
    id,
    userId,
    episodeId: body.episodeId,
    segmentId: body.segmentId || null,
    type: body.type,
    color: body.color || 'yellow',
    startOffset: body.startOffset ?? null,
    endOffset: body.endOffset ?? null,
    noteContent: body.noteContent || null,
    createdAt: now,
    updatedAt: now,
  });

  return NextResponse.json({ id, ...body, createdAt: now });
}
```

#### PUT /api/annotations/[id]

更新标注（修改颜色、笔记内容）：

```typescript
export async function PUT(
  request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const body = await request.json();
  const userId = DEMO_USER_ID;

  await db
    .update(annotations)
    .set({
      ...body,
      updatedAt: new Date().toISOString(),
    })
    .where(
      and(
        eq(annotations.id, id),
        eq(annotations.userId, userId)
      )
    );

  return NextResponse.json({ success: true });
}
```

#### DELETE /api/annotations/[id]

删除标注。

#### GET /api/annotations — 全局查询（高亮回顾页）

```typescript
// 支持分页 + 按 podcast/episode 过滤
export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const userId = DEMO_USER_ID;
  const episodeId = searchParams.get('episodeId');
  const podcastId = searchParams.get('podcastId');
  const page = parseInt(searchParams.get('page') || '1');
  const limit = parseInt(searchParams.get('limit') || '50');

  let query = db
    .select({
      annotation: annotations,
      episodeTitle: episodes.title,
      podcastId: episodes.podcastId,
      podcastTitle: podcasts.title,
      segmentOriginalText: transcriptSegments.originalText,
      segmentTranslatedText: transcriptSegments.translatedText,
      segmentStartTime: transcriptSegments.startTime,
    })
    .from(annotations)
    .innerJoin(episodes, eq(annotations.episodeId, episodes.id))
    .innerJoin(podcasts, eq(episodes.podcastId, podcasts.id))
    .leftJoin(transcriptSegments, eq(annotations.segmentId, transcriptSegments.id))
    .where(eq(annotations.userId, userId))
    .orderBy(desc(annotations.createdAt))
    .limit(limit)
    .offset((page - 1) * limit);

  // 动态过滤条件
  // ...

  const results = await query;
  return NextResponse.json({ data: results, page, limit });
}
```

### 12.3 标注 Zustand Store

客户端标注状态管理（缓存 + 乐观更新）：

```typescript
// stores/annotationStore.ts

interface AnnotationState {
  // 当前集的标注缓存（key: episodeId）
  annotationsByEpisode: Record<string, Annotation[]>;
  loading: boolean;

  // Actions
  fetchAnnotations: (episodeId: string) => Promise<void>;
  addAnnotation: (data: CreateAnnotationBody) => Promise<Annotation>;
  updateAnnotation: (id: string, data: Partial<Annotation>) => Promise<void>;
  deleteAnnotation: (id: string, episodeId: string) => Promise<void>;
}

export const useAnnotationStore = create<AnnotationState>()((set, get) => ({
  annotationsByEpisode: {},
  loading: false,

  fetchAnnotations: async (episodeId) => {
    set({ loading: true });
    const res = await fetch(`/api/episodes/${episodeId}/annotations`);
    const data = await res.json();
    set((state) => ({
      annotationsByEpisode: {
        ...state.annotationsByEpisode,
        [episodeId]: data,
      },
      loading: false,
    }));
  },

  addAnnotation: async (body) => {
    // 乐观更新
    const tempId = `temp-${Date.now()}`;
    const optimistic = { id: tempId, ...body, createdAt: new Date().toISOString() };

    set((state) => ({
      annotationsByEpisode: {
        ...state.annotationsByEpisode,
        [body.episodeId]: [
          ...(state.annotationsByEpisode[body.episodeId] || []),
          optimistic as Annotation,
        ],
      },
    }));

    // 实际请求
    const res = await fetch('/api/annotations', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    const created = await res.json();

    // 替换临时 ID
    set((state) => ({
      annotationsByEpisode: {
        ...state.annotationsByEpisode,
        [body.episodeId]: state.annotationsByEpisode[body.episodeId]?.map(
          (a) => (a.id === tempId ? created : a)
        ) || [],
      },
    }));

    return created;
  },

  // updateAnnotation, deleteAnnotation 类似乐观更新模式
}));
```

### 12.4 TranscriptPanel 增强

#### 高亮渲染

在现有的 TranscriptPanel 组件中，为每个 segment 增加高亮状态渲染：

```typescript
// components/transcript/HighlightedSegment.tsx

interface HighlightedSegmentProps {
  segment: TranscriptSegment;
  annotations: Annotation[];
  onHighlight: (segmentId: string, color: string) => void;
  onAddNote: (segmentId: string, content: string) => void;
  onRemoveHighlight: (annotationId: string) => void;
}

export function HighlightedSegment({
  segment,
  annotations,
  onHighlight,
  onAddNote,
  onRemoveHighlight,
}: HighlightedSegmentProps) {
  const highlight = annotations.find(
    (a) => a.segmentId === segment.id && a.type === 'highlight'
  );
  const notes = annotations.filter(
    (a) => a.segmentId === segment.id && a.type === 'note'
  );

  const bgColorClass = highlight
    ? {
        yellow: 'bg-yellow-500/20 border-l-2 border-yellow-500',
        green: 'bg-green-500/20 border-l-2 border-green-500',
        blue: 'bg-blue-500/20 border-l-2 border-blue-500',
        purple: 'bg-purple-500/20 border-l-2 border-purple-500',
      }[highlight.color] || ''
    : '';

  return (
    <div className={`px-3 py-2 rounded transition-colors ${bgColorClass}`}>
      {/* 原文 + 译文 */}
      <p className="text-zinc-300 text-sm">{segment.originalText}</p>
      <p className="text-zinc-500 text-xs mt-1">{segment.translatedText}</p>

      {/* 笔记 */}
      {notes.map((note) => (
        <div key={note.id} className="mt-2 pl-3 border-l border-zinc-600">
          <p className="text-zinc-400 text-xs">📝 {note.noteContent}</p>
        </div>
      ))}
    </div>
  );
}
```

#### 浮动工具条 (HighlightToolbar)

```typescript
// components/transcript/HighlightToolbar.tsx

interface HighlightToolbarProps {
  position: { x: number; y: number };
  visible: boolean;
  onHighlight: (color: string) => void;
  onNote: () => void;
  onClose: () => void;
}

// 使用 Portals 渲染到 body 层，避免被 overflow:hidden 截断
// 通过 mouseup / selectionchange 事件触发显示
// 位置跟随选中文本的 getBoundingClientRect()
```

**文本选中检测逻辑**:

```typescript
// hooks/useTextSelection.ts

export function useTextSelection(containerRef: RefObject<HTMLElement>) {
  const [selection, setSelection] = useState<{
    text: string;
    segmentId: string;
    startOffset: number;
    endOffset: number;
    rect: DOMRect;
  } | null>(null);

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    const handleSelectionChange = () => {
      const sel = window.getSelection();
      if (!sel || sel.isCollapsed || !sel.rangeCount) {
        setSelection(null);
        return;
      }

      const range = sel.getRangeAt(0);
      // 确认选中范围在 container 内
      if (!container.contains(range.commonAncestorContainer)) {
        setSelection(null);
        return;
      }

      // 从 DOM data-segment-id 属性获取 segmentId
      const segmentEl = range.startContainer.parentElement?.closest('[data-segment-id]');
      const segmentId = segmentEl?.getAttribute('data-segment-id');

      if (segmentId) {
        setSelection({
          text: sel.toString(),
          segmentId,
          startOffset: range.startOffset,
          endOffset: range.endOffset,
          rect: range.getBoundingClientRect(),
        });
      }
    };

    document.addEventListener('selectionchange', handleSelectionChange);
    return () => document.removeEventListener('selectionchange', handleSelectionChange);
  }, [containerRef]);

  return selection;
}
```

### 12.5 NotesPanel 组件

```typescript
// components/transcript/NotesPanel.tsx

interface NotesPanelProps {
  episodeId: string;
  onSeekTo: (time: number) => void; // 跳转到音频时间点
}

export function NotesPanel({ episodeId, onSeekTo }: NotesPanelProps) {
  const annotations = useAnnotationStore(
    (s) => s.annotationsByEpisode[episodeId] || []
  );

  // 按时间戳排序（通过 segment 的 startTime）
  const sortedAnnotations = useMemo(() => {
    return [...annotations]
      .filter((a) => a.type === 'note' || a.type === 'highlight')
      .sort((a, b) => {
        // 需要 segment startTime，从关联数据获取
        return 0; // 实际按 startTime 排序
      });
  }, [annotations]);

  return (
    <div className="space-y-3">
      <h3 className="text-sm font-medium text-zinc-300">Notes & Highlights</h3>
      {sortedAnnotations.map((a) => (
        <div
          key={a.id}
          className="p-3 bg-zinc-800/50 rounded-lg cursor-pointer hover:bg-zinc-800"
          onClick={() => onSeekTo(/* segment startTime */)}
        >
          <span className="text-xs text-zinc-500">[{formatTime(/* startTime */)}]</span>
          <p className="text-sm text-zinc-300 mt-1">
            {a.type === 'highlight' ? '🖍️' : '📝'} {a.noteContent || '(highlight)'}
          </p>
        </div>
      ))}
    </div>
  );
}
```

### 12.6 高亮回顾页面

```typescript
// app/highlights/page.tsx

// 使用 GET /api/annotations 全局查询
// 按 podcast 分组展示
// 每条高亮：原文 + 译文 + 笔记 + 时间戳 + 点击跳转
// 支持搜索（前端过滤 or 后端 LIKE 查询）
```

---

## 13. Phase 5: 知识导出与同步

### 13.1 ExportAdapter 抽象层

采用策略模式（Strategy Pattern），与现有 AI Provider Registry 同构：

```typescript
// lib/export/types.ts

export type ExportPlatform = 'obsidian' | 'feishu' | 'dingtalk' | 'markdown';

export interface ExportContent {
  episodeId: string;
  episodeTitle: string;
  podcastTitle: string;
  publishedAt: string | null;
  duration: number | null;
  // 字幕
  segments?: {
    startTime: number;
    originalText: string;
    translatedText: string;
  }[];
  // 标注
  annotations: {
    type: 'highlight' | 'note';
    color: string;
    segmentStartTime?: number;
    originalText?: string;
    translatedText?: string;
    noteContent?: string;
  }[];
}

export interface ExportResult {
  success: boolean;
  url?: string; // 导出后的文档链接（飞书/钉钉）
  filePath?: string; // 本地文件路径（Obsidian）
  error?: string;
}

export interface ExportAdapter {
  platform: ExportPlatform;
  name: string;
  export(content: ExportContent, config: Record<string, unknown>): Promise<ExportResult>;
  validateConfig(config: Record<string, unknown>): boolean;
}
```

### 13.2 Markdown 导出生成器（核心）

所有平台导出的基础——先生成 Markdown，再转换为目标格式：

```typescript
// lib/export/markdown-generator.ts

export function generateMarkdown(content: ExportContent, options: {
  includeFullTranscript: boolean;
  includeHighlightsOnly: boolean;
}): string {
  const lines: string[] = [];

  // Frontmatter (YAML)
  lines.push('---');
  lines.push(`title: "${content.podcastTitle} - ${content.episodeTitle}"`);
  lines.push(`date: ${content.publishedAt || new Date().toISOString()}`);
  lines.push(`source: 10timesPod`);
  lines.push(`podcast: "${content.podcastTitle}"`);
  lines.push(`tags: [podcast, ${content.podcastTitle.toLowerCase().replace(/\s+/g, '-')}]`);
  lines.push('---');
  lines.push('');

  // Title
  lines.push(`# ${content.podcastTitle} - ${content.episodeTitle}`);
  lines.push('');
  lines.push(`> Published: ${content.publishedAt || 'Unknown'}`);
  if (content.duration) {
    lines.push(`> Duration: ${formatDuration(content.duration)}`);
  }
  lines.push(`> Exported: ${new Date().toISOString()}`);
  lines.push('');

  // Highlights & Notes section
  if (content.annotations.length > 0) {
    lines.push('## Highlights & Notes');
    lines.push('');

    for (const ann of content.annotations) {
      if (ann.segmentStartTime !== undefined) {
        lines.push(`### [${formatTime(ann.segmentStartTime)}]`);
      }
      lines.push('');

      if (ann.originalText) {
        lines.push(`> 🇺🇸 ${ann.originalText}`);
      }
      if (ann.translatedText) {
        lines.push(`> 🇨🇳 ${ann.translatedText}`);
      }

      if (ann.noteContent) {
        lines.push('');
        lines.push(`📝 **Note**: ${ann.noteContent}`);
      }

      lines.push('');
      lines.push('---');
      lines.push('');
    }
  }

  // Full transcript (optional)
  if (options.includeFullTranscript && content.segments) {
    lines.push('## Full Transcript');
    lines.push('');

    for (const seg of content.segments) {
      lines.push(`**[${formatTime(seg.startTime)}]** ${seg.originalText}`);
      lines.push(`${seg.translatedText}`);
      lines.push('');
    }
  }

  return lines.join('\n');
}
```

### 13.3 Obsidian Adapter

```typescript
// lib/export/adapters/obsidian.ts

export class ObsidianAdapter implements ExportAdapter {
  platform: ExportPlatform = 'obsidian';
  name = 'Obsidian';

  async export(content: ExportContent, config: Record<string, unknown>): Promise<ExportResult> {
    const markdown = generateMarkdown(content, {
      includeFullTranscript: config.includeFullTranscript as boolean ?? false,
      includeHighlightsOnly: true,
    });

    const vaultName = config.vaultName as string;
    const folderPath = config.folderPath as string || 'Podcasts';
    const fileName = `${content.podcastTitle} - ${content.episodeTitle}`.replace(/[/\\:*?"<>|]/g, '_');

    if (vaultName) {
      // 方案 A: 通过 Obsidian URI Protocol
      const encoded = encodeURIComponent(markdown);
      const uri = `obsidian://new?vault=${encodeURIComponent(vaultName)}&file=${encodeURIComponent(`${folderPath}/${fileName}`)}&content=${encoded}`;

      return {
        success: true,
        url: uri,
      };
    }

    // 方案 B: 返回 Markdown 文件内容供下载
    return {
      success: true,
      filePath: `${fileName}.md`,
      // 前端处理文件下载
    };
  }

  validateConfig(config: Record<string, unknown>): boolean {
    return true; // Obsidian 不强制要求配置
  }
}
```

### 13.4 飞书 Adapter

```typescript
// lib/export/adapters/feishu.ts

export class FeishuAdapter implements ExportAdapter {
  platform: ExportPlatform = 'feishu';
  name = '飞书';

  async export(content: ExportContent, config: Record<string, unknown>): Promise<ExportResult> {
    const accessToken = config.accessToken as string;
    const spaceId = config.spaceId as string; // 知识库 ID

    if (!accessToken) {
      return { success: false, error: '飞书未授权，请在设置中授权' };
    }

    const markdown = generateMarkdown(content, {
      includeFullTranscript: config.includeFullTranscript as boolean ?? false,
      includeHighlightsOnly: true,
    });

    // 飞书 API: 创建文档
    // POST https://open.feishu.cn/open-apis/docx/v1/documents
    // 然后写入内容（需要转换 Markdown → 飞书 Block 格式）

    try {
      // 1. 创建空文档
      const createRes = await fetch('https://open.feishu.cn/open-apis/docx/v1/documents', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          title: `${content.podcastTitle} - ${content.episodeTitle}`,
          folder_token: spaceId || undefined,
        }),
      });

      const createData = await createRes.json();
      const documentId = createData.data?.document?.document_id;

      // 2. 写入内容（将 Markdown 转换为飞书 Block）
      // 飞书支持 Markdown -> Block 的服务端转换
      // 实际实现需要使用飞书的 Block API 逐块写入

      return {
        success: true,
        url: `https://docs.feishu.cn/${documentId}`,
      };
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error.message : '飞书导出失败',
      };
    }
  }

  validateConfig(config: Record<string, unknown>): boolean {
    return !!config.accessToken;
  }
}
```

### 13.5 钉钉 Adapter

结构与飞书类似，使用钉钉开放平台 API：

```typescript
// lib/export/adapters/dingtalk.ts

export class DingTalkAdapter implements ExportAdapter {
  platform: ExportPlatform = 'dingtalk';
  name = '钉钉';

  async export(content: ExportContent, config: Record<string, unknown>): Promise<ExportResult> {
    const accessToken = config.accessToken as string;
    const spaceId = config.spaceId as string;

    // 钉钉 API: POST /v1.0/doc/documents
    // 类似飞书的流程
    // ...
  }

  validateConfig(config: Record<string, unknown>): boolean {
    return !!config.accessToken;
  }
}
```

### 13.6 Export Registry

```typescript
// lib/export/registry.ts

import { ObsidianAdapter } from './adapters/obsidian';
import { FeishuAdapter } from './adapters/feishu';
import { DingTalkAdapter } from './adapters/dingtalk';
import { MarkdownAdapter } from './adapters/markdown';

const adapters: Record<ExportPlatform, ExportAdapter> = {
  obsidian: new ObsidianAdapter(),
  feishu: new FeishuAdapter(),
  dingtalk: new DingTalkAdapter(),
  markdown: new MarkdownAdapter(), // 纯下载 .md 文件
};

export function getExportAdapter(platform: ExportPlatform): ExportAdapter {
  return adapters[platform];
}

export function getAvailableAdapters(): ExportAdapter[] {
  return Object.values(adapters);
}
```

### 13.7 导出 API

```typescript
// app/api/export/route.ts

export async function POST(request: Request) {
  const body = await request.json();
  const { episodeId, platform, contentType, configId } = body;
  // contentType: 'highlights' | 'highlights_notes' | 'full'

  const userId = DEMO_USER_ID;

  // 1. 获取 episode + podcast 信息
  const episode = await db.select().from(episodes)
    .innerJoin(podcasts, eq(episodes.podcastId, podcasts.id))
    .where(eq(episodes.id, episodeId))
    .get();

  // 2. 获取标注
  const anns = await db.select().from(annotations)
    .where(and(
      eq(annotations.episodeId, episodeId),
      eq(annotations.userId, userId)
    ));

  // 3. 获取字幕（如果需要完整导出）
  let segments = undefined;
  if (contentType === 'full') {
    const transcript = await db.select().from(transcripts)
      .where(eq(transcripts.episodeId, episodeId))
      .get();

    if (transcript) {
      segments = await db.select().from(transcriptSegments)
        .where(eq(transcriptSegments.transcriptId, transcript.id))
        .orderBy(asc(transcriptSegments.startTime));
    }
  }

  // 4. 获取导出配置
  const exportConfig = configId
    ? await db.select().from(exportConfigs).where(eq(exportConfigs.id, configId)).get()
    : await db.select().from(exportConfigs)
        .where(and(eq(exportConfigs.userId, userId), eq(exportConfigs.platform, platform)))
        .get();

  // 5. 组装 ExportContent
  const exportContent: ExportContent = {
    episodeId,
    episodeTitle: episode?.episodes.title || '',
    podcastTitle: episode?.podcasts.title || '',
    publishedAt: episode?.episodes.publishedAt || null,
    duration: episode?.episodes.duration || null,
    segments: segments?.map(s => ({
      startTime: s.startTime,
      originalText: s.originalText,
      translatedText: s.translatedText || '',
    })),
    annotations: anns.map(a => ({
      type: a.type as 'highlight' | 'note',
      color: a.color,
      noteContent: a.noteContent || undefined,
      // segmentStartTime, originalText, translatedText 需要从 segment 关联获取
    })),
  };

  // 6. 执行导出
  const adapter = getExportAdapter(platform);
  const config = exportConfig ? JSON.parse(exportConfig.config) : {};
  const result = await adapter.export(exportContent, config);

  return NextResponse.json(result);
}
```

### 13.8 ExportButton 组件

```typescript
// components/export/ExportButton.tsx

interface ExportButtonProps {
  episodeId: string;
  hasAnnotations: boolean;
}

export function ExportButton({ episodeId, hasAnnotations }: ExportButtonProps) {
  const [open, setOpen] = useState(false);
  const [platform, setPlatform] = useState<ExportPlatform>('obsidian');
  const [contentType, setContentType] = useState<'highlights' | 'highlights_notes' | 'full'>('highlights_notes');
  const [exporting, setExporting] = useState(false);

  const handleExport = async () => {
    setExporting(true);
    try {
      const res = await fetch('/api/export', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ episodeId, platform, contentType }),
      });
      const result = await res.json();

      if (result.success) {
        if (result.url) {
          // Obsidian URI 或飞书/钉钉文档链接
          window.open(result.url, '_blank');
        }
        toast.success('导出成功');
      } else {
        toast.error(result.error || '导出失败');
      }
    } finally {
      setExporting(false);
      setOpen(false);
    }
  };

  return (
    // Popover with platform selector + content type + export button
    // See PRD 6.5 wireframe
  );
}
```

### 13.9 OAuth 授权流程（飞书/钉钉）

```
用户点击"授权飞书" → 跳转飞书 OAuth 页面 → 授权后回调 → 保存 token 到 exportConfigs

API:
  GET /api/auth/feishu     → 返回 OAuth 授权 URL
  GET /api/auth/feishu/callback → 处理回调，保存 token
  GET /api/auth/dingtalk   → 返回 OAuth 授权 URL
  GET /api/auth/dingtalk/callback → 处理回调，保存 token
```

**安全考虑**: OAuth Token 存储在服务端 `exportConfigs.config` JSON 中（加密存储），前端不直接接触 token。

---

## 14. Phase 4-5 新增文件清单

```
lib/
  db/
    schema.ts                          ← 新增 annotations + exportConfigs 表
  export/
    types.ts                           ← ExportAdapter 接口定义
    registry.ts                        ← Adapter 注册中心
    markdown-generator.ts              ← Markdown 生成器
    adapters/
      obsidian.ts                      ← Obsidian 导出
      feishu.ts                        ← 飞书导出
      dingtalk.ts                      ← 钉钉导出
      markdown.ts                      ← 纯 Markdown 下载

stores/
  annotationStore.ts                   ← 标注状态管理

hooks/
  useTextSelection.ts                  ← 文本选中检测

components/
  transcript/
    HighlightedSegment.tsx             ← 带高亮的字幕段落
    HighlightToolbar.tsx               ← 浮动标注工具条
    NotesPanel.tsx                     ← 笔记面板
  export/
    ExportButton.tsx                   ← 导出按钮 + 面板
    ExportSettings.tsx                 ← 设置页导出配置
    PlatformAuth.tsx                   ← OAuth 授权组件

app/
  highlights/
    page.tsx                           ← 高亮回顾页面
  api/
    annotations/
      route.ts                         ← 标注 CRUD
      [id]/route.ts                    ← 单条标注操作
    episodes/[id]/annotations/
      route.ts                         ← 单集标注查询
    export/
      route.ts                         ← 导出执行
      config/route.ts                  ← 导出配置管理
    auth/
      feishu/route.ts                  ← 飞书 OAuth
      feishu/callback/route.ts
      dingtalk/route.ts                ← 钉钉 OAuth
      dingtalk/callback/route.ts
```

---

## 15. Phase 4-5 新增依赖

| 包名 | 用途 | 阶段 | 大小 |
|------|------|------|------|
| `nanoid` | 标注 ID 生成 | Phase 4 | ~1KB（已有） |
| 无新依赖 | Phase 4a 标注基础不需要新依赖 | Phase 4a | - |
| `@feishu/node-sdk` (可选) | 飞书 API SDK | Phase 5 | ~50KB |
| `dingtalk-jsapi` (可选) | 钉钉 API SDK | Phase 5 | ~30KB |

Phase 4 核心标注功能不需要引入任何新依赖，全部使用原生 DOM API + 现有库实现。

---

## 16. Phase 4-5 组件依赖关系

```
EpisodePage (增强)
  ├── TranscriptPanel (增强)
  │   ├── HighlightedSegment (新增)
  │   ├── HighlightToolbar (新增)
  │   └── useTextSelection (新增 hook)
  ├── NotesPanel (新增)
  ├── ExportButton (新增)
  └── useAnnotationStore (新增 store)

HighlightsPage (新增)
  ├── useAnnotationStore
  └── EpisodeRow (复用)

SettingsPage (增强)
  ├── ExportSettings (新增)
  └── PlatformAuth (新增)

ExportButton
  ├── getExportAdapter (registry)
  └── generateMarkdown (core)
```

---

## 17. Phase 4-5 测试策略

### 17.1 单元测试

| 模块 | 测试重点 |
|------|----------|
| `annotationStore` | CRUD 操作、乐观更新、错误回滚 |
| `markdown-generator` | 各种内容组合的 Markdown 输出正确性 |
| `useTextSelection` | 选中检测、segmentId 提取、offset 计算 |
| `ExportAdapter` | 各平台 adapter 的 validateConfig 和 export 逻辑 |

### 17.2 集成测试

| 场景 | 预期行为 |
|------|----------|
| 创建高亮 → 刷新页面 → 高亮仍存在 | 标注持久化到数据库 |
| 高亮 3 段 + 添加 2 条笔记 → 导出 Obsidian | 生成完整 Markdown，5 条内容全部包含 |
| 飞书 token 过期 → 尝试导出 | 提示用户重新授权 |
| 删除标注 → NotesPanel 立即更新 | 乐观更新，UI 即时响应 |

### 17.3 手动测试

- [ ] 段落点击高亮 → 4 种颜色切换
- [ ] 自由文本选中 → 高亮工具条位置正确
- [ ] 笔记输入 → 保存 → 编辑 → 删除
- [ ] NotesPanel 点击 → 音频跳转到对应时间点
- [ ] `/highlights` 页面按播客分组展示
- [ ] Obsidian URI 导出 → 打开 Obsidian 创建笔记
- [ ] Markdown 下载 → 文件内容格式正确
- [ ] 飞书授权 → 导出 → 飞书文档创建成功
