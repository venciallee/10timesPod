# Claude Code Agent Prompts — Phase 4: 标注系统与知识导出

> 对应 PRD: `PRD-subscription-playback.md` (F6, F7)
> 对应技术方案: `TECH_DESIGN_subscription_playback.md` (§12-§17)
> 日期: 2026-03-08

---

## 工作量评估

### 文件依赖分析

```
                     ┌─────────────────────────────────┐
                     │   lib/db/schema.ts (MODIFY)      │
                     │   lib/db/index.ts  (MODIFY)      │
                     │   lib/types.ts     (MODIFY)      │
                     └─────────┬───────────────────────┘
                               │ DB 基础层
              ┌────────────────┼────────────────┐
              ▼                ▼                ▼
  ┌───────────────────┐ ┌──────────────┐ ┌──────────────────────┐
  │ API Routes        │ │ Store/Hooks  │ │ Export Infra          │
  │ (annotations/)    │ │ (annotStore) │ │ (types/registry/      │
  │ (episodes/[id]/   │ │ (useTextSel) │ │  md-generator/        │
  │  annotations/)    │ │              │ │  adapters/)           │
  └────────┬──────────┘ └──────┬───────┘ └──────────┬───────────┘
           │                   │                     │
           └───────────┬───────┘                     │
                       ▼                             │
           ┌───────────────────────┐                 │
           │ UI Components         │                 │
           │ (HighlightedSegment)  │                 │
           │ (HighlightToolbar)    │                 │
           │ (NotesPanel)          │                 │
           │ (SubtitlePanel改造)   │                 │
           └───────────┬───────────┘                 │
                       │                             │
                       ▼                             ▼
           ┌──────────────────────────────────────────┐
           │ Pages & Integration                       │
           │ (EpisodePage 集成标注+导出)                │
           │ (highlights/page.tsx)                     │
           │ (ExportButton / ExportSettings)           │
           │ (api/export/route.ts)                    │
           └──────────────────────────────────────────┘
```

### Agent 划分方案：4 个 Agent，2 轮

**Round 1（并行，零文件冲突）**:
- **Agent A: DB Schema + Annotation API** — 数据基础层，所有后续工作依赖此
- **Agent B: Export 基础设施 + Store/Hooks** — 导出核心逻辑 + 客户端状态管理

**Round 2（并行，依赖 Round 1 完成）**:
- **Agent C: 字幕标注 UI 组件** — SegmentRow 改造、HighlightToolbar、NotesPanel
- **Agent D: 页面集成 + 导出 UI** — EpisodePage 集成、Highlights 页面、ExportButton

### 预估工时

| Agent | 文件数 | 复杂度 | 预估时间 |
|-------|--------|--------|----------|
| A: DB + API | 5 个文件（2 修改 + 3 新增） | 中 | 15-20 min |
| B: Export + Store | 8 个文件（1 修改 + 7 新增） | 中 | 15-20 min |
| C: 标注 UI | 4 个文件（2 修改 + 2 新增） | 高（DOM 交互） | 20-30 min |
| D: 页面集成 | 5 个文件（1 修改 + 4 新增） | 中高 | 20-25 min |

---

## Round 1: Agent A — DB Schema + Annotation API

### Prompt

```
你是一个 Next.js 16 + Drizzle ORM + LibSQL 项目的后端开发者。

## 项目上下文

项目名: 10timesPod，双语字幕播客播放器
路径: 当前工作目录就是项目根目录
技术栈: Next.js 16 (App Router), TypeScript, Drizzle ORM, LibSQL (SQLite), React 19

## 你的任务

为「标注系统」新增数据库表和 CRUD API。这是 Phase 4 的基础层，其他 Agent 依赖你的产出。

## 需要修改/新增的文件

### 1. 修改 `lib/db/schema.ts` — 新增 annotations 和 exportConfigs 表

在文件末尾新增：

```typescript
export const annotations = sqliteTable('annotations', {
  id: text('id').primaryKey(),
  userId: text('user_id').notNull(),
  episodeId: text('episode_id').notNull(),
  segmentId: text('segment_id'),  // nullable, FK to transcript_segments
  type: text('type').notNull(),   // 'highlight' | 'note'
  color: text('color').notNull().default('yellow'), // 'yellow' | 'green' | 'blue' | 'purple'
  startOffset: integer('start_offset'), // 自由选中时的起始偏移
  endOffset: integer('end_offset'),     // 自由选中时的结束偏移
  noteContent: text('note_content'),    // Markdown 笔记内容
  createdAt: text('created_at').default('CURRENT_TIMESTAMP'),
  updatedAt: text('updated_at').default('CURRENT_TIMESTAMP'),
});

