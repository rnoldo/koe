'use client'

import { useState, useMemo, use } from 'react'
import { useRouter } from 'next/navigation'
import { useStore } from '@/store'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { ChannelIcon, ArrowLeft, Search, Plus, X, GripVertical, Check, Trash2 } from '@/components/icons'
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

  const m = Math.floor(video.duration / 60)
  const s = Math.floor(video.duration % 60)

  return (
    <div ref={setNodeRef} style={style} className="flex items-center gap-3 p-2 bg-white rounded-lg border border-gray/10">
      <button {...attributes} {...listeners} className="text-gray cursor-grab active:cursor-grabbing">
        <GripVertical size={14} />
      </button>
      <div
        className="w-16 h-10 rounded flex items-center justify-center text-white/60 text-xs shrink-0"
        style={{ backgroundColor: video.thumbnailColor }}
      >
        {m}:{s.toString().padStart(2, '0')}
      </div>
      <span className="text-sm flex-1 truncate">{video.title}</span>
      <button onClick={onRemove} className="text-gray hover:text-red-500 cursor-pointer">
        <X size={14} />
      </button>
    </div>
  )
}

export default function ChannelEditorPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params)
  const router = useRouter()
  const channels = useStore((s) => s.channels)
  const videos = useStore((s) => s.videos)
  const updateChannel = useStore((s) => s.updateChannel)

  const channel = channels.find((c) => c.id === id)

  const [name, setName] = useState(channel?.name || '')
  const [iconName, setIconName] = useState(channel?.iconName || 'tv')
  const [iconColor, setIconColor] = useState(channel?.iconColor || '#C15F3C')
  const [volume, setVolume] = useState(channel?.defaultVolume || 60)
  const [selectedVideoIds, setSelectedVideoIds] = useState<string[]>(channel?.videoIds || [])
  const [search, setSearch] = useState('')

  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 5 } }))

  const availableVideos = useMemo(() => {
    let result = videos.filter((v) => !selectedVideoIds.includes(v.id))
    if (search) {
      const q = search.toLowerCase()
      result = result.filter((v) => v.title.toLowerCase().includes(q))
    }
    return result
  }, [videos, selectedVideoIds, search])

  const selectedVideos = useMemo(
    () => selectedVideoIds.map((id) => videos.find((v) => v.id === id)).filter(Boolean) as typeof videos,
    [selectedVideoIds, videos]
  )

  if (!channel) {
    return (
      <div className="text-center py-16 text-gray">
        <p>频道不存在</p>
        <button onClick={() => router.push('/admin/channels')} className="text-primary underline mt-2 cursor-pointer">
          返回
        </button>
      </div>
    )
  }

  const handleSave = () => {
    updateChannel(id, { name, iconName, iconColor, defaultVolume: volume, videoIds: selectedVideoIds })
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
      <div className="flex items-center gap-4 mb-6">
        <button onClick={() => router.push('/admin/channels')} className="text-gray hover:text-foreground cursor-pointer">
          <ArrowLeft size={20} />
        </button>
        <h2 className="text-xl font-medium">编辑频道</h2>
        <div className="flex-1" />
        <Button variant="secondary" onClick={() => router.push('/admin/channels')}>取消</Button>
        <Button onClick={handleSave}>保存</Button>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Left: Channel settings */}
        <div className="space-y-6">
          <div className="bg-white rounded-xl border border-gray/20 p-5 space-y-4">
            <div>
              <label className="block text-sm text-gray mb-1">频道名称</label>
              <Input value={name} onChange={(e) => setName(e.target.value)} />
            </div>

            <div>
              <label className="block text-sm text-gray mb-1">图标</label>
              <div className="flex flex-wrap gap-2">
                {CHANNEL_ICONS.map((icon) => (
                  <button
                    key={icon}
                    onClick={() => setIconName(icon)}
                    className={`w-9 h-9 rounded-lg flex items-center justify-center cursor-pointer border ${
                      iconName === icon ? 'border-primary bg-primary/5' : 'border-gray/20'
                    }`}
                  >
                    <ChannelIcon name={icon} color={iconName === icon ? iconColor : '#B1ADA1'} size={16} />
                  </button>
                ))}
              </div>
            </div>

            <div>
              <label className="block text-sm text-gray mb-1">颜色</label>
              <div className="flex gap-2 flex-wrap">
                {CHANNEL_COLORS.map((color) => (
                  <button
                    key={color}
                    onClick={() => setIconColor(color)}
                    className={`w-7 h-7 rounded-full cursor-pointer border-2 ${
                      iconColor === color ? 'border-foreground scale-110' : 'border-transparent'
                    }`}
                    style={{ backgroundColor: color }}
                  />
                ))}
              </div>
            </div>

            <div>
              <label className="block text-sm text-gray mb-1">默认音量: {volume}%</label>
              <input
                type="range"
                min={0}
                max={100}
                value={volume}
                onChange={(e) => setVolume(Number(e.target.value))}
                className="w-full accent-primary"
              />
            </div>

            {/* Preview */}
            <div className="pt-4 border-t border-gray/10">
              <p className="text-xs text-gray mb-2">预览</p>
              <div className="flex items-center gap-3">
                <div
                  className="w-12 h-12 rounded-xl flex items-center justify-center"
                  style={{ backgroundColor: iconColor + '20' }}
                >
                  <ChannelIcon name={iconName} color={iconColor} size={24} />
                </div>
                <span className="font-medium" style={{ color: iconColor }}>{name || '未命名'}</span>
              </div>
            </div>
          </div>
        </div>

        {/* Right: Video picker (2 cols) */}
        <div className="lg:col-span-2 grid grid-cols-1 md:grid-cols-2 gap-4">
          {/* Available videos */}
          <div className="bg-white rounded-xl border border-gray/20 p-4 flex flex-col max-h-[600px]">
            <h3 className="font-medium mb-3">视频库</h3>
            <div className="relative mb-3">
              <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-gray" />
              <Input
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="搜索..."
                className="pl-8 text-sm py-1.5"
              />
            </div>
            <div className="flex-1 overflow-auto space-y-1.5">
              {availableVideos.map((v) => (
                <button
                  key={v.id}
                  onClick={() => addVideo(v.id)}
                  className="w-full flex items-center gap-3 p-2 rounded-lg hover:bg-bg transition-colors cursor-pointer text-left"
                >
                  <div
                    className="w-14 h-9 rounded flex items-center justify-center text-white/60 text-xs shrink-0"
                    style={{ backgroundColor: v.thumbnailColor }}
                  />
                  <span className="text-sm flex-1 truncate">{v.title}</span>
                  <Plus size={14} className="text-gray shrink-0" />
                </button>
              ))}
              {availableVideos.length === 0 && (
                <p className="text-xs text-gray text-center py-4">没有更多视频</p>
              )}
            </div>
          </div>

          {/* Selected videos */}
          <div className="bg-white rounded-xl border border-gray/20 p-4 flex flex-col max-h-[600px]">
            <h3 className="font-medium mb-3">
              已选视频 <span className="text-gray font-normal">({selectedVideoIds.length})</span>
            </h3>
            <div className="flex-1 overflow-auto">
              {selectedVideos.length === 0 ? (
                <p className="text-xs text-gray text-center py-8">从左侧添加视频</p>
              ) : (
                <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={handleDragEnd}>
                  <SortableContext items={selectedVideoIds} strategy={verticalListSortingStrategy}>
                    <div className="space-y-1.5">
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
