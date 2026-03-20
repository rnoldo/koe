# KidsTV Pad Web 原型 — 开发任务清单

## 项目脚手架 + 设计系统
- [x] Next.js 14+ 项目初始化 (App Router + TypeScript + Tailwind)
- [x] 安装依赖 (zustand, @dnd-kit, lucide-react)
- [x] Claude 设计 tokens 配置 (globals.css)
- [x] 基础 UI 组件 (Button, Input)
- [x] 图标系统 (ChannelIcon + lucide 导出)

## 数据层
- [x] TypeScript 类型定义 (types/index.ts)
- [x] Mock 数据 (data/mock.ts)
- [x] Zustand store + persist (store/index.ts)

## 儿童前台
- [x] 频道选择主页 (/kids) — 轮播 + 动画
- [x] Mock 播放页 (/kids/play) — 模拟播放 + 进度
- [x] 左右换台 (触摸/键盘/点击)
- [x] 电视雪花切台动画
- [x] 上滑节目单 (playlist overlay)
- [x] 自动连播 (视频结束 → 下一集)
- [x] 断点续播 (切台回来恢复进度)
- [x] 启动恢复 (入口页重定向)

## 家长后台
- [x] PIN 验证入口 (/admin)
- [x] 后台布局 (admin/layout.tsx — 导航 + 权限守卫)
- [x] 媒体源管理 (/admin/sources)
- [x] 视频库浏览 (/admin/library) — 网格/列表 + 搜索筛选
- [x] 频道列表 (/admin/channels) — 拖拽排序
- [x] 频道编辑器 (/admin/channels/[id]) — 视频选择器 + 拖拽排序
- [x] 设置页 (/admin/settings) — PIN/时长/音量

## 观看管控
- [x] 观看时长累计 (每10秒记一次)
- [x] 每日限额判断
- [x] 时间段判断
- [x] 超时锁定界面 (PIN 解锁)

## 打磨
- [x] 空状态 (无频道/无视频)
- [x] 进度条动画
- [ ] 频道切换过渡动画优化
- [ ] 首次使用引导
- [ ] 响应式适配 (手机/平板/桌面)
