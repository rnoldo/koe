import { MediaSource, Video, Channel } from '@/types'

export const MOCK_SOURCES: MediaSource[] = [
  {
    id: 'src-1',
    name: 'NAS 动画片',
    type: 'smb',
    config: { host: '192.168.1.100', share: 'videos', username: 'admin' },
    isEnabled: true,
    lastScanDate: '2026-03-19T10:30:00Z',
    scanStatus: 'idle',
    errorMessage: null,
    createdAt: '2026-03-01T00:00:00Z',
    videoCount: 12,
  },
  {
    id: 'src-2',
    name: '阿里云盘 儿歌',
    type: 'aliyunDrive',
    config: { rootFolderId: 'abc123' },
    isEnabled: true,
    lastScanDate: '2026-03-18T08:00:00Z',
    scanStatus: 'idle',
    errorMessage: null,
    createdAt: '2026-03-05T00:00:00Z',
    videoCount: 8,
  },
  {
    id: 'src-3',
    name: 'Emby 服务器',
    type: 'emby',
    config: { serverUrl: 'http://192.168.1.200:8096', userId: 'user1' },
    isEnabled: false,
    lastScanDate: null,
    scanStatus: 'error',
    errorMessage: '连接超时',
    createdAt: '2026-03-10T00:00:00Z',
    videoCount: 0,
  },
]

const colors = ['#E07A5F', '#3D405B', '#81B29A', '#F2CC8F', '#6D6875', '#B5838D', '#C15F3C', '#ae5630']

function mockVideos(sourceId: string, prefix: string, count: number, startId: number): Video[] {
  return Array.from({ length: count }, (_, i) => ({
    id: `vid-${startId + i}`,
    title: `${prefix} 第${i + 1}集`,
    sourceId,
    remotePath: `/videos/${prefix}/${i + 1}.mp4`,
    duration: 300 + Math.floor(Math.random() * 900), // 5-20 min
    resolution: '1920x1080',
    fileSize: 100_000_000 + Math.floor(Math.random() * 500_000_000),
    thumbnailColor: colors[(startId + i) % colors.length],
    addedAt: '2026-03-15T00:00:00Z',
  }))
}

export const MOCK_VIDEOS: Video[] = [
  ...mockVideos('src-1', '小猪佩奇', 6, 1),
  ...mockVideos('src-1', '汪汪队立大功', 6, 7),
  ...mockVideos('src-2', '宝宝巴士儿歌', 4, 13),
  ...mockVideos('src-2', '碰碰狐恐龙儿歌', 4, 17),
]

export const MOCK_CHANNELS: Channel[] = [
  {
    id: 'ch-1',
    name: '动画片',
    iconName: 'tv',
    iconColor: '#C15F3C',
    defaultVolume: 60,
    sortOrder: 0,
    videoIds: ['vid-1', 'vid-2', 'vid-3', 'vid-4', 'vid-5', 'vid-6'],
    createdAt: '2026-03-01T00:00:00Z',
  },
  {
    id: 'ch-2',
    name: '冒险故事',
    iconName: 'rocket',
    iconColor: '#3D405B',
    defaultVolume: 50,
    sortOrder: 1,
    videoIds: ['vid-7', 'vid-8', 'vid-9', 'vid-10', 'vid-11', 'vid-12'],
    createdAt: '2026-03-02T00:00:00Z',
  },
  {
    id: 'ch-3',
    name: '儿歌',
    iconName: 'music',
    iconColor: '#81B29A',
    defaultVolume: 40,
    sortOrder: 2,
    videoIds: ['vid-13', 'vid-14', 'vid-15', 'vid-16'],
    createdAt: '2026-03-03T00:00:00Z',
  },
  {
    id: 'ch-4',
    name: '恐龙乐园',
    iconName: 'star',
    iconColor: '#F2CC8F',
    defaultVolume: 55,
    sortOrder: 3,
    videoIds: ['vid-17', 'vid-18', 'vid-19', 'vid-20'],
    createdAt: '2026-03-04T00:00:00Z',
  },
]

export const DEFAULT_SETTINGS = {
  pin: '1234',
  dailyLimitMinutes: null as number | null,
  allowedStartTime: null as string | null,
  allowedEndTime: null as string | null,
  maxVolume: 80,
  lastChannelId: null as string | null,
}
