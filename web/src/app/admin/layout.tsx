'use client'

import { usePathname, useRouter } from 'next/navigation'
import { useStore } from '@/store'
import { useT } from '@/i18n'
import type { Locale } from '@/i18n'
import { HardDrive, FolderOpen, Tv, Settings, LogOut, ArrowLeft } from '@/components/icons'

export default function AdminLayout({ children }: { children: React.ReactNode }) {
  const pathname = usePathname()
  const router = useRouter()
  const isAdminAuthenticated = useStore((s) => s.isAdminAuthenticated)
  const logoutAdmin = useStore((s) => s.logoutAdmin)
  const getTodayWatchTime = useStore((s) => s.getTodayWatchTime)
  const locale = useStore((s) => s.locale)
  const setLocale = useStore((s) => s.setLocale)
  const t = useT()

  const NAV_ITEMS = [
    { href: '/admin/sources', label: t('admin.sources'), icon: HardDrive },
    { href: '/admin/library', label: t('admin.library'), icon: FolderOpen },
    { href: '/admin/channels', label: t('admin.channels'), icon: Tv },
    { href: '/admin/settings', label: t('admin.settings'), icon: Settings },
  ]

  if (pathname === '/admin') {
    return <>{children}</>
  }

  if (!isAdminAuthenticated) {
    router.replace('/admin')
    return (
      <div className="h-full flex items-center justify-center bg-bg">
        <div className="w-5 h-5 border-2 border-primary border-t-transparent rounded-full animate-spin" />
      </div>
    )
  }

  const todayMinutes = Math.floor(getTodayWatchTime() / 60)

  const toggleLocale = () => {
    setLocale(locale === 'en' ? 'zh' : 'en' as Locale)
  }

  return (
    <div className="h-full flex flex-col bg-bg">
      {/* Top bar */}
      <header className="border-b border-border bg-surface/80 backdrop-blur-sm sticky top-0 z-20">
        <div className="max-w-5xl mx-auto px-6 h-12 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <button
              onClick={() => router.push('/kids')}
              className="text-gray hover:text-foreground transition-colors cursor-pointer"
            >
              <ArrowLeft size={16} />
            </button>
            <span className="text-sm font-medium text-foreground tracking-tight">KidsTV</span>
            <span className="text-[11px] text-gray px-2 py-0.5 bg-bg rounded-md">
              {t('admin.todayMinutes', { count: todayMinutes })}
            </span>
          </div>
          <div className="flex items-center gap-3">
            <button
              onClick={toggleLocale}
              className="text-[11px] text-gray hover:text-foreground px-2 py-0.5 bg-bg rounded-md cursor-pointer transition-colors"
            >
              {locale === 'en' ? '中文' : 'EN'}
            </button>
            <button
              onClick={() => { logoutAdmin(); router.push('/kids') }}
              className="flex items-center gap-1.5 text-[13px] text-gray hover:text-foreground transition-colors cursor-pointer"
            >
              <LogOut size={13} />
              {t('common.logout')}
            </button>
          </div>
        </div>
      </header>

      {/* Nav */}
      <nav className="border-b border-border bg-surface/50">
        <div className="max-w-5xl mx-auto px-6 flex gap-0.5">
          {NAV_ITEMS.map(({ href, label, icon: Icon }) => {
            const active = pathname.startsWith(href)
            return (
              <button
                key={href}
                onClick={() => router.push(href)}
                className={`
                  flex items-center gap-1.5 px-3.5 py-2.5 text-[13px] transition-all cursor-pointer border-b-[1.5px]
                  ${active
                    ? 'border-primary text-primary font-medium'
                    : 'border-transparent text-gray hover:text-foreground-secondary'
                  }
                `}
              >
                <Icon size={14} />
                {label}
              </button>
            )
          })}
        </div>
      </nav>

      {/* Content */}
      <main className="flex-1 overflow-auto">
        <div className="max-w-5xl mx-auto px-6 py-6">
          {children}
        </div>
      </main>
    </div>
  )
}
