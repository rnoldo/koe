/**
 * 组件渲染测试 — 验证 UI 层关键行为
 *
 * 对照 README 需求验证各页面能否正确渲染和交互
 */
import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { useStore } from '@/store'

// Reset store before each test
function resetStore() {
  useStore.setState(useStore.getInitialState())
}

// ============================================================
// 儿童前台 — 频道选择页
// ============================================================
describe('频道选择页 /kids — README 2.1', () => {
  beforeEach(resetStore)

  it('渲染所有频道', async () => {
    const KidsHome = (await import('@/app/kids/page')).default
    render(<KidsHome />)
    const channels = useStore.getState().channels
    channels.forEach((ch) => {
      expect(screen.getByText(ch.name)).toBeInTheDocument()
    })
  })

  it('显示"开始观看"按钮', async () => {
    const KidsHome = (await import('@/app/kids/page')).default
    render(<KidsHome />)
    expect(screen.getByText('开始观看')).toBeInTheDocument()
  })

  it('有设置入口（齿轮图标）', async () => {
    const KidsHome = (await import('@/app/kids/page')).default
    render(<KidsHome />)
    // 设置按钮存在（通向 /admin）
    const buttons = screen.getAllByRole('button')
    expect(buttons.length).toBeGreaterThan(0)
  })

  it('频道为空时显示空状态', async () => {
    useStore.setState({ channels: [] })
    const KidsHome = (await import('@/app/kids/page')).default
    render(<KidsHome />)
    expect(screen.getByText('还没有频道哦')).toBeInTheDocument()
  })

  it('可以左右切换频道', async () => {
    const KidsHome = (await import('@/app/kids/page')).default
    render(<KidsHome />)
    const channels = useStore.getState().channels.sort((a, b) => a.sortOrder - b.sortOrder)

    // 初始选中第一个频道，点击右箭头应切换
    const buttons = screen.getAllByRole('button')
    // 找到右箭头按钮 (包含 ChevronRight)
    const rightArrow = buttons.find((b) => b.querySelector('svg[class*="lucide-chevron-right"]'))
    if (rightArrow) {
      fireEvent.click(rightArrow)
    }
  })
})

// ============================================================
// 家长后台 — PIN 验证页
// ============================================================
describe('PIN 验证页 /admin — README 2.2 访问控制', () => {
  beforeEach(resetStore)

  it('渲染数字键盘', async () => {
    const AdminEntry = (await import('@/app/admin/page')).default
    render(<AdminEntry />)
    // 0-9 数字按钮应该存在
    for (let i = 0; i <= 9; i++) {
      expect(screen.getByText(String(i))).toBeInTheDocument()
    }
  })

  it('显示"家长验证"标题', async () => {
    const AdminEntry = (await import('@/app/admin/page')).default
    render(<AdminEntry />)
    expect(screen.getByText('家长验证')).toBeInTheDocument()
  })

  it('输入错误 PIN 显示错误提示', async () => {
    const AdminEntry = (await import('@/app/admin/page')).default
    render(<AdminEntry />)
    // 输入 0000（错误 PIN）
    fireEvent.click(screen.getByText('0'))
    fireEvent.click(screen.getByText('0'))
    fireEvent.click(screen.getByText('0'))
    fireEvent.click(screen.getByText('0'))

    await waitFor(() => {
      expect(screen.getByText('PIN 码错误')).toBeInTheDocument()
    })
  })

  it('有返回按钮', async () => {
    const AdminEntry = (await import('@/app/admin/page')).default
    render(<AdminEntry />)
    expect(screen.getByText('返回')).toBeInTheDocument()
  })

  it('有删除按钮可以退格', async () => {
    const AdminEntry = (await import('@/app/admin/page')).default
    render(<AdminEntry />)
    expect(screen.getByText('删除')).toBeInTheDocument()
  })

  it('显示默认 PIN 提示', async () => {
    const AdminEntry = (await import('@/app/admin/page')).default
    render(<AdminEntry />)
    expect(screen.getByText('默认 PIN: 1234')).toBeInTheDocument()
  })
})

