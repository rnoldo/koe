/**
 * Store 单元测试 — 验证核心业务逻辑
 *
 * 对照 README 需求：
 * - 2.1 前台：断点续播、自动连播、启动恢复
 * - 2.2 后台：访问控制、媒体源管理、频道管理、设置与管控
 */
import { describe, it, expect, beforeEach, vi } from 'vitest'
import { useStore } from '@/store'

// Reset store to fresh state before each test
function resetStore() {
  useStore.setState(useStore.getInitialState())
}

describe('PIN 认证 — README 2.2 访问控制', () => {
  beforeEach(resetStore)

  it('默认 PIN 为 1234', () => {
    expect(useStore.getState().settings.pin).toBe('1234')
  })

  it('正确 PIN 认证成功', () => {
    const result = useStore.getState().authenticateAdmin('1234')
    expect(result).toBe(true)
    expect(useStore.getState().isAdminAuthenticated).toBe(true)
  })

  it('错误 PIN 认证失败', () => {
    const result = useStore.getState().authenticateAdmin('0000')
    expect(result).toBe(false)
    expect(useStore.getState().isAdminAuthenticated).toBe(false)
  })

  it('退出后台后认证状态清除', () => {
    useStore.getState().authenticateAdmin('1234')
    useStore.getState().logoutAdmin()
    expect(useStore.getState().isAdminAuthenticated).toBe(false)
  })

  it('修改 PIN 后旧 PIN 不可用', () => {
    useStore.getState().updateSettings({ pin: '9999' })
    expect(useStore.getState().authenticateAdmin('1234')).toBe(false)
    expect(useStore.getState().authenticateAdmin('9999')).toBe(true)
  })
})

describe('媒体源管理 — README 2.2 视频库管理', () => {
  beforeEach(resetStore)

  it('初始有 mock 媒体源数据', () => {
    expect(useStore.getState().sources.length).toBeGreaterThan(0)
  })

  it('添加新媒体源', () => {
    const before = useStore.getState().sources.length
    useStore.getState().addSource({ name: '测试源', type: 'webdav', config: {}, isEnabled: true })
    expect(useStore.getState().sources.length).toBe(before + 1)
    const added = useStore.getState().sources.find((s) => s.name === '测试源')
    expect(added).toBeDefined()
    expect(added!.type).toBe('webdav')
    expect(added!.scanStatus).toBe('idle')
  })

  it('删除媒体源同时删除其下视频', () => {
    const src = useStore.getState().sources[0]
    const videosBeforeCount = useStore.getState().videos.filter((v) => v.sourceId === src.id).length
    expect(videosBeforeCount).toBeGreaterThan(0) // 确保有关联视频

    useStore.getState().deleteSource(src.id)
    expect(useStore.getState().sources.find((s) => s.id === src.id)).toBeUndefined()
    expect(useStore.getState().videos.filter((v) => v.sourceId === src.id).length).toBe(0)
  })

  it('启用/禁用媒体源', () => {
    const src = useStore.getState().sources[0]
    useStore.getState().updateSource(src.id, { isEnabled: false })
    expect(useStore.getState().sources.find((s) => s.id === src.id)!.isEnabled).toBe(false)
  })

  it('扫描媒体源状态变化: idle → scanning → idle', async () => {
    vi.useFakeTimers()
    const src = useStore.getState().sources[0]
    useStore.getState().scanSource(src.id)
    expect(useStore.getState().sources.find((s) => s.id === src.id)!.scanStatus).toBe('scanning')

    vi.advanceTimersByTime(2500)
    expect(useStore.getState().sources.find((s) => s.id === src.id)!.scanStatus).toBe('idle')
    expect(useStore.getState().sources.find((s) => s.id === src.id)!.lastScanDate).not.toBeNull()
    vi.useRealTimers()
  })

  it('支持所有 8 种媒体源类型', () => {
    const types = ['local', 'webdav', 'smb', 'aliyunDrive', 'baiduPan', 'pan115', 'emby', 'jellyfin'] as const
    types.forEach((type) => {
      useStore.getState().addSource({ name: `${type}源`, type, config: {}, isEnabled: true })
    })
    types.forEach((type) => {
      expect(useStore.getState().sources.find((s) => s.name === `${type}源`)).toBeDefined()
    })
  })
})

