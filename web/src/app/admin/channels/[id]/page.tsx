'use client'

import { useState, useMemo, use } from 'react'
import { useRouter } from 'next/navigation'
import { useStore } from '@/store'
import { useT } from '@/i18n'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { ChannelIcon, ArrowLeft, Search, Plus, X, GripVertical } from '@/components/icons'
import { CHANNEL_ICONS, CHANNEL_COLORS } from '@/types'
import {
  DndContext,
  closestCenter,
  PointerSensor,
  useSensor,
  useSensors,
  DragEndEvent,
} from '@dnd-kit/core'
import {
  SortableContext,
  verticalListSortingStrategy,
  useSortable,
} from '@dnd-kit/sortable'
import { CSS } from '@dnd-kit/utilities'

function formatTime(s: number) {
  const m = Math.floor(s / 60)
  const sec = Math.floor(s % 60)
  return `${m}:${sec.toString().padStart(2, '0')}`
}

function SortableVideoItem({
  video,
  onRemove,
}: {
  video: { id: string; title: string; thumbnailColor: string; duration: number }
  onRemove: () => void
}) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({
    id: video.id,
  })
  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.5 : 1,
  }

  return (
    <div ref={setNodeRef} style={style} className="flex items-center gap-2.5 p-2 bg-surface rounded-lg border border-border/60 group">
      <button {...attributes} {...listeners} className="text-gray-light cursor-grab active:cursor-grabbing">
        <GripVertical size={13} />
      </button>
      <div
        className="w-14 h-9 rounded flex items-center justify-center text-white/60 text-[10px] shrink-0"
        style={{ backgroundColor: video.thumbnailColor }}
      >
        {formatTime(video.duration)}
      </div>
      <span className="text-[13px] flex-1 truncate">{video.title}</span>
      <button onClick={onRemove} className="text-gray-light hover:text-red-400 cursor-pointer opacity-0 group-hover:opacity-100 transition-opacity">
        <X size={13} />
      </button>
    </div>
  )
}

