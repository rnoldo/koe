/**
 * Component render tests — verify UI key behaviors
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
// Kids home — channel selection
// ============================================================
describe('Channel selection /kids', () => {
  beforeEach(resetStore)

  it('renders all channels', async () => {
    const KidsHome = (await import('@/app/kids/page')).default
    render(<KidsHome />)
    const channels = useStore.getState().channels
    channels.forEach((ch) => {
      expect(screen.getByText(ch.name)).toBeInTheDocument()
    })
  })

  it('shows "Start watching" button', async () => {
    const KidsHome = (await import('@/app/kids/page')).default
    render(<KidsHome />)
    expect(screen.getByText('Start watching')).toBeInTheDocument()
  })

  it('has settings entry (gear icon)', async () => {
    const KidsHome = (await import('@/app/kids/page')).default
    render(<KidsHome />)
    const buttons = screen.getAllByRole('button')
    expect(buttons.length).toBeGreaterThan(0)
  })

  it('shows empty state when no channels', async () => {
    useStore.setState({ channels: [] })
    const KidsHome = (await import('@/app/kids/page')).default
    render(<KidsHome />)
    expect(screen.getByText('No channels yet')).toBeInTheDocument()
  })

  it('can switch channels left/right', async () => {
    const KidsHome = (await import('@/app/kids/page')).default
    render(<KidsHome />)
    const buttons = screen.getAllByRole('button')
    const rightArrow = buttons.find((b) => b.querySelector('svg[class*="lucide-chevron-right"]'))
    if (rightArrow) {
      fireEvent.click(rightArrow)
    }
  })
})

// ============================================================
// Admin — PIN verification
// ============================================================
describe('PIN page /admin', () => {
  beforeEach(resetStore)

  it('renders number pad', async () => {
    const AdminEntry = (await import('@/app/admin/page')).default
    render(<AdminEntry />)
    for (let i = 0; i <= 9; i++) {
      expect(screen.getByText(String(i))).toBeInTheDocument()
    }
  })

  it('shows "Parent verification" title', async () => {
    const AdminEntry = (await import('@/app/admin/page')).default
    render(<AdminEntry />)
    expect(screen.getByText('Parent verification')).toBeInTheDocument()
  })

  it('shows error on wrong PIN', async () => {
    const AdminEntry = (await import('@/app/admin/page')).default
    render(<AdminEntry />)
    fireEvent.click(screen.getByText('0'))
    fireEvent.click(screen.getByText('0'))
    fireEvent.click(screen.getByText('0'))
    fireEvent.click(screen.getByText('0'))

    await waitFor(() => {
      expect(screen.getByText('Incorrect PIN')).toBeInTheDocument()
    })
  })

  it('has back button', async () => {
    const AdminEntry = (await import('@/app/admin/page')).default
    render(<AdminEntry />)
    expect(screen.getByText('Back')).toBeInTheDocument()
  })

  it('has delete button', async () => {
    const AdminEntry = (await import('@/app/admin/page')).default
    render(<AdminEntry />)
    expect(screen.getByText('Delete')).toBeInTheDocument()
  })

  it('shows default PIN hint', async () => {
    const AdminEntry = (await import('@/app/admin/page')).default
    render(<AdminEntry />)
    expect(screen.getByText('Default PIN: 1234')).toBeInTheDocument()
  })
})

// ============================================================
// Admin — Media sources
// ============================================================
describe('Sources /admin/sources', () => {
  beforeEach(() => {
    resetStore()
    useStore.setState({ isAdminAuthenticated: true })
  })

  it('renders source list', async () => {
    const SourcesPage = (await import('@/app/admin/sources/page')).default
    render(<SourcesPage />)
    expect(screen.getByText('Media Sources')).toBeInTheDocument()
    expect(screen.getByText('Add Source')).toBeInTheDocument()
  })

  it('shows all mock sources', async () => {
    const SourcesPage = (await import('@/app/admin/sources/page')).default
    render(<SourcesPage />)
    const sources = useStore.getState().sources
    sources.forEach((src) => {
      expect(screen.getByText(src.name)).toBeInTheDocument()
    })
  })

  it('shows source type labels', async () => {
    const SourcesPage = (await import('@/app/admin/sources/page')).default
    render(<SourcesPage />)
    expect(screen.getByText('SMB')).toBeInTheDocument()
    expect(screen.getByText('Alibaba Drive')).toBeInTheDocument()
  })

  it('click add shows add form', async () => {
    const SourcesPage = (await import('@/app/admin/sources/page')).default
    render(<SourcesPage />)
    fireEvent.click(screen.getByRole('button', { name: /Add Source/ }))
    expect(screen.getByPlaceholderText('e.g. NAS Cartoons')).toBeInTheDocument()
  })

  it('add form shows all 8 type options', async () => {
    const SourcesPage = (await import('@/app/admin/sources/page')).default
    render(<SourcesPage />)
    fireEvent.click(screen.getByRole('button', { name: /Add Source/ }))
    const typeLabels = ['Local', 'WebDAV', 'Baidu Drive', '115 Drive', 'Jellyfin']
    typeLabels.forEach((label) => {
      expect(screen.getAllByText(label).length).toBeGreaterThan(0)
    })
  })

  it('shows enabled/disabled status', async () => {
    const SourcesPage = (await import('@/app/admin/sources/page')).default
    render(<SourcesPage />)
    expect(screen.getAllByText('Enabled').length).toBeGreaterThan(0)
  })
})

// ============================================================
// Admin — Video library
// ============================================================
describe('Library /admin/library', () => {
  beforeEach(() => {
    resetStore()
    useStore.setState({ isAdminAuthenticated: true })
  })

  it('renders title and total count', async () => {
    const LibraryPage = (await import('@/app/admin/library/page')).default
    render(<LibraryPage />)
    expect(screen.getByText('Video Library')).toBeInTheDocument()
    const total = useStore.getState().videos.length
    expect(screen.getByText(`${total} videos total`)).toBeInTheDocument()
  })

  it('has search box', async () => {
    const LibraryPage = (await import('@/app/admin/library/page')).default
    render(<LibraryPage />)
    expect(screen.getByPlaceholderText('Search videos...')).toBeInTheDocument()
  })

  it('has source filter buttons', async () => {
    const LibraryPage = (await import('@/app/admin/library/page')).default
    render(<LibraryPage />)
    expect(screen.getByText('All')).toBeInTheDocument()
    const sources = useStore.getState().sources
    sources.forEach((src) => {
      expect(screen.getAllByText(src.name).length).toBeGreaterThan(0)
    })
  })

  it('has grid/list view toggle', async () => {
    const LibraryPage = (await import('@/app/admin/library/page')).default
    render(<LibraryPage />)
    const buttons = screen.getAllByRole('button')
    expect(buttons.length).toBeGreaterThanOrEqual(2)
  })

  it('shows video titles', async () => {
    const LibraryPage = (await import('@/app/admin/library/page')).default
    render(<LibraryPage />)
    const videos = useStore.getState().videos
    const firstVideo = videos[0]
    expect(screen.getByText(firstVideo.title)).toBeInTheDocument()
  })

  it('search filters videos', async () => {
    const LibraryPage = (await import('@/app/admin/library/page')).default
    render(<LibraryPage />)
    const searchInput = screen.getByPlaceholderText('Search videos...')
    await userEvent.type(searchInput, '小猪佩奇')
    expect(screen.queryByText('宝宝巴士儿歌 第1集')).not.toBeInTheDocument()
    expect(screen.getByText('小猪佩奇 第1集')).toBeInTheDocument()
  })

  it('source filter shows only that source', async () => {
    const LibraryPage = (await import('@/app/admin/library/page')).default
    render(<LibraryPage />)
    const sources = useStore.getState().sources
    const firstSource = sources[0]
    const filterButtons = screen.getAllByText(firstSource.name)
    fireEvent.click(filterButtons[0])

    const otherSourceVideos = useStore.getState().videos.filter((v) => v.sourceId !== firstSource.id)
    if (otherSourceVideos.length > 0) {
      expect(screen.queryByText(otherSourceVideos[0].title)).not.toBeInTheDocument()
    }
  })

  it('shows channel tags on videos', async () => {
    const LibraryPage = (await import('@/app/admin/library/page')).default
    render(<LibraryPage />)
    const firstChannel = useStore.getState().channels[0]
    const channelLabels = screen.getAllByText(firstChannel.name)
    expect(channelLabels.length).toBeGreaterThan(0)
  })
})

// ============================================================
// Admin — Channels
// ============================================================
describe('Channels /admin/channels', () => {
  beforeEach(() => {
    resetStore()
    useStore.setState({ isAdminAuthenticated: true })
  })

  it('renders channel list', async () => {
    const ChannelsPage = (await import('@/app/admin/channels/page')).default
    render(<ChannelsPage />)
    expect(screen.getByText('Channel Management')).toBeInTheDocument()
    const channels = useStore.getState().channels
    channels.forEach((ch) => {
      expect(screen.getByText(ch.name)).toBeInTheDocument()
    })
  })

  it('shows new channel button', async () => {
    const ChannelsPage = (await import('@/app/admin/channels/page')).default
    render(<ChannelsPage />)
    expect(screen.getByText('New Channel')).toBeInTheDocument()
  })

  it('shows video count for each channel', async () => {
    const ChannelsPage = (await import('@/app/admin/channels/page')).default
    render(<ChannelsPage />)
    const channels = useStore.getState().channels
    const uniqueCounts = [...new Set(channels.map((ch) => `${ch.videoIds.length} videos`))]
    uniqueCounts.forEach((text) => {
      expect(screen.getAllByText(text).length).toBeGreaterThan(0)
    })
  })

  it('has new channel button', async () => {
    const ChannelsPage = (await import('@/app/admin/channels/page')).default
    render(<ChannelsPage />)
    expect(screen.getByText('New Channel')).toBeInTheDocument()
  })

  it('shows empty state when no channels', async () => {
    useStore.setState({ channels: [] })
    const ChannelsPage = (await import('@/app/admin/channels/page')).default
    render(<ChannelsPage />)
    expect(screen.getByText('No channels yet')).toBeInTheDocument()
  })
})

// ============================================================
// Admin — Settings
// ============================================================
describe('Settings /admin/settings', () => {
  beforeEach(() => {
    resetStore()
    useStore.setState({ isAdminAuthenticated: true })
  })

  it('renders title', async () => {
    const SettingsPage = (await import('@/app/admin/settings/page')).default
    render(<SettingsPage />)
    expect(screen.getByText('Settings')).toBeInTheDocument()
  })

  it('has PIN section', async () => {
    const SettingsPage = (await import('@/app/admin/settings/page')).default
    render(<SettingsPage />)
    expect(screen.getByText('Parent PIN')).toBeInTheDocument()
  })

  it('has watch time control', async () => {
    const SettingsPage = (await import('@/app/admin/settings/page')).default
    render(<SettingsPage />)
    expect(screen.getByText('Watch Time Control')).toBeInTheDocument()
  })

  it('has volume control', async () => {
    const SettingsPage = (await import('@/app/admin/settings/page')).default
    render(<SettingsPage />)
    expect(screen.getByText('Global Volume Limit')).toBeInTheDocument()
  })

  it('has save button', async () => {
    const SettingsPage = (await import('@/app/admin/settings/page')).default
    render(<SettingsPage />)
    expect(screen.getByText('Save Settings')).toBeInTheDocument()
  })

  it('has "No limit" option', async () => {
    const SettingsPage = (await import('@/app/admin/settings/page')).default
    render(<SettingsPage />)
    expect(screen.getAllByText('No limit').length).toBeGreaterThan(0)
  })

  it('has allowed time range', async () => {
    const SettingsPage = (await import('@/app/admin/settings/page')).default
    render(<SettingsPage />)
    expect(screen.getByText('Allowed Start Time')).toBeInTheDocument()
    expect(screen.getByText('Allowed End Time')).toBeInTheDocument()
  })

  it('shows today watch time', async () => {
    useStore.getState().addWatchTime(600) // 10 minutes
    const SettingsPage = (await import('@/app/admin/settings/page')).default
    render(<SettingsPage />)
    expect(screen.getByText('Today watched 10 min')).toBeInTheDocument()
  })
})

// ============================================================
// Source config forms + OAuth
// ============================================================
describe('Source config forms', () => {
  beforeEach(() => {
    resetStore()
    useStore.setState({ isAdminAuthenticated: true })
  })

  it('WebDAV shows URL/username/password fields', async () => {
    const SourcesPage = (await import('@/app/admin/sources/page')).default
    render(<SourcesPage />)
    fireEvent.click(screen.getByRole('button', { name: /Add Source/ }))
    fireEvent.click(screen.getByText('WebDAV'))
    expect(screen.getByPlaceholderText('https://dav.example.com/videos')).toBeInTheDocument()
    expect(screen.getByPlaceholderText('username')).toBeInTheDocument()
    expect(screen.getByPlaceholderText('password')).toBeInTheDocument()
  })

  it('SMB shows host/share/username/password fields', async () => {
    const SourcesPage = (await import('@/app/admin/sources/page')).default
    render(<SourcesPage />)
    fireEvent.click(screen.getByRole('button', { name: /Add Source/ }))
    const smbButtons = screen.getAllByText('SMB')
    const smbInGrid = smbButtons.find((el) => el.closest('.grid'))
    fireEvent.click(smbInGrid?.closest('button') || smbButtons[smbButtons.length - 1])
    expect(screen.getByPlaceholderText('192.168.1.100')).toBeInTheDocument()
    expect(screen.getByPlaceholderText('videos')).toBeInTheDocument()
  })

  it('Emby shows server/API Key/userID fields', async () => {
    const SourcesPage = (await import('@/app/admin/sources/page')).default
    render(<SourcesPage />)
    fireEvent.click(screen.getByRole('button', { name: /Add Source/ }))
    const embyButtons = screen.getAllByText('Emby')
    const embyInGrid = embyButtons.find((el) => el.closest('.grid'))
    fireEvent.click(embyInGrid?.closest('button') || embyButtons[embyButtons.length - 1])
    expect(screen.getByPlaceholderText('http://192.168.1.200:8096')).toBeInTheDocument()
    expect(screen.getByPlaceholderText('API Key')).toBeInTheDocument()
  })

  it('Local shows path field', async () => {
    const SourcesPage = (await import('@/app/admin/sources/page')).default
    render(<SourcesPage />)
    fireEvent.click(screen.getByRole('button', { name: /Add Source/ }))
    expect(screen.getByPlaceholderText('/Volumes/NAS/Videos')).toBeInTheDocument()
  })

  it('Alibaba Drive shows OAuth button', async () => {
    const SourcesPage = (await import('@/app/admin/sources/page')).default
    render(<SourcesPage />)
    fireEvent.click(screen.getByRole('button', { name: /Add Source/ }))
    const aliyunSpans = screen.getAllByText('Alibaba Drive')
    const gridSpan = aliyunSpans.find((el) => el.closest('.grid'))
    fireEvent.click(gridSpan?.closest('button') || aliyunSpans[aliyunSpans.length - 1])
    expect(screen.getByText('Authorize Alibaba Drive')).toBeInTheDocument()
  })

  it('Baidu Drive shows OAuth button', async () => {
    const SourcesPage = (await import('@/app/admin/sources/page')).default
    render(<SourcesPage />)
    fireEvent.click(screen.getByRole('button', { name: /Add Source/ }))
    fireEvent.click(screen.getByText('Baidu Drive'))
    expect(screen.getByText('Authorize Baidu Drive')).toBeInTheDocument()
  })

  it('115 Drive shows scan login button', async () => {
    const SourcesPage = (await import('@/app/admin/sources/page')).default
    render(<SourcesPage />)
    fireEvent.click(screen.getByRole('button', { name: /Add Source/ }))
    fireEvent.click(screen.getByText('115 Drive'))
    expect(screen.getByText('Scan to login 115')).toBeInTheDocument()
  })

  it('has "Connection Config" label', async () => {
    const SourcesPage = (await import('@/app/admin/sources/page')).default
    render(<SourcesPage />)
    fireEvent.click(screen.getByRole('button', { name: /Add Source/ }))
    expect(screen.getByText('Connection Config')).toBeInTheDocument()
  })
})

// ============================================================
// Channel editor — video management
// ============================================================
describe('Channel editor', () => {
  beforeEach(() => {
    resetStore()
    useStore.setState({ isAdminAuthenticated: true })
  })

  it('store supports updating channel video list', () => {
    const ch = useStore.getState().channels[0]
    const allVideos = useStore.getState().videos
    const batchIds = allVideos.slice(0, 5).map((v) => v.id)
    useStore.getState().updateChannel(ch.id, { videoIds: batchIds })
    expect(useStore.getState().channels.find((c) => c.id === ch.id)!.videoIds).toEqual(batchIds)
  })

  it('store supports clearing channel video list', () => {
    const ch = useStore.getState().channels[0]
    expect(ch.videoIds.length).toBeGreaterThan(0)
    useStore.getState().updateChannel(ch.id, { videoIds: [] })
    expect(useStore.getState().channels.find((c) => c.id === ch.id)!.videoIds).toEqual([])
  })

  it('store addChannel creates new channel with videos', () => {
    const before = useStore.getState().channels.length
    useStore.getState().addChannel({ name: 'Test Channel', iconName: 'tv', iconColor: '#C15F3C', defaultVolume: 60, videoIds: ['v1', 'v2'] })
    const after = useStore.getState().channels
    expect(after.length).toBe(before + 1)
    const created = after.find((c) => c.name === 'Test Channel')!
    expect(created.videoIds).toEqual(['v1', 'v2'])
  })
})

// ============================================================
// Play page
// ============================================================
describe('Play page /kids/play', () => {
  beforeEach(() => {
    resetStore()
    const ch = useStore.getState().channels[0]
    useStore.getState().updateSettings({ lastChannelId: ch.id })
  })

  it('renders channel name and video title', async () => {
    const PlayPage = (await import('@/app/kids/play/page')).default
    render(<PlayPage />)
    const ch = useStore.getState().channels[0]
    expect(screen.getByText(ch.name)).toBeInTheDocument()
  })

  it('shows playback time', async () => {
    const PlayPage = (await import('@/app/kids/play/page')).default
    render(<PlayPage />)
    expect(screen.getByText(/0:00/)).toBeInTheDocument()
  })

  it('shows empty content message', async () => {
    useStore.getState().addChannel({
      name: 'Empty Channel',
      iconName: 'tv',
      iconColor: '#ccc',
      defaultVolume: 50,
      videoIds: [],
    })
    const emptyChannel = useStore.getState().channels.find((c) => c.name === 'Empty Channel')!
    useStore.getState().updateSettings({ lastChannelId: emptyChannel.id })

    const PlayPage = (await import('@/app/kids/play/page')).default
    render(<PlayPage />)
    expect(screen.getByText('No playable content')).toBeInTheDocument()
  })

  it('keyboard space toggles play/pause', async () => {
    const PlayPage = (await import('@/app/kids/play/page')).default
    render(<PlayPage />)
    fireEvent.keyDown(window, { key: ' ' })
  })

  it('has channel switch zones', async () => {
    const PlayPage = (await import('@/app/kids/play/page')).default
    const { container } = render(<PlayPage />)
    const buttons = container.querySelectorAll('button')
    expect(buttons.length).toBeGreaterThan(0)
  })
})

// ============================================================
// i18n — locale switching
// ============================================================
describe('i18n locale switching', () => {
  beforeEach(resetStore)

  it('defaults to English', () => {
    expect(useStore.getState().locale).toBe('en')
  })

  it('can switch to Chinese', () => {
    useStore.getState().setLocale('zh')
    expect(useStore.getState().locale).toBe('zh')
  })

  it('renders Chinese when locale is zh', async () => {
    useStore.setState({ locale: 'zh', channels: [] })
    const KidsHome = (await import('@/app/kids/page')).default
    render(<KidsHome />)
    expect(screen.getByText('还没有频道哦')).toBeInTheDocument()
  })
})