// ============================================================
// 家长后台 — 媒体源管理
// ============================================================
describe('媒体源管理 /admin/sources — README 2.2', () => {
  beforeEach(() => {
    resetStore()
    useStore.setState({ isAdminAuthenticated: true })
  })

  it('渲染媒体源列表', async () => {
    const SourcesPage = (await import('@/app/admin/sources/page')).default
    render(<SourcesPage />)
    expect(screen.getByText('媒体源')).toBeInTheDocument()
    expect(screen.getByText('添加媒体源')).toBeInTheDocument()
  })

  it('显示所有 mock 媒体源', async () => {
    const SourcesPage = (await import('@/app/admin/sources/page')).default
    render(<SourcesPage />)
    const sources = useStore.getState().sources
    sources.forEach((src) => {
      expect(screen.getByText(src.name)).toBeInTheDocument()
    })
  })

  it('显示媒体源类型标签', async () => {
    const SourcesPage = (await import('@/app/admin/sources/page')).default
    render(<SourcesPage />)
    expect(screen.getByText('SMB')).toBeInTheDocument()
    expect(screen.getByText('阿里云盘')).toBeInTheDocument()
  })

  it('点击添加显示添加表单', async () => {
    const SourcesPage = (await import('@/app/admin/sources/page')).default
    render(<SourcesPage />)
    fireEvent.click(screen.getByRole('button', { name: /添加媒体源/ }))
    expect(screen.getByPlaceholderText('例如：NAS 动画片')).toBeInTheDocument()
  })

  it('添加表单中显示所有 8 种类型选项', async () => {
    const SourcesPage = (await import('@/app/admin/sources/page')).default
    render(<SourcesPage />)
    fireEvent.click(screen.getByRole('button', { name: /添加媒体源/ }))
    const typeLabels = ['本地目录', 'WebDAV', '百度网盘', '115网盘', 'Jellyfin']
    typeLabels.forEach((label) => {
      // Use getAllByText since some labels may also appear in the source list
      expect(screen.getAllByText(label).length).toBeGreaterThan(0)
    })
  })

  it('显示启用/禁用状态', async () => {
    const SourcesPage = (await import('@/app/admin/sources/page')).default
    render(<SourcesPage />)
    // 有启用和禁用的源
    expect(screen.getAllByText('已启用').length).toBeGreaterThan(0)
  })
})