export default function ChannelEditorPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params)
  const isNew = id === 'new'
  const router = useRouter()
  const channels = useStore((s) => s.channels)
  const videos = useStore((s) => s.videos)
  const sources = useStore((s) => s.sources)
  const updateChannel = useStore((s) => s.updateChannel)
  const addChannel = useStore((s) => s.addChannel)
  const t = useT()

  const channel = isNew ? null : channels.find((c) => c.id === id)

  const [name, setName] = useState(channel?.name || '')
  const [iconName, setIconName] = useState(channel?.iconName || 'tv')
  const [iconColor, setIconColor] = useState(channel?.iconColor || '#C15F3C')
  const [volume, setVolume] = useState(channel?.defaultVolume || 60)
  const [selectedVideoIds, setSelectedVideoIds] = useState<string[]>(channel?.videoIds || [])
  const [search, setSearch] = useState('')
  const [sourceFilter, setSourceFilter] = useState<string | null>(null)

  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 5 } }))

  const availableVideos = useMemo(() => {
    let result = videos.filter((v) => !selectedVideoIds.includes(v.id))
    if (sourceFilter) result = result.filter((v) => v.sourceId === sourceFilter)
    if (search) {
      const q = search.toLowerCase()
      result = result.filter((v) => v.title.toLowerCase().includes(q))
    }
    return result
  }, [videos, selectedVideoIds, search, sourceFilter])

  const selectedVideos = useMemo(
    () => selectedVideoIds.map((id) => videos.find((v) => v.id === id)).filter(Boolean) as typeof videos,
    [selectedVideoIds, videos]
  )

  if (!isNew && !channel) {
    return (
      <div className="text-center py-16 text-gray">
        <p className="text-sm">{t('channels.channelNotExist')}</p>
        <button onClick={() => router.push('/admin/channels')} className="text-primary text-sm mt-2 cursor-pointer hover:underline">
          {t('common.back')}
        </button>
      </div>
    )
  }

  const handleSave = () => {
    if (!name.trim()) return
    if (isNew) {
      addChannel({ name, iconName, iconColor, defaultVolume: volume, videoIds: selectedVideoIds })
    } else {
      updateChannel(id, { name, iconName, iconColor, defaultVolume: volume, videoIds: selectedVideoIds })
    }
    router.push('/admin/channels')
  }

  const addVideo = (videoId: string) => {
    setSelectedVideoIds((ids) => [...ids, videoId])
  }

  const removeVideo = (videoId: string) => {
    setSelectedVideoIds((ids) => ids.filter((i) => i !== videoId))
  }

  const handleDragEnd = (event: DragEndEvent) => {
    const { active, over } = event
    if (!over || active.id === over.id) return
    const oldIndex = selectedVideoIds.indexOf(active.id as string)
    const newIndex = selectedVideoIds.indexOf(over.id as string)
    const newOrder = [...selectedVideoIds]
    const [moved] = newOrder.splice(oldIndex, 1)
    newOrder.splice(newIndex, 0, moved)
    setSelectedVideoIds(newOrder)
  }

  return (
    <div>
      {/* Header */}
      <div className="flex items-center gap-3 mb-6">
        <button onClick={() => router.push('/admin/channels')} className="text-gray hover:text-foreground cursor-pointer">
          <ArrowLeft size={18} />
        </button>
        <h2 className="text-lg font-medium tracking-tight">{isNew ? t('channels.newChannel') : t('channels.editChannel')}</h2>
        <div className="flex-1" />
        <Button variant="secondary" onClick={() => router.push('/admin/channels')}>{t('common.cancel')}</Button>
        <Button onClick={handleSave} disabled={!name.trim()}>{isNew ? t('common.create') : t('common.save')}</Button>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-5">
        {/* Left: Channel settings */}
        <div>
          <div className="bg-surface rounded-xl border border-border p-5 space-y-5">
            <div>
              <label className="block text-xs text-foreground-secondary mb-1">{t('channels.channelName')}</label>
              <Input value={name} onChange={(e) => setName(e.target.value)} placeholder={t('channels.channelNamePlaceholder')} />
            </div>

            <div>
              <label className="block text-xs text-foreground-secondary mb-1.5">{t('channels.icon')}</label>
              <div className="flex flex-wrap gap-1.5">
                {CHANNEL_ICONS.map((icon) => (
                  <button
                    key={icon}
                    onClick={() => setIconName(icon)}
                    className={`w-8 h-8 rounded-lg flex items-center justify-center cursor-pointer transition-all ${
                      iconName === icon
                        ? 'bg-primary/8 ring-1.5 ring-primary/40 scale-110'
                        : 'hover:bg-bg-secondary'
                    }`}
                  >
                    <ChannelIcon name={icon} color={iconName === icon ? iconColor : '#C4C0B8'} size={15} />
                  </button>
                ))}
              </div>
            </div>

            <div>
              <label className="block text-xs text-foreground-secondary mb-1.5">{t('channels.color')}</label>
              <div className="flex gap-1.5 flex-wrap">
                {CHANNEL_COLORS.map((color) => (
                  <button
                    key={color}
                    onClick={() => setIconColor(color)}
                    className={`w-6 h-6 rounded-full cursor-pointer transition-all ${
                      iconColor === color ? 'ring-2 ring-offset-1 ring-foreground/30 scale-110' : 'hover:scale-105'
                    }`}
                    style={{ backgroundColor: color }}
                  />
                ))}
              </div>
            </div>

            <div>
              <label className="block text-xs text-foreground-secondary mb-1">
                {t('channels.volume')} <span className="text-gray">{volume}%</span>
              </label>
              <input
                type="range"
                min={0}
                max={100}
                value={volume}
                onChange={(e) => setVolume(Number(e.target.value))}
                className="w-full"
              />
            </div>

            {/* Preview */}
            <div className="pt-4 border-t border-border">
              <p className="text-[10px] text-gray uppercase tracking-wider mb-2">{t('common.preview')}</p>
              <div className="flex items-center gap-3">
                <div
                  className="w-11 h-11 rounded-xl flex items-center justify-center"
                  style={{ backgroundColor: iconColor + '18' }}
                >
                  <ChannelIcon name={iconName} color={iconColor} size={22} />
                </div>
                <div>
                  <span className="text-sm font-medium" style={{ color: iconColor }}>{name || t('common.untitled')}</span>
                  <p className="text-[11px] text-gray">{t('common.videos', { count: selectedVideoIds.length })}</p>
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* Right: Video picker (2 cols) */}
        <div className="lg:col-span-2 grid grid-cols-1 md:grid-cols-2 gap-4">
          {/* Available videos — click to add directly */}
          <div className="bg-surface rounded-xl border border-border p-4 flex flex-col" style={{ maxHeight: 640 }}>
            <div className="flex items-center justify-between mb-2">
              <h3 className="text-sm font-medium">{t('channels.videoLibrary')}</h3>
              <span className="text-[11px] text-gray">{t('common.available', { count: availableVideos.length })}</span>
            </div>

            {/* Search + filter */}
            <div className="space-y-2 mb-3">
              <div className="relative">
                <Search size={13} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-gray-light" />
                <Input
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                  placeholder={t('channels.searchVideos')}
                  className="pl-8 py-1.5 text-[13px]"
                />
              </div>
              {sources.length > 1 && (
                <div className="flex gap-1 flex-wrap">
                  <button
                    onClick={() => setSourceFilter(null)}
                    className={`px-2 py-0.5 rounded text-[11px] cursor-pointer transition-colors ${
                      !sourceFilter ? 'bg-primary text-white' : 'bg-bg text-gray hover:text-foreground-secondary'
                    }`}
                  >
                    {t('common.all')}
                  </button>
                  {sources.map((src) => (
                    <button
                      key={src.id}
                      onClick={() => setSourceFilter(src.id === sourceFilter ? null : src.id)}
                      className={`px-2 py-0.5 rounded text-[11px] cursor-pointer transition-colors ${
                        sourceFilter === src.id ? 'bg-primary text-white' : 'bg-bg text-gray hover:text-foreground-secondary'
                      }`}
                    >
                      {src.name}
                    </button>
                  ))}
                </div>
              )}
            </div>

            {/* Video list — click to add */}
            <div className="flex-1 overflow-auto space-y-0.5">
              {availableVideos.map((v) => (
                <div
                  key={v.id}
                  className="flex items-center gap-2.5 p-2 rounded-lg transition-colors cursor-pointer text-left hover:bg-bg"
                  onClick={() => addVideo(v.id)}
                >
                  <div
                    className="w-12 h-8 rounded flex items-center justify-center text-white/50 text-[10px] shrink-0"
                    style={{ backgroundColor: v.thumbnailColor }}
                  >
                    {formatTime(v.duration)}
                  </div>
                  <span className="text-[13px] flex-1 truncate">{v.title}</span>
                  <Plus size={12} className="text-gray-light shrink-0" />
                </div>
              ))}
              {availableVideos.length === 0 && (
                <p className="text-xs text-gray text-center py-6">{t('channels.noMoreVideos')}</p>
              )}
            </div>
          </div>

          {/* Selected videos — sortable */}
          <div className="bg-surface rounded-xl border border-border p-4 flex flex-col" style={{ maxHeight: 640 }}>
            <div className="flex items-center justify-between mb-3">
              <h3 className="text-sm font-medium">
                {t('common.selected')} <span className="text-gray font-normal">{selectedVideoIds.length}</span>
              </h3>
              {selectedVideoIds.length > 0 && (
                <button
                  onClick={() => setSelectedVideoIds([])}
                  className="text-[11px] text-gray hover:text-red-400 cursor-pointer"
                >
                  {t('channels.clearAll')}
                </button>
              )}
            </div>
            <div className="flex-1 overflow-auto">
              {selectedVideos.length === 0 ? (
                <div className="text-center py-10">
                  <p className="text-xs text-gray">{t('channels.clickToAdd')}</p>
                </div>
              ) : (
                <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={handleDragEnd}>
                  <SortableContext items={selectedVideoIds} strategy={verticalListSortingStrategy}>
                    <div className="space-y-1">
                      {selectedVideos.map((v) => (
                        <SortableVideoItem key={v.id} video={v} onRemove={() => removeVideo(v.id)} />
                      ))}
                    </div>
                  </SortableContext>
                </DndContext>
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
