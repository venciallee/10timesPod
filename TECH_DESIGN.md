# 10timesPod — 技术设计文档

## 1. 技术栈选型

### 1.1 推荐方案：Next.js 全栈

| 层级 | 技术 | 选型理由 |
|------|------|----------|
| **框架** | Next.js 14 (App Router) | SSR/SSG 灵活切换，API Routes 做后端，一套代码前后端一体 |
| **语言** | TypeScript | 类型安全，适合中大型项目 |
| **UI** | Tailwind CSS + shadcn/ui | 快速构建美观 UI，组件化开箱即用 |
| **状态管理** | Zustand | 轻量、简洁，适合播放器全局状态 |
| **数据库** | SQLite (Turso) / PostgreSQL (Supabase) | MVP 用 SQLite 足够，后期可迁移 PG |
| **ORM** | Drizzle ORM | 类型安全，轻量，SQL-like 写法 |
| **认证** | NextAuth.js (Auth.js) | 支持 Google OAuth + 邮箱登录 |
| **部署** | Vercel / Docker self-host | Vercel 零配置部署，或 Docker 私有化 |

### 1.2 为什么不选前后端分离

MVP 阶段用 Next.js 全栈的优势在于：减少一半的部署和运维工作量，API Routes 天然解决 CORS 问题，且 Server Components 可以直接在服务端调用数据库和外部 API，避免 API Key 暴露。后期如果需要拆分，Next.js 的 API Routes 可以平滑迁移为独立后端。


## 2. 系统架构

### 2.1 整体架构图

