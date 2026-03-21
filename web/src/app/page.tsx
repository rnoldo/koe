'use client'

import { useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { useT } from '@/i18n'

export default function Home() {
  const router = useRouter()
  const t = useT()

  useEffect(() => {
    router.replace('/kids')
  }, [router])

  return (
    <div className="h-full flex items-center justify-center">
      <div className="text-gray text-lg">{t('common.loading')}</div>
    </div>
  )
}
