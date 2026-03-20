'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { useStore } from '@/store'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { ChannelIcon, Plus, Trash2, GripVertical, Edit, X, Tv } from '@/components/icons'
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

function SortableChannel({
  channel,
  videoCount,
  onEdit,
  onDelete,
}: {
  channel: { id: string; name: string; iconName: string; iconColor: string; videoIds: string[] }
  videoCount: number
  onEdit: () => void
  onDelete: () => void
}) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({
    id: channel.id,
  })

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.5 : 1,
  }

  return (
    <div
      ref={setNodeRef}
      style={style}
      className="bg-white rounded-xl border border-gray/20 p-4 flex items-center gap-4"
    >
      <button {...attributes} {...listeners} className="text-gray cursor-grab active:cursor-grabbing">
        <GripVertical size={18} />
      </button>
      <div
        className="w-10 h-10 rounded-xl flex items-center justify-center shrink-0"
        style={{ backgroundColor: channel.iconColor + '20' }}
      >
        <ChannelIcon name={channel.iconName} color={channel.iconColor} size={20} />
      </div>
      <div className="flex-1">
        <p className="font-medium">{channel.name}</p>
        <p className="text-xs text-gray">{videoCount} 个视频</p>
      </div>
      <div className="flex items-center gap-2">
        <Button variant="ghost" size="sm" onClick={onEdit}>
          <Edit size={14} />
        </Button>
        <Button variant="ghost" size="sm" onClick={onDelete}>
          <Trash2 size={14} className="text-red-500" />
        </Button>
      </div>
    </div>
  )
}

export default function ChannelsPage() {
  const router = useRouter()
  const channels = useStore((s) => s.channels)
  const addChannel = useStore((s) => s.addChannel)
  const deleteChannel = useStore((s) => s.deleteChannel)
  const reorderChannels = useStore((s) => s.reorderChannels)
  const [showAdd, setShowAdd] = useState(false)
  const [newName, setNewName] = useState('')
  const [newIcon, setNewIcon] = useState<string>(CHANNEL_ICONS[0])
  const [newColor, setNewColor] = useState<string>(CHANNEL_COLORS[0])

  const sorted = [...channels].sort((a, b) => a.sortOrder - b.sortOrder)
  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 5 } }))

  const handleDragEnd = (event: DragEndEvent) => {
    const { active, over } = event
    if (!over || active.id === over.id) return
    const oldIndex = sorted.findIndex((c) => c.id === active.id)
    const newIndex = sorted.findIndex((c) => c.id === over.id)
    const newOrder = [...sorted]
    const [moved] = newOrder.splice(oldIndex, 1)
    newOrder.splice(newIndex, 0, moved)
    reorderChannels(newOrder.map((c) => c.id))
  }

  const handleAdd = () => {
    if (!newName.trim()) return
    addChannel({ name: newName, iconName: newIcon, iconColor: newColor, defaultVolume: 60, videoIds: [] })
    setNewName('')
    setShowAdd(false)
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <div>
          <h2 className="text-xl font-medium">频道管理</h2>
          <p className="text-sm text-gray mt-1">拖拽排序，点击编辑频道内容</p>
        </div>
        <Button onClick={() => setShowAdd(true)}>
          <Plus size={16} />
          新建频道
        </Button>
      </div>

      {/* Add channel */}
      {showAdd && (
        <div className="mb-6 bg-white rounded-xl border border-gray/20 p-6">
          <div className="flex items-center justify-between mb-4">
            <h3 className="font-medium">新建频道</h3>
            <button onClick={() => setShowAdd(false)} className="text-gray cursor-pointer"><X size={18} /></button>
          </div>
          <div className="space-y-4">
            <div>
              <label className="block text-sm text-gray mb-1">名称</label>
              <Input value={newName} onChange={(e) => setNewName(e.target.value)} placeholder="频道名称" />
            </div>
            <div>
              <label className="block text-sm text-gray mb-1">图标</label>
              <div className="flex flex-wrap gap-2">
                {CHANNEL_ICONS.map((icon) => (
                  <button
                    key={icon}
                    onClick={() => setNewIcon(icon)}
                    className={`w-10 h-10 rounded-xl flex items-center justify-center cursor-pointer border ${
                      newIcon === icon ? 'border-primary bg-primary/5' : 'border-gray/20'
                    }`}
                  >
                    <ChannelIcon name={icon} color={newIcon === icon ? newColor : '#B1ADA1'} size={18} />
                  </button>
                ))}
              </div>
            </div>
            <div>
              <label className="block text-sm text-gray mb-1">颜色</label>
              <div className="flex gap-2">
                {CHANNEL_COLORS.map((color) => (
                  <button
                    key={color}
                    onClick={() => setNewColor(color)}
                    className={`w-8 h-8 rounded-full cursor-pointer border-2 ${
                      newColor === color ? 'border-foreground scale-110' : 'border-transparent'
                    }`}
                    style={{ backgroundColor: color }}
                  />
                ))}
              </div>
            </div>
            <div className="flex justify-end gap-2">
              <Button variant="secondary" onClick={() => setShowAdd(false)}>取消</Button>
              <Button onClick={handleAdd}>创建</Button>
            </div>
          </div>
        </div>
      )}

      {sorted.length === 0 ? (
        <div className="text-center py-16 text-gray">
          <Tv size={48} className="mx-auto mb-4 opacity-30" />
          <p>还没有频道</p>
        </div>
      ) : (
        <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={handleDragEnd}>
          <SortableContext items={sorted.map((c) => c.id)} strategy={verticalListSortingStrategy}>
            <div className="space-y-3">
              {sorted.map((ch) => (
                <SortableChannel
                  key={ch.id}
                  channel={ch}
                  videoCount={ch.videoIds.length}
                  onEdit={() => router.push(`/admin/channels/${ch.id}`)}
                  onDelete={() => deleteChannel(ch.id)}
                />
              ))}
            </div>
          </SortableContext>
        </DndContext>
      )}
    </div>
  )
}
