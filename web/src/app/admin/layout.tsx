'use client'

import { usePathname, useRouter } from 'next/navigation'
import { useStore } from '@/store'
import { HardDrive, FolderOpen, Tv, Settings, LogOut, ArrowLeft } from '@/components/icons'

const NAV_ITEMS = [
  { href: '/admin/sources', label: '媒体源', icon: HardDrive },
  { href: '/admin/library', label: '视频库', icon: FolderOpen },
  { href: '/admin/channels', label: '频道', icon: Tv },
  { href: '/admin/settings', label: '设置', icon: Settings },
]

export default function AdminLayout({ children }: { children: React.ReactNode }) {
  const pathname = usePathname()
  const router = useRouter()
  const isAdminAuthenticated = useStore((s) => s.isAdminAuthenticated)
  const logoutAdmin = useStore((s) => s.logoutAdmin)
  const getTodayWatchTime = useStore((s) => s.getTodayWatchTime)

  // PIN page renders without the admin shell
  if (pathname === '/admin') {
    return <>{children}</>
  }

  // Guard: redirect to PIN if not authenticated
  if (!isAdminAuthenticated) {
    if (typeof window !== 'undefined') {
      router.replace('/admin')
    }
    return null
  }

  const todayMinutes = Math.floor(getTodayWatchTime() / 60)

  return (
    <div className="h-full flex flex-col">
      {/* Top bar */}
      <header className="border-b border-gray/20 bg-white">
        <div className="max-w-6xl mx-auto px-6 h-14 flex items-center justify-between">
          <div className="flex items-center gap-4">
            <button
              onClick={() => router.push('/kids')}
              className="text-gray hover:text-foreground transition-colors cursor-pointer"
            >
              <ArrowLeft size={18} />
            </button>
            <h1 className="text-lg font-medium text-foreground">KidsTV 管理</h1>
            <span className="text-sm text-gray px-3 py-1 bg-bg rounded-full">
              今日观看 {todayMinutes} 分钟
            </span>
          </div>
          <button
            onClick={() => { logoutAdmin(); router.push('/kids') }}
            className="flex items-center gap-2 text-sm text-gray hover:text-foreground transition-colors cursor-pointer"
          >
            <LogOut size={16} />
            退出
          </button>
        </div>
      </header>

      {/* Nav tabs */}
      <nav className="border-b border-gray/20 bg-white">
        <div className="max-w-6xl mx-auto px-6 flex gap-1">
          {NAV_ITEMS.map(({ href, label, icon: Icon }) => {
            const active = pathname.startsWith(href)
            return (
              <button
                key={href}
                onClick={() => router.push(href)}
                className={`
                  flex items-center gap-2 px-4 py-3 text-sm transition-colors cursor-pointer border-b-2
                  ${active
                    ? 'border-primary text-primary'
                    : 'border-transparent text-gray hover:text-foreground'
                  }
                `}
              >
                <Icon size={16} />
                {label}
              </button>
            )
          })}
        </div>
      </nav>

      {/* Content */}
      <main className="flex-1 overflow-auto">
        <div className="max-w-6xl mx-auto px-6 py-6">
          {children}
        </div>
      </main>
    </div>
  )
}
