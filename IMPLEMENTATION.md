# KidsTV Pad — SwiftUI Native 实现方案

## 1. 技术栈总览

| 层级 | 技术选型 | 说明 |
|------|---------|------|
| UI 框架 | SwiftUI | iPad 原生，支持 iPadOS 16+ |
| 播放引擎 | KSPlayer | 基于 AVPlayer + FFmpeg，格式兼容性强，原生支持 SwiftUI |
| 本地数据库 | SwiftData | Apple 原生 ORM，配合 SwiftUI 数据绑定最自然 |
| 网络存储 - WebDAV | SWXMLHash + URLSession | WebDAV 本质是 HTTP 扩展，可直接用 URLSession 实现 PROPFIND/GET |
| 网络存储 - SMB | AMSMB2 | 成熟的 Swift SMB2/3 客户端库 |
| 网络存储 - 阿里云盘 | 阿里云盘 Open API | OAuth2 授权，REST API |
| 网络存储 - 百度网盘 | 百度网盘 Open API | OAuth2 授权，REST API |
| 网络存储 - 115网盘 | 逆向 API / Cookie 登录 | 115 无官方开放 API，参考 Alist 实现 |
| 媒体服务 - Emby | Emby REST API | 通过 API 获取媒体库列表及流地址 |
| 媒体服务 - Jellyfin | Jellyfin REST API | 与 Emby API 高度兼容，可共用大部分代码 |
| 缩略图生成 | AVAssetImageGenerator | 从视频流中按时间点截取帧 |
| 后台任务 | BGTaskScheduler | iOS 原生后台任务调度，用于定期扫描更新 |
| 密码存储 | Keychain Services | 家长密码安全存储 |
| 包管理 | Swift Package Manager | 统一依赖管理 |

---

## 2. 项目架构

```
KidsTVPad/
├── App/
│   ├── KidsTVPadApp.swift              # 应用入口
│   └── AppState.swift                  # 全局应用状态（当前模式、锁定状态等）
│
├── Models/                             # SwiftData 模型
│   ├── MediaSource.swift               # 媒体源配置
│   ├── Video.swift                     # 视频元数据
│   ├── Channel.swift                   # 频道
│   ├── ChannelVideo.swift              # 频道-视频关联（含排序）
│   ├── PlaybackState.swift             # 播放进度记录
│   ├── WatchTimeRecord.swift           # 观看时长记录
│   └── AppSettings.swift              # 全局设置
│
├── Services/
│   ├── Storage/                        # 存储协议层
│   │   ├── StorageProvider.swift       # 统一协议接口
│   │   ├── LocalStorageProvider.swift
│   │   ├── WebDAVProvider.swift
│   │   ├── SMBProvider.swift
│   │   ├── AliyunDriveProvider.swift
│   │   ├── BaiduPanProvider.swift
│   │   ├── Pan115Provider.swift
│   │   ├── EmbyProvider.swift
│   │   └── JellyfinProvider.swift
│   │
│   ├── MediaIndexer.swift              # 媒体扫描与索引服务
│   ├── ThumbnailService.swift          # 缩略图生成与缓存
│   ├── PlaybackEngine.swift            # 播放控制封装
│   ├── WatchTimeGuard.swift            # 观看时长管控
│   └── BackgroundTaskManager.swift     # 后台任务调度
│
├── Views/
│   ├── Kids/                           # 儿童前台界面
│   │   ├── KidsHomeView.swift          # 频道选择主界面
│   │   ├── ChannelPlayerView.swift     # 频道播放界面
│   │   ├── ChannelPlaylistView.swift   # 频道内视频列表
│   │   ├── ChannelSwitcher.swift       # 换台动画/手势组件
│   │   └── LockScreenView.swift        # 超时锁定界面
│   │
│   ├── Admin/                          # 家长后台界面
│   │   ├── AdminEntryView.swift        # 密码验证入口
│   │   ├── AdminDashboard.swift        # 后台主界面
│   │   ├── SourceManagement/           # 媒体源管理
│   │   │   ├── SourceListView.swift
│   │   │   ├── AddSourceView.swift
│   │   │   └── SourceDetailView.swift
│   │   ├── Library/                    # 视频库
│   │   │   ├── LibraryView.swift
│   │   │   └── VideoDetailView.swift
│   │   ├── Channels/                   # 频道管理
│   │   │   ├── ChannelListView.swift
│   │   │   ├── ChannelEditorView.swift
│   │   │   └── VideoPickerView.swift
│   │   └── Settings/                   # 设置
│   │       ├── SettingsView.swift
│   │       ├── WatchTimeSettingsView.swift
│   │       └── PasswordSettingsView.swift
│   │
│   └── Shared/                         # 共享组件
│       ├── VideoThumbnailView.swift
│       ├── ChannelIconView.swift
│       └── SearchBar.swift
│
└── Utilities/
    ├── VideoFileDetector.swift          # 视频文件格式识别
    ├── MetadataExtractor.swift          # 元数据提取
    └── DateHelper.swift
```

