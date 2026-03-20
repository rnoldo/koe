# KidsTV Pad — Web 原型实现方案

## 技术栈

- **框架**: Next.js 16 (App Router) + TypeScript
- **样式**: Tailwind CSS v4 + Claude 设计 tokens
- **状态**: Zustand + persist middleware (localStorage)
- **拖拽**: @dnd-kit/core + @dnd-kit/sortable
- **图标**: lucide-react
- **后端**: 无，纯前端 mock 数据

## 设计 tokens

```
主色: #C15F3C / 深色: #ae5630
背景: #F4F3EE / 灰: #B1ADA1 / 前景: #2C2C2C
字体: ui-serif, Georgia, Cambria, "Times New Roman", Times, serif
间距: 4px 网格
```

## 路由架构

| 路由 | 文件 | 用途 |
|------|------|------|
| `/` | `app/page.tsx` | 入口 → 有上次频道则跳 `/kids/play`，否则 `/kids` |
| `/kids` | `app/kids/page.tsx` | 频道选择主页（轮播） |
| `/kids/play` | `app/kids/play/page.tsx` | 模拟视频播放 + 换台 + 节目单 |
| `/admin` | `app/admin/page.tsx` | PIN 验证 |
| `/admin/sources` | `app/admin/sources/page.tsx` | 媒体源管理 |
| `/admin/library` | `app/admin/library/page.tsx` | 视频库浏览 |
| `/admin/channels` | `app/admin/channels/page.tsx` | 频道列表（拖拽排序） |
| `/admin/channels/[id]` | `app/admin/channels/[id]/page.tsx` | 频道编辑器 |
| `/admin/settings` | `app/admin/settings/page.tsx` | 设置 |

## 数据模型 (`src/types/index.ts`)

- **MediaSource** — 媒体源（SMB/WebDAV/阿里云盘等）
- **Video** — 视频元数据
- **Channel** — 频道（含 videoIds 列表）
- **PlaybackState** — 按频道保存播放进度
- **WatchTimeRecord** — 每日观看时长
- **AppSettings** — 全局设置（PIN、时长限制、音量等）

## 状态管理 (`src/store/index.ts`)

Zustand store 包含：
- 数据 CRUD（sources / videos / channels）
- 播放状态保存与恢复
- 观看时长追踪 + 超限判断
- PIN 认证
- 设置管理
- localStorage 持久化（刷新后状态保持）

## 组件结构

```
src/
├── app/                    # Next.js App Router 页面
│   ├── admin/              # 家长后台
│   │   ├── layout.tsx      # 后台导航 shell
│   │   ├── page.tsx        # PIN 验证入口
│   │   ├── sources/        # 媒体源管理
│   │   ├── library/        # 视频库
│   │   ├── channels/       # 频道管理 + 编辑器
│   │   └── settings/       # 设置
│   ├── kids/               # 儿童前台
│   │   ├── page.tsx        # 频道选择
│   │   └── play/           # 播放页
│   ├── layout.tsx          # 根布局
│   └── page.tsx            # 入口重定向
├── components/
│   ├── icons.tsx           # 图标统一导出 + ChannelIcon
│   └── ui/                 # 基础 UI 组件
│       ├── button.tsx
│       └── input.tsx
├── data/
│   └── mock.ts             # Mock 数据
├── store/
│   └── index.ts            # Zustand store
└── types/
    └── index.ts            # TypeScript 类型
```

## 关键交互

### 儿童端
1. **频道选择**: 轮播 UI，左右箭头或滑动切换，点击开始观看
2. **播放页**:
   - 模拟视频播放（彩色背景 + 计时器）
   - 左右滑动/点击边缘: 切台（带电视雪花动画）
   - 点击屏幕中央: 显示/隐藏控制层
   - 上滑/键盘↑: 打开节目单
   - 自动记忆进度，切回频道时恢复
   - 播完自动播下一集
3. **锁定界面**: 超时后覆盖全屏，需 PIN 解锁

### 家长端
1. PIN 数字键盘验证
2. 顶部导航: 媒体源 | 视频库 | 频道 | 设置
3. 媒体源: 添加/删除/扫描，状态指示灯
4. 视频库: 网格/列表切换，按源筛选，搜索
5. 频道管理: 拖拽排序，频道编辑器（图标/颜色/音量/视频选择器）
6. 设置: PIN修改、每日限额滑块、时间段、全局音量
