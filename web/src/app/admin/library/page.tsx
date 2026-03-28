'use client'

import { useState, useMemo } from 'react'
import { useStore, useHydrated } from '@/store'
import { useT } from '@/i18n'
import { Search, LayoutGrid, List, FolderOpen } from '@/components/icons'
import { Input } from '@/components/ui/input'

function formatDuration(s: number) {
  const m = Math.floor(s / 60)
  const sec = Math.floor(s % 60)
  return `${m}:${sec.toString().padStart(2, '0')}`
}

function formatSize(bytes: number) {
  if (bytes > 1_000_000_000) return `${(bytes / 1_000_000_000).toFixed(1)} GB`
  return `${(bytes / 1_000_000).toFixed(0)} MB`
}

export default function LibraryPage() {
  const videos = useStore((s) => s.videos)
  const sources = useStore((s) => s.sources)
  const channels = useStore((s) => s.channels)
  const [search, setSearch] = useState('')
  const [sourceFilter, setSourceFilter] = useState<string | null>(null)
  const [viewMode, setViewMode] = useState<'grid' | 'list'>('grid')
  const hydrated = useHydrated()
  const t = useT()

  const filtered = useMemo(() => {
    let result = videos
    if (sourceFilter) result = result.filter((v) => v.sourceId === sourceFilter)
    if (search) {
      const q = search.toLowerCase()
      result = result.filter((v) => v.title.toLowerCase().includes(q))
    }
    return result
  }, [videos, search, sourceFilter])

  const getSourceName = (id: string) => sources.find((s) => s.id === id)?.name || t('library.unknownSource')
  const getChannelNames = (videoId: string) =>
    channels.filter((c) => c.videoIds.includes(videoId)).map((c) => c.name)

  if (!hydrated) {
    return (
      <div>
        <div className="flex items-center justify-between mb-5">
          <div>
            <div className="h-5 w-24 bg-bg-secondary rounded animate-pulse" />
            <div className="h-4 w-32 bg-bg-secondary rounded animate-pulse mt-2" />
          </div>
        </div>
        <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-4">
          {Array.from({ length: 10 }, (_, i) => (
            <div key={i}>
              <div className="aspect-video rounded-lg bg-bg-secondary animate-pulse mb-2" />
              <div className="h-4 w-3/4 bg-bg-secondary rounded animate-pulse" />
              <div className="h-3 w-1/2 bg-bg-secondary rounded animate-pulse mt-1" />
            </div>
          ))}
        </div>
      </div>
    )
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-5">
        <div>
          <h2 className="text-lg font-medium tracking-tight">{t('library.title')}</h2>
          <p className="text-sm text-foreground-secondary mt-0.5">{t('library.totalVideos', { count: videos.length })}</p>
        </div>
        <div className="flex items-center gap-0.5 bg-bg-secondary rounded-lg p-0.5">
          <button
            onClick={() => setViewMode('grid')}
            className={`p-1.5 rounded-md cursor-pointer transition-all ${viewMode === 'grid' ? 'bg-surface text-primary shadow-sm' : 'text-gray'}`}
          >
            <LayoutGrid size={15} />
          </button>
          <button
            onClick={() => setViewMode('list')}
            className={`p-1.5 rounded-md cursor-pointer transition-all ${viewMode === 'list' ? 'bg-surface text-primary shadow-sm' : 'text-gray'}`}
          >
            <List size={15} />
          </button>
        </div>
      </div>

      {/* Filters */}
      <div className="flex items-center gap-3 mb-5">
        <div className="relative flex-1 max-w-xs">
          <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-light" />
          <Input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder={t('library.searchPlaceholder')}
            className="pl-8"
          />
        </div>
        <div className="flex gap-1">
          <button
            onClick={() => setSourceFilter(null)}
            className={`px-2.5 py-1.5 rounded-lg text-[12px] cursor-pointer transition-all ${
              !sourceFilter ? 'bg-primary text-white shadow-sm' : 'bg-surface border border-border text-gray hover:text-foreground-secondary'
            }`}
          >
            {t('common.all')}
          </button>
          {sources.map((src) => (
            <button
              key={src.id}
              onClick={() => setSourceFilter(src.id)}
              className={`px-2.5 py-1.5 rounded-lg text-[12px] cursor-pointer transition-all ${
                sourceFilter === src.id ? 'bg-primary text-white shadow-sm' : 'bg-surface border border-border text-gray hover:text-foreground-secondary'
              }`}
            >
              {src.name}
            </button>
          ))}
        </div>
      </div>

      {filtered.length === 0 ? (
        <div className="text-center py-20 text-gray">
          <FolderOpen size={36} className="mx-auto mb-3 opacity-20" />
          <p className="text-sm">{t('library.noVideos')}</p>
        </div>
      ) : viewMode === 'grid' ? (
        <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-4">
          {filtered.map((v) => (
            <div key={v.id} className="group">
              <div
                className="aspect-video rounded-lg flex items-center justify-center text-white/50 text-[11px] mb-2 shadow-sm"
                style={{ backgroundColor: v.thumbnailColor }}
              >
                {formatDuration(v.duration)}
              </div>
              <p className="text-[13px] font-medium truncate leading-tight">{v.title}</p>
              <p className="text-[11px] text-gray mt-0.5">{getSourceName(v.sourceId)}</p>
              {getChannelNames(v.id).length > 0 && (
                <div className="flex gap-1 mt-1 flex-wrap">
                  {getChannelNames(v.id).map((name) => (
                    <span key={name} className="text-[10px] px-1.5 py-0.5 bg-primary/8 text-primary rounded">
                      {name}
                    </span>
                  ))}
                </div>
              )}
            </div>
          ))}
        </div>
      ) : (
        <div className="bg-surface rounded-xl border border-border divide-y divide-border/60">
          {filtered.map((v) => (
            <div key={v.id} className="flex items-center gap-4 p-3 hover:bg-bg/40 transition-colors">
              <div
                className="w-20 h-12 rounded-lg flex items-center justify-center text-white/50 text-[10px] shrink-0"
                style={{ backgroundColor: v.thumbnailColor }}
              >
                {formatDuration(v.duration)}
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-[13px] font-medium truncate">{v.title}</p>
                <div className="flex items-center gap-2.5 text-[11px] text-gray mt-0.5">
                  <span>{getSourceName(v.sourceId)}</span>
                  <span>{v.resolution}</span>
                  <span>{formatSize(v.fileSize)}</span>
                </div>
              </div>
              <div className="flex gap-1">
                {getChannelNames(v.id).map((name) => (
                  <span key={name} className="text-[10px] px-1.5 py-0.5 bg-primary/8 text-primary rounded-full">
                    {name}
                  </span>
                ))}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