```
┌─────────────────────────────────────────────────────────────┐
│                        用户浏览器                            │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────────┐  │
│  │ 播放页面  │  │ 订阅管理  │  │ 模型设置  │  │ 个人中心   │  │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬───────┘  │
│       │              │             │              │          │
│  ┌────┴──────────────┴─────────────┴──────────────┴───┐     │
│  │              Zustand 全局状态管理                     │     │
│  │  (播放状态 / 当前字幕 / 用户设置 / 模型配置)          │     │
│  └────────────────────────┬───────────────────────────┘     │
└───────────────────────────┼─────────────────────────────────┘
                            │ HTTP / WebSocket
┌───────────────────────────┼─────────────────────────────────┐
│                    Next.js Server                            │
│  ┌────────────────────────┴───────────────────────────┐     │
│  │              API Routes (Route Handlers)             │     │
│  ├─────────┬──────────┬───────────┬───────────────────┤     │
│  │ /podcast│ /episode │ /transcript│ /ai              │     │
│  │  RSS解析 │ 单集管理  │ 转录管理   │ AI代理层         │     │
│  └────┬────┴────┬─────┴─────┬─────┴────────┬──────────┘     │
│       │         │           │              │                │
│  ┌────┴─────────┴───────────┴──────────────┴────────┐       │
│  │                 服务层 (Services)                  │       │
│  ├──────────┬───────────┬──────────┬────────────────┤       │
│  │ RSS      │ Audio     │ AI       │ Provider       │       │
│  │ Service  │ Service   │ Service  │ Registry       │       │
│  └────┬─────┴─────┬─────┴────┬─────┴───────┬────────┘       │
│       │           │          │             │                │
│  ┌────┴───┐  ┌────┴───┐  ┌──┴──────┐  ┌───┴────────┐      │
│  │ DB     │  │ Cache  │  │外部 AI  │  │ RSS Feeds  │      │
│  │ SQLite │  │ Redis? │  │ APIs    │  │            │      │
│  └────────┘  └────────┘  └─────────┘  └────────────┘      │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 AI Provider 抽象层（核心设计）

模型设置页的核心技术难点在于抽象一套统一的 AI Provider 接口，屏蔽不同厂商的 API 差异。

```
┌──────────────────────────────────────────────┐
│              AI Service (统一接口)             │
│                                              │
│  transcribe(audio) → TranscriptResult        │
│  translate(text, targetLang) → string        │
│  testConnection(config) → boolean            │
│                                              │
├──────────────────────────────────────────────┤
│           Provider Registry (注册表)          │
│  ┌──────────┐ ┌────────┐ ┌───────────────┐  │
│  │OpenRouter│ │ OpenAI │ │Custom Endpoint│  │
│  │ Provider │ │Provider│ │   Provider    │  │
│  └──────────┘ └────────┘ └───────────────┘  │
│       │            │              │          │
│       ▼            ▼              ▼          │
│  ┌──────────────────────────────────────┐   │
│  │     OpenAI SDK (统一客户端)            │   │
│  │  baseURL 和 apiKey 按 provider 切换   │   │
│  └──────────────────────────────────────┘   │
└──────────────────────────────────────────────┘
```

**关键设计决策**: OpenRouter、OpenAI、以及大多数国内模型服务都兼容 OpenAI API 格式。因此底层统一使用 `openai` SDK，只需切换 `baseURL` 和 `apiKey` 即可适配不同提供方，大幅简化实现。


## 3. 数据模型

### 3.1 核心表结构

```sql
-- 用户表
CREATE TABLE users (
  id            TEXT PRIMARY KEY,
  email         TEXT UNIQUE NOT NULL,
  name          TEXT,
  avatar_url    TEXT,
  created_at    DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 播客表
CREATE TABLE podcasts (
  id            TEXT PRIMARY KEY,
  title         TEXT NOT NULL,
  description   TEXT,
  author        TEXT,
  image_url     TEXT,
  feed_url      TEXT UNIQUE NOT NULL,
  website_url   TEXT,
  language      TEXT DEFAULT 'en',
  is_featured   BOOLEAN DEFAULT FALSE,   -- 是否为推荐播客
  last_fetched  DATETIME,
  created_at    DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 单集表
CREATE TABLE episodes (
  id            TEXT PRIMARY KEY,
  podcast_id    TEXT NOT NULL REFERENCES podcasts(id),
  title         TEXT NOT NULL,
  description   TEXT,
  audio_url     TEXT NOT NULL,
  duration      INTEGER,                  -- 秒
  published_at  DATETIME,
  guid          TEXT UNIQUE,              -- RSS guid 去重
  created_at    DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 转录表（英文）
CREATE TABLE transcripts (
  id            TEXT PRIMARY KEY,
  episode_id    TEXT NOT NULL REFERENCES episodes(id),
  status        TEXT DEFAULT 'pending',   -- pending / processing / completed / failed
  model_used    TEXT,                     -- e.g. whisper-large-v3
  created_at    DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 转录段落（逐句）
CREATE TABLE transcript_segments (
  id            TEXT PRIMARY KEY,
  transcript_id TEXT NOT NULL REFERENCES transcripts(id),
  segment_index INTEGER NOT NULL,
  start_time    REAL NOT NULL,            -- 秒，如 12.5
  end_time      REAL NOT NULL,
  text          TEXT NOT NULL,
  speaker       TEXT,                     -- 说话人（如可识别）
  translation   TEXT,                     -- 中文翻译
  translation_status TEXT DEFAULT 'pending' -- pending / completed
);

-- 用户订阅关系
CREATE TABLE subscriptions (
  user_id       TEXT NOT NULL REFERENCES users(id),
  podcast_id    TEXT NOT NULL REFERENCES podcasts(id),
  subscribed_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, podcast_id)
);

-- 播放进度
CREATE TABLE play_progress (
  user_id       TEXT NOT NULL REFERENCES users(id),
  episode_id    TEXT NOT NULL REFERENCES episodes(id),
  position      REAL NOT NULL DEFAULT 0,  -- 当前播放位置（秒）
  completed     BOOLEAN DEFAULT FALSE,
  updated_at    DATETIME DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, episode_id)
);

-- 模型配置（每用户）
CREATE TABLE ai_configs (
  id            TEXT PRIMARY KEY,
  user_id       TEXT NOT NULL REFERENCES users(id),
  provider      TEXT NOT NULL,            -- 'openrouter' | 'openai' | 'custom'
  api_key_enc   TEXT NOT NULL,            -- 加密存储的 API Key
  base_url      TEXT,                     -- 自定义端点 URL
  transcription_model TEXT DEFAULT 'whisper-large-v3',
  translation_model   TEXT DEFAULT 'gpt-4o-mini',
  is_active     BOOLEAN DEFAULT TRUE,
  created_at    DATETIME DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(user_id, provider)
);
```


## 4. API 设计

### 4.1 核心 API 端点

```
# 播客管理
POST   /api/podcasts/subscribe     - 订阅播客 (body: { feedUrl })
DELETE /api/podcasts/:id/unsubscribe - 取消订阅
GET    /api/podcasts/subscriptions  - 获取用户订阅列表
GET    /api/podcasts/featured       - 获取推荐播客列表
GET    /api/podcasts/:id            - 获取播客详情
GET    /api/podcasts/:id/episodes   - 获取单集列表（分页）

# 单集与转录
GET    /api/episodes/:id            - 获取单集详情
GET    /api/episodes/:id/transcript - 获取转录（含翻译）
POST   /api/episodes/:id/transcribe - 触发转录任务
POST   /api/episodes/:id/translate  - 触发翻译任务

# 实时翻译（流式）
POST   /api/translate/stream        - 实时翻译（SSE 流式返回）
       body: { segments: [...], model: string }

# AI 配置
GET    /api/settings/ai             - 获取当前 AI 配置
PUT    /api/settings/ai             - 更新 AI 配置
POST   /api/settings/ai/test        - 测试连接

# 播放进度
PUT    /api/progress/:episodeId     - 更新播放进度
GET    /api/progress/recent         - 获取最近播放列表

# 认证
POST   /api/auth/[...nextauth]      - NextAuth 认证端点
```

### 4.2 关键 API 详细设计

#### 转录接口响应格式
```json
{
  "episodeId": "ep_xxx",
  "status": "completed",
  "segments": [
    {
      "index": 0,
      "startTime": 0.0,
      "endTime": 5.2,
      "text": "Welcome to today's episode.",
      "translation": "欢迎收听今天的节目。",
      "speaker": "Host"
    },
    {
      "index": 1,
      "startTime": 5.2,
      "endTime": 12.8,
      "text": "We're going to talk about artificial intelligence.",
      "translation": "我们将讨论人工智能。",
      "speaker": "Host"
    }
  ]
}
```

#### AI 配置接口
```json
// PUT /api/settings/ai
{
  "provider": "openrouter",
  "apiKey": "sk-or-v1-xxxx",
  "baseUrl": null,
  "transcriptionModel": "openai/whisper-large-v3",
  "translationModel": "anthropic/claude-sonnet-4"
}

// POST /api/settings/ai/test 响应
{
  "success": true,
  "provider": "openrouter",
  "models": ["openai/whisper-large-v3", "anthropic/claude-sonnet-4", ...],
  "message": "连接成功，已获取可用模型列表"
}
```


## 5. 核心模块设计

### 5.1 RSS 解析服务

```typescript
// services/rss.ts
interface RSSService {
  // 解析 RSS Feed，返回播客信息和单集列表
  parseFeed(feedUrl: string): Promise<{
    podcast: PodcastMeta;
    episodes: EpisodeMeta[];
  }>;

  // 定时刷新所有订阅的 RSS Feed
  refreshFeeds(): Promise<void>;
}
```

使用 `rss-parser` 库解析 RSS/Atom Feed。需处理的边界情况包括：不同的 enclosure 格式、iTunes 特有标签（`<itunes:duration>`, `<itunes:image>`）、Feed 编码问题。

### 5.2 AI Provider 系统

```typescript
// services/ai/types.ts
interface AIProvider {
  id: string;                    // 'openrouter' | 'openai' | 'custom'
  name: string;
  baseUrl: string;
  supportedCapabilities: ('transcription' | 'translation' | 'chat')[];

  // 获取可用模型列表
  listModels(apiKey: string): Promise<ModelInfo[]>;

  // 测试连接
  testConnection(apiKey: string): Promise<TestResult>;
}

interface TranscriptionService {
  transcribe(audioUrl: string, config: AIConfig): Promise<TranscriptSegment[]>;
}

interface TranslationService {
  // 批量翻译（预生成）
  translateBatch(segments: string[], config: AIConfig): Promise<string[]>;

  // 流式翻译（实时）
  translateStream(text: string, config: AIConfig): AsyncGenerator<string>;
}

// services/ai/provider-registry.ts
class ProviderRegistry {
  private providers = new Map<string, AIProvider>();

  register(provider: AIProvider) { ... }
  get(id: string): AIProvider { ... }

  // 根据用户配置创建 OpenAI 兼容客户端
  createClient(config: AIConfig): OpenAI {
    const provider = this.get(config.provider);
    return new OpenAI({
      apiKey: config.apiKey,
      baseURL: config.baseUrl || provider.baseUrl,
    });
  }
}
```

**各 Provider 的 BaseURL**:

| Provider | Base URL | 说明 |
|----------|----------|------|
| OpenRouter | `https://openrouter.ai/api/v1` | 聚合网关，支持所有主流模型 |
| OpenAI | `https://api.openai.com/v1` | 直连 OpenAI |
| Custom | 用户自定义 | 如 `http://localhost:11434/v1`（Ollama） |

### 5.3 转录流水线

```
用户点击"生成转录"
        │
        ▼
┌─────────────────┐
│ 1. 下载音频到临时 │  (or stream from URL)
│    存储           │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 2. 调用 Whisper  │  POST /audio/transcriptions
│    API 转录      │  (支持 OpenAI / OpenRouter)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 3. 解析返回的    │  提取 segments + timestamps
│    时间戳数据    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 4. 存入数据库    │  transcript_segments 表
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 5. 触发翻译任务  │  异步批量翻译
└─────────────────┘
```

**转录优化策略**: 对于长音频（>1小时），分片处理每次 30 分钟，并行调用 Whisper API 后拼接结果。

### 5.4 翻译策略

翻译采用"预生成 + 实时兜底"的双轨策略：

**预生成翻译**: 转录完成后自动触发，将所有 segments 按 20 句一组打包发给 LLM，Prompt 要求保持上下文连贯：

```
你是一个专业的播客字幕翻译员。请将以下英文播客转录文本翻译为自然流畅的中文。
要求：
1. 保持口语化，符合播客对话风格
2. 专业术语保留英文并在括号内注中文
3. 每句独立翻译，保持与原文一一对应
4. 不要添加或省略内容

英文原文：
[1] So today we're going to talk about artificial intelligence.
[2] I think the most interesting thing is how fast things are moving.
...

请按相同编号格式返回中文翻译。
```

**实时翻译**: 如果用户播放到尚未翻译的段落，前端通过 SSE 流式接口实时请求翻译，逐句返回并缓存到数据库。


### 5.5 字幕同步引擎（前端）

```typescript
// hooks/useSubtitleSync.ts
function useSubtitleSync(segments: TranscriptSegment[]) {
  const audioRef = useRef<HTMLAudioElement>(null);
  const [activeIndex, setActiveIndex] = useState(0);

  useEffect(() => {
    const audio = audioRef.current;
    if (!audio || !segments.length) return;

    const onTimeUpdate = () => {
      const currentTime = audio.currentTime;
      // 二分查找当前时间对应的 segment
      const index = binarySearchSegment(segments, currentTime);
      if (index !== activeIndex) {
        setActiveIndex(index);
        // 自动滚动到当前句
        scrollToSegment(index);
      }
    };

    audio.addEventListener('timeupdate', onTimeUpdate);
    return () => audio.removeEventListener('timeupdate', onTimeUpdate);
  }, [segments, activeIndex]);

  return { activeIndex, audioRef };
}
```

使用二分查找保证 O(log n) 性能，即使 2 小时播客有几千个 segments 也能流畅同步。


## 6. 模型设置页技术细节

### 6.1 配置存储策略

```
┌─────────────┐
│  用户浏览器   │
│             │
│ localStorage│──┐
│ (API Key    │  │  首次加载时读取
│  encrypted) │  │  用户修改时写入
└─────────────┘  │
                 │
                 ▼
         ┌──────────────┐         ┌──────────────┐
         │  前端状态      │ ──────→│ API Routes   │
         │  (Zustand)   │  请求时  │ 代理转发     │
         │  provider    │  附带   │              │
         │  apiKey      │  config │ 解密 Key     │
         │  models      │         │ 调用外部 AI  │
         └──────────────┘         └──────────────┘
```

**安全设计**:
- API Key 在前端使用 AES-GCM 加密后存入 localStorage，解密密钥派生自用户 session token
- 所有 AI API 调用走后端 Route Handler 代理，前端永远不直接调用外部 API
- 后端接收到请求后解密 Key，调用对应 Provider，返回结果
- 同时在服务端 `ai_configs` 表备份加密配置，支持跨设备同步

### 6.2 模型设置页组件结构

```typescript
// app/settings/page.tsx
<SettingsPage>
  <ProviderSelector>          // 下拉选择：OpenRouter / OpenAI / 自定义
    <ProviderCard>            // 每个 Provider 的配置卡片
      <APIKeyInput />         // 密文输入 + 显示/隐藏切换
      <BaseURLInput />        // 仅自定义模式显示
      <ConnectionTestBtn />   // 测试连接 → 显示结果
    </ProviderCard>
  </ProviderSelector>

  <ModelSelector>
    <TranscriptionModelPicker />  // Whisper 模型选择
    <TranslationModelPicker />    // LLM 模型选择（下拉 + 搜索）
  </ModelSelector>

  <UsageStats />              // 显示本月用量概览（可选）
</SettingsPage>
```

### 6.3 Provider 配置预设

```typescript
const PROVIDER_PRESETS = {
  openrouter: {
    name: 'OpenRouter',
    baseUrl: 'https://openrouter.ai/api/v1',
    description: '聚合网关，一个 Key 访问所有主流模型',
    modelsEndpoint: '/models',
    defaultTranscriptionModel: 'openai/whisper-large-v3',
    defaultTranslationModel: 'anthropic/claude-sonnet-4',
    docUrl: 'https://openrouter.ai/keys',
  },
  openai: {
    name: 'OpenAI',
    baseUrl: 'https://api.openai.com/v1',
    description: '直连 OpenAI 官方 API',
    modelsEndpoint: '/models',
    defaultTranscriptionModel: 'whisper-1',
    defaultTranslationModel: 'gpt-4o-mini',
    docUrl: 'https://platform.openai.com/api-keys',
  },
  custom: {
    name: '自定义端点',
    baseUrl: '', // 用户填写
    description: '兼容 OpenAI API 格式的任意端点（Ollama, Azure, 国内代理等）',
    modelsEndpoint: '/models',
    defaultTranscriptionModel: '',
    defaultTranslationModel: '',
    docUrl: '',
  },
};
```


## 7. 前端路由与页面结构

```
app/
├── layout.tsx                 # 全局布局 + 底部播放栏
├── page.tsx                   # 首页（发现/推荐）
├── podcasts/
│   └── [id]/
│       ├── page.tsx           # 播客详情 + 单集列表
│       └── episodes/
│           └── [episodeId]/
│               └── page.tsx   # 播放页（核心）
├── subscriptions/
│   └── page.tsx               # 订阅管理
├── settings/
│   ├── page.tsx               # 设置首页
│   └── ai/
│       └── page.tsx           # 模型设置页
├── profile/
│   └── page.tsx               # 个人中心
└── api/
    ├── podcasts/              # 播客相关 API
    ├── episodes/              # 单集相关 API
    ├── translate/             # 翻译 API
    ├── settings/              # 设置 API
    ├── progress/              # 播放进度 API
    └── auth/                  # 认证 API
```


## 8. 关键技术方案

### 8.1 音频播放与跨域

播客音频文件通常托管在 CDN 上，部分可能有跨域限制。解决方案：

- **优先直连**: 大多数播客 CDN 允许跨域，前端 `<audio>` 标签直接播放
- **后端代理兜底**: 对于有跨域限制的音频，通过 `/api/audio/proxy?url=xxx` 后端代理流式转发

### 8.2 长音频转录优化

一集播客通常 30-120 分钟，完整转录耗时较长。优化方案：

- 按 30 分钟分片，并行调用 Whisper API
- 转录任务异步执行，前端轮询状态
- 转录结果全局缓存，同一单集不重复转录
- 未来可引入 Whisper local 模型在服务端运行

### 8.3 实时翻译流式传输

```typescript
// app/api/translate/stream/route.ts
export async function POST(req: Request) {
  const { segments, config } = await req.json();
  const client = providerRegistry.createClient(config);

  const stream = new ReadableStream({
    async start(controller) {
      for (const segment of segments) {
        const result = await client.chat.completions.create({
          model: config.translationModel,
          messages: [
            { role: 'system', content: TRANSLATION_PROMPT },
            { role: 'user', content: segment.text },
          ],
          stream: true,
        });

        let translation = '';
        for await (const chunk of result) {
          const text = chunk.choices[0]?.delta?.content || '';
          translation += text;
          controller.enqueue(
            encoder.encode(`data: ${JSON.stringify({
              segmentIndex: segment.index,
              partial: translation,
            })}\n\n`)
          );
        }
      }
      controller.close();
    },
  });

  return new Response(stream, {
    headers: { 'Content-Type': 'text/event-stream' },
  });
}
```


## 9. 项目目录结构

```
10timespod/
├── app/                       # Next.js App Router 页面
├── components/                # 共享组件
│   ├── ui/                    # shadcn/ui 基础组件
│   ├── player/                # 播放器组件
│   │   ├── AudioPlayer.tsx
│   │   ├── PlayBar.tsx        # 底部常驻播放栏
│   │   ├── SpeedControl.tsx
│   │   └── ProgressBar.tsx
│   ├── transcript/            # 字幕组件
│   │   ├── SubtitlePanel.tsx  # 字幕面板
│   │   ├── SegmentRow.tsx     # 单句行（英+中）
│   │   └── DisplayModeToggle.tsx
│   ├── podcast/               # 播客相关组件
│   │   ├── PodcastCard.tsx
│   │   ├── EpisodeList.tsx
│   │   └── SubscribeButton.tsx
│   └── settings/              # 设置组件
│       ├── ProviderSelector.tsx
│       ├── APIKeyInput.tsx
│       ├── ModelPicker.tsx
│       └── ConnectionTest.tsx
├── services/                  # 后端服务层
│   ├── rss.ts                 # RSS 解析
│   ├── ai/
│   │   ├── provider-registry.ts
│   │   ├── transcription.ts
│   │   ├── translation.ts
│   │   └── providers/
│   │       ├── openrouter.ts
│   │       ├── openai.ts
│   │       └── custom.ts
│   └── db/
│       ├── schema.ts          # Drizzle schema
│       └── queries.ts
├── hooks/                     # 自定义 Hooks
│   ├── useAudioPlayer.ts
│   ├── useSubtitleSync.ts
│   └── useAIConfig.ts
├── stores/                    # Zustand stores
│   ├── playerStore.ts
│   └── settingsStore.ts
├── lib/                       # 工具函数
│   ├── crypto.ts              # API Key 加解密
│   ├── constants.ts           # 常量（Provider 预设等）
│   └── utils.ts
├── drizzle/                   # 数据库迁移
├── public/                    # 静态资源
├── package.json
├── tailwind.config.ts
├── drizzle.config.ts
└── next.config.ts
```


## 10. 部署方案

### 10.1 MVP 推荐：Vercel + Turso

```
┌──────────┐     ┌──────────┐     ┌──────────┐
│  Vercel  │────→│  Turso   │     │ External │
│ (Next.js)│     │ (SQLite) │     │ AI APIs  │
│          │────────────────────→│(OpenRouter│
│          │     │          │     │ / OpenAI)│
└──────────┘     └──────────┘     └──────────┘
```

- Vercel 免费计划足够 MVP 阶段使用
- Turso（分布式 SQLite）免费额度 9GB 存储 + 500M 读取
- 无需管理服务器，零运维

### 10.2 长期：Docker Self-host

如果需要私有化部署或控制成本，提供 Docker Compose 一键部署方案，包含 Next.js App + PostgreSQL + Redis（可选）。


## 11. 开发计划（对应 PRD 里程碑）

### M1: 基础播放（Week 1-2）
- 搭建 Next.js 项目骨架 + 数据库 schema
- RSS 解析服务 + 播客订阅功能
- 音频播放器组件（播放/暂停/进度/变速）
- 热门播客预置数据

### M2: 转录与翻译（Week 3-4）
- AI Provider 抽象层 + OpenRouter/OpenAI 实现
- **模型设置页**（Provider 选择 + API Key + 连接测试）
- Whisper 转录流水线
- 翻译服务（预生成 + 实时流式）
- 字幕同步引擎 + 双语对照 UI

### M3: 体验完善（Week 5-6）
- 用户认证（NextAuth + Google OAuth）
- 播放进度持久化 + 续播
- 底部常驻播放栏
- 响应式 UI 打磨
- 首页推荐布局

### M4: AI 增强（Week 7-9）
- AI 单集摘要
- 自动章节识别
- 播客搜索（集成 PodcastIndex API）