---

## 3. 数据模型设计

### 3.1 MediaSource — 媒体源

```swift
@Model
class MediaSource {
    var id: UUID
    var name: String                     // 用户自定义名称
    var type: SourceType                 // local / webdav / smb / aliyun / baidu / pan115 / emby / jellyfin
    var config: SourceConfig             // JSON 编码的配置（地址、凭证等）
    var isEnabled: Bool
    var lastScanDate: Date?
    var scanStatus: ScanStatus           // idle / scanning / error
    var errorMessage: String?
    var createdAt: Date

    @Relationship(deleteRule: .cascade)
    var videos: [Video]
}

enum SourceType: String, Codable {
    case local, webdav, smb, aliyunDrive, baiduPan, pan115, emby, jellyfin
}

// 各类型的配置用 enum + associated value，Codable 编码存储
enum SourceConfig: Codable {
    case local(path: String)
    case webdav(url: String, username: String, password: String)
    case smb(host: String, share: String, username: String, password: String)
    case aliyunDrive(refreshToken: String, rootFolderId: String?)
    case baiduPan(accessToken: String, refreshToken: String, rootPath: String?)
    case pan115(cookies: String, rootCid: String?)
    case emby(serverUrl: String, apiKey: String, userId: String)
    case jellyfin(serverUrl: String, apiKey: String, userId: String)
}
```

### 3.2 Video — 视频

```swift
@Model
class Video {
    var id: UUID
    var title: String                    // 显示标题（可从文件名推导或用户编辑）
    var remotePath: String               // 在媒体源中的路径/ID
    var streamUrl: String?               // 缓存的可播放 URL（可能有时效性）
    var duration: TimeInterval?          // 时长（秒）
    var resolution: String?              // 如 "1920x1080"
    var fileSize: Int64?
    var thumbnailPath: String?           // 本地缩略图缓存路径
    var addedAt: Date
    var lastModified: Date?

    var source: MediaSource?

    @Relationship
    var channelEntries: [ChannelVideo]
}
```

### 3.3 Channel — 频道

```swift
@Model
class Channel {
    var id: UUID
    var name: String
    var iconName: String                 // SF Symbol 名称或自定义图标标识
    var iconColor: String                // 十六进制色值
    var defaultVolume: Float             // 0.0 ~ 1.0
    var sortOrder: Int
    var createdAt: Date

    @Relationship(deleteRule: .cascade)
    var videoEntries: [ChannelVideo]
}
```

### 3.4 ChannelVideo — 频道视频关联

```swift
@Model
class ChannelVideo {
    var id: UUID
    var sortOrder: Int

    var channel: Channel?
    var video: Video?
}
```

### 3.5 PlaybackState — 播放进度

```swift
@Model
class PlaybackState {
    var id: UUID
    var channelId: UUID
    var currentVideoId: UUID
    var currentTime: TimeInterval        // 当前播放时间点
    var updatedAt: Date
}
```

### 3.6 WatchTimeRecord — 观看时长记录

```swift
@Model
class WatchTimeRecord {
    var id: UUID
    var date: String                     // "yyyy-MM-dd"
    var totalSeconds: Int
    var lastUpdated: Date
}
```

### 3.7 AppSettings — 全局设置

```swift
@Model
class AppSettings {
    var id: UUID

    // 家长密码（实际密码哈希存 Keychain，这里存配置）
    var isPasswordSet: Bool

    // 时长控制
    var dailyLimitMinutes: Int?          // nil = 不限制
    var allowedStartTime: String?        // "08:00"
    var allowedEndTime: String?          // "20:00"

    // 音量
    var maxVolume: Float                 // 全局最大音量 0.0 ~ 1.0

    // 上次状态
    var lastChannelId: UUID?
}
```

---

## 4. 存储协议层设计

### 4.1 统一接口