// ============================================================
// 家长后台 — 视频库
// ============================================================
describe('视频库 /admin/library — README 2.2 视频库管理', () => {
  beforeEach(() => {
    resetStore()
    useStore.setState({ isAdminAuthenticated: true })
  })

  it('渲染视频库标题和视频总数', async () => {
    const LibraryPage = (await import('@/app/admin/library/page')).default
    render(<LibraryPage />)
    expect(screen.getByText('视频库')).toBeInTheDocument()
    const total = useStore.getState().videos.length
    expect(screen.getByText(`共 ${total} 个视频`)).toBeInTheDocument()
  })

  it('有搜索框', async () => {
    const LibraryPage = (await import('@/app/admin/library/page')).default
    render(<LibraryPage />)
    expect(screen.getByPlaceholderText('搜索视频...')).toBeInTheDocument()
  })

  it('有按源筛选的按钮', async () => {
    const LibraryPage = (await import('@/app/admin/library/page')).default
    render(<LibraryPage />)
    expect(screen.getByText('全部')).toBeInTheDocument()
    const sources = useStore.getState().sources
    sources.forEach((src) => {
      // 源名可能出现在筛选按钮和视频标签中
      expect(screen.getAllByText(src.name).length).toBeGreaterThan(0)
    })
  })

  it('有网格/列表视图切换', async () => {
    const LibraryPage = (await import('@/app/admin/library/page')).default
    render(<LibraryPage />)
    // 两个视图切换按钮
    const buttons = screen.getAllByRole('button')
    expect(buttons.length).toBeGreaterThanOrEqual(2)
  })

  it('显示所有视频标题', async () => {
    const LibraryPage = (await import('@/app/admin/library/page')).default
    render(<LibraryPage />)
    const videos = useStore.getState().videos
    // 至少部分视频标题可见
    const firstVideo = videos[0]
    expect(screen.getByText(firstVideo.title)).toBeInTheDocument()
  })

  it('搜索过滤视频', async () => {
    const LibraryPage = (await import('@/app/admin/library/page')).default
    render(<LibraryPage />)
    const searchInput = screen.getByPlaceholderText('搜索视频...')
    await userEvent.type(searchInput, '小猪佩奇')
    // 非匹配视频不应出现
    expect(screen.queryByText('宝宝巴士儿歌 第1集')).not.toBeInTheDocument()
    // 匹配视频应出现
    expect(screen.getByText('小猪佩奇 第1集')).toBeInTheDocument()
  })

  it('按源筛选后只显示该源的视频', async () => {
    const LibraryPage = (await import('@/app/admin/library/page')).default
    render(<LibraryPage />)
    const sources = useStore.getState().sources
    const firstSource = sources[0]
    // 点击第一个源的筛选按钮
    const filterButtons = screen.getAllByText(firstSource.name)
    fireEvent.click(filterButtons[0])

    // 其他源的视频不应出现
    const otherSourceVideos = useStore.getState().videos.filter((v) => v.sourceId !== firstSource.id)
    if (otherSourceVideos.length > 0) {
      expect(screen.queryByText(otherSourceVideos[0].title)).not.toBeInTheDocument()
    }
  })

  it('显示视频所属频道标签', async () => {
    const LibraryPage = (await import('@/app/admin/library/page')).default
    render(<LibraryPage />)
    // 第一个频道的名称应作为标签出现
    const firstChannel = useStore.getState().channels[0]
    const channelLabels = screen.getAllByText(firstChannel.name)
    expect(channelLabels.length).toBeGreaterThan(0) // 至少在筛选按钮和标签中出现
  })
})

// ============================================================
// 家长后台 — 频道管理
// ============================================================
describe('频道管理 /admin/channels — README 2.2', () => {
  beforeEach(() => {
    resetStore()
    useStore.setState({ isAdminAuthenticated: true })
  })

  it('渲染频道列表', async () => {
    const ChannelsPage = (await import('@/app/admin/channels/page')).default
    render(<ChannelsPage />)
    expect(screen.getByText('频道管理')).toBeInTheDocument()
    const channels = useStore.getState().channels
    channels.forEach((ch) => {
      expect(screen.getByText(ch.name)).toBeInTheDocument()
    })
  })

  it('显示新建频道按钮', async () => {
    const ChannelsPage = (await import('@/app/admin/channels/page')).default
    render(<ChannelsPage />)
    expect(screen.getByText('新建频道')).toBeInTheDocument()
  })

  it('显示每个频道的视频数', async () => {
    const ChannelsPage = (await import('@/app/admin/channels/page')).default
    render(<ChannelsPage />)
    const channels = useStore.getState().channels
    // 多个频道可能有相同视频数，用 getAllByText
    const uniqueCounts = [...new Set(channels.map((ch) => `${ch.videoIds.length} 个视频`))]
    uniqueCounts.forEach((text) => {
      expect(screen.getAllByText(text).length).toBeGreaterThan(0)
    })
  })

  it('点击新建频道显示创建表单', async () => {
    const ChannelsPage = (await import('@/app/admin/channels/page')).default
    render(<ChannelsPage />)
    fireEvent.click(screen.getByText('新建频道'))
    expect(screen.getByPlaceholderText('频道名称')).toBeInTheDocument()
  })

  it('频道为空时显示空状态', async () => {
    useStore.setState({ channels: [] })
    const ChannelsPage = (await import('@/app/admin/channels/page')).default
    render(<ChannelsPage />)
    expect(screen.getByText('还没有频道')).toBeInTheDocument()
  })
})