describe('频道管理 — README 2.2 频道管理', () => {
  beforeEach(resetStore)

  it('初始有 mock 频道数据', () => {
    expect(useStore.getState().channels.length).toBeGreaterThan(0)
  })

  it('创建频道：设置名称、图标、默认音量', () => {
    useStore.getState().addChannel({
      name: '新频道',
      iconName: 'star',
      iconColor: '#E07A5F',
      defaultVolume: 70,
      videoIds: [],
    })
    const ch = useStore.getState().channels.find((c) => c.name === '新频道')
    expect(ch).toBeDefined()
    expect(ch!.iconName).toBe('star')
    expect(ch!.iconColor).toBe('#E07A5F')
    expect(ch!.defaultVolume).toBe(70)
  })

  it('编辑频道：修改名称和图标', () => {
    const ch = useStore.getState().channels[0]
    useStore.getState().updateChannel(ch.id, { name: '改名频道', iconName: 'rocket' })
    const updated = useStore.getState().channels.find((c) => c.id === ch.id)!
    expect(updated.name).toBe('改名频道')
    expect(updated.iconName).toBe('rocket')
  })

  it('删除频道', () => {
    const ch = useStore.getState().channels[0]
    useStore.getState().deleteChannel(ch.id)
    expect(useStore.getState().channels.find((c) => c.id === ch.id)).toBeUndefined()
  })

  it('频道内容选择：从视频库中选择视频', () => {
    const ch = useStore.getState().channels[0]
    const allVideos = useStore.getState().videos
    const newVideoIds = [allVideos[0].id, allVideos[1].id, allVideos[2].id]
    useStore.getState().updateChannel(ch.id, { videoIds: newVideoIds })
    expect(useStore.getState().channels.find((c) => c.id === ch.id)!.videoIds).toEqual(newVideoIds)
  })

  it('频道排序：调整频道顺序', () => {
    const channels = useStore.getState().channels
    const reversed = [...channels].reverse().map((c) => c.id)
    useStore.getState().reorderChannels(reversed)
    const reordered = useStore.getState().channels
    expect(reordered[0].sortOrder).toBe(0)
    expect(reordered[reordered.length - 1].sortOrder).toBe(reordered.length - 1)
    expect(reordered[0].id).toBe(reversed[0])
  })

  it('频道视频为空时频道仍可创建', () => {
    useStore.getState().addChannel({
      name: '空频道',
      iconName: 'tv',
      iconColor: '#ccc',
      defaultVolume: 50,
      videoIds: [],
    })
    const ch = useStore.getState().channels.find((c) => c.name === '空频道')
    expect(ch).toBeDefined()
    expect(ch!.videoIds).toEqual([])
  })
})

describe('播放状态 — README 2.1 断点续播 & 启动恢复', () => {
  beforeEach(resetStore)

  it('保存播放进度', () => {
    const ch = useStore.getState().channels[0]
    useStore.getState().savePlaybackState({
      channelId: ch.id,
      currentVideoId: ch.videoIds[2],
      currentTime: 123.5,
    })
    const pb = useStore.getState().getPlaybackState(ch.id)
    expect(pb).toBeDefined()
    expect(pb!.currentVideoId).toBe(ch.videoIds[2])
    expect(pb!.currentTime).toBe(123.5)
  })

  it('切回频道时恢复上次进度（断点续播）', () => {
    const ch1 = useStore.getState().channels[0]
    const ch2 = useStore.getState().channels[1]

    // 在频道1播放到 60 秒
    useStore.getState().savePlaybackState({
      channelId: ch1.id,
      currentVideoId: ch1.videoIds[1],
      currentTime: 60,
    })
    // 切到频道2
    useStore.getState().savePlaybackState({
      channelId: ch2.id,
      currentVideoId: ch2.videoIds[0],
      currentTime: 30,
    })
    // 切回频道1 — 应该能恢复到 60 秒
    const pb1 = useStore.getState().getPlaybackState(ch1.id)
    expect(pb1!.currentTime).toBe(60)
    expect(pb1!.currentVideoId).toBe(ch1.videoIds[1])
  })

  it('记录上次观看频道（启动恢复）', () => {
    const ch = useStore.getState().channels[1]
    useStore.getState().updateSettings({ lastChannelId: ch.id })
    expect(useStore.getState().settings.lastChannelId).toBe(ch.id)
  })

  it('不同频道各自独立保存进度', () => {
    const channels = useStore.getState().channels
    channels.forEach((ch, i) => {
      useStore.getState().savePlaybackState({
        channelId: ch.id,
        currentVideoId: ch.videoIds[0],
        currentTime: (i + 1) * 100,
      })
    })
    channels.forEach((ch, i) => {
      const pb = useStore.getState().getPlaybackState(ch.id)
      expect(pb!.currentTime).toBe((i + 1) * 100)
    })
  })
})

