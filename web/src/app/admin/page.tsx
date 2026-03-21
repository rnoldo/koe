'use client'

import { useState, useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { useStore } from '@/store'
import { useT } from '@/i18n'
import { Lock } from '@/components/icons'

export default function AdminEntry() {
  const router = useRouter()
  const authenticateAdmin = useStore((s) => s.authenticateAdmin)
  const isAdminAuthenticated = useStore((s) => s.isAdminAuthenticated)
  const [pin, setPin] = useState('')
  const [error, setError] = useState(false)
  const [shake, setShake] = useState(false)
  const t = useT()

  useEffect(() => {
    if (isAdminAuthenticated) {
      router.replace('/admin/sources')
    }
  }, [isAdminAuthenticated, router])

  if (isAdminAuthenticated) {
    return null
  }

  const handleDigit = (d: number) => {
    setError(false)
    const next = pin + d
    setPin(next)
    if (next.length >= 4) {
      if (authenticateAdmin(next)) {
        router.push('/admin/sources')
      } else {
        setError(true)
        setShake(true)
        setTimeout(() => { setShake(false); setPin('') }, 500)
      }
    }
  }

  const handleDelete = () => {
    setPin((p) => p.slice(0, -1))
    setError(false)
  }

  return (
    <div className="h-full flex flex-col items-center justify-center bg-bg">
      <div className={`flex flex-col items-center gap-5 ${shake ? 'animate-shake' : ''}`}>
        <div className="w-14 h-14 rounded-2xl bg-primary/8 flex items-center justify-center">
          <Lock size={24} className="text-primary" />
        </div>
        <div className="text-center">
          <h1 className="text-lg font-medium text-foreground tracking-tight">{t('admin.parentAuth')}</h1>
          <p className="text-[13px] text-gray mt-1">{t('admin.enterPin')}</p>
        </div>

        {/* PIN dots */}
        <div className="flex gap-3 my-2">
          {[0, 1, 2, 3].map((i) => (
            <div
              key={i}
              className={`w-3 h-3 rounded-full transition-all duration-200 ${
                i < pin.length
                  ? error ? 'bg-red-400 scale-110' : 'bg-primary scale-110'
                  : 'bg-border'
              }`}
            />
          ))}
        </div>

        {error && <p className="text-red-400 text-[13px] -mt-1">{t('admin.wrongPin')}</p>}

        {/* Number pad */}
        <div className="grid grid-cols-3 gap-2.5 mt-1">
          {[1, 2, 3, 4, 5, 6, 7, 8, 9].map((n) => (
            <button
              key={n}
              onClick={() => handleDigit(n)}
              className="w-14 h-14 rounded-xl bg-surface hover:bg-bg-secondary border border-border text-lg font-medium transition-all cursor-pointer active:scale-95"
            >
              {n}
            </button>
          ))}
          <button
            onClick={() => router.push('/kids')}
            className="w-14 h-14 rounded-xl text-gray text-[13px] cursor-pointer hover:bg-bg-secondary transition-colors"
          >
            {t('common.back')}
          </button>
          <button
            onClick={() => handleDigit(0)}
            className="w-14 h-14 rounded-xl bg-surface hover:bg-bg-secondary border border-border text-lg font-medium transition-all cursor-pointer active:scale-95"
          >
            0
          </button>
          <button
            onClick={handleDelete}
            className="w-14 h-14 rounded-xl text-gray text-[13px] cursor-pointer hover:bg-bg-secondary transition-colors"
          >
            {t('common.delete')}
          </button>
        </div>

        <p className="text-[11px] text-gray-light mt-3">{t('admin.defaultPin')}</p>
      </div>
    </div>
  )
}
