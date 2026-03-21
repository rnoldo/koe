'use client'

import { useState, useEffect, useCallback, useRef } from 'react'
import { useRouter } from 'next/navigation'
import { useStore } from '@/store'
import { useT } from '@/i18n'
import { ChannelIcon, Pause, Play, X, Settings } from '@/components/icons'
import type { Channel, Video } from '@/types'

function formatTime(s: number) {
  const m = Math.floor(s / 60)
  const sec = Math.floor(s % 60)
  return `${m}:${sec.toString().padStart(2, '0')}`
}

type SlideDirection = 'left' | 'right' | 'up' | 'down' | null

export default function KidsPage() {
  const router = useRouter()
  const channels = useStore((s) => s.channels)
  const videos = useStore((s) => s.videos)
  const settings = useStore((s) => s.settings)
  const playbackStates = useStore((s) => s.playbackStates)
  const savePlaybackState = useStore((s) => s.savePlaybackState)
  const updateSettings = useStore((s) => s.updateSettings)
  const addWatchTime = useStore((s) => s.addWatchTime)
  const isTimeLimitReached = useStore((s) => s.isTimeLimitReached)
  const isWithinAllowedTime = useStore((s) => s.isWithinAllowedTime)
  const t = useT()

  const sorted = [...channels].sort((a, b) => a.sortOrder - b.sortOrder)

  // Channel & video state
  const [channelIndex, setChannelIndex] = useState(() => {
    const idx = sorted.findIndex((c) => c.id === settings.lastChannelId)
    return idx >= 0 ? idx : 0
  })
  const [videoIndex, setVideoIndex] = useState(0)
  const [isPlaying, setIsPlaying] = useState(true)
  const [currentTime, setCurrentTime] = useState(0)

  // UI state
  const [slideAnimation, setSlideAnimation] = useState<SlideDirection>(null)
  const [showChannelOverlay, setShowChannelOverlay] = useState(false)
  const [showHud, setShowHud] = useState(true)
  const [showPauseIcon, setShowPauseIcon] = useState(false)
  const [showVideoList, setShowVideoList] = useState(false)
  const [closingVideoList, setClosingVideoList] = useState(false)
  const [isLocked, setIsLocked] = useState(false)
  const [pinInput, setPinInput] = useState('')

  // Refs
  const timerRef = useRef<ReturnType<typeof setInterval>>(null)
  const watchTimerRef = useRef<ReturnType<typeof setInterval>>(null)
  const hudTimerRef = useRef<ReturnType<typeof setTimeout>>(null)
  const touchStartRef = useRef<{ x: number; y: number } | null>(null)
  const videoListRef = useRef<HTMLDivElement>(null)

  const channel = sorted[channelIndex] as Channel | undefined
  const channelVideos = channel
    ? channel.videoIds.map((id) => videos.find((v) => v.id === id)).filter(Boolean) as Video[]
    : []
  const currentVideo = channelVideos[videoIndex]

  // Load playback state when channel changes
  useEffect(() => {
    if (!channel) return
    const saved = playbackStates[channel.id]
    if (saved) {
      const idx = channel.videoIds.indexOf(saved.currentVideoId)
      setVideoIndex(idx >= 0 ? idx : 0)
      setCurrentTime(saved.currentTime)
    } else {
      setVideoIndex(0)
      setCurrentTime(0)
    }
    updateSettings({ lastChannelId: channel.id })
  }, [channel?.id]) // eslint-disable-line react-hooks/exhaustive-deps

  // Playback timer
  useEffect(() => {
    if (!isPlaying || !currentVideo || isLocked) {
      if (timerRef.current) clearInterval(timerRef.current)
      return
    }
    timerRef.current = setInterval(() => {
      setCurrentTime((t) => {
        const next = t + 1
        if (next >= currentVideo.duration) {
          // Auto-advance to next video
          setVideoIndex((i) => (i + 1) % channelVideos.length)
          setCurrentTime(0)
          showHudBriefly()
          return 0
        }
        return next
      })
    }, 1000)
    return () => { if (timerRef.current) clearInterval(timerRef.current) }
  }, [isPlaying, currentVideo?.id, isLocked, channelVideos.length]) // eslint-disable-line react-hooks/exhaustive-deps

  // Save playback state periodically
  useEffect(() => {
    if (!channel || !currentVideo) return
    const save = () => {
      savePlaybackState({
        channelId: channel.id,
        currentVideoId: currentVideo.id,
        currentTime,
      })
    }
    const interval = setInterval(save, 5000)
    return () => { clearInterval(interval); save() }
  }, [channel?.id, currentVideo?.id, currentTime]) // eslint-disable-line react-hooks/exhaustive-deps

  // Watch time tracking
  useEffect(() => {
    if (!isPlaying || isLocked) return
    watchTimerRef.current = setInterval(() => {
      addWatchTime(10)
      if (isTimeLimitReached() || !isWithinAllowedTime()) {
        setIsLocked(true)
        setIsPlaying(false)
      }
    }, 10000)
    return () => { if (watchTimerRef.current) clearInterval(watchTimerRef.current) }
  }, [isPlaying, isLocked]) // eslint-disable-line react-hooks/exhaustive-deps

  // Show HUD on initial load
  useEffect(() => {
    showHudBriefly()
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  const showHudBriefly = useCallback(() => {
    setShowHud(true)
    if (hudTimerRef.current) clearTimeout(hudTimerRef.current)
    hudTimerRef.current = setTimeout(() => setShowHud(false), 2000)
  }, [])

  // Channel switching
  const switchChannel = useCallback((direction: 1 | -1) => {
    if (sorted.length <= 1) return
    const anim = direction === 1 ? 'left' : 'right'
    setSlideAnimation(anim)
    setTimeout(() => {
      setChannelIndex((i) => (i + direction + sorted.length) % sorted.length)
      setSlideAnimation(null)
      setShowChannelOverlay(true)
      showHudBriefly()
      setTimeout(() => setShowChannelOverlay(false), 2000)
    }, 150)
  }, [sorted.length, showHudBriefly])

  // Video switching
  const switchVideo = useCallback((direction: 1 | -1) => {
    if (channelVideos.length <= 1) return
    const anim = direction === 1 ? 'up' : 'down'
    setSlideAnimation(anim)
    setTimeout(() => {
      setVideoIndex((i) => (i + direction + channelVideos.length) % channelVideos.length)
      setCurrentTime(0)
      setSlideAnimation(null)
      showHudBriefly()
    }, 150)
  }, [channelVideos.length, showHudBriefly])

  // Toggle play/pause
  const togglePlayPause = useCallback(() => {
    setIsPlaying((p) => !p)
    setShowPauseIcon(true)
    showHudBriefly()
    setTimeout(() => setShowPauseIcon(false), 600)
  }, [showHudBriefly])

  // Open/close video list panel
  const openVideoList = useCallback(() => {
    setShowVideoList(true)
    setClosingVideoList(false)
  }, [])

  const closeVideoList = useCallback(() => {
    setClosingVideoList(true)
    setTimeout(() => {
      setShowVideoList(false)
      setClosingVideoList(false)
    }, 200)
  }, [])

  // Touch gesture handling
  const handleTouchStart = (e: React.TouchEvent) => {
    touchStartRef.current = { x: e.touches[0].clientX, y: e.touches[0].clientY }
  }

  const handleTouchEnd = (e: React.TouchEvent) => {
    if (!touchStartRef.current) return
    const dx = e.changedTouches[0].clientX - touchStartRef.current.x
    const dy = e.changedTouches[0].clientY - touchStartRef.current.y
    const absDx = Math.abs(dx)
    const absDy = Math.abs(dy)
    const startX = touchStartRef.current.x
    const screenWidth = window.innerWidth
    touchStartRef.current = null

    // Tap on right 20% → open video list
    if (absDx < 10 && absDy < 10) {
      if (startX > screenWidth * 0.8) {
        openVideoList()
        return
      }
      // Tap center → play/pause
      togglePlayPause()
      return
    }

    // Horizontal swipe → change channel
    if (absDx > absDy && absDx > 60) {
      switchChannel(dx < 0 ? 1 : -1)
      return
    }

    // Vertical swipe → change video
    if (absDy > absDx && absDy > 60) {
      switchVideo(dy < 0 ? 1 : -1)
      return
    }
  }

  // Keyboard shortcuts
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (isLocked) return
      if (showVideoList) {
        if (e.key === 'Escape' || e.key === 'l' || e.key === 'L') closeVideoList()
        return
      }
      if (e.key === 'ArrowLeft') switchChannel(-1)
      if (e.key === 'ArrowRight') switchChannel(1)
      if (e.key === 'ArrowUp') { e.preventDefault(); switchVideo(-1) }
      if (e.key === 'ArrowDown') { e.preventDefault(); switchVideo(1) }
      if (e.key === ' ') { e.preventDefault(); togglePlayPause() }
      if (e.key === 'l' || e.key === 'L') openVideoList()
      if (e.key === 'Escape') router.push('/admin')
    }
    window.addEventListener('keydown', handler)
    return () => window.removeEventListener('keydown', handler)
  }, [isLocked, showVideoList, switchChannel, switchVideo, togglePlayPause, openVideoList, closeVideoList, router])

  // Unlock
  const handleUnlock = () => {
    if (pinInput === settings.pin) {
      setIsLocked(false)
      setIsPlaying(true)
      setPinInput('')
    }
  }

  // === EMPTY STATE ===
  if (sorted.length === 0) {
    return (
      <div className="h-full flex flex-col items-center justify-center gap-5 p-8 bg-black text-white">
        <div className="w-20 h-20 rounded-3xl bg-white/10 flex items-center justify-center">
          <span className="text-4xl">📺</span>
        </div>
        <p className="text-lg text-white/70">{t('kids.noChannels')}</p>
        <p className="text-sm text-white/40">{t('kids.noChannelsHint')}</p>
        <button
          onClick={() => router.push('/admin')}
          className="mt-2 text-sm text-primary hover:underline cursor-pointer"
        >
          {t('kids.goSettings')}
        </button>
      </div>
    )
  }

  // === LOCK SCREEN ===
  if (isLocked) {
    return (
      <div className="h-full flex flex-col items-center justify-center gap-6 bg-gradient-to-b from-[#2C2C2C] to-[#1a1a1a] text-white">
        <div className="text-6xl mb-2">🌙</div>
        <h1 className="text-2xl">{t('play.timesUp')}</h1>
        <p className="text-gray">{t('play.restHint')}</p>
        <div className="mt-8 flex flex-col items-center gap-3">
          <p className="text-sm text-gray">{t('play.parentUnlock')}</p>
          {/* 3x3 + 0 numpad */}
          <div className="flex flex-col gap-2">
            {[[1, 2, 3], [4, 5, 6], [7, 8, 9]].map((row, ri) => (
              <div key={ri} className="flex gap-2">
                {row.map((n) => (
                  <button
                    key={n}
                    onClick={() => setPinInput((p) => p + n)}
                    className="w-14 h-14 rounded-xl bg-white/10 hover:bg-white/20 flex items-center justify-center text-lg cursor-pointer transition-colors"
                  >
                    {n}
                  </button>
                ))}
              </div>
            ))}
            <div className="flex gap-2">
              <button
                onClick={() => setPinInput('')}
                className="w-14 h-14 rounded-xl bg-white/10 hover:bg-white/20 flex items-center justify-center text-xs cursor-pointer transition-colors"
              >
                {t('common.clear')}
              </button>
              <button
                onClick={() => setPinInput((p) => p + '0')}
                className="w-14 h-14 rounded-xl bg-white/10 hover:bg-white/20 flex items-center justify-center text-lg cursor-pointer transition-colors"
              >
                0
              </button>
              <button
                onClick={handleUnlock}
                className="w-14 h-14 rounded-xl bg-primary hover:bg-primary-dark flex items-center justify-center text-xs cursor-pointer transition-colors"
              >
                {t('common.unlock')}
              </button>
            </div>
          </div>
          <p className="text-xs text-gray mt-1">
            {pinInput ? '●'.repeat(pinInput.length) : t('play.enterPin')}
          </p>
        </div>
      </div>
    )
  }

  // === MAIN TV EXPERIENCE ===
  const slideClass = slideAnimation
    ? `animate-slide-in-${slideAnimation === 'left' ? 'left' : slideAnimation === 'right' ? 'right' : slideAnimation === 'up' ? 'up' : 'down'}`
    : ''

  return (
    <div
      className="h-full relative bg-black select-none overflow-hidden"
      onTouchStart={handleTouchStart}
      onTouchEnd={handleTouchEnd}
      onClick={(e) => {
        // Mouse click handling (non-touch)
        if (showVideoList) return
        const rect = e.currentTarget.getBoundingClientRect()
        const x = e.clientX - rect.left
        const width = rect.width
        if (x > width * 0.8) {
          openVideoList()
        } else {
          togglePlayPause()
        }
      }}
    >
      {/* Video display */}
      <div className={`absolute inset-0 flex items-center justify-center ${slideClass}`}>
        <div
          className="w-full h-full flex flex-col items-center justify-center"
          style={{ backgroundColor: currentVideo?.thumbnailColor || '#333' }}
        >
          {channel && (
            <div className="flex items-center gap-2 mb-3 text-white/40">
              <ChannelIcon name={channel.iconName} color="rgba(255,255,255,0.4)" size={16} />
              <span className="text-sm">{channel.name}</span>
            </div>
          )}
          <p className="text-white/80 text-3xl font-serif">{currentVideo?.title}</p>
          <p className="text-white/40 text-sm mt-3">
            {formatTime(currentTime)} / {formatTime(currentVideo?.duration || 0)}
          </p>
        </div>
      </div>

      {/* Play/pause icon pulse */}
      {showPauseIcon && (
        <div className="absolute inset-0 flex items-center justify-center z-20 pointer-events-none">
          <div className="w-20 h-20 rounded-full bg-black/40 flex items-center justify-center animate-pulse-fade">
            {isPlaying ? (
              <Play size={36} className="text-white ml-1" />
            ) : (
              <Pause size={36} className="text-white" />
            )}
          </div>
        </div>
      )}

      {/* Channel switch overlay */}
      {showChannelOverlay && channel && (
        <div className="absolute inset-0 flex items-center justify-center z-20 pointer-events-none">
          <div className="animate-channel-overlay flex flex-col items-center gap-3 bg-black/60 px-10 py-6 rounded-2xl backdrop-blur-sm">
            <ChannelIcon name={channel.iconName} color={channel.iconColor} size={40} />
            <p className="text-white text-xl font-serif">{channel.name}</p>
            <p className="text-white/50 text-sm">
              {t('kids.channelInfo', {
                current: String(channelIndex + 1),
                total: String(sorted.length),
              })}
            </p>
          </div>
        </div>
      )}

      {/* HUD — bottom indicators */}
      <div
        className={`absolute bottom-0 left-0 right-0 z-10 transition-opacity duration-300 ${
          showHud ? 'opacity-100' : 'opacity-0'
        }`}
      >
        <div className="flex items-center justify-between px-5 py-3 bg-gradient-to-t from-black/60 to-transparent">
          <div className="flex items-center gap-3 text-white/50 text-xs">
            {channel && (
              <>
                <span className="flex items-center gap-1.5">
                  <ChannelIcon name={channel.iconName} color="rgba(255,255,255,0.5)" size={12} />
                  {t('kids.channelInfo', {
                    current: String(channelIndex + 1),
                    total: String(sorted.length),
                  })}
                </span>
                <span>·</span>
                <span>
                  ▶ {t('kids.videoInfo', {
                    current: String(videoIndex + 1),
                    total: String(channelVideos.length),
                  })}
                </span>
              </>
            )}
          </div>
          {currentVideo && (
            <span className="text-white/40 text-xs">
              {formatTime(currentTime)} / {formatTime(currentVideo.duration)}
            </span>
          )}
        </div>
      </div>

      {/* Progress bar — always visible */}
      {currentVideo && (
        <div className="absolute bottom-0 left-0 right-0 h-[3px] bg-white/10 z-10">
          <div
            className="h-full bg-primary transition-all duration-1000 ease-linear"
            style={{ width: `${(currentTime / currentVideo.duration) * 100}%` }}
          />
        </div>
      )}

      {/* Right edge visual hint */}
      {!showVideoList && (
        <div className="absolute right-0 top-0 bottom-0 w-[3px] bg-white/5 z-10" />
      )}

      {/* Settings button */}
      <button
        onClick={(e) => { e.stopPropagation(); router.push('/admin') }}
        className="absolute bottom-3 right-3 z-10 text-white/10 hover:text-white/40 cursor-pointer transition-colors"
      >
        <Settings size={14} />
      </button>

      {/* Video list panel */}
      {showVideoList && (
        <>
          {/* Backdrop */}
          <div
            className="absolute inset-0 z-30 bg-black/40"
            onClick={(e) => { e.stopPropagation(); closeVideoList() }}
          />
          {/* Panel */}
          <div
            ref={videoListRef}
            className={`absolute right-0 top-0 bottom-0 w-[35%] min-w-[280px] max-w-[400px] z-40 bg-black/90 backdrop-blur-md flex flex-col ${
              closingVideoList ? 'animate-panel-out' : 'animate-panel-in'
            }`}
            onClick={(e) => e.stopPropagation()}
          >
            {/* Panel header */}
            <div className="flex items-center justify-between p-4 border-b border-white/10">
              <div className="flex items-center gap-2.5">
                {channel && <ChannelIcon name={channel.iconName} color={channel.iconColor} size={18} />}
                <span className="text-white text-sm font-medium">
                  {channel?.name} · {t('kids.videoList')}
                </span>
              </div>
              <button
                onClick={closeVideoList}
                className="text-white/40 hover:text-white cursor-pointer transition-colors"
              >
                <X size={18} />
              </button>
            </div>
            {/* Video list */}
            <div className="flex-1 overflow-auto p-3">
              <div className="space-y-1.5">
                {channelVideos.map((v, i) => (
                  <button
                    key={v.id}
                    onClick={() => {
                      setVideoIndex(i)
                      setCurrentTime(0)
                      closeVideoList()
                      showHudBriefly()
                    }}
                    className={`w-full flex items-center gap-3 p-2.5 rounded-xl transition-colors cursor-pointer ${
                      i === videoIndex
                        ? 'bg-primary/20 text-primary'
                        : 'text-white/70 hover:bg-white/5'
                    }`}
                  >
                    <div
                      className="w-16 h-10 rounded-lg flex items-center justify-center text-white/60 text-[10px] shrink-0"
                      style={{ backgroundColor: v.thumbnailColor }}
                    >
                      {i === videoIndex && isPlaying ? '▶' : formatTime(v.duration)}
                    </div>
                    <div className="text-left min-w-0">
                      <p className="text-sm truncate">{v.title}</p>
                      <p className="text-[11px] text-white/30">{formatTime(v.duration)}</p>
                    </div>
                  </button>
                ))}
              </div>
            </div>
          </div>
        </>
      )}
    </div>
  )
}