```swift
protocol StorageProvider {
    /// 列出指定路径下的所有项目
    func listItems(at path: String) async throws -> [RemoteItem]

    /// 递归扫描所有视频文件
    func scanVideos(from rootPath: String) async throws -> [RemoteItem]

    /// 获取可播放的流 URL（部分源需要临时签名）
    func getStreamUrl(for item: RemoteItem) async throws -> URL

    /// 获取文件的可读流（用于缩略图生成等）
    func getFileStream(for item: RemoteItem, range: ClosedRange<Int64>?) async throws -> Data

    /// 测试连接
    func testConnection() async throws -> Bool
}

struct RemoteItem {
    let name: String
    let path: String                     // 在源中的唯一路径/ID
    let isDirectory: Bool
    let size: Int64?
    let modifiedDate: Date?
}
```

### 4.2 各 Provider 实现要点

**WebDAVProvider**
- 使用 URLSession 发送 PROPFIND 请求遍历目录
- 播放时直接用 GET URL，KSPlayer 支持 HTTP 流播放
- 支持 HTTP Basic / Digest 认证

**SMBProvider**
- 使用 AMSMB2 库连接 SMB2/3 共享
- 遍历通过 `contentsOfDirectory`
- 播放策略：通过 AMSMB2 读取数据，转为本地 HTTP 代理流（启动本地 HTTP Server，按需从 SMB 拉取数据转发）

**AliyunDriveProvider**
- OAuth2 授权流，WebView 内完成登录
- 使用 Open API: `/adrive/v1.0/openFile/list` 遍历目录
- 播放地址通过 `/adrive/v1.0/openFile/getDownloadUrl` 获取（有时效性，需刷新）

**BaiduPanProvider**
- OAuth2 授权
- 使用 `xpan/file?method=list` 遍历
- 播放地址通过 `xpan/file?method=filemetas` + `dlink` 获取

**Pan115Provider**
- 无官方 API，使用 Cookie 认证
- 提供 Web 登录界面让用户扫码获取 Cookie
- 参考 Alist 的 115 实现做目录遍历和下载地址获取

**EmbyProvider / JellyfinProvider**
- REST API 获取媒体库 Items
- 播放 URL: `{server}/Videos/{itemId}/stream`
- 两者 API 高度兼容，可抽取基类 `MediaServerProvider`

### 4.3 本地 HTTP 代理（关键组件）

对于 SMB、网盘等不支持直接 HTTP 流播放的源，需要一个**本地 HTTP 代理服务**：

```swift
class LocalStreamProxy {
    private var server: GCDWebServer  // 或用 NIO 实现

    /// 启动本地代理，返回 localhost URL
    func proxyStream(provider: StorageProvider, item: RemoteItem) -> URL

    /// 处理播放器的 HTTP Range 请求，从 provider 按需拉取数据转发
    func handleRangeRequest(range: ClosedRange<Int64>) async -> Data
}
```

这样 KSPlayer 始终对接一个 HTTP URL，不需要关心底层是什么协议。

---

## 5. 核心服务实现

### 5.1 MediaIndexer — 媒体扫描与索引

```
扫描流程:
┌─────────────┐     ┌──────────────┐     ┌───────────────┐     ┌──────────────┐
│ 遍历媒体源   │ ──▶ │ 过滤视频文件  │ ──▶ │ Diff 对比数据库│ ──▶ │ 增量更新入库  │
│ (递归目录)   │     │ (扩展名匹配)  │     │ (新增/删除/修改)│     │ (写入SwiftData)│
└─────────────┘     └──────────────┘     └───────────────┘     └──────────────┘
                                                                       │
                                                                       ▼
                                                               ┌──────────────┐
                                                               │ 异步提取元数据│
                                                               │ + 生成缩略图  │
                                                               └──────────────┘
```

**核心逻辑：**
- 支持的视频扩展名：`.mp4`, `.mkv`, `.avi`, `.mov`, `.m4v`, `.wmv`, `.flv`, `.ts`, `.webm`
- **增量扫描**：对比文件路径 + 修改时间，只处理变化的文件
- **元数据提取**：通过 KSPlayer/AVFoundation 获取时长、分辨率
- **缩略图生成**：取视频 10% 时间点的帧，压缩后存入 `Caches` 目录
- **扫描触发时机**：
  - 手动触发（后台管理界面的刷新按钮）
  - App 进入前台时自动扫描
  - BGTaskScheduler 注册定期后台扫描（约每 6 小时）

### 5.2 PlaybackEngine — 播放控制

