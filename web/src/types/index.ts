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

export const SOURCE_TYPES: SourceType[] = ['local', 'webdav', 'smb', 'aliyunDrive', 'baiduPan', 'pan115', 'emby', 'jellyfin']

// Per-source-type config field definitions
export interface ConfigField {
  key: string
  labelKey: string // i18n key
  placeholder: string
  type?: 'text' | 'password' | 'url' | 'number'
  required?: boolean
}

export const SOURCE_CONFIG_FIELDS: Record<SourceType, ConfigField[]> = {
  local: [
    { key: 'path', labelKey: 'config.dirPath', placeholder: '/Volumes/NAS/Videos', required: true },
  ],
  webdav: [
    { key: 'url', labelKey: 'config.serverUrl', placeholder: 'https://dav.example.com/videos', type: 'url', required: true },
    { key: 'username', labelKey: 'config.username', placeholder: 'username', required: true },
    { key: 'password', labelKey: 'config.password', placeholder: 'password', type: 'password', required: true },
  ],
  smb: [
    { key: 'host', labelKey: 'config.hostAddr', placeholder: '192.168.1.100', required: true },
    { key: 'share', labelKey: 'config.shareName', placeholder: 'videos', required: true },
    { key: 'username', labelKey: 'config.username', placeholder: 'username' },
    { key: 'password', labelKey: 'config.password', placeholder: 'password', type: 'password' },
  ],
  aliyunDrive: [
    { key: 'rootFolderId', labelKey: 'config.rootFolderId', placeholder: 'config.optionalRoot' },
  ],
  baiduPan: [
    { key: 'rootPath', labelKey: 'config.rootPath', placeholder: 'config.optionalPath' },
  ],
  pan115: [
    { key: 'rootCid', labelKey: 'config.rootCid', placeholder: 'config.optionalRoot' },
  ],
  emby: [
    { key: 'serverUrl', labelKey: 'config.serverUrl', placeholder: 'http://192.168.1.200:8096', type: 'url', required: true },
    { key: 'apiKey', labelKey: 'config.apiKey', placeholder: 'API Key', type: 'password', required: true },
    { key: 'userId', labelKey: 'config.userId', placeholder: 'User ID', required: true },
  ],
  jellyfin: [
    { key: 'serverUrl', labelKey: 'config.serverUrl', placeholder: 'http://192.168.1.200:8096', type: 'url', required: true },
    { key: 'apiKey', labelKey: 'config.apiKey', placeholder: 'API Key', type: 'password', required: true },
    { key: 'userId', labelKey: 'config.userId', placeholder: 'User ID', required: true },
  ],
}

// Source types that require OAuth flow
export const OAUTH_SOURCE_TYPES: SourceType[] = ['aliyunDrive', 'baiduPan', 'pan115']
