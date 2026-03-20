'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { useStore } from '@/store'
import { ChannelIcon, Settings, ChevronLeft, ChevronRight, Play } from '@/components/icons'

export default function KidsHome() {
  const router = useRouter()
  const channels = useStore((s) => s.channels)
  const updateSettings = useStore((s) => s.updateSettings)
  const [selectedIndex, setSelectedIndex] = useState(0)

  const sorted = [...channels].sort((a, b) => a.sortOrder - b.sortOrder)
  const current = sorted[selectedIndex]

  if (sorted.length === 0) {
    return (
      <div className="h-full flex flex-col items-center justify-center gap-6 p-8">
        <div className="text-6xl">📺</div>
        <p className="text-xl text-gray">还没有频道哦</p>
        <p className="text-gray">请家长先去后台添加频道</p>
        <button
          onClick={() => router.push('/admin')}
          className="mt-4 text-primary underline cursor-pointer"
        >
          前往设置
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
    <div className="h-full flex flex-col items-center justify-center relative select-none">
      {/* Settings gear */}
      <button
        onClick={() => router.push('/admin')}
        className="absolute top-6 right-6 text-gray/50 hover:text-gray transition-colors cursor-pointer"
      >
        <Settings size={20} />
      </button>

      {/* Channel carousel */}
      <div className="flex items-center gap-8 mb-12">
        <button
          onClick={prev}
          className="p-3 rounded-full hover:bg-gray/10 transition-colors text-gray cursor-pointer"
        >
          <ChevronLeft size={28} />
        </button>

        <div className="flex flex-col items-center gap-4">
          {/* Channel icons row */}
          <div className="flex items-center gap-6">
            {sorted.map((ch, i) => (
              <button
                key={ch.id}
                onClick={() => setSelectedIndex(i)}
                className={`
                  flex flex-col items-center gap-2 p-4 rounded-2xl transition-all duration-300 cursor-pointer
                  ${i === selectedIndex ? 'scale-125 bg-white shadow-lg' : 'opacity-40 scale-90'}
                `}
              >
                <div
                  className="w-16 h-16 rounded-2xl flex items-center justify-center"
                  style={{ backgroundColor: ch.iconColor + '20' }}
                >
                  <ChannelIcon name={ch.iconName} color={ch.iconColor} size={32} />
                </div>
                <span
                  className="text-sm font-medium"
                  style={{ color: i === selectedIndex ? ch.iconColor : undefined }}
                >
                  {ch.name}
                </span>
              </button>
            ))}
          </div>
        </div>

        <button
          onClick={next}
          className="p-3 rounded-full hover:bg-gray/10 transition-colors text-gray cursor-pointer"
        >
          <ChevronRight size={28} />
        </button>
      </div>

      {/* Play button */}
      <button
        onClick={goPlay}
        className="flex items-center gap-3 px-8 py-4 rounded-2xl text-white text-xl transition-all duration-200 hover:scale-105 cursor-pointer"
        style={{ backgroundColor: current?.iconColor || '#C15F3C' }}
      >
        <Play size={24} fill="white" />
        开始观看
      </button>

      {/* Dots indicator */}
      <div className="flex gap-2 mt-8">
        {sorted.map((_, i) => (
          <div
            key={i}
            className={`w-2 h-2 rounded-full transition-all duration-300 ${
              i === selectedIndex ? 'bg-primary w-6' : 'bg-gray/30'
            }`}
          />
        ))}
      </div>
    </div>
  )
}