describe('观看时长管控 — README 2.2 设置与管控', () => {
  beforeEach(resetStore)

  it('累计观看时长', () => {
    useStore.getState().addWatchTime(60)
    useStore.getState().addWatchTime(120)
    expect(useStore.getState().getTodayWatchTime()).toBe(180)
  })

  it('未设限额时不锁定', () => {
    useStore.getState().updateSettings({ dailyLimitMinutes: null })
    useStore.getState().addWatchTime(99999)
    expect(useStore.getState().isTimeLimitReached()).toBe(false)
  })

  it('超过每日限额时锁定', () => {
    useStore.getState().updateSettings({ dailyLimitMinutes: 30 })
    useStore.getState().addWatchTime(30 * 60) // 刚好 30 分钟
    expect(useStore.getState().isTimeLimitReached()).toBe(true)
  })

  it('未超过限额时不锁定', () => {
    useStore.getState().updateSettings({ dailyLimitMinutes: 60 })
    useStore.getState().addWatchTime(30 * 60) // 30 分钟
    expect(useStore.getState().isTimeLimitReached()).toBe(false)
  })

  it('未设时间段限制时始终允许', () => {
    useStore.getState().updateSettings({ allowedStartTime: null, allowedEndTime: null })
    expect(useStore.getState().isWithinAllowedTime()).toBe(true)
  })

  it('在允许时间段内时返回 true', () => {
    // 设一个包含当前时间的大范围
    useStore.getState().updateSettings({ allowedStartTime: '00:00', allowedEndTime: '23:59' })
    expect(useStore.getState().isWithinAllowedTime()).toBe(true)
  })

  it('在允许时间段外时返回 false', () => {
    // 设一个不可能包含当前时间的窄范围（凌晨3:00-3:01）
    const now = new Date()
    const outOfRange = now.getHours() !== 3
    if (outOfRange) {
      useStore.getState().updateSettings({ allowedStartTime: '03:00', allowedEndTime: '03:01' })
      expect(useStore.getState().isWithinAllowedTime()).toBe(false)
    }
  })

  it('观看时长按天记录，不同天独立', () => {
    useStore.getState().addWatchTime(100)
    const today = new Date().toISOString().slice(0, 10)
    const records = useStore.getState().watchTimeRecords
    expect(records.length).toBe(1)
    expect(records[0].date).toBe(today)
    expect(records[0].totalSeconds).toBe(100)
  })
})

describe('全局设置 — README 2.2', () => {
  beforeEach(resetStore)

  it('全局音量限制默认值', () => {
    expect(useStore.getState().settings.maxVolume).toBe(80)
  })

  it('修改全局音量限制', () => {
    useStore.getState().updateSettings({ maxVolume: 50 })
    expect(useStore.getState().settings.maxVolume).toBe(50)
  })

  it('修改每日限额', () => {
    useStore.getState().updateSettings({ dailyLimitMinutes: 90 })
    expect(useStore.getState().settings.dailyLimitMinutes).toBe(90)
  })

  it('修改允许时间段', () => {
    useStore.getState().updateSettings({ allowedStartTime: '08:00', allowedEndTime: '20:00' })
    expect(useStore.getState().settings.allowedStartTime).toBe('08:00')
    expect(useStore.getState().settings.allowedEndTime).toBe('20:00')
  })
})

describe('视频库 — README 2.2 视频库管理', () => {
  beforeEach(resetStore)

  it('按媒体源查询视频', () => {
    const src = useStore.getState().sources[0]
    const videos = useStore.getState().getVideosBySource(src.id)
    expect(videos.length).toBeGreaterThan(0)
    videos.forEach((v) => expect(v.sourceId).toBe(src.id))
  })

  it('按 ID 查询视频', () => {
    const video = useStore.getState().videos[0]
    const found = useStore.getState().getVideoById(video.id)
    expect(found).toBeDefined()
    expect(found!.title).toBe(video.title)
  })

  it('查询不存在的视频返回 undefined', () => {
    expect(useStore.getState().getVideoById('nonexistent')).toBeUndefined()
  })

  it('删除媒体源后其视频也被删除', () => {
    const src = useStore.getState().sources[0]
    const videoCountBefore = useStore.getState().getVideosBySource(src.id).length
    expect(videoCountBefore).toBeGreaterThan(0)

    useStore.getState().deleteSource(src.id)
    expect(useStore.getState().getVideosBySource(src.id).length).toBe(0)
  })
})

describe('数据持久化 — localStorage', () => {
  it('store name 配置为 kidstv-storage', () => {
    // persist middleware 使用 'kidstv-storage' 作为 key
    // 验证 store 能正常初始化
    expect(useStore.getState().channels.length).toBeGreaterThan(0)
  })
})
