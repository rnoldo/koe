'use client'

import { useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { useStore } from '@/store'

export default function Home() {
  const router = useRouter()
  const lastChannelId = useStore((s) => s.settings.lastChannelId)
  const channels = useStore((s) => s.channels)

  useEffect(() => {
    if (lastChannelId && channels.some((c) => c.id === lastChannelId)) {
      router.replace('/kids/play')
    } else {
      router.replace('/kids')
    }
  }, [lastChannelId, channels, router])

  return (
    <div className="h-full flex items-center justify-center">
      <div className="text-gray text-lg">载入中...</div>
    </div>
  )
}