```swift
class PlaybackEngine: ObservableObject {
    @Published var isPlaying: Bool
    @Published var currentTime: TimeInterval
    @Published var duration: TimeInterval
    @Published var currentVideo: Video?

    private var player: KSPlayerLayer
    private var playlist: [Video]        // 当前频道的视频列表
    private var currentIndex: Int

    /// 切换频道 — 恢复该频道的播放进度
    func switchToChannel(_ channel: Channel)

    /// 播放指定视频
    func play(video: Video, from time: TimeInterval = 0)

    /// 当前视频结束 — 自动播放下一个
    func onVideoFinished()

    /// 持久化当前播放进度（节流：每 5 秒写一次）
    func persistProgress()

    /// 应用音量上限
    func applyVolumeLimit(_ maxVolume: Float)
}
```

**播放状态持久化策略：**
- 每 5 秒自动保存一次当前进度到 SwiftData
- 切换频道时立即保存
- App 进入后台时立即保存
- 启动时读取 `AppSettings.lastChannelId` + 对应 `PlaybackState` 恢复

### 5.3 WatchTimeGuard — 观看时长管控

```swift
class WatchTimeGuard: ObservableObject {
    @Published var isLocked: Bool
    @Published var remainingMinutes: Int?
    @Published var isOutsideAllowedTime: Bool

    /// 每分钟检查一次：
    /// 1. 当前时间是否在允许的时间段内
    /// 2. 今日累计观看时长是否超过限额
    func tick()

    /// 播放时累加今日观看时长
    func recordWatchTime(seconds: Int)

    /// 超时后锁定界面，需家长密码解锁
    func lock()
}
```

---

## 6. 界面设计与交互

### 6.1 儿童前台

**主界面 — 频道选择 (KidsHomeView)**
```
┌─────────────────────────────────────────────────┐
│                                                 │
│     🐻         🚀         🎵         🌈        │
│    动画片     科学探索     儿歌       故事       │
│                                                 │
│              ← 左右滑动切换频道 →                │
│                                                 │
│                  [ ▶ 开始观看 ]                  │
│                                                 │
│                          ⚙️ (小字，角落，家长入口) │
└─────────────────────────────────────────────────┘
```

**播放界面 (ChannelPlayerView)**
- 全屏视频播放
- 左右滑动：切换频道（带电视雪花/切台动画）
- 上滑：显示当前频道视频列表（ChannelPlaylistView）
- 轻点屏幕：显示/隐藏简易控制栏（暂停、频道名、视频标题）
- 无进度条（防止儿童随意拖动）、无音量调节（由家长预设）

**锁定界面 (LockScreenView)**
- 超时后全屏覆盖，显示"今天的观看时间结束啦"
- 只有输入家长密码才能解锁或延长时间

### 6.2 家长后台

**入口 (AdminEntryView)**
- 点击设置图标后弹出数字密码键盘
- 首次使用引导设置 4-6 位密码

**后台仪表盘 (AdminDashboard)**
- Tab 导航：媒体源 | 视频库 | 频道管理 | 设置
- 顶部显示今日观看时长统计

**媒体源管理 (SourceManagement/)**
- 列表展示所有已添加的媒体源，状态指示灯（正常/扫描中/错误）
- 添加源时选择类型，表单填写对应配置
- 网盘类型提供 OAuth/WebView 登录流程
- 每个源支持：编辑、删除、手动刷新、查看索引的视频数量

**视频库 (Library/)**
- 网格展示所有已索引视频（缩略图 + 标题 + 时长）
- 支持按媒体源筛选
- 搜索栏：按标题搜索
- 视频详情：标题编辑、元数据查看、所属频道列表

**频道管理 (Channels/)**
- 拖拽排序频道列表
- 频道编辑器：
  - 名称、图标（从 SF Symbols 选择或内置图标集）、颜色
  - 默认音量滑块
  - 视频选择器 (VideoPickerView)：
    - 左侧：视频库（支持搜索、按源筛选、多选）
    - 右侧：已选视频列表（支持拖拽排序、移除）

**设置 (Settings/)**
- 修改家长密码
- 每日观看限额（滑块，15 分钟步进，或"不限制"）
- 允许时间段（开始时间 ~ 结束时间 picker）
- 全局最大音量（滑块）

---

## 7. 关键技术实现细节

### 7.1 频道切换动画

模拟传统电视换台效果：

