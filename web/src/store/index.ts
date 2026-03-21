import { create } from 'zustand'
import { persist } from 'zustand/middleware'
import { MediaSource, Video, Channel, PlaybackState, WatchTimeRecord, AppSettings } from '@/types'
import { MOCK_SOURCES, MOCK_VIDEOS, MOCK_CHANNELS, DEFAULT_SETTINGS } from '@/data/mock'
type Locale = 'en' | 'zh'

interface AppStore {
  // Data
  sources: MediaSource[]
  videos: Video[]
  channels: Channel[]
  playbackStates: Record<string, PlaybackState> // keyed by channelId
  watchTimeRecords: WatchTimeRecord[]
  settings: AppSettings

  // Locale
  locale: Locale
  setLocale: (locale: Locale) => void

  // Auth
  isAdminAuthenticated: boolean
  authenticateAdmin: (pin: string) => boolean
  logoutAdmin: () => void

  // Sources
  addSource: (source: Omit<MediaSource, 'id' | 'createdAt' | 'videoCount' | 'lastScanDate' | 'scanStatus' | 'errorMessage'>) => void
  updateSource: (id: string, updates: Partial<MediaSource>) => void
  deleteSource: (id: string) => void
  scanSource: (id: string) => void

  // Videos
  getVideosBySource: (sourceId: string) => Video[]
  getVideoById: (id: string) => Video | undefined

  // Channels
  addChannel: (channel: Omit<Channel, 'id' | 'createdAt' | 'sortOrder'>) => void
  updateChannel: (id: string, updates: Partial<Channel>) => void
  deleteChannel: (id: string) => void
  reorderChannels: (ids: string[]) => void

  // Playback
  savePlaybackState: (state: Omit<PlaybackState, 'updatedAt'>) => void
  getPlaybackState: (channelId: string) => PlaybackState | undefined

  // Watch time
  addWatchTime: (seconds: number) => void
  getTodayWatchTime: () => number
  isTimeLimitReached: () => boolean
  isWithinAllowedTime: () => boolean

  // Settings
  updateSettings: (updates: Partial<AppSettings>) => void
}

function generateId() {
  return `${Date.now()}-${Math.random().toString(36).slice(2, 9)}`
}

function todayStr() {
  return new Date().toISOString().slice(0, 10)
}

export const useStore = create<AppStore>()(
  persist(
    (set, get) => ({
      sources: MOCK_SOURCES,
      videos: MOCK_VIDEOS,
      channels: MOCK_CHANNELS,
      playbackStates: {},
      watchTimeRecords: [],
      settings: DEFAULT_SETTINGS,
      locale: 'en' as Locale,
      setLocale: (locale: Locale) => set({ locale }),
      isAdminAuthenticated: false,

      authenticateAdmin: (pin: string) => {
        const ok = pin === get().settings.pin
        if (ok) set({ isAdminAuthenticated: true })
        return ok
      },
      logoutAdmin: () => set({ isAdminAuthenticated: false }),

      addSource: (source) => {
        const newSource: MediaSource = {
          ...source,
          id: generateId(),
          createdAt: new Date().toISOString(),
          videoCount: 0,
          lastScanDate: null,
          scanStatus: 'idle',
          errorMessage: null,
        }
        set((s) => ({ sources: [...s.sources, newSource] }))
      },
      updateSource: (id, updates) => {
        set((s) => ({
          sources: s.sources.map((src) => (src.id === id ? { ...src, ...updates } : src)),
        }))
      },
      deleteSource: (id) => {
        set((s) => ({
          sources: s.sources.filter((src) => src.id !== id),
          videos: s.videos.filter((v) => v.sourceId !== id),
        }))
      },
      scanSource: (id) => {
        set((s) => ({
          sources: s.sources.map((src) =>
            src.id === id ? { ...src, scanStatus: 'scanning' as const } : src
          ),
        }))
        // Simulate scan completing
        setTimeout(() => {
          set((s) => ({
            sources: s.sources.map((src) =>
              src.id === id
                ? { ...src, scanStatus: 'idle' as const, lastScanDate: new Date().toISOString() }
                : src
            ),
          }))
        }, 2000)
      },

      getVideosBySource: (sourceId) => get().videos.filter((v) => v.sourceId === sourceId),
      getVideoById: (id) => get().videos.find((v) => v.id === id),

      addChannel: (channel) => {
        const channels = get().channels
        const newChannel: Channel = {
          ...channel,
          id: generateId(),
          createdAt: new Date().toISOString(),
          sortOrder: channels.length,
        }
        set((s) => ({ channels: [...s.channels, newChannel] }))
      },
      updateChannel: (id, updates) => {
        set((s) => ({
          channels: s.channels.map((ch) => (ch.id === id ? { ...ch, ...updates } : ch)),
        }))
      },
      deleteChannel: (id) => {
        set((s) => ({
          channels: s.channels.filter((ch) => ch.id !== id),
        }))
      },
      reorderChannels: (ids) => {
        set((s) => ({
          channels: ids
            .map((id, i) => {
              const ch = s.channels.find((c) => c.id === id)
              return ch ? { ...ch, sortOrder: i } : null
            })
            .filter(Boolean) as Channel[],
        }))
      },

      savePlaybackState: (state) => {
        set((s) => ({
          playbackStates: {
            ...s.playbackStates,
            [state.channelId]: { ...state, updatedAt: new Date().toISOString() },
          },
        }))
      },
      getPlaybackState: (channelId) => get().playbackStates[channelId],

      addWatchTime: (seconds) => {
        const today = todayStr()
        set((s) => {
          const existing = s.watchTimeRecords.find((r) => r.date === today)
          if (existing) {
            return {
              watchTimeRecords: s.watchTimeRecords.map((r) =>
                r.date === today ? { ...r, totalSeconds: r.totalSeconds + seconds } : r
              ),
            }
          }
          return {
            watchTimeRecords: [...s.watchTimeRecords, { date: today, totalSeconds: seconds }],
          }
        })
      },
      getTodayWatchTime: () => {
        const today = todayStr()
        return get().watchTimeRecords.find((r) => r.date === today)?.totalSeconds ?? 0
      },
      isTimeLimitReached: () => {
        const { settings } = get()
        if (!settings.dailyLimitMinutes) return false
        const watched = get().getTodayWatchTime()
        return watched >= settings.dailyLimitMinutes * 60
      },
      isWithinAllowedTime: () => {
        const { settings } = get()
        if (!settings.allowedStartTime || !settings.allowedEndTime) return true
        const now = new Date()
        const currentMinutes = now.getHours() * 60 + now.getMinutes()
        const [startH, startM] = settings.allowedStartTime.split(':').map(Number)
        const [endH, endM] = settings.allowedEndTime.split(':').map(Number)
        const startMinutes = startH * 60 + startM
        const endMinutes = endH * 60 + endM
        return currentMinutes >= startMinutes && currentMinutes <= endMinutes
      },

      updateSettings: (updates) => {
        set((s) => ({ settings: { ...s.settings, ...updates } }))
      },
    }),
    {
      name: 'kidstv-storage',
    }
  )
)