export const exportConfigs = sqliteTable('export_configs', {
  id: text('id').primaryKey(),
  userId: text('user_id').notNull(),
  platform: text('platform').notNull(), // 'obsidian' | 'feishu' | 'dingtalk' | 'markdown'
  config: text('config').notNull().default('{}'), // JSON 存储平台特定配置
  isDefault: integer('is_default', { mode: 'boolean' }).default(false),
  createdAt: text('created_at').default('CURRENT_TIMESTAMP'),
  updatedAt: text('updated_at').default('CURRENT_TIMESTAMP'),
});
```

### 2. 修改 `lib/db/index.ts` — 在 initDB 的 SQL 中新增建表语句

在 `CREATE TABLE IF NOT EXISTS ai_configs` 之后、`INSERT OR IGNORE INTO users` 之前，加入：

```sql
CREATE TABLE IF NOT EXISTS annotations (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  episode_id TEXT NOT NULL,
  segment_id TEXT,
  type TEXT NOT NULL,
  color TEXT NOT NULL DEFAULT 'yellow',
  start_offset INTEGER,
  end_offset INTEGER,
  note_content TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_annotations_user_episode ON annotations(user_id, episode_id);
CREATE INDEX IF NOT EXISTS idx_annotations_episode ON annotations(episode_id);

CREATE TABLE IF NOT EXISTS export_configs (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  platform TEXT NOT NULL,
  config TEXT NOT NULL DEFAULT '{}',
  is_default INTEGER DEFAULT 0,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);
```

### 3. 修改 `lib/types.ts` — 新增 Annotation 类型

在文件末尾追加：

```typescript
// Annotation types
export interface Annotation {
  id: string;
  userId: string;
  episodeId: string;
  segmentId?: string | null;
  type: 'highlight' | 'note';
  color: string;
  startOffset?: number | null;
  endOffset?: number | null;
  noteContent?: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface CreateAnnotationBody {
  episodeId: string;
  segmentId?: string;
  type: 'highlight' | 'note';
  color?: string;
  startOffset?: number;
  endOffset?: number;
  noteContent?: string;
}

export interface ExportConfig {
  id: string;
  userId: string;
  platform: 'obsidian' | 'feishu' | 'dingtalk' | 'markdown';
  config: Record<string, unknown>;
  isDefault: boolean;
  createdAt: string;
  updatedAt: string;
}
```

### 4. 新增 `app/api/annotations/route.ts` — 标注全局 CRUD

```typescript
import { NextResponse } from 'next/server';
import { db, initPromise } from '@/lib/db';
import { annotations } from '@/lib/db/schema';
import { eq, and, desc } from 'drizzle-orm';
import { nanoid } from 'nanoid';

const DEMO_USER_ID = 'demo-user';

// GET /api/annotations — 全局查询（高亮回顾页）
// 支持 ?episodeId=xxx 和 ?page=1&limit=50
export async function GET(request: Request) {
  await initPromise;
  const { searchParams } = new URL(request.url);
  const episodeId = searchParams.get('episodeId');
  const page = parseInt(searchParams.get('page') || '1');
  const limit = parseInt(searchParams.get('limit') || '50');

  // 注意: 这里需要 JOIN episodes + podcasts + transcriptSegments
  // 以获取 episodeTitle, podcastTitle, segmentText 等上下文信息
  // 用到的 schema import: episodes, podcasts, transcriptSegments
  import { episodes, podcasts, transcriptSegments } from '@/lib/db/schema';

  let conditions = [eq(annotations.userId, DEMO_USER_ID)];
  if (episodeId) {
    conditions.push(eq(annotations.episodeId, episodeId));
  }

  const results = await db
    .select({
      id: annotations.id,
      userId: annotations.userId,
      episodeId: annotations.episodeId,
      segmentId: annotations.segmentId,
      type: annotations.type,
      color: annotations.color,
      startOffset: annotations.startOffset,
      endOffset: annotations.endOffset,
      noteContent: annotations.noteContent,
      createdAt: annotations.createdAt,
      updatedAt: annotations.updatedAt,
      // JOIN 数据
      episodeTitle: episodes.title,
      podcastId: episodes.podcastId,
      podcastTitle: podcasts.title,
      segmentText: transcriptSegments.text,
      segmentTranslation: transcriptSegments.translation,
      segmentStartTime: transcriptSegments.startTime,
    })
    .from(annotations)
    .innerJoin(episodes, eq(annotations.episodeId, episodes.id))
    .innerJoin(podcasts, eq(episodes.podcastId, podcasts.id))
    .leftJoin(transcriptSegments, eq(annotations.segmentId, transcriptSegments.id))
    .where(and(...conditions))
    .orderBy(desc(annotations.createdAt))
    .limit(limit)
    .offset((page - 1) * limit);

  return NextResponse.json({ data: results, page, limit });
}

// POST /api/annotations — 创建标注
export async function POST(request: Request) {
  await initPromise;
  const body = await request.json();
  const id = nanoid();
  const now = new Date().toISOString();

  await db.insert(annotations).values({
    id,
    userId: DEMO_USER_ID,
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

  return NextResponse.json({
    id,
    userId: DEMO_USER_ID,
    ...body,
    createdAt: now,
    updatedAt: now,
  });
}
```

### 5. 新增 `app/api/annotations/[id]/route.ts` — 单条标注操作

```typescript
import { NextResponse } from 'next/server';
import { db, initPromise } from '@/lib/db';
import { annotations } from '@/lib/db/schema';
import { eq, and } from 'drizzle-orm';

const DEMO_USER_ID = 'demo-user';

// PUT /api/annotations/[id] — 更新标注
export async function PUT(
  request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  await initPromise;
  const { id } = await params;
  const body = await request.json();

  // 只允许更新特定字段
  const updateData: Record<string, unknown> = {
    updatedAt: new Date().toISOString(),
  };
  if (body.color !== undefined) updateData.color = body.color;
  if (body.noteContent !== undefined) updateData.noteContent = body.noteContent;

  await db
    .update(annotations)
    .set(updateData)
    .where(and(eq(annotations.id, id), eq(annotations.userId, DEMO_USER_ID)));

  return NextResponse.json({ success: true });
}

// DELETE /api/annotations/[id] — 删除标注
export async function DELETE(
  _request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  await initPromise;
  const { id } = await params;

  await db
    .delete(annotations)
    .where(and(eq(annotations.id, id), eq(annotations.userId, DEMO_USER_ID)));

  return NextResponse.json({ success: true });
}
```

### 6. 新增 `app/api/episodes/[id]/annotations/route.ts` — 单集标注查询

```typescript
import { NextResponse } from 'next/server';
import { db, initPromise } from '@/lib/db';
import { annotations } from '@/lib/db/schema';
import { eq, and, asc } from 'drizzle-orm';

const DEMO_USER_ID = 'demo-user';

// GET /api/episodes/[id]/annotations — 获取某集的所有标注
export async function GET(
  _request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  await initPromise;
  const { id: episodeId } = await params;

  const results = await db
    .select()
    .from(annotations)
    .where(
      and(
        eq(annotations.episodeId, episodeId),
        eq(annotations.userId, DEMO_USER_ID)
      )
    )
    .orderBy(asc(annotations.createdAt));

  return NextResponse.json(results);
}
```

## 重要注意事项

1. 项目使用 `nanoid` 生成 ID，已安装，直接 import
2. `DEMO_USER_ID = 'demo-user'` 是项目中的固定用户 ID（参考 `lib/db/index.ts` 最后一行）
3. Next.js 16 的 App Router 中，动态路由参数 `params` 是 `Promise` 类型，需要 `await params`
4. API 路由都要先 `await initPromise` 确保数据库初始化
5. **不要修改任何其他已有文件**，只修改上述 3 个文件 + 新增 3 个文件
6. Drizzle ORM 的 `and()` 函数可以接收数组展开：`and(...conditions)`
7. 确保所有 import 路径正确，项目使用 `@/` 路径别名

完成后请运行 `npx tsc --noEmit` 检查类型是否正确。
```

---

## Round 1: Agent B — Export 基础设施 + Annotation Store + Hooks

### Prompt

```
你是一个 Next.js 16 + TypeScript 项目的前端开发者。

## 项目上下文

项目名: 10timesPod，双语字幕播客播放器
路径: 当前工作目录就是项目根目录
技术栈: Next.js 16 (App Router), TypeScript, Zustand 5, React 19, Tailwind CSS v4, shadcn/ui

## 你的任务

创建「知识导出系统」的核心基础设施和「标注系统」的客户端状态管理。你负责的是纯逻辑层，不涉及 UI 组件。

## 需要新增的文件

### 1. 新增 `stores/annotationStore.ts` — 标注客户端状态管理

```typescript
import { create } from 'zustand';

// 注意: Annotation 类型定义在 lib/types.ts 中，由 Agent A 添加
// 如果 types.ts 还没更新，先在本文件定义临时类型
export interface Annotation {
  id: string;
  userId: string;
  episodeId: string;
  segmentId?: string | null;
  type: 'highlight' | 'note';
  color: string;
  startOffset?: number | null;
  endOffset?: number | null;
  noteContent?: string | null;
  createdAt: string;
  updatedAt: string;
}

interface CreateAnnotationBody {
  episodeId: string;
  segmentId?: string;
  type: 'highlight' | 'note';
  color?: string;
  startOffset?: number;
  endOffset?: number;
  noteContent?: string;
}

interface AnnotationState {
  // 按 episodeId 缓存标注
  annotationsByEpisode: Record<string, Annotation[]>;
  loading: boolean;
  error: string | null;

  // Actions
  fetchAnnotations: (episodeId: string) => Promise<void>;
  addAnnotation: (data: CreateAnnotationBody) => Promise<Annotation | null>;
  updateAnnotation: (id: string, episodeId: string, data: { color?: string; noteContent?: string }) => Promise<void>;
  deleteAnnotation: (id: string, episodeId: string) => Promise<void>;
  getAnnotationsForSegment: (episodeId: string, segmentId: string) => Annotation[];
}

export const useAnnotationStore = create<AnnotationState>()((set, get) => ({
  annotationsByEpisode: {},
  loading: false,
  error: null,

  fetchAnnotations: async (episodeId: string) => {
    set({ loading: true, error: null });
    try {
      const res = await fetch(`/api/episodes/${episodeId}/annotations`);
      if (!res.ok) throw new Error('Failed to fetch annotations');
      const data: Annotation[] = await res.json();
      set((state) => ({
        annotationsByEpisode: {
          ...state.annotationsByEpisode,
          [episodeId]: data,
        },
        loading: false,
      }));
    } catch (err) {
      set({ loading: false, error: err instanceof Error ? err.message : 'Unknown error' });
    }
  },

  addAnnotation: async (body: CreateAnnotationBody) => {
    // 乐观更新
    const tempId = `temp-${Date.now()}-${Math.random().toString(36).slice(2)}`;
    const now = new Date().toISOString();
    const optimistic: Annotation = {
      id: tempId,
      userId: 'demo-user',
      episodeId: body.episodeId,
      segmentId: body.segmentId || null,
      type: body.type,
      color: body.color || 'yellow',
      startOffset: body.startOffset ?? null,
      endOffset: body.endOffset ?? null,
      noteContent: body.noteContent || null,
      createdAt: now,
      updatedAt: now,
    };

    set((state) => ({
      annotationsByEpisode: {
        ...state.annotationsByEpisode,
        [body.episodeId]: [
          ...(state.annotationsByEpisode[body.episodeId] || []),
          optimistic,
        ],
      },
    }));

    try {
      const res = await fetch('/api/annotations', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });
      if (!res.ok) throw new Error('Failed to create annotation');
      const created: Annotation = await res.json();

      // 替换临时 ID
      set((state) => ({
        annotationsByEpisode: {
          ...state.annotationsByEpisode,
          [body.episodeId]: (state.annotationsByEpisode[body.episodeId] || []).map(
            (a) => (a.id === tempId ? created : a)
          ),
        },
      }));
      return created;
    } catch {
      // 回滚
      set((state) => ({
        annotationsByEpisode: {
          ...state.annotationsByEpisode,
          [body.episodeId]: (state.annotationsByEpisode[body.episodeId] || []).filter(
            (a) => a.id !== tempId
          ),
        },
      }));
      return null;
    }
  },

  updateAnnotation: async (id, episodeId, data) => {
    // 乐观更新
    const prev = get().annotationsByEpisode[episodeId] || [];
    set((state) => ({
      annotationsByEpisode: {
        ...state.annotationsByEpisode,
        [episodeId]: prev.map((a) =>
          a.id === id ? { ...a, ...data, updatedAt: new Date().toISOString() } : a
        ),
      },
    }));

    try {
      await fetch(`/api/annotations/${id}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
      });
    } catch {
      // 回滚
      set((state) => ({
        annotationsByEpisode: {
          ...state.annotationsByEpisode,
          [episodeId]: prev,
        },
      }));
    }
  },

  deleteAnnotation: async (id, episodeId) => {
    const prev = get().annotationsByEpisode[episodeId] || [];
    set((state) => ({
      annotationsByEpisode: {
        ...state.annotationsByEpisode,
        [episodeId]: prev.filter((a) => a.id !== id),
      },
    }));

    try {
      await fetch(`/api/annotations/${id}`, { method: 'DELETE' });
    } catch {
      set((state) => ({
        annotationsByEpisode: {
          ...state.annotationsByEpisode,
          [episodeId]: prev,
        },
      }));
    }
  },

  getAnnotationsForSegment: (episodeId, segmentId) => {
    return (get().annotationsByEpisode[episodeId] || []).filter(
      (a) => a.segmentId === segmentId
    );
  },
}));
```

### 2. 新增 `hooks/useTextSelection.ts` — 文本选中检测

```typescript
'use client';

import { useState, useEffect, useCallback, type RefObject } from 'react';

export interface TextSelectionInfo {
  text: string;
  segmentId: string;
  startOffset: number;
  endOffset: number;
  rect: DOMRect;
}

export function useTextSelection(containerRef: RefObject<HTMLElement | null>) {
  const [selection, setSelection] = useState<TextSelectionInfo | null>(null);

  const clearSelection = useCallback(() => {
    setSelection(null);
  }, []);

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    const handleMouseUp = () => {
      // 延迟执行，等 Selection API 更新
      requestAnimationFrame(() => {
        const sel = window.getSelection();
        if (!sel || sel.isCollapsed || !sel.rangeCount) {
          return; // 不在 mouseup 时清除，让 HighlightToolbar 可以处理
        }

        const range = sel.getRangeAt(0);

        // 确认选中范围在 container 内
        if (!container.contains(range.commonAncestorContainer)) {
          setSelection(null);
          return;
        }

        // 从 DOM data-segment-id 属性获取 segmentId
        const startEl = range.startContainer.parentElement?.closest('[data-segment-id]')
          || range.startContainer.closest?.('[data-segment-id]');
        const segmentId = startEl?.getAttribute('data-segment-id');

        if (segmentId) {
          setSelection({
            text: sel.toString().trim(),
            segmentId,
            startOffset: range.startOffset,
            endOffset: range.endOffset,
            rect: range.getBoundingClientRect(),
          });
        }
      });
    };

    const handleMouseDown = (e: MouseEvent) => {
      // 如果点击在 toolbar 上，不清除
      const target = e.target as HTMLElement;
      if (target.closest('[data-highlight-toolbar]')) return;
      setSelection(null);
    };

    container.addEventListener('mouseup', handleMouseUp);
    document.addEventListener('mousedown', handleMouseDown);

    return () => {
      container.removeEventListener('mouseup', handleMouseUp);
      document.removeEventListener('mousedown', handleMouseDown);
    };
  }, [containerRef]);

  return { selection, clearSelection };
}
```

### 3. 新增 `lib/export/types.ts` — 导出系统类型定义

```typescript
export type ExportPlatform = 'obsidian' | 'feishu' | 'dingtalk' | 'markdown';

export interface ExportContent {
  episodeId: string;
  episodeTitle: string;
  podcastTitle: string;
  publishedAt: string | null;
  duration: number | null;
  segments?: {
    startTime: number;
    originalText: string;
    translatedText: string;
  }[];
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
  url?: string;
  markdown?: string;  // 用于 Markdown 下载
  fileName?: string;
  error?: string;
}

export interface ExportAdapter {
  platform: ExportPlatform;
  name: string;
  icon: string; // Lucide icon 名称
  export(content: ExportContent, config: Record<string, unknown>): Promise<ExportResult>;
  validateConfig(config: Record<string, unknown>): boolean;
}
```

### 4. 新增 `lib/export/markdown-generator.ts` — Markdown 生成器

实现 `generateMarkdown(content, options)` 函数。

输出格式参考 PRD 中 3.7.2 的 Markdown 模板：
- 带 YAML frontmatter (title, date, source, podcast, tags)
- "## Highlights & Notes" 区块：每个标注包含时间戳、原文、译文、笔记
- 可选 "## Full Transcript" 区块：完整字幕

```typescript
import type { ExportContent } from './types';

function formatTime(seconds: number): string {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = Math.floor(seconds % 60);
  if (h > 0) return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
  return `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
}

function formatDuration(seconds: number): string {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  if (h > 0) return `${h}h ${m}m`;
  return `${m}m`;
}

export function generateMarkdown(
  content: ExportContent,
  options: { includeFullTranscript: boolean }
): string {
  const lines: string[] = [];

  // YAML frontmatter
  lines.push('---');
  lines.push(`title: "${content.podcastTitle} - ${content.episodeTitle}"`);
  lines.push(`date: ${content.publishedAt || new Date().toISOString()}`);
  lines.push(`source: 10timesPod`);
  lines.push(`podcast: "${content.podcastTitle}"`);
  const tag = content.podcastTitle.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '');
  lines.push(`tags: [podcast, ${tag}]`);
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

  // Highlights & Notes
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

  // Full transcript
  if (options.includeFullTranscript && content.segments && content.segments.length > 0) {
    lines.push('## Full Transcript');
    lines.push('');

    for (const seg of content.segments) {
      lines.push(`**[${formatTime(seg.startTime)}]** ${seg.originalText}`);
      if (seg.translatedText) {
        lines.push(`${seg.translatedText}`);
      }
      lines.push('');
    }
  }

  return lines.join('\n');
}
```

### 5. 新增 `lib/export/adapters/obsidian.ts`

Obsidian 导出适配器：支持 URI Protocol 和 Markdown 文件下载两种模式。

```typescript
import type { ExportAdapter, ExportContent, ExportResult } from '../types';
import { generateMarkdown } from '../markdown-generator';

export class ObsidianAdapter implements ExportAdapter {
  platform = 'obsidian' as const;
  name = 'Obsidian';
  icon = 'BookOpen';

  async export(content: ExportContent, config: Record<string, unknown>): Promise<ExportResult> {
    const markdown = generateMarkdown(content, {
      includeFullTranscript: (config.includeFullTranscript as boolean) ?? false,
    });

    const vaultName = config.vaultName as string;
    const folderPath = (config.folderPath as string) || 'Podcasts';
    const fileName = `${content.podcastTitle} - ${content.episodeTitle}`
      .replace(/[/\\:*?"<>|]/g, '_');

    if (vaultName) {
      // Obsidian URI Protocol
      const encoded = encodeURIComponent(markdown);
      const uri = `obsidian://new?vault=${encodeURIComponent(vaultName)}&file=${encodeURIComponent(`${folderPath}/${fileName}`)}&content=${encoded}`;
      return { success: true, url: uri };
    }

    // Markdown 文件下载
    return {
      success: true,
      markdown,
      fileName: `${fileName}.md`,
    };
  }

  validateConfig(): boolean {
    return true; // Obsidian 不强制配置
  }
}
```

### 6. 新增 `lib/export/adapters/markdown.ts`

纯 Markdown 下载适配器：

```typescript
import type { ExportAdapter, ExportContent, ExportResult } from '../types';
import { generateMarkdown } from '../markdown-generator';

export class MarkdownAdapter implements ExportAdapter {
  platform = 'markdown' as const;
  name = 'Markdown';
  icon = 'FileText';

  async export(content: ExportContent, config: Record<string, unknown>): Promise<ExportResult> {
    const markdown = generateMarkdown(content, {
      includeFullTranscript: (config.includeFullTranscript as boolean) ?? true,
    });

    const fileName = `${content.podcastTitle} - ${content.episodeTitle}`
      .replace(/[/\\:*?"<>|]/g, '_');

    return {
      success: true,
      markdown,
      fileName: `${fileName}.md`,
    };
  }

  validateConfig(): boolean {
    return true;
  }
}
```

### 7. 新增 `lib/export/adapters/feishu.ts` — 飞书占位（Phase 5 实现）

```typescript
import type { ExportAdapter, ExportContent, ExportResult } from '../types';

export class FeishuAdapter implements ExportAdapter {
  platform = 'feishu' as const;
  name = '飞书';
  icon = 'Send';

  async export(_content: ExportContent, config: Record<string, unknown>): Promise<ExportResult> {
    if (!config.accessToken) {
      return { success: false, error: '飞书未授权，请在设置中连接飞书账号' };
    }
    // TODO: Phase 5 实现飞书 API 集成
    return { success: false, error: '飞书导出功能即将上线' };
  }

  validateConfig(config: Record<string, unknown>): boolean {
    return !!config.accessToken;
  }
}
```

### 8. 新增 `lib/export/adapters/dingtalk.ts` — 钉钉占位（Phase 5 实现）

同飞书，创建占位适配器。

### 9. 新增 `lib/export/registry.ts` — 导出注册中心

```typescript
import type { ExportAdapter, ExportPlatform } from './types';
import { ObsidianAdapter } from './adapters/obsidian';
import { MarkdownAdapter } from './adapters/markdown';
import { FeishuAdapter } from './adapters/feishu';
import { DingTalkAdapter } from './adapters/dingtalk';

const adapters: Record<ExportPlatform, ExportAdapter> = {
  obsidian: new ObsidianAdapter(),
  markdown: new MarkdownAdapter(),
  feishu: new FeishuAdapter(),
  dingtalk: new DingTalkAdapter(),
};

export function getExportAdapter(platform: ExportPlatform): ExportAdapter {
  const adapter = adapters[platform];
  if (!adapter) throw new Error(`Unknown export platform: ${platform}`);
  return adapter;
}

export function getAvailableAdapters(): ExportAdapter[] {
  return Object.values(adapters);
}
```

## 重要注意事项

1. **不要修改任何已有文件**，所有文件都是新增
2. 导出目录结构：`lib/export/types.ts`、`lib/export/registry.ts`、`lib/export/markdown-generator.ts`、`lib/export/adapters/*.ts`
3. `useTextSelection` hook 依赖 DOM 上的 `data-segment-id` 属性（Round 2 的 Agent C 会在 SegmentRow 上添加）
4. `annotationStore` 使用乐观更新模式：先更新 UI，再发 API 请求，失败则回滚
5. 确保所有 export 使用 named export（不是 default export）
6. 文件建好后请运行 `npx tsc --noEmit` 检查类型

完成后请确认创建了以下文件：
- stores/annotationStore.ts
- hooks/useTextSelection.ts
- lib/export/types.ts
- lib/export/markdown-generator.ts
- lib/export/adapters/obsidian.ts
- lib/export/adapters/markdown.ts
- lib/export/adapters/feishu.ts
- lib/export/adapters/dingtalk.ts
- lib/export/registry.ts
```

---

## Round 2: Agent C — 字幕标注 UI 组件

### 前置条件

Round 1 的 Agent A 和 Agent B 必须完成。Agent C 依赖：
- `annotations` 表已建（Agent A）
- `annotationStore` 已创建（Agent B）
- `useTextSelection` hook 已创建（Agent B）

### Prompt

```
你是一个 React 19 + TypeScript + Tailwind CSS v4 项目的前端组件开发者。

## 项目上下文

项目名: 10timesPod，双语字幕播客播放器
路径: 当前工作目录就是项目根目录
技术栈: Next.js 16, React 19, TypeScript, Zustand 5, Tailwind CSS v4, shadcn/ui, Lucide React

## 你的任务

改造字幕面板的 UI 组件，使其支持「标注」功能：段落高亮、自由文本选中高亮、浮动工具条、笔记面板。

## 已有的依赖（由其他 Agent 创建）

- `stores/annotationStore.ts` — 标注 Zustand store，提供 `useAnnotationStore`
  - `fetchAnnotations(episodeId)` — 获取某集所有标注
  - `addAnnotation(body)` — 创建标注（乐观更新）
  - `updateAnnotation(id, episodeId, data)` — 更新标注
  - `deleteAnnotation(id, episodeId)` — 删除标注
  - `annotationsByEpisode` — Record<string, Annotation[]>

- `hooks/useTextSelection.ts` — 文本选中 hook
  - `useTextSelection(containerRef)` — 返回 `{ selection, clearSelection }`
  - `selection` 包含：`text, segmentId, startOffset, endOffset, rect`
  - 需要 DOM 元素上有 `data-segment-id` 属性

- Annotation 类型：`{ id, userId, episodeId, segmentId, type, color, startOffset, endOffset, noteContent, createdAt, updatedAt }`

## 现有组件分析

### SegmentRow 组件 (`components/transcript/SegmentRow.tsx`)

当前代码结构：
- `forwardRef` 组件，接收 `segment, isActive, displayMode, onClick`
- 渲染：时间戳 + 原文(text) + 译文(translation)
- 有 active 高亮样式（绿色左边框）
- 无任何标注相关功能

### SubtitlePanel 组件 (`components/transcript/SubtitlePanel.tsx`)

当前代码结构：
- 获取 transcript 数据
- 工具栏：DisplayModeToggle + TranscribeButton
- 渲染 SegmentRow 列表，通过 `useSubtitleSync` 自动滚动

## 需要修改/新增的文件

### 1. 修改 `components/transcript/SegmentRow.tsx` — 添加高亮渲染 + data-segment-id

关键改动：
- 外层 div 添加 `data-segment-id={segment.id}` 属性
- 新增 `annotations` prop（Annotation[]）
- 根据 annotations 中的 highlight 类型标注，渲染背景色
- 如果有 note 类型标注，在段落下方显示笔记内容
- 添加段落级一键高亮：hover 时显示小的高亮按钮

```typescript
interface SegmentRowProps {
  segment: TranscriptSegment;
  isActive: boolean;
  displayMode: DisplayMode;
  onClick: () => void;
  // ---- 新增 ----
  annotations?: Annotation[];
  onHighlightSegment?: (segmentId: string, color: string) => void;
  onRemoveHighlight?: (annotationId: string) => void;
}
```

改造后的渲染逻辑：
- 检查 `annotations` 中是否有 `type === 'highlight'` 且 `segmentId === segment.id` 的记录
- 如有，给 segment 添加背景色：yellow→'bg-yellow-500/15', green→'bg-green-500/15', blue→'bg-blue-500/15', purple→'bg-purple-500/15'
- hover 时右上角显示小的 Highlighter 图标按钮
- 如有 note 类型标注，在译文下方显示笔记：

```tsx
{notes.length > 0 && notes.map(note => (
  <div key={note.id} className="mt-2 pl-3 border-l-2 border-zinc-600">
    <p className="text-zinc-400 text-xs leading-relaxed">📝 {note.noteContent}</p>
  </div>
))}
```

**完整实现示例**（保留所有现有功能，新增标注）：

```tsx
'use client';

import { forwardRef, useState } from 'react';
import { cn } from '@/lib/utils';
import { Highlighter } from 'lucide-react';
import type { TranscriptSegment, DisplayMode, Annotation } from '@/lib/types';

function formatTime(seconds: number): string {
  const mins = Math.floor(seconds / 60);
  const secs = Math.floor(seconds % 60);
  return `${mins}:${secs.toString().padStart(2, '0')}`;
}

const highlightColors: Record<string, string> = {
  yellow: 'bg-yellow-500/15 border-l-yellow-500',
  green: 'bg-green-500/15 border-l-green-500',
  blue: 'bg-blue-500/15 border-l-blue-500',
  purple: 'bg-purple-500/15 border-l-purple-500',
};

interface SegmentRowProps {
  segment: TranscriptSegment;
  isActive: boolean;
  displayMode: DisplayMode;
  onClick: () => void;
  annotations?: Annotation[];
  onHighlightSegment?: (segmentId: string, color: string) => void;
  onRemoveHighlight?: (annotationId: string) => void;
}

export const SegmentRow = forwardRef<HTMLDivElement, SegmentRowProps>(
  function SegmentRow({ segment, isActive, displayMode, onClick, annotations = [], onHighlightSegment, onRemoveHighlight }, ref) {
    const [hovered, setHovered] = useState(false);

    const highlight = annotations.find(a => a.type === 'highlight' && a.segmentId === segment.id);
    const notes = annotations.filter(a => a.type === 'note' && a.segmentId === segment.id);

    const highlightClass = highlight ? highlightColors[highlight.color] || '' : '';

    return (
      <div
        ref={ref}
        data-segment-id={segment.id}
        onClick={onClick}
        onMouseEnter={() => setHovered(true)}
        onMouseLeave={() => setHovered(false)}
        className={cn(
          'flex gap-3 px-4 py-3 cursor-pointer transition-colors border-l-2 relative group',
          highlight
            ? highlightClass
            : isActive
              ? 'bg-zinc-800 border-l-emerald-500'
              : 'border-l-transparent hover:bg-zinc-900'
        )}
      >
        {/* Timestamp */}
        <span className="text-zinc-500 text-xs font-mono pt-0.5 shrink-0 w-12 text-right">
          {formatTime(segment.startTime)}
        </span>

        {/* Text content */}
        <div className="flex-1 min-w-0">
          {(displayMode === 'en' || displayMode === 'bilingual') && (
            <p className={cn('text-base leading-relaxed', isActive ? 'text-white font-medium' : 'text-zinc-200')}>
              {segment.text}
            </p>
          )}

          {(displayMode === 'zh' || displayMode === 'bilingual') && segment.translation && (
            <p className={cn('text-sm leading-relaxed text-zinc-400', displayMode === 'bilingual' ? 'mt-1' : '', isActive && displayMode === 'zh' ? 'text-zinc-200 font-medium' : '')}>
              {segment.translation}
            </p>
          )}

          {(displayMode === 'zh' || displayMode === 'bilingual') && !segment.translation && segment.translationStatus === 'pending' && (
            <p className="text-sm text-zinc-600 italic mt-1">翻译待生成...</p>
          )}

          {/* Notes */}
          {notes.map(note => (
            <div key={note.id} className="mt-2 pl-3 border-l-2 border-zinc-600">
              <p className="text-zinc-400 text-xs leading-relaxed">📝 {note.noteContent}</p>
            </div>
          ))}
        </div>

        {/* Quick highlight button (appears on hover) */}
        {hovered && !highlight && onHighlightSegment && (
          <button
            onClick={(e) => {
              e.stopPropagation();
              onHighlightSegment(segment.id, 'yellow');
            }}
            className="absolute top-2 right-2 p-1.5 rounded bg-zinc-800/80 hover:bg-zinc-700 text-zinc-400 hover:text-yellow-400 transition-colors"
            title="Highlight this segment"
          >
            <Highlighter className="size-3.5" />
          </button>
        )}

        {/* Remove highlight button */}
        {hovered && highlight && onRemoveHighlight && (
          <button
            onClick={(e) => {
              e.stopPropagation();
              onRemoveHighlight(highlight.id);
            }}
            className="absolute top-2 right-2 p-1.5 rounded bg-zinc-800/80 hover:bg-zinc-700 text-zinc-400 hover:text-red-400 transition-colors"
            title="Remove highlight"
          >
            <Highlighter className="size-3.5" />
          </button>
        )}
      </div>
    );
  }
);
```

### 2. 新增 `components/transcript/HighlightToolbar.tsx` — 浮动标注工具条

当用户选中文本时，在选中区域上方弹出一个工具条，包含：
- 4 个颜色按钮（黄、绿、蓝、紫）点击直接高亮
- 1 个笔记按钮（点击后展开内联输入框）

```typescript
'use client';

import { useState } from 'react';
import { createPortal } from 'react-dom';
import { Highlighter, StickyNote, X } from 'lucide-react';
import type { TextSelectionInfo } from '@/hooks/useTextSelection';

interface HighlightToolbarProps {
  selection: TextSelectionInfo;
  onHighlight: (color: string) => void;
  onAddNote: (content: string) => void;
  onClose: () => void;
}

const COLORS = [
  { name: 'yellow', class: 'bg-yellow-500', hover: 'hover:bg-yellow-400' },
  { name: 'green', class: 'bg-green-500', hover: 'hover:bg-green-400' },
  { name: 'blue', class: 'bg-blue-500', hover: 'hover:bg-blue-400' },
  { name: 'purple', class: 'bg-purple-500', hover: 'hover:bg-purple-400' },
];

export function HighlightToolbar({ selection, onHighlight, onAddNote, onClose }: HighlightToolbarProps) {
  const [showNoteInput, setShowNoteInput] = useState(false);
  const [noteText, setNoteText] = useState('');

  // 定位: 在选中文本的上方
  const top = selection.rect.top - 48 + window.scrollY;
  const left = selection.rect.left + selection.rect.width / 2;

  const handleSubmitNote = () => {
    if (noteText.trim()) {
      onAddNote(noteText.trim());
      setNoteText('');
      setShowNoteInput(false);
    }
  };

  return createPortal(
    <div
      data-highlight-toolbar
      className="fixed z-50"
      style={{ top: `${selection.rect.top - 48}px`, left: `${left}px`, transform: 'translateX(-50%)' }}
    >
      <div className="bg-zinc-900 border border-zinc-700 rounded-lg shadow-xl flex items-center gap-1 px-2 py-1.5">
        {/* Color buttons */}
        {COLORS.map(c => (
          <button
            key={c.name}
            onClick={() => onHighlight(c.name)}
            className={`size-5 rounded-full ${c.class} ${c.hover} transition-colors ring-2 ring-transparent hover:ring-white/30`}
            title={`Highlight ${c.name}`}
          />
        ))}

        <div className="w-px h-4 bg-zinc-700 mx-1" />

        {/* Note button */}
        <button
          onClick={() => setShowNoteInput(!showNoteInput)}
          className="p-1 rounded text-zinc-400 hover:text-zinc-200 hover:bg-zinc-800 transition-colors"
          title="Add note"
        >
          <StickyNote className="size-4" />
        </button>

        {/* Close */}
        <button
          onClick={onClose}
          className="p-1 rounded text-zinc-500 hover:text-zinc-300 transition-colors"
        >
          <X className="size-3.5" />
        </button>
      </div>

      {/* Note input */}
      {showNoteInput && (
        <div className="mt-1 bg-zinc-900 border border-zinc-700 rounded-lg p-2 min-w-[280px]">
          <textarea
            autoFocus
            value={noteText}
            onChange={(e) => setNoteText(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter' && !e.shiftKey) {
                e.preventDefault();
                handleSubmitNote();
              }
            }}
            placeholder="Write a note..."
            className="w-full bg-zinc-800 text-zinc-200 text-sm rounded px-3 py-2 resize-none focus:outline-none focus:ring-1 focus:ring-emerald-500"
            rows={2}
          />
          <div className="flex justify-end mt-1.5">
            <button
              onClick={handleSubmitNote}
              disabled={!noteText.trim()}
              className="px-3 py-1 text-xs bg-emerald-600 hover:bg-emerald-500 disabled:bg-zinc-700 disabled:text-zinc-500 text-white rounded transition-colors"
            >
              Save
            </button>
          </div>
        </div>
      )}
    </div>,
    document.body
  );
}
```

### 3. 新增 `components/transcript/NotesPanel.tsx` — 笔记面板

在字幕面板右侧或作为 tab 显示的笔记时间线面板：

```typescript
'use client';

import { useMemo } from 'react';
import { Trash2 } from 'lucide-react';
import { useAnnotationStore, type Annotation } from '@/stores/annotationStore';

interface NotesPanelProps {
  episodeId: string;
  onSeekTo: (time: number) => void;
  // segmentTimes: 用于将 segmentId 映射为 startTime
  segmentTimes: Record<string, number>;
}

function formatTime(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${s.toString().padStart(2, '0')}`;
}

export function NotesPanel({ episodeId, onSeekTo, segmentTimes }: NotesPanelProps) {
  const annotations = useAnnotationStore(s => s.annotationsByEpisode[episodeId] || []);
  const deleteAnnotation = useAnnotationStore(s => s.deleteAnnotation);

  const items = useMemo(() => {
    return annotations
      .filter(a => a.segmentId)
      .sort((a, b) => {
        const timeA = a.segmentId ? (segmentTimes[a.segmentId] ?? 0) : 0;
        const timeB = b.segmentId ? (segmentTimes[b.segmentId] ?? 0) : 0;
        return timeA - timeB;
      });
  }, [annotations, segmentTimes]);

  if (items.length === 0) {
    return (
      <div className="flex-1 flex items-center justify-center p-4">
        <p className="text-zinc-500 text-sm text-center">
          No highlights or notes yet.<br />
          Select text in the transcript to get started.
        </p>
      </div>
    );
  }

  return (
    <div className="flex-1 overflow-y-auto p-3 space-y-2">
      <h3 className="text-xs font-medium text-zinc-400 uppercase tracking-wider px-1">
        Notes & Highlights ({items.length})
      </h3>
      {items.map(item => {
        const time = item.segmentId ? segmentTimes[item.segmentId] : undefined;
        return (
          <div
            key={item.id}
            className="p-3 bg-zinc-800/50 rounded-lg cursor-pointer hover:bg-zinc-800 transition-colors group"
            onClick={() => time !== undefined && onSeekTo(time)}
          >
            <div className="flex items-center justify-between">
              <span className="text-xs text-zinc-500 font-mono">
                {time !== undefined ? `[${formatTime(time)}]` : ''}
              </span>
              <div className="flex items-center gap-1">
                <span className={`size-2 rounded-full bg-${item.color}-500`} />
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    deleteAnnotation(item.id, episodeId);
                  }}
                  className="p-1 text-zinc-600 hover:text-red-400 opacity-0 group-hover:opacity-100 transition-all"
                >
                  <Trash2 className="size-3" />
                </button>
              </div>
            </div>
            <p className="text-sm text-zinc-300 mt-1">
              {item.type === 'highlight' ? '🖍️' : '📝'}{' '}
              {item.noteContent || '(highlighted)'}
            </p>
          </div>
        );
      })}
    </div>
  );
}
```

### 4. 修改 `components/transcript/SubtitlePanel.tsx` — 集成标注功能

在现有的 SubtitlePanel 中集成标注系统：

关键改动：
- 导入 `useAnnotationStore`、`useTextSelection`、`HighlightToolbar`
- 在组件加载时 `fetchAnnotations(episodeId)`
- 给外层容器增加 ref，传给 `useTextSelection`
- 向 `SegmentRow` 传递 `annotations`、`onHighlightSegment`、`onRemoveHighlight` props
- 当 `selection` 非空时渲染 `HighlightToolbar`
- 在工具栏区域增加一个 Notes 面板切换按钮

**你需要保持现有的所有功能完整不变**（DisplayModeToggle、TranscribeButton、SegmentRow 列表、自动滚动），在此基础上添加标注集成。

SubtitlePanel 的改造要点：

```typescript
// 新增 imports
import { useRef, useEffect } from 'react';
import { useAnnotationStore } from '@/stores/annotationStore';
import { useTextSelection } from '@/hooks/useTextSelection';
import { HighlightToolbar } from './HighlightToolbar';
import { StickyNote } from 'lucide-react';

// 在 SubtitlePanel 函数体内：
const transcriptContainerRef = useRef<HTMLDivElement>(null);
const { selection, clearSelection } = useTextSelection(transcriptContainerRef);
const annotations = useAnnotationStore(s => s.annotationsByEpisode[episodeId] || []);
const { fetchAnnotations, addAnnotation, deleteAnnotation } = useAnnotationStore();

// 加载标注
useEffect(() => {
  fetchAnnotations(episodeId);
}, [episodeId, fetchAnnotations]);

// 标注操作
const handleHighlightSegment = async (segmentId: string, color: string) => {
  await addAnnotation({ episodeId, segmentId, type: 'highlight', color });
};

const handleHighlightSelection = async (color: string) => {
  if (!selection) return;
  await addAnnotation({
    episodeId,
    segmentId: selection.segmentId,
    type: 'highlight',
    color,
    startOffset: selection.startOffset,
    endOffset: selection.endOffset,
  });
  clearSelection();
  window.getSelection()?.removeAllRanges();
};

const handleAddNote = async (content: string) => {
  if (!selection) return;
  await addAnnotation({
    episodeId,
    segmentId: selection.segmentId,
    type: 'note',
    noteContent: content,
  });
  clearSelection();
  window.getSelection()?.removeAllRanges();
};

const handleRemoveHighlight = async (annotationId: string) => {
  await deleteAnnotation(annotationId, episodeId);
};
```

在 SegmentRow 的渲染中传入新 props：

```tsx
<SegmentRow
  key={segment.id}
  ref={(el) => registerSegmentRef(index, el)}
  segment={segment}
  isActive={index === activeIndex}
  displayMode={displayMode}
  onClick={() => onSegmentClick(segment.startTime)}
  annotations={annotations.filter(a => a.segmentId === segment.id)}
  onHighlightSegment={handleHighlightSegment}
  onRemoveHighlight={handleRemoveHighlight}
/>
```

渲染 HighlightToolbar：

```tsx
{selection && (
  <HighlightToolbar
    selection={selection}
    onHighlight={handleHighlightSelection}
    onAddNote={handleAddNote}
    onClose={clearSelection}
  />
)}
```

给 transcript scroll 容器加上 ref：

```tsx
<div
  ref={(el) => {
    // 合并两个 ref
    (scrollContainerRef as React.MutableRefObject<HTMLDivElement | null>).current = el;
    (transcriptContainerRef as React.MutableRefObject<HTMLDivElement | null>).current = el;
  }}
  className="flex-1 overflow-y-auto scroll-smooth"
>
```

## 重要注意事项

1. **保持现有功能 100% 不变**：DisplayModeToggle、TranscribeButton、自动滚动、segment 点击跳转
2. Annotation 类型可以从 `@/stores/annotationStore` 或 `@/lib/types` 导入
3. 使用 Lucide React 图标：`Highlighter`, `StickyNote`, `X`, `Trash2`
4. 所有新组件标记为 `'use client'`
5. `data-segment-id` 属性**必须**添加在 SegmentRow 的外层 div 上，`useTextSelection` 依赖它
6. HighlightToolbar 使用 `createPortal` 渲染到 body，避免被 scroll 容器截断
7. 颜色映射使用 Tailwind 的 opacity modifier：`bg-yellow-500/15`
8. 完成后运行 `npx tsc --noEmit` 检查类型
```

---

## Round 2: Agent D — 页面集成 + 导出 UI + Highlights 页面

### 前置条件

Round 1 的 Agent A 和 Agent B 必须完成。Agent D 依赖：
- API 路由已就绪（Agent A）
- Export 基础设施已就绪（Agent B）
- annotationStore 已就绪（Agent B）

### Prompt

```
你是一个 Next.js 16 + React 19 项目的全栈开发者。

## 项目上下文

项目名: 10timesPod，双语字幕播客播放器
路径: 当前工作目录就是项目根目录
技术栈: Next.js 16 (App Router), TypeScript, React 19, Zustand 5, Tailwind CSS v4, shadcn/ui, Lucide React, Drizzle ORM, LibSQL

## 你的任务

创建「高亮回顾页面」、「导出按钮组件」和「导出 API」，并在播放页面集成导出功能。

## 已有的依赖（由其他 Agent 创建）

- **API**:
  - `GET /api/annotations?episodeId=xxx&page=1&limit=50` — 返回 `{ data: [...], page, limit }`
  - `GET /api/episodes/[id]/annotations` — 返回 Annotation[]
  - `POST /api/annotations` — 创建标注
  - `PUT/DELETE /api/annotations/[id]` — 更新/删除标注

- **Export 基础设施**:
  - `lib/export/types.ts` — ExportPlatform, ExportContent, ExportResult, ExportAdapter
  - `lib/export/registry.ts` — `getExportAdapter(platform)`, `getAvailableAdapters()`
  - `lib/export/markdown-generator.ts` — `generateMarkdown(content, options)`
  - `lib/export/adapters/` — obsidian, markdown, feishu, dingtalk

- **Store**:
  - `stores/annotationStore.ts` — `useAnnotationStore` (fetchAnnotations, addAnnotation, etc.)

- **DB**:
  - `annotations` 表、`export_configs` 表
  - `transcripts` 表、`transcriptSegments` 表（已有）

## 需要新增/修改的文件

### 1. 新增 `app/api/export/route.ts` — 导出 API

```typescript
import { NextResponse } from 'next/server';
import { db, initPromise } from '@/lib/db';
import { annotations, episodes, podcasts, transcripts, transcriptSegments } from '@/lib/db/schema';
import { eq, and, asc } from 'drizzle-orm';
import { getExportAdapter } from '@/lib/export/registry';
import type { ExportContent } from '@/lib/export/types';

const DEMO_USER_ID = 'demo-user';

export async function POST(request: Request) {
  await initPromise;
  const body = await request.json();
  const { episodeId, platform, contentType } = body;
  // contentType: 'highlights' | 'highlights_notes' | 'full'

  // 1. 获取 episode + podcast
  const episodeData = await db
    .select({
      episodeId: episodes.id,
      episodeTitle: episodes.title,
      publishedAt: episodes.publishedAt,
      duration: episodes.duration,
      podcastTitle: podcasts.title,
    })
    .from(episodes)
    .innerJoin(podcasts, eq(episodes.podcastId, podcasts.id))
    .where(eq(episodes.id, episodeId))
    .get();

  if (!episodeData) {
    return NextResponse.json({ success: false, error: 'Episode not found' }, { status: 404 });
  }

  // 2. 获取标注 + segment 信息
  const anns = await db
    .select({
      type: annotations.type,
      color: annotations.color,
      noteContent: annotations.noteContent,
      segmentText: transcriptSegments.text,
      segmentTranslation: transcriptSegments.translation,
      segmentStartTime: transcriptSegments.startTime,
    })
    .from(annotations)
    .leftJoin(transcriptSegments, eq(annotations.segmentId, transcriptSegments.id))
    .where(and(
      eq(annotations.episodeId, episodeId),
      eq(annotations.userId, DEMO_USER_ID)
    ))
    .orderBy(asc(transcriptSegments.startTime));

  // 3. 获取字幕（如果需要完整导出）
  let segments = undefined;
  if (contentType === 'full') {
    const transcript = await db
      .select()
      .from(transcripts)
      .where(eq(transcripts.episodeId, episodeId))
      .get();

    if (transcript) {
      const segs = await db
        .select()
        .from(transcriptSegments)
        .where(eq(transcriptSegments.transcriptId, transcript.id))
        .orderBy(asc(transcriptSegments.startTime));

      segments = segs.map(s => ({
        startTime: s.startTime,
        originalText: s.text,
        translatedText: s.translation || '',
      }));
    }
  }

  // 4. 组装 ExportContent
  const exportContent: ExportContent = {
    episodeId,
    episodeTitle: episodeData.episodeTitle,
    podcastTitle: episodeData.podcastTitle,
    publishedAt: episodeData.publishedAt || null,
    duration: episodeData.duration || null,
    segments,
    annotations: anns.map(a => ({
      type: a.type as 'highlight' | 'note',
      color: a.color || 'yellow',
      segmentStartTime: a.segmentStartTime ?? undefined,
      originalText: a.segmentText ?? undefined,
      translatedText: a.segmentTranslation ?? undefined,
      noteContent: a.noteContent ?? undefined,
    })),
  };

  // 5. 导出
  try {
    const adapter = getExportAdapter(platform);
    const result = await adapter.export(exportContent, {});
    return NextResponse.json(result);
  } catch (err) {
    return NextResponse.json({
      success: false,
      error: err instanceof Error ? err.message : 'Export failed',
    });
  }
}
```

### 2. 新增 `components/export/ExportButton.tsx` — 导出按钮 + 弹出面板

一个按钮，点击后弹出面板让用户选择导出平台和内容范围。

```typescript
'use client';

import { useState } from 'react';
import { Download, BookOpen, FileText, Send, X } from 'lucide-react';

type ContentType = 'highlights' | 'highlights_notes' | 'full';

interface ExportButtonProps {
  episodeId: string;
  hasAnnotations: boolean;
}

const platforms = [
  { id: 'obsidian', name: 'Obsidian', icon: BookOpen, available: true },
  { id: 'markdown', name: 'Markdown', icon: FileText, available: true },
  { id: 'feishu', name: '飞书', icon: Send, available: false },
  { id: 'dingtalk', name: '钉钉', icon: Send, available: false },
] as const;

export function ExportButton({ episodeId, hasAnnotations }: ExportButtonProps) {
  const [open, setOpen] = useState(false);
  const [platform, setPlatform] = useState<string>('obsidian');
  const [contentType, setContentType] = useState<ContentType>('highlights_notes');
  const [exporting, setExporting] = useState(false);
  const [result, setResult] = useState<{ success: boolean; message: string } | null>(null);

  const handleExport = async () => {
    setExporting(true);
    setResult(null);
    try {
      const res = await fetch('/api/export', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ episodeId, platform, contentType }),
      });
      const data = await res.json();

      if (data.success) {
        if (data.url) {
          window.open(data.url, '_blank');
          setResult({ success: true, message: 'Opened in app!' });
        } else if (data.markdown && data.fileName) {
          // 触发 Markdown 文件下载
          const blob = new Blob([data.markdown], { type: 'text/markdown' });
          const url = URL.createObjectURL(blob);
          const a = document.createElement('a');
          a.href = url;
          a.download = data.fileName;
          a.click();
          URL.revokeObjectURL(url);
          setResult({ success: true, message: `Downloaded ${data.fileName}` });
        }
      } else {
        setResult({ success: false, message: data.error || 'Export failed' });
      }
    } catch {
      setResult({ success: false, message: 'Export failed' });
    } finally {
      setExporting(false);
    }
  };

  return (
    <div className="relative">
      <button
        onClick={() => setOpen(!open)}
        disabled={!hasAnnotations}
        className="flex items-center gap-1.5 px-3 py-1.5 text-xs bg-zinc-800 hover:bg-zinc-700 disabled:opacity-40 disabled:cursor-not-allowed text-zinc-300 rounded-lg transition-colors"
        title={hasAnnotations ? 'Export highlights & notes' : 'No annotations to export'}
      >
        <Download className="size-3.5" />
        Export
      </button>

      {open && (
        <div className="absolute bottom-full right-0 mb-2 w-72 bg-zinc-900 border border-zinc-700 rounded-xl shadow-2xl p-4 z-50">
          <div className="flex items-center justify-between mb-3">
            <h4 className="text-sm font-medium text-zinc-200">Export to...</h4>
            <button onClick={() => setOpen(false)} className="text-zinc-500 hover:text-zinc-300">
              <X className="size-4" />
            </button>
          </div>

          {/* Content type */}
          <div className="space-y-1.5 mb-3">
            <p className="text-xs text-zinc-500">Content</p>
            {[
              { value: 'highlights', label: 'Highlights only' },
              { value: 'highlights_notes', label: 'Highlights + Notes' },
              { value: 'full', label: 'Full transcript + All' },
            ].map(opt => (
              <label key={opt.value} className="flex items-center gap-2 cursor-pointer">
                <input
                  type="radio"
                  name="contentType"
                  value={opt.value}
                  checked={contentType === opt.value}
                  onChange={() => setContentType(opt.value as ContentType)}
                  className="accent-emerald-500"
                />
                <span className="text-xs text-zinc-300">{opt.label}</span>
              </label>
            ))}
          </div>

          {/* Platform */}
          <div className="space-y-1.5 mb-4">
            <p className="text-xs text-zinc-500">Platform</p>
            <div className="grid grid-cols-2 gap-1.5">
              {platforms.map(p => {
                const Icon = p.icon;
                return (
                  <button
                    key={p.id}
                    onClick={() => p.available && setPlatform(p.id)}
                    disabled={!p.available}
                    className={`flex items-center gap-1.5 px-2.5 py-2 rounded-lg text-xs transition-colors ${
                      platform === p.id
                        ? 'bg-emerald-600/20 text-emerald-400 border border-emerald-600/40'
                        : p.available
                          ? 'bg-zinc-800 text-zinc-300 hover:bg-zinc-700 border border-transparent'
                          : 'bg-zinc-800/50 text-zinc-600 cursor-not-allowed border border-transparent'
                    }`}
                  >
                    <Icon className="size-3.5" />
                    {p.name}
                    {!p.available && <span className="text-[10px] text-zinc-600">Soon</span>}
                  </button>
                );
              })}
            </div>
          </div>

          {/* Export button */}
          <button
            onClick={handleExport}
            disabled={exporting}
            className="w-full py-2 bg-emerald-600 hover:bg-emerald-500 disabled:bg-zinc-700 text-white text-sm font-medium rounded-lg transition-colors"
          >
            {exporting ? 'Exporting...' : 'Export Now'}
          </button>

          {/* Result */}
          {result && (
            <p className={`text-xs mt-2 ${result.success ? 'text-emerald-400' : 'text-red-400'}`}>
              {result.message}
            </p>
          )}
        </div>
      )}
    </div>
  );
}
```

### 3. 新增 `app/highlights/page.tsx` — 高亮回顾页面

展示用户所有高亮和笔记，按播客分组。

```typescript
'use client';

import { useEffect, useState, useMemo } from 'react';
import Link from 'next/link';
import { Search, Highlighter, BookOpen } from 'lucide-react';

interface AnnotationWithContext {
  id: string;
  type: string;
  color: string;
  noteContent: string | null;
  createdAt: string;
  episodeId: string;
  episodeTitle: string;
  podcastId: string;
  podcastTitle: string;
  segmentText: string | null;
  segmentTranslation: string | null;
  segmentStartTime: number | null;
}

export default function HighlightsPage() {
  const [annotations, setAnnotations] = useState<AnnotationWithContext[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');

  useEffect(() => {
    async function fetchAll() {
      try {
        const res = await fetch('/api/annotations?limit=200');
        if (res.ok) {
          const data = await res.json();
          setAnnotations(data.data || []);
        }
      } catch (err) {
        console.error('Failed to fetch annotations:', err);
      } finally {
        setLoading(false);
      }
    }
    fetchAll();
  }, []);

  // 搜索过滤
  const filtered = useMemo(() => {
    if (!search.trim()) return annotations;
    const q = search.toLowerCase();
    return annotations.filter(a =>
      (a.segmentText?.toLowerCase().includes(q)) ||
      (a.segmentTranslation?.toLowerCase().includes(q)) ||
      (a.noteContent?.toLowerCase().includes(q)) ||
      (a.episodeTitle?.toLowerCase().includes(q)) ||
      (a.podcastTitle?.toLowerCase().includes(q))
    );
  }, [annotations, search]);

  // 按 podcast 分组
  const grouped = useMemo(() => {
    const map = new Map<string, { podcastTitle: string; items: AnnotationWithContext[] }>();
    for (const a of filtered) {
      const key = a.podcastId || 'unknown';
      if (!map.has(key)) {
        map.set(key, { podcastTitle: a.podcastTitle || 'Unknown', items: [] });
      }
      map.get(key)!.items.push(a);
    }
    return Array.from(map.entries());
  }, [filtered]);

  function formatTime(seconds: number): string {
    const m = Math.floor(seconds / 60);
    const s = Math.floor(seconds % 60);
    return `${m}:${s.toString().padStart(2, '0')}`;
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-[60vh]">
        <div className="text-zinc-500 text-sm">加载中...</div>
      </div>
    );
  }

  return (
    <div className="max-w-3xl mx-auto px-4 py-8">
      {/* Header */}
      <div className="flex items-center gap-3 mb-6">
        <Highlighter className="size-6 text-yellow-500" />
        <h1 className="text-xl font-semibold text-zinc-50">Highlights & Notes</h1>
        <span className="text-sm text-zinc-500">({annotations.length})</span>
      </div>

      {/* Search */}
      <div className="relative mb-6">
        <Search className="absolute left-3 top-1/2 -translate-y-1/2 size-4 text-zinc-500" />
        <input
          type="text"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Search highlights and notes..."
          className="w-full bg-zinc-900 border border-zinc-800 rounded-lg pl-10 pr-4 py-2.5 text-sm text-zinc-200 placeholder-zinc-600 focus:outline-none focus:ring-1 focus:ring-emerald-500"
        />
      </div>

      {/* Content */}
      {grouped.length === 0 ? (
        <div className="text-center py-16">
          <BookOpen className="size-12 text-zinc-700 mx-auto mb-3" />
          <p className="text-zinc-500">
            {search ? 'No results found' : 'No highlights yet'}
          </p>
          <p className="text-zinc-600 text-sm mt-1">
            Start highlighting text in your podcast transcripts
          </p>
        </div>
      ) : (
        <div className="space-y-8">
          {grouped.map(([podcastId, group]) => (
            <div key={podcastId}>
              <h2 className="text-sm font-medium text-zinc-400 mb-3">
                {group.podcastTitle}
              </h2>
              <div className="space-y-2">
                {group.items.map(item => (
                  <Link
                    key={item.id}
                    href={`/podcasts/${item.podcastId}/episodes/${item.episodeId}`}
                    className="block p-4 bg-zinc-900 hover:bg-zinc-800/80 rounded-xl border border-zinc-800 transition-colors"
                  >
                    <div className="flex items-start gap-3">
                      <span className={`mt-1 size-2.5 rounded-full shrink-0 bg-${item.color}-500`} />
                      <div className="flex-1 min-w-0">
                        {item.segmentText && (
                          <p className="text-sm text-zinc-200 leading-relaxed">
                            {item.segmentText}
                          </p>
                        )}
                        {item.segmentTranslation && (
                          <p className="text-xs text-zinc-500 mt-1">
                            {item.segmentTranslation}
                          </p>
                        )}
                        {item.noteContent && (
                          <p className="text-xs text-zinc-400 mt-2 pl-3 border-l-2 border-zinc-700">
                            📝 {item.noteContent}
                          </p>
                        )}
                        <div className="flex items-center gap-2 mt-2 text-xs text-zinc-600">
                          <span>{item.episodeTitle}</span>
                          {item.segmentStartTime !== null && (
                            <>
                              <span>·</span>
                              <span className="font-mono">{formatTime(item.segmentStartTime)}</span>
                            </>
                          )}
                        </div>
                      </div>
                    </div>
                  </Link>
                ))}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
```

### 4. 修改 `app/podcasts/[id]/episodes/[episodeId]/page.tsx` — 集成导出按钮

在播放页面的 Header 区域（Back 按钮所在行）增加 ExportButton。

**改动点**：
- 导入 `ExportButton` 和 `useAnnotationStore`
- 在 header 右侧添加 ExportButton
- 传入 `episodeId` 和 `hasAnnotations`

```tsx
// 在 import 中新增
import { ExportButton } from '@/components/export/ExportButton';
import { useAnnotationStore } from '@/stores/annotationStore';

// 在组件中
const annotationsForEpisode = useAnnotationStore(s => s.annotationsByEpisode[episodeId] || []);

// 在 Header 中修改
<div className="px-4 py-4 border-b border-zinc-800 shrink-0">
  <div className="flex items-center justify-between mb-2">
    <Link href={`/podcasts/${podcastId}`} className="inline-flex items-center gap-1 text-zinc-400 hover:text-zinc-200 text-sm">
      <ArrowLeft className="size-4" />
      Back
    </Link>
    <ExportButton episodeId={episodeId} hasAnnotations={annotationsForEpisode.length > 0} />
  </div>
  <h1 className="text-lg font-semibold text-zinc-50 leading-tight">{episode.title}</h1>
  {/* ...rest of header */}
</div>
```

### 5. 修改导航（添加 Highlights 入口）

在项目的导航/侧边栏中添加 `/highlights` 页面入口。查找项目中的导航组件（可能是 `components/layout/Sidebar.tsx` 或 `app/layout.tsx` 中的导航），添加一个 Highlights 链接。

使用 Lucide React 的 `Highlighter` 图标，链接到 `/highlights`。

## 重要注意事项

1. **ExportButton 中的文件下载**: 使用 Blob + URL.createObjectURL 实现客户端下载，不需要服务端文件系统操作
2. **highlights 页面的数据格式**: `GET /api/annotations` 返回 JOIN 后的数据，包含 episodeTitle, podcastTitle, segmentText 等
3. 颜色 badge 使用动态 Tailwind class `bg-${color}-500`（注意 Tailwind 的 purge 可能不会扫描到，如果不生效可以改用内联 style）
4. 所有页面组件都是 `'use client'`
5. Next.js 16 的动态参数是 `params: Promise<{...}>`，需要 `use(params)` 解包
6. 完成后运行 `npx tsc --noEmit` 检查类型
```

---

## 执行顺序总结

```
┌─────────────────────────────────────────────┐
│                Round 1 (并行)                │
│                                              │
│  Agent A: Schema + API    Agent B: Export +  │
│  ├─ schema.ts (修改)      Store + Hooks      │
│  ├─ index.ts (修改)       ├─ annotStore      │
│  ├─ types.ts (修改)       ├─ useTextSel      │
│  ├─ api/annotations/      ├─ export/types    │
│  └─ api/episodes/[id]/    ├─ md-generator    │
│     annotations/           ├─ adapters/*      │
│                             └─ registry       │
│                                              │
│  ~15-20 min each         ~15-20 min each     │
└──────────────────┬──────────────────────────┘
                   │ Round 1 完成
                   ▼
┌─────────────────────────────────────────────┐
│                Round 2 (并行)                │
│                                              │
│  Agent C: 标注 UI        Agent D: 页面集成    │
│  ├─ SegmentRow (修改)    ├─ api/export/       │
│  ├─ HighlightToolbar     ├─ ExportButton      │
│  ├─ NotesPanel           ├─ highlights page   │
│  └─ SubtitlePanel (修改) └─ EpisodePage (修改)│
│                                              │
│  ~20-30 min each         ~20-25 min each     │
└──────────────────────────────────────────────┘
                   │
                   ▼
            全部完成 → 集成测试
```

**总计预估**: Round 1 ~20 min + Round 2 ~30 min = 约 50 min 完成全部开发
