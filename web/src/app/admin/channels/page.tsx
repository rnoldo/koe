'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { useStore, useHydrated } from '@/store'
import { useT } from '@/i18n'
import { Button } from '@/components/ui/button'
import { ChannelIcon, Plus, Trash2, GripVertical, Edit, Tv, X } from '@/components/icons'
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
  videoCountLabel,
  onEdit,
  onDelete,
  confirmingDelete,
  onCancelDelete,
}: {
  channel: { id: string; name: string; iconName: string; iconColor: string; videoIds: string[] }
  videoCountLabel: string
  onEdit: () => void
  onDelete: () => void
  confirmingDelete?: boolean
  onCancelDelete?: () => void
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
      className="bg-surface rounded-xl border border-border p-3.5 flex items-center gap-3.5 hover:shadow-sm transition-shadow group"
    >
      <button {...attributes} {...listeners} className="text-gray-light cursor-grab active:cursor-grabbing">
        <GripVertical size={15} />
      </button>
      <div
        className="w-9 h-9 rounded-xl flex items-center justify-center shrink-0"
        style={{ backgroundColor: channel.iconColor + '15' }}
      >
        <ChannelIcon name={channel.iconName} color={channel.iconColor} size={18} />
      </div>
      <div className="flex-1">
        <p className="text-sm font-medium tracking-tight">{channel.name}</p>
        <p className="text-[11px] text-gray">{videoCountLabel}</p>
      </div>
      <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
        {confirmingDelete ? (
          <>
            <Button variant="danger" size="sm" onClick={onDelete}>
              <Trash2 size={13} />
            </Button>
            <Button variant="ghost" size="sm" onClick={onCancelDelete}>
              <X size={13} />
            </Button>
          </>
        ) : (
          <>
            <Button variant="ghost" size="sm" onClick={onEdit}>
              <Edit size={13} />
            </Button>
            <Button variant="ghost" size="sm" onClick={onDelete}>
              <Trash2 size={13} className="text-red-400" />
            </Button>
          </>
        )}
      </div>
    </div>
  )
}

export default function ChannelsPage() {
  const router = useRouter()
  const channels = useStore((s) => s.channels)
  const deleteChannel = useStore((s) => s.deleteChannel)
  const reorderChannels = useStore((s) => s.reorderChannels)
  const [confirmDeleteId, setConfirmDeleteId] = useState<string | null>(null)
  const hydrated = useHydrated()
  const t = useT()
  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 5 } }))

  const sorted = [...channels].sort((a, b) => a.sortOrder - b.sortOrder)

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

  if (!hydrated) {
    return (
      <div>
        <div className="flex items-center justify-between mb-6">
          <div>
            <div className="h-5 w-32 bg-bg-secondary rounded animate-pulse" />
            <div className="h-4 w-48 bg-bg-secondary rounded animate-pulse mt-2" />
          </div>
          <div className="h-9 w-28 bg-bg-secondary rounded-lg animate-pulse" />
        </div>
        <div className="space-y-2">
          {[1, 2, 3].map((i) => (
            <div key={i} className="bg-surface rounded-xl border border-border p-3.5 flex items-center gap-3.5">
              <div className="w-4 h-4 bg-bg-secondary rounded animate-pulse" />
              <div className="w-9 h-9 rounded-xl bg-bg-secondary animate-pulse" />
              <div className="flex-1">
                <div className="h-4 w-32 bg-bg-secondary rounded animate-pulse" />
                <div className="h-3 w-20 bg-bg-secondary rounded animate-pulse mt-1.5" />
              </div>
            </div>
          ))}
        </div>
      </div>
    )
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <div>
          <h2 className="text-lg font-medium tracking-tight">{t('channels.title')}</h2>
          <p className="text-sm text-foreground-secondary mt-0.5">{t('channels.subtitle')}</p>
        </div>
        <Button onClick={() => router.push('/admin/channels/new')}>
          <Plus size={14} />
          {t('channels.newChannel')}
        </Button>
      </div>

      {sorted.length === 0 ? (
        <div className="text-center py-20 text-gray">
          <Tv size={36} className="mx-auto mb-3 opacity-20" />
          <p className="text-sm">{t('channels.noChannels')}</p>
        </div>
      ) : (
        <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={handleDragEnd}>
          <SortableContext items={sorted.map((c) => c.id)} strategy={verticalListSortingStrategy}>
            <div className="space-y-2">
              {sorted.map((ch) => (
                <SortableChannel
                  key={ch.id}
                  channel={ch}
                  videoCountLabel={t('common.videos', { count: ch.videoIds.length })}
                  onEdit={() => router.push(`/admin/channels/${ch.id}`)}
                  onDelete={() => {
                    if (confirmDeleteId === ch.id) {
                      deleteChannel(ch.id)
                      setConfirmDeleteId(null)
                    } else {
                      setConfirmDeleteId(ch.id)
                    }
                  }}
                  confirmingDelete={confirmDeleteId === ch.id}
                  onCancelDelete={() => setConfirmDeleteId(null)}
                />
              ))}
            </div>
          </SortableContext>
        </DndContext>
      )}
    </div>
  )
}
