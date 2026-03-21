'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { useStore } from '@/store'
import { useT } from '@/i18n'
import { ChannelIcon, Settings, ChevronLeft, ChevronRight, Play } from '@/components/icons'

export default function KidsHome() {
  const router = useRouter()
  const channels = useStore((s) => s.channels)
  const updateSettings = useStore((s) => s.updateSettings)
  const [selectedIndex, setSelectedIndex] = useState(0)
  const t = useT()

  const sorted = [...channels].sort((a, b) => a.sortOrder - b.sortOrder)
  const current = sorted[selectedIndex]

  if (sorted.length === 0) {
    return (
      <div className="h-full flex flex-col items-center justify-center gap-5 p-8">
        <div className="w-20 h-20 rounded-3xl bg-bg-secondary flex items-center justify-center">
          <span className="text-4xl">📺</span>
        </div>
        <p className="text-lg text-foreground-secondary">{t('kids.noChannels')}</p>
        <p className="text-sm text-gray">{t('kids.noChannelsHint')}</p>
        <button
          onClick={() => router.push('/admin')}
          className="mt-2 text-sm text-primary hover:underline cursor-pointer"
        >
          {t('kids.goSettings')}
        </button>
      </div>
    )
  }

  const goPlay = () => {
    if (!current) return
    updateSettings({ lastChannelId: current.id })
    router.push('/kids/play')
  }

  const prev = () => setSelectedIndex((i) => (i - 1 + sorted.length) % sorted.length)
  const next = () => setSelectedIndex((i) => (i + 1) % sorted.length)

  return (
    <div className="h-full flex flex-col items-center justify-center relative select-none bg-bg">
      {/* Settings gear — very subtle */}
      <button
        onClick={() => router.push('/admin')}
        className="absolute top-5 right-5 text-gray-light/40 hover:text-gray transition-colors cursor-pointer"
      >
        <Settings size={18} />
      </button>

      {/* Channel carousel */}
      <div className="flex items-center gap-6 mb-10">
        <button
          onClick={prev}
          className="p-2.5 rounded-full hover:bg-bg-secondary transition-colors text-gray-light cursor-pointer"
        >
          <ChevronLeft size={24} />
        </button>

        <div className="flex items-center gap-5">
          {sorted.map((ch, i) => {
            const isSelected = i === selectedIndex
            return (
              <button
                key={ch.id}
                onClick={() => setSelectedIndex(i)}
                className={`
                  flex flex-col items-center gap-2 p-4 rounded-2xl transition-all duration-300 cursor-pointer
                  ${isSelected
                    ? 'scale-[1.15] bg-surface shadow-lg shadow-black/5'
                    : 'opacity-35 scale-[0.85] hover:opacity-50'
                  }
                `}
              >
                <div
                  className="w-16 h-16 rounded-2xl flex items-center justify-center transition-all"
                  style={{ backgroundColor: ch.iconColor + (isSelected ? '15' : '10') }}
                >
                  <ChannelIcon name={ch.iconName} color={ch.iconColor} size={30} />
                </div>
                <span
                  className="text-[13px] font-medium tracking-tight"
                  style={{ color: isSelected ? ch.iconColor : undefined }}
                >
                  {ch.name}
                </span>
              </button>
            )
          })}
        </div>

        <button
          onClick={next}
          className="p-2.5 rounded-full hover:bg-bg-secondary transition-colors text-gray-light cursor-pointer"
        >
          <ChevronRight size={24} />
        </button>
      </div>

      {/* Play button */}
      <button
        onClick={goPlay}
        className="flex items-center gap-2.5 px-7 py-3.5 rounded-2xl text-white text-lg tracking-tight transition-all duration-200 hover:scale-[1.03] active:scale-[0.98] cursor-pointer shadow-lg"
        style={{
          backgroundColor: current?.iconColor || '#C15F3C',
          boxShadow: `0 8px 24px ${(current?.iconColor || '#C15F3C')}30`,
        }}
      >
        <Play size={20} fill="white" />
        {t('kids.startWatching')}
      </button>

      {/* Dots indicator */}
      <div className="flex gap-1.5 mt-8">
        {sorted.map((_, i) => (
          <div
            key={i}
            className={`h-1.5 rounded-full transition-all duration-300 ${
              i === selectedIndex ? 'bg-primary w-5' : 'bg-border w-1.5'
            }`}
          />
        ))}
      </div>
    </div>
  )
}
