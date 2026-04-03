# 百度网盘视频播放：简化方案调研

## 背景

当前实现（`BaiduPlaybackPipeline.swift`，42KB）自己管理 segment 下载、缓冲区、线程同步、TS 拼接，非常复杂。
本文档记录一个可能更简单的方案，供决策参考。

---

## 竞品是怎么做的

### VidHub（威力播）
- GitHub 组织（VidHub-OmiSoftware）里有 FFmpeg、libplacebo、dav1d 等 fork，确认是 **FFmpeg 内核**
- 直接把百度 `dlink`（直链）+ 正确 headers 传给 FFmpeg，让 FFmpeg 自己处理一切

### 网易爆米花
- 2025年5月 v2.0 发布"全新自研播放器内核"，支持 TrueHD 7.1、ISO 镜像等
- 同样是 **FFmpeg 内核**

### 关键原理
FFmpeg 的 libavformat 支持在打开 URL 时设置自定义 headers：

```c
av_dict_set(&opts, "user_agent", "xpanvideo;...", 0);
av_dict_set(&opts, "headers", "Referer: https://pan.baidu.com/\r\n", 0);
avformat_open_input(&ctx, url, NULL, &opts);
```

**FFmpeg 的 HLS demuxer 会把这些 headers 继承到每一个 segment 请求上**（实现在 `libavformat/hls.c`）。
这不是代理，不需要本地 HTTP server，FFmpeg 自己就搞定了。

### 我们用的 mpv 底层也是 FFmpeg
mpv 已经暴露了对应选项：
- `--user-agent=...`
- `--http-header-fields=Key:Value,Key2:Value2`

`MPVPlayerView.swift` 第 166-173 行已经有设置这两个选项的代码。

---

## 现有方案 vs 简化方案

### 现有方案
```
Swift: adToken 两步流程 → 获取 M3U8 → 解析所有 segments
BaiduPlaybackPipeline: 自己下载 segments、管理缓冲区、拼接成虚拟流
mpv: 读 kidstv://session/... 虚拟 URL（通过 stream_cb）
```

自己实现了 HLS 播放器的核心逻辑。

### 简化方案
```
Swift: adToken 两步流程 → 获取 M3U8 内容 → 写入临时文件（保留绝对 CDN URL）
mpv: 播放 file://xxx.m3u8，设置 user-agent + Referer
FFmpeg HLS demuxer: 自己去百度 CDN 拉 segments，自动带上 headers
```

mpv/FFmpeg 自己做 HLS 播放器该做的事。

---

## 改动范围

只需改 `BaiduPanScanner.swift` 末尾的返回部分：

**现在（约第 63 行）**：
```swift
return try await BaiduPlaybackPipeline.shared.preparePlayableMedia(
    video: video,
    segments: segments,
    headers: requestHeaders
)
```

**改成**：
```swift
// 把 M3U8 内容写入临时文件
let tmpURL = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString)
    .appendingPathExtension("m3u8")
try playlist.content.write(to: tmpURL, atomically: true, encoding: .utf8)

return StreamableMedia(
    url: tmpURL,
    httpHeaders: requestHeaders   // user-agent + Referer 通过现有逻辑传给 mpv
)
```

`BaiduPlaybackPipeline.swift` 整个可以删掉。

---

## 风险点

1. **FFmpeg HLS segment headers 继承** — 这是有据可查的行为，但没有在本项目里实际跑过，需要验证
2. **M3U8 里的 segment URL** — 需确认是绝对 URL（`https://d.pcs.baidu.com/...`），不是相对路径。当前代码里 `resolvedSegments()` 已经做了 absolute 处理，说明原始 M3U8 可能有相对路径，写 temp 文件前需要确保已转换为绝对 URL
3. **Seek 行为** — FFmpeg HLS demuxer 支持通过 HTTP Range 请求 seek，应该没问题，但需测试
4. **tmp 文件清理** — 需要在播放结束后删除临时 M3U8 文件

---

## 结论

如果 FFmpeg headers 继承在实际运行中确认可行，整个 `BaiduPlaybackPipeline.swift`（42KB，含缓冲管理、线程同步、TS transmux）都可以删掉，替换为十几行代码。

验证成本低（改几行试一下），失败了也很容易回滚。
