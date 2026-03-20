'use client'

import { useState, useMemo } from 'react'
import { useStore } from '@/store'
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

  const filtered = useMemo(() => {
    let result = videos
    if (sourceFilter) result = result.filter((v) => v.sourceId === sourceFilter)
    if (search) {
      const q = search.toLowerCase()
      result = result.filter((v) => v.title.toLowerCase().includes(q))
    }
    return result
  }, [videos, search, sourceFilter])

  const getSourceName = (id: string) => sources.find((s) => s.id === id)?.name || '未知源'
  const getChannelNames = (videoId: string) =>
    channels.filter((c) => c.videoIds.includes(videoId)).map((c) => c.name)

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <div>
          <h2 className="text-xl font-medium">视频库</h2>
          <p className="text-sm text-gray mt-1">共 {videos.length} 个视频</p>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => setViewMode('grid')}
            className={`p-2 rounded-lg cursor-pointer ${viewMode === 'grid' ? 'bg-primary/10 text-primary' : 'text-gray'}`}
          >
            <LayoutGrid size={18} />
          </button>
          <button
            onClick={() => setViewMode('list')}
            className={`p-2 rounded-lg cursor-pointer ${viewMode === 'list' ? 'bg-primary/10 text-primary' : 'text-gray'}`}
          >
            <List size={18} />
          </button>
        </div>
      </div>

      {/* Filters */}
      <div className="flex items-center gap-3 mb-6">
        <div className="relative flex-1 max-w-sm">
          <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-gray" />
          <Input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="搜索视频..."
            className="pl-9"
          />
        </div>
        <div className="flex gap-2">
          <button
            onClick={() => setSourceFilter(null)}
            className={`px-3 py-2 rounded-lg text-sm cursor-pointer ${
              !sourceFilter ? 'bg-primary text-white' : 'bg-white border border-gray/20'
            }`}
          >
            全部
          </button>
          {sources.map((src) => (
            <button
              key={src.id}
              onClick={() => setSourceFilter(src.id)}
              className={`px-3 py-2 rounded-lg text-sm cursor-pointer ${
                sourceFilter === src.id ? 'bg-primary text-white' : 'bg-white border border-gray/20'
              }`}
            >
              {src.name}
            </button>
          ))}
        </div>
      </div>

      {filtered.length === 0 ? (
        <div className="text-center py-16 text-gray">
          <FolderOpen size={48} className="mx-auto mb-4 opacity-30" />
          <p>没有找到视频</p>
        </div>
      ) : viewMode === 'grid' ? (
        <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-4">
          {filtered.map((v) => (
            <div key={v.id} className="group">
              <div
                className="aspect-video rounded-xl flex items-center justify-center text-white/60 text-xs mb-2"
                style={{ backgroundColor: v.thumbnailColor }}
              >
                {formatDuration(v.duration)}
              </div>
              <p className="text-sm font-medium truncate">{v.title}</p>
              <p className="text-xs text-gray">{getSourceName(v.sourceId)}</p>
              {getChannelNames(v.id).length > 0 && (
                <div className="flex gap-1 mt-1 flex-wrap">
                  {getChannelNames(v.id).map((name) => (
                    <span key={name} className="text-xs px-1.5 py-0.5 bg-primary/10 text-primary rounded">
                      {name}
                    </span>
                  ))}
                </div>
              )}
            </div>
          ))}
        </div>
      ) : (
        <div className="bg-white rounded-xl border border-gray/20 divide-y divide-gray/10">
          {filtered.map((v) => (
            <div key={v.id} className="flex items-center gap-4 p-3">
              <div
                className="w-24 h-14 rounded-lg flex items-center justify-center text-white/60 text-xs shrink-0"
                style={{ backgroundColor: v.thumbnailColor }}
              >
                {formatDuration(v.duration)}
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-sm font-medium truncate">{v.title}</p>
                <div className="flex items-center gap-3 text-xs text-gray mt-0.5">
                  <span>{getSourceName(v.sourceId)}</span>
                  <span>{v.resolution}</span>
                  <span>{formatSize(v.fileSize)}</span>
                </div>
              </div>
              <div className="flex gap-1">
                {getChannelNames(v.id).map((name) => (
                  <span key={name} className="text-xs px-2 py-1 bg-primary/10 text-primary rounded-full">
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
