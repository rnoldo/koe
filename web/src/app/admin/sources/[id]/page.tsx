'use client'

import { use, useState } from 'react'
import { useRouter } from 'next/navigation'
import { useStore } from '@/store'
import { useT } from '@/i18n'
import type { TranslationKey } from '@/i18n'
import { Button } from '@/components/ui/button'
import { ArrowLeft, RefreshCw, Trash2, SourceTypeIcon } from '@/components/icons'
import { SOURCE_CONFIG_FIELDS } from '@/types'

function formatDuration(s: number) {
  const m = Math.floor(s / 60)
  const sec = Math.floor(s % 60)
  return `${m}:${sec.toString().padStart(2, '0')}`
}

function formatSize(bytes: number) {
  if (bytes > 1_000_000_000) return `${(bytes / 1_000_000_000).toFixed(1)} GB`
  return `${(bytes / 1_000_000).toFixed(0)} MB`
}

export default function SourceDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params)
  const router = useRouter()
  const sources = useStore((s) => s.sources)
  const videos = useStore((s) => s.videos)
  const channels = useStore((s) => s.channels)
  const scanSource = useStore((s) => s.scanSource)
  const deleteSource = useStore((s) => s.deleteSource)
  const locale = useStore((s) => s.locale)
  const [confirmDelete, setConfirmDelete] = useState(false)
  const t = useT()

  const source = sources.find((s) => s.id === id)
  const sourceVideos = videos.filter((v) => v.sourceId === id)

  if (!source) {
    return (
      <div className="text-center py-16 text-gray">
        <p className="text-sm">{t('sources.sourceNotExist')}</p>
        <button onClick={() => router.push('/admin/sources')} className="text-primary text-sm mt-2 cursor-pointer hover:underline">
          {t('common.back')}
        </button>
      </div>
    )
  }

  const getChannelNames = (videoId: string) =>
    channels.filter((c) => c.videoIds.includes(videoId)).map((c) => c.name)

  const statusLabel = () => {
    if (source.scanStatus === 'scanning') return t('sources.statusScanning')
    if (source.scanStatus === 'error') return t('sources.statusError')
    return t('sources.statusIdle')
  }

  const statusColor = () => {
    if (source.scanStatus === 'scanning') return 'text-amber-600 bg-amber-50'
    if (source.scanStatus === 'error') return 'text-red-600 bg-red-50'
    return 'text-emerald-600 bg-emerald-50'
  }

  const configFields = SOURCE_CONFIG_FIELDS[source.type]

  const handleDelete = () => {
    deleteSource(source.id)
    router.push('/admin/sources')
  }

  return (
    <div>
      {/* Header */}
      <div className="flex items-center gap-3 mb-6">
        <button onClick={() => router.push('/admin/sources')} className="text-gray hover:text-foreground cursor-pointer">
          <ArrowLeft size={18} />
        </button>
        <div className="flex items-center gap-2.5">
          <div className="w-9 h-9 rounded-lg bg-bg-secondary flex items-center justify-center">
            <SourceTypeIcon type={source.type} size={18} className="text-foreground-secondary" />
          </div>
          <div>
            <h2 className="text-lg font-medium tracking-tight">{source.name}</h2>
            <span className="text-[11px] text-foreground-secondary">
              {t(`sourceType.${source.type}` as TranslationKey)}
            </span>
          </div>
        </div>
        <div className="flex-1" />
        <Button
          variant="secondary"
          onClick={() => scanSource(source.id)}
          disabled={source.scanStatus === 'scanning'}
        >
          <RefreshCw size={14} className={source.scanStatus === 'scanning' ? 'animate-spin' : ''} />
          {source.scanStatus === 'scanning' ? t('sources.scanning') : t('sources.rescan')}
        </Button>
        {confirmDelete ? (
          <>
            <span className="text-xs text-red-500">{t('confirm.deleteSource')}</span>
            <Button variant="danger" size="sm" onClick={handleDelete}>
              {t('confirm.confirm')}
            </Button>
            <Button variant="ghost" size="sm" onClick={() => setConfirmDelete(false)}>
              {t('common.cancel')}
            </Button>
          </>
        ) : (
          <Button variant="ghost" onClick={() => setConfirmDelete(true)}>
            <Trash2 size={14} className="text-red-400" />
          </Button>
        )}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-5">
        {/* Left: Source info */}
        <div>
          <div className="bg-surface rounded-xl border border-border p-5 space-y-4">
            {/* Status */}
            <div className="flex items-center justify-between">
              <span className="text-xs text-foreground-secondary">{t('sources.status')}</span>
              <span className={`text-[11px] px-2 py-0.5 rounded-md font-medium ${statusColor()}`}>
                {statusLabel()}
              </span>
            </div>

            {/* Video count */}
            <div className="flex items-center justify-between">
              <span className="text-xs text-foreground-secondary">{t('sources.videoCount')}</span>
              <span className="text-sm font-medium">{sourceVideos.length}</span>
            </div>

            {/* Last scan */}
            {source.lastScanDate && (
              <div className="flex items-center justify-between">
                <span className="text-xs text-foreground-secondary">{t('sources.lastScan')}</span>
                <span className="text-[11px] text-gray">
                  {new Date(source.lastScanDate).toLocaleString(locale === 'zh' ? 'zh-CN' : 'en-US', {
                    month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit',
                  })}
                </span>
              </div>
            )}

            {/* Created */}
            <div className="flex items-center justify-between">
              <span className="text-xs text-foreground-secondary">{t('sources.createdAt')}</span>
              <span className="text-[11px] text-gray">
                {new Date(source.createdAt).toLocaleString(locale === 'zh' ? 'zh-CN' : 'en-US', {
                  year: 'numeric', month: 'short', day: 'numeric',
                })}
              </span>
            </div>

            {/* Error */}
            {source.errorMessage && (
              <div className="p-2.5 rounded-lg bg-red-50 text-red-600 text-[12px]">
                {source.errorMessage}
              </div>
            )}

            {/* Config */}
            {configFields.length > 0 && Object.keys(source.config).length > 0 && (
              <div className="pt-4 border-t border-border">
                <p className="text-[10px] text-gray uppercase tracking-wider mb-3">{t('sources.config')}</p>
                <div className="space-y-2">
                  {configFields.map((field) => {
                    const value = source.config[field.key]
                    if (!value) return null
                    return (
                      <div key={field.key} className="flex items-center justify-between">
                        <span className="text-xs text-foreground-secondary">{t(field.labelKey as TranslationKey)}</span>
                        <span className="text-[12px] text-foreground font-mono">
                          {field.type === 'password' ? '••••••' : value}
                        </span>
                      </div>
                    )
                  })}
                </div>
              </div>
            )}
          </div>
        </div>

        {/* Right: Video list */}
        <div className="lg:col-span-2">
          <div className="bg-surface rounded-xl border border-border p-4">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-sm font-medium">{t('sources.videoList')}</h3>
              <span className="text-[11px] text-gray">{t('common.videos', { count: sourceVideos.length })}</span>
            </div>

            {sourceVideos.length === 0 ? (
              <div className="text-center py-12 text-gray">
                <p className="text-sm">{t('sources.noVideos')}</p>
              </div>
            ) : (
              <div className="divide-y divide-border/60">
                {sourceVideos.map((v) => (
                  <div key={v.id} className="flex items-center gap-3.5 py-2.5">
                    <div
                      className="w-16 h-10 rounded-lg flex items-center justify-center text-white/50 text-[10px] shrink-0"
                      style={{ backgroundColor: v.thumbnailColor }}
                    >
                      {formatDuration(v.duration)}
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="text-[13px] font-medium truncate">{v.title}</p>
                      <div className="flex items-center gap-2 text-[11px] text-gray mt-0.5">
                        <span>{v.resolution}</span>
                        <span>{formatSize(v.fileSize)}</span>
                      </div>
                    </div>
                    <div className="flex gap-1 shrink-0">
                      {getChannelNames(v.id).map((name) => (
                        <span key={name} className="text-[10px] px-1.5 py-0.5 bg-primary/8 text-primary rounded">
                          {name}
                        </span>
                      ))}
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  )
}