```swift
struct ChannelSwitcher: View {
    @State private var showStatic = false

    func switchChannel(to channel: Channel) {
        // 1. 显示电视雪花/噪点动画（0.3s）
        withAnimation { showStatic = true }

        // 2. 后台切换播放源
        playbackEngine.switchToChannel(channel)

        // 3. 隐藏雪花，显示新频道画面
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation { showStatic = false }
        }
    }
}
```

### 7.2 SMB 流播放方案

SMB 不支持 HTTP Range 请求，需要本地代理转发：

```
KSPlayer ──HTTP Range Request──▶ LocalStreamProxy (localhost:8080)
                                       │
                                       ▼
                                 AMSMB2 read(offset, length)
                                       │
                                       ▼
                                 SMB Server (NAS)
```

使用 GCDWebServer 或 Swift NIO 实现本地 HTTP 服务，监听 Range 请求，按需从 SMB 拉取对应字节段返回。

### 7.3 网盘播放链刷新

网盘的下载/播放链通常有时效（阿里云盘 ~15min，百度 ~8h）：

```swift
class StreamUrlManager {
    private var cache: [String: (url: URL, expiry: Date)] = [:]

    func getStreamUrl(for video: Video) async throws -> URL {
        if let cached = cache[video.id.uuidString],
           cached.expiry > Date().addingTimeInterval(60) { // 提前 1 分钟刷新
            return cached.url
        }
        let provider = resolveProvider(for: video.source)
        let url = try await provider.getStreamUrl(for: video.remoteItem)
        cache[video.id.uuidString] = (url, Date().addingTimeInterval(video.source.urlTTL))
        return url
    }
}
```

### 7.4 后台扫描注册

```swift
// AppDelegate 或 App init
BGTaskScheduler.shared.register(
    forTaskWithIdentifier: "com.kidstvpad.mediascan",
    using: nil
) { task in
    let indexer = MediaIndexer()
    Task {
        await indexer.scanAllSources()
        task.setTaskCompleted(success: true)
    }
}

// 调度：每 6 小时
func scheduleBackgroundScan() {
    let request = BGProcessingTaskRequest(identifier: "com.kidstvpad.mediascan")
    request.requiresNetworkConnectivity = true
    request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
    try? BGTaskScheduler.shared.submit(request)
}
```

---

## 8. 第三方依赖

| 依赖 | 用途 | 许可证 |
|------|------|--------|
| [KSPlayer](https://github.com/kingslay/KSPlayer) | 视频播放引擎 | LGPL |
| [AMSMB2](https://github.com/amosavian/AMSMB2) | SMB2/3 客户端 | BSD |
| [SWXMLHash](https://github.com/drmohundro/SWXMLHash) | XML 解析（WebDAV 响应） | MIT |
| [GCDWebServer](https://github.com/swiber/GCDWebServer) | 本地 HTTP 代理 | BSD |
| [KeychainAccess](https://github.com/kishikawakatsumi/KeychainAccess) | Keychain 简化封装 | MIT |

> 注：KSPlayer 使用 LGPL 许可证，以动态库方式链接即可满足合规要求。如果上架 App Store 需要注意这一点。

---

## 9. 开发阶段划分

### Phase 1 — 核心骨架（可运行的最小闭环）
- SwiftUI 项目搭建 + SwiftData 模型
- 儿童前台 UI（频道选择 + 播放界面 + 换台手势）
- 本地目录媒体源 + 扫描索引
- KSPlayer 集成 + 播放控制
- 断点续播 + 自动连播 + 启动恢复
- 家长密码 + 频道 CRUD

### Phase 2 — 网络存储协议
- WebDAV Provider
- SMB Provider + 本地 HTTP 代理
- 媒体源管理 UI（添加/编辑/删除/测试连接）

### Phase 3 — 网盘与媒体服务器
- 阿里云盘 Provider（OAuth 登录流 + API 对接）
- 百度网盘 Provider
- 115 网盘 Provider
- Emby / Jellyfin Provider

### Phase 4 — 管控与打磨
- 每日时长限制 + 时间段控制 + 锁定界面
- 全局音量限制
- 缩略图生成优化（懒加载 + 缓存策略）
- 后台定时扫描（BGTaskScheduler）
- 频道切换动画打磨
- iPad 横竖屏适配

### Phase 5 — 上架准备
- 隐私合规（App Tracking Transparency 不需要，但隐私声明要写）
- App Store 审核注意事项（儿童类应用有特殊审核标准 — Kids Category Guidelines）
- 无内购、无广告、无追踪
- 应用图标、启动屏、App Store 截图
