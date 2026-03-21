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

export default function PlayPage() {
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

  const [channelIndex, setChannelIndex] = useState(() => {
    const idx = sorted.findIndex((c) => c.id === settings.lastChannelId)
    return idx >= 0 ? idx : 0
  })
  const [isPlaying, setIsPlaying] = useState(true)
  const [currentTime, setCurrentTime] = useState(0)
  const [showControls, setShowControls] = useState(false)
  const [showPlaylist, setShowPlaylist] = useState(false)
  const [showStatic, setShowStatic] = useState(false)
  const [isLocked, setIsLocked] = useState(false)
  const [pinInput, setPinInput] = useState('')

  const channel = sorted[channelIndex] as Channel | undefined
  const channelVideos = channel ? channel.videoIds.map((id) => videos.find((v) => v.id === id)).filter(Boolean) as Video[] : []

  const pb = channel ? playbackStates[channel.id] : undefined
  const [videoIndex, setVideoIndex] = useState(() => {
    if (pb && channel) {
      const idx = channel.videoIds.indexOf(pb.currentVideoId)
      return idx >= 0 ? idx : 0
    }
    return 0
  })

  const currentVideo = channelVideos[videoIndex]
  const timerRef = useRef<ReturnType<typeof setInterval>>(null)
  const watchTimerRef = useRef<ReturnType<typeof setInterval>>(null)
  const controlsTimerRef = useRef<ReturnType<typeof setTimeout>>(null)

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

  useEffect(() => {
    if (!isPlaying || !currentVideo || isLocked) {
      if (timerRef.current) clearInterval(timerRef.current)
      return
    }
    timerRef.current = setInterval(() => {
      setCurrentTime((t) => {
        const next = t + 1
        if (next >= currentVideo.duration) {
          setVideoIndex((i) => (i + 1) % channelVideos.length)
          return 0
        }
        return next
      })
    }, 1000)
    return () => { if (timerRef.current) clearInterval(timerRef.current) }
  }, [isPlaying, currentVideo?.id, isLocked]) // eslint-disable-line react-hooks/exhaustive-deps

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

  useEffect(() => {
    if (!showControls) return
    controlsTimerRef.current = setTimeout(() => setShowControls(false), 3000)
    return () => { if (controlsTimerRef.current) clearTimeout(controlsTimerRef.current) }
  }, [showControls])

  const switchChannel = useCallback((direction: 1 | -1) => {
    setShowStatic(true)
    setTimeout(() => {
      setChannelIndex((i) => (i + direction + sorted.length) % sorted.length)
      setShowStatic(false)
    }, 400)
  }, [sorted.length])

  const touchStartRef = useRef<{ x: number; y: number } | null>(null)

  const handleTouchStart = (e: React.TouchEvent) => {
    touchStartRef.current = { x: e.touches[0].clientX, y: e.touches[0].clientY }
  }

  const handleTouchEnd = (e: React.TouchEvent) => {
    if (!touchStartRef.current) return
    const dx = e.changedTouches[0].clientX - touchStartRef.current.x
    const dy = e.changedTouches[0].clientY - touchStartRef.current.y

    if (Math.abs(dy) > Math.abs(dx) && dy < -80) {
      setShowPlaylist(true)
      return
    }
    if (Math.abs(dx) > 80) {
      switchChannel(dx < 0 ? 1 : -1)
    } else if (Math.abs(dx) < 10 && Math.abs(dy) < 10) {
      setShowControls((v) => !v)
    }
    touchStartRef.current = null
  }

  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (isLocked) return
      if (e.key === 'ArrowLeft') switchChannel(-1)
      if (e.key === 'ArrowRight') switchChannel(1)
      if (e.key === 'ArrowUp') setShowPlaylist(true)
      if (e.key === 'ArrowDown') setShowPlaylist(false)
      if (e.key === ' ') { e.preventDefault(); setIsPlaying((p) => !p) }
      if (e.key === 'Escape') router.push('/kids')
    }
    window.addEventListener('keydown', handler)
    return () => window.removeEventListener('keydown', handler)
  }, [isLocked, switchChannel, router])

  const handleUnlock = () => {
    if (pinInput === settings.pin) {
      setIsLocked(false)
      setIsPlaying(true)
      setPinInput('')
    }
  }

  if (!channel || channelVideos.length === 0) {
    return (
      <div className="h-full flex flex-col items-center justify-center gap-4 bg-black text-white">
        <p className="text-xl">{t('play.noContent')}</p>
        <button onClick={() => router.push('/kids')} className="text-primary underline cursor-pointer">
          {t('play.backToChannels')}
        </button>
      </div>
    )
  }

  if (isLocked) {
    return (
      <div className="h-full flex flex-col items-center justify-center gap-6 bg-gradient-to-b from-[#2C2C2C] to-[#1a1a1a] text-white">
        <div className="text-6xl mb-2">🌙</div>
        <h1 className="text-2xl">{t('play.timesUp')}</h1>
        <p className="text-gray">{t('play.restHint')}</p>
        <div className="mt-8 flex flex-col items-center gap-3">
          <p className="text-sm text-gray">{t('play.parentUnlock')}</p>
          <div className="flex gap-2">
            {[1, 2, 3, 4, 5, 6, 7, 8, 9, 0].map((n) => (
              <button
                key={n}
                onClick={() => setPinInput((p) => p + n)}
                className="w-12 h-12 rounded-xl bg-white/10 hover:bg-white/20 flex items-center justify-center text-lg cursor-pointer"
              >
                {n}
              </button>
            ))}
          </div>
          <div className="flex gap-2 mt-2">
            <button
              onClick={() => setPinInput('')}
              className="px-4 py-2 rounded-lg bg-white/10 text-sm cursor-pointer"
            >
              {t('common.clear')}
            </button>
            <button
              onClick={handleUnlock}
              className="px-4 py-2 rounded-lg bg-primary text-sm cursor-pointer"
            >
              {t('common.unlock')}
            </button>
          </div>
          <p className="text-xs text-gray mt-1">
            {pinInput ? '●'.repeat(pinInput.length) : t('play.enterPin')}
          </p>
        </div>
      </div>
    )
  }

  return (
    <div
      className="h-full relative bg-black select-none overflow-hidden"
      onTouchStart={handleTouchStart}
      onTouchEnd={handleTouchEnd}
    >
      {/* Mock video display */}
      <div className="absolute inset-0 flex items-center justify-center">
        <div
          className="w-full h-full flex flex-col items-center justify-center"
          style={{ backgroundColor: currentVideo?.thumbnailColor || '#333' }}
        >
          <p className="text-white/80 text-4xl font-serif mb-4">{channel.name}</p>
          <p className="text-white/60 text-xl">{currentVideo?.title}</p>
          <p className="text-white/40 text-sm mt-2">
            {formatTime(currentTime)} / {formatTime(currentVideo?.duration || 0)}
          </p>
          {!isPlaying && (
            <div className="mt-6 w-16 h-16 rounded-full bg-white/20 flex items-center justify-center">
              <Play size={32} className="text-white ml-1" />
            </div>
          )}
        </div>
      </div>

      {/* TV static transition */}
      {showStatic && (
        <div className="absolute inset-0 tv-static z-30 bg-gray-500" />
      )}

      {/* Controls overlay */}
      {showControls && !showPlaylist && (
        <div
          className="absolute inset-0 z-20 flex flex-col justify-between"
          onClick={() => setShowControls(false)}
        >
          <div className="flex items-center justify-between p-4 bg-gradient-to-b from-black/60 to-transparent">
            <div className="flex items-center gap-3">
              <ChannelIcon name={channel.iconName} color="white" size={20} />
              <span className="text-white text-sm">{channel.name}</span>
            </div>
            <button
              onClick={(e) => { e.stopPropagation(); router.push('/kids') }}
              className="text-white/60 hover:text-white cursor-pointer"
            >
              <X size={20} />
            </button>
          </div>

          <div className="flex items-center justify-center">
            <button
              onClick={(e) => { e.stopPropagation(); setIsPlaying((p) => !p) }}
              className="w-20 h-20 rounded-full bg-white/20 flex items-center justify-center cursor-pointer hover:bg-white/30"
            >
              {isPlaying ? (
                <Pause size={36} className="text-white" />
              ) : (
                <Play size={36} className="text-white ml-1" />
              )}
            </button>
          </div>

          <div className="p-4 bg-gradient-to-t from-black/60 to-transparent">
            <p className="text-white/80 text-sm text-center">{currentVideo?.title}</p>
            <div className="flex justify-center gap-6 mt-2 text-white/30 text-xs">
              <span>{t('play.prevChannel')}</span>
              <span>{t('play.playlist')}</span>
              <span>{t('play.nextChannel')}</span>
            </div>
          </div>
        </div>
      )}

      {/* Channel switch arrows */}
      <button
        className="absolute left-0 top-0 bottom-0 w-16 z-10 cursor-pointer opacity-0 hover:opacity-100 flex items-center justify-center"
        onClick={() => switchChannel(-1)}
      >
        <div className="bg-black/30 rounded-full p-2">
          <span className="text-white text-2xl">‹</span>
        </div>
      </button>
      <button
        className="absolute right-0 top-0 bottom-0 w-16 z-10 cursor-pointer opacity-0 hover:opacity-100 flex items-center justify-center"
        onClick={() => switchChannel(1)}
      >
        <div className="bg-black/30 rounded-full p-2">
          <span className="text-white text-2xl">›</span>
        </div>
      </button>

      {/* Playlist overlay */}
      {showPlaylist && (
        <div className="absolute inset-0 z-30 bg-black/90 flex flex-col">
          <div className="flex items-center justify-between p-4 border-b border-white/10">
            <div className="flex items-center gap-3">
              <ChannelIcon name={channel.iconName} color={channel.iconColor} size={20} />
              <span className="text-white">{channel.name} · {t('play.playlistTitle')}</span>
            </div>
            <button
              onClick={() => setShowPlaylist(false)}
              className="text-white/60 hover:text-white cursor-pointer"
            >
              <X size={20} />
            </button>
          </div>
          <div className="flex-1 overflow-auto p-4">
            <div className="space-y-2">
              {channelVideos.map((v, i) => (
                <button
                  key={v.id}
                  onClick={() => { setVideoIndex(i); setCurrentTime(0); setShowPlaylist(false) }}
                  className={`w-full flex items-center gap-4 p-3 rounded-xl transition-colors cursor-pointer ${
                    i === videoIndex ? 'bg-primary/20 text-primary' : 'text-white/70 hover:bg-white/5'
                  }`}
                >
                  <div
                    className="w-20 h-12 rounded-lg flex items-center justify-center text-white/60 text-xs shrink-0"
                    style={{ backgroundColor: v.thumbnailColor }}
                  >
                    {i === videoIndex && isPlaying ? '▶' : formatTime(v.duration)}
                  </div>
                  <div className="text-left">
                    <p className="text-sm">{v.title}</p>
                    <p className="text-xs text-white/40">{formatTime(v.duration)}</p>
                  </div>
                </button>
              ))}
            </div>
          </div>
        </div>
      )}

      <button
        onClick={() => router.push('/admin')}
        className="absolute bottom-4 right-4 z-10 text-white/10 hover:text-white/40 cursor-pointer transition-colors"
      >
        <Settings size={16} />
      </button>

      {currentVideo && (
        <div className="absolute bottom-0 left-0 right-0 h-0.5 bg-white/10 z-10">
          <div
            className="h-full bg-primary transition-all duration-1000 ease-linear"
            style={{ width: `${(currentTime / currentVideo.duration) * 100}%` }}
          />
        </div>
      )}
    </div>
  )
}
