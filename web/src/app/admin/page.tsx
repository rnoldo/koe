'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { useStore } from '@/store'
import { Lock } from '@/components/icons'

export default function AdminEntry() {
  const router = useRouter()
  const authenticateAdmin = useStore((s) => s.authenticateAdmin)
  const isAdminAuthenticated = useStore((s) => s.isAdminAuthenticated)
  const [pin, setPin] = useState('')
  const [error, setError] = useState(false)
  const [shake, setShake] = useState(false)

  // Already authenticated
  if (isAdminAuthenticated) {
    router.replace('/admin/sources')
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
      <div className={`flex flex-col items-center gap-6 ${shake ? 'animate-shake' : ''}`}>
        <div className="w-16 h-16 rounded-full bg-primary/10 flex items-center justify-center">
          <Lock size={28} className="text-primary" />
        </div>
        <h1 className="text-xl text-foreground">家长验证</h1>
        <p className="text-sm text-gray">输入 PIN 码进入管理后台</p>

        {/* PIN dots */}
        <div className="flex gap-3 my-4">
          {[0, 1, 2, 3].map((i) => (
            <div
              key={i}
              className={`w-4 h-4 rounded-full transition-all duration-200 ${
                i < pin.length
                  ? error ? 'bg-red-500' : 'bg-primary'
                  : 'bg-gray/30'
              }`}
            />
          ))}
        </div>

        {error && <p className="text-red-500 text-sm">PIN 码错误</p>}

        {/* Number pad */}
        <div className="grid grid-cols-3 gap-3 mt-2">
          {[1, 2, 3, 4, 5, 6, 7, 8, 9].map((n) => (
            <button
              key={n}
              onClick={() => handleDigit(n)}
              className="w-16 h-16 rounded-2xl bg-white hover:bg-gray/10 border border-gray/20 text-xl font-medium transition-colors cursor-pointer"
            >
              {n}
            </button>
          ))}
          <button
            onClick={() => router.push('/kids')}
            className="w-16 h-16 rounded-2xl text-gray text-sm cursor-pointer hover:bg-gray/10"
          >
            返回
          </button>
          <button
            onClick={() => handleDigit(0)}
            className="w-16 h-16 rounded-2xl bg-white hover:bg-gray/10 border border-gray/20 text-xl font-medium transition-colors cursor-pointer"
          >
            0
          </button>
          <button
            onClick={handleDelete}
            className="w-16 h-16 rounded-2xl text-gray text-sm cursor-pointer hover:bg-gray/10"
          >
            删除
          </button>
        </div>

        <p className="text-xs text-gray mt-4">默认 PIN: 1234</p>
      </div>

      <style>{`
        @keyframes shake {
          0%, 100% { transform: translateX(0); }
          20%, 60% { transform: translateX(-8px); }
          40%, 80% { transform: translateX(8px); }
        }
        .animate-shake { animation: shake 0.4s ease-in-out; }
      `}</style>
    </div>
  )
}
