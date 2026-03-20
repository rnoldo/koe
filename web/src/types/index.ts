export type SourceType = 'local' | 'webdav' | 'smb' | 'aliyunDrive' | 'baiduPan' | 'pan115' | 'emby' | 'jellyfin'

export interface MediaSource {
  id: string
  name: string
  type: SourceType
  config: Record<string, string>
  isEnabled: boolean
  lastScanDate: string | null
  scanStatus: 'idle' | 'scanning' | 'error'
  errorMessage: string | null
  createdAt: string
  videoCount: number
}

export interface Video {
  id: string
  title: string
  sourceId: string
  remotePath: string
  duration: number // seconds
  resolution: string
  fileSize: number
  thumbnailColor: string // mock: random color for placeholder
  addedAt: string
}

export interface Channel {
  id: string
  name: string
  iconName: string
  iconColor: string
  defaultVolume: number // 0-100
  sortOrder: number
  videoIds: string[]
  createdAt: string
}

export interface PlaybackState {
  channelId: string
  currentVideoId: string
  currentTime: number // seconds
  updatedAt: string
}

export interface WatchTimeRecord {
  date: string // "yyyy-MM-dd"
  totalSeconds: number
}

export interface AppSettings {
  pin: string // 4-6 digit PIN
  dailyLimitMinutes: number | null // null = unlimited
  allowedStartTime: string | null // "HH:mm"
  allowedEndTime: string | null // "HH:mm"
  maxVolume: number // 0-100
  lastChannelId: string | null
}

// Icons available for channels
export const CHANNEL_ICONS = [
  'tv', 'film', 'music', 'star', 'heart', 'smile',
  'sun', 'moon', 'cloud', 'zap', 'compass', 'globe',
  'book', 'palette', 'rocket', 'gamepad-2', 'puzzle', 'flower-2',
] as const

export const CHANNEL_COLORS = [
  '#C15F3C', '#ae5630', '#E07A5F', '#3D405B', '#81B29A',
  '#F2CC8F', '#6D6875', '#B5838D', '#E5989B', '#FFB4A2',
] as const

export const SOURCE_TYPE_LABELS: Record<SourceType, string> = {
  local: '本地目录',
  webdav: 'WebDAV',
  smb: 'SMB',
  aliyunDrive: '阿里云盘',
  baiduPan: '百度网盘',
  pan115: '115网盘',
  emby: 'Emby',
  jellyfin: 'Jellyfin',
}