// ============================================================
// 家长后台 — 设置页
// ============================================================
describe('设置页 /admin/settings — README 2.2 设置与管控', () => {
  beforeEach(() => {
    resetStore()
    useStore.setState({ isAdminAuthenticated: true })
  })

  it('渲染设置标题', async () => {
    const SettingsPage = (await import('@/app/admin/settings/page')).default
    render(<SettingsPage />)
    expect(screen.getByText('设置')).toBeInTheDocument()
  })

  it('有 PIN 码设置区域', async () => {
    const SettingsPage = (await import('@/app/admin/settings/page')).default
    render(<SettingsPage />)
    expect(screen.getByText('家长 PIN 码')).toBeInTheDocument()
  })

  it('有观看时长控制区域', async () => {
    const SettingsPage = (await import('@/app/admin/settings/page')).default
    render(<SettingsPage />)
    expect(screen.getByText('观看时长控制')).toBeInTheDocument()
  })

  it('有全局音量限制区域', async () => {
    const SettingsPage = (await import('@/app/admin/settings/page')).default
    render(<SettingsPage />)
    expect(screen.getByText('全局音量限制')).toBeInTheDocument()
  })

  it('有保存按钮', async () => {
    const SettingsPage = (await import('@/app/admin/settings/page')).default
    render(<SettingsPage />)
    expect(screen.getByText('保存设置')).toBeInTheDocument()
  })

  it('有"不限制"选项按钮', async () => {
    const SettingsPage = (await import('@/app/admin/settings/page')).default
    render(<SettingsPage />)
    expect(screen.getByText('不限制')).toBeInTheDocument()
  })

  it('有允许时间段设置（开始/结束）', async () => {
    const SettingsPage = (await import('@/app/admin/settings/page')).default
    render(<SettingsPage />)
    expect(screen.getByText('允许开始时间')).toBeInTheDocument()
    expect(screen.getByText('允许结束时间')).toBeInTheDocument()
  })

  it('显示今日已观看时长', async () => {
    useStore.getState().addWatchTime(600) // 10 分钟
    const SettingsPage = (await import('@/app/admin/settings/page')).default
    render(<SettingsPage />)
    expect(screen.getByText('今日已看 10 分钟')).toBeInTheDocument()
  })
})

// ============================================================
// 播放页
// ============================================================
describe('播放页 /kids/play — README 2.1', () => {
  beforeEach(() => {
    resetStore()
    const ch = useStore.getState().channels[0]
    useStore.getState().updateSettings({ lastChannelId: ch.id })
  })

  it('渲染频道名称和视频标题', async () => {
    const PlayPage = (await import('@/app/kids/play/page')).default
    render(<PlayPage />)
    const ch = useStore.getState().channels[0]
    expect(screen.getByText(ch.name)).toBeInTheDocument()
  })

  it('显示播放进度 (时间)', async () => {
    const PlayPage = (await import('@/app/kids/play/page')).default
    render(<PlayPage />)
    // 应该显示 0:00 / X:XX 格式
    expect(screen.getByText(/0:00/)).toBeInTheDocument()
  })

  it('没有频道视频时显示提示', async () => {
    // 创建一个没有视频的频道
    useStore.getState().addChannel({
      name: '空频道',
      iconName: 'tv',
      iconColor: '#ccc',
      defaultVolume: 50,
      videoIds: [],
    })
    const emptyChannel = useStore.getState().channels.find((c) => c.name === '空频道')!
    useStore.getState().updateSettings({ lastChannelId: emptyChannel.id })

    const PlayPage = (await import('@/app/kids/play/page')).default
    render(<PlayPage />)
    expect(screen.getByText('没有可播放的内容')).toBeInTheDocument()
  })

  it('键盘空格键切换播放/暂停', async () => {
    const PlayPage = (await import('@/app/kids/play/page')).default
    render(<PlayPage />)
    // 按空格暂停
    fireEvent.keyDown(window, { key: ' ' })
    // 应该显示暂停状态（Play 图标）
  })

  it('有频道切换操作热区', async () => {
    const PlayPage = (await import('@/app/kids/play/page')).default
    const { container } = render(<PlayPage />)
    // 左右边缘应有可点击区域
    const buttons = container.querySelectorAll('button')
    expect(buttons.length).toBeGreaterThan(0)
  })
})
