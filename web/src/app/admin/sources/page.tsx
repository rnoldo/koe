'use client'

import { useState } from 'react'
import { useStore } from '@/store'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Plus, Trash2, RefreshCw, HardDrive, X } from '@/components/icons'
import { SOURCE_TYPE_LABELS, SourceType } from '@/types'

export default function SourcesPage() {
  const sources = useStore((s) => s.sources)
  const addSource = useStore((s) => s.addSource)
  const deleteSource = useStore((s) => s.deleteSource)
  const scanSource = useStore((s) => s.scanSource)
  const updateSource = useStore((s) => s.updateSource)
  const [showAdd, setShowAdd] = useState(false)
  const [newName, setNewName] = useState('')
  const [newType, setNewType] = useState<SourceType>('local')

  const handleAdd = () => {
    if (!newName.trim()) return
    addSource({ name: newName, type: newType, config: {}, isEnabled: true })
    setNewName('')
    setShowAdd(false)
  }

  const statusDot = (status: string) => {
    if (status === 'scanning') return 'bg-yellow-400 animate-pulse'
    if (status === 'error') return 'bg-red-500'
    return 'bg-green-500'
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <div>
          <h2 className="text-xl font-medium">媒体源</h2>
          <p className="text-sm text-gray mt-1">管理视频来源，支持多种存储协议</p>
        </div>
        <Button onClick={() => setShowAdd(true)}>
          <Plus size={16} />
          添加媒体源
        </Button>
      </div>

      {/* Add source dialog */}
      {showAdd && (
        <div className="mb-6 bg-white rounded-xl border border-gray/20 p-6">
          <div className="flex items-center justify-between mb-4">
            <h3 className="font-medium">添加媒体源</h3>
            <button onClick={() => setShowAdd(false)} className="text-gray cursor-pointer">
              <X size={18} />
            </button>
          </div>
          <div className="space-y-4">
            <div>
              <label className="block text-sm text-gray mb-1">名称</label>
              <Input
                value={newName}
                onChange={(e) => setNewName(e.target.value)}
                placeholder="例如：NAS 动画片"
              />
            </div>
            <div>
              <label className="block text-sm text-gray mb-1">类型</label>
              <div className="grid grid-cols-4 gap-2">
                {(Object.keys(SOURCE_TYPE_LABELS) as SourceType[]).map((type) => (
                  <button
                    key={type}
                    onClick={() => setNewType(type)}
                    className={`px-3 py-2 rounded-lg text-sm border transition-colors cursor-pointer ${
                      newType === type
                        ? 'border-primary bg-primary/5 text-primary'
                        : 'border-gray/20 hover:border-gray/40'
                    }`}
                  >
                    {SOURCE_TYPE_LABELS[type]}
                  </button>
                ))}
              </div>
            </div>
            <div className="flex justify-end gap-2">
              <Button variant="secondary" onClick={() => setShowAdd(false)}>取消</Button>
              <Button onClick={handleAdd}>添加</Button>
            </div>
          </div>
        </div>
      )}

      {/* Source list */}
      {sources.length === 0 ? (
        <div className="text-center py-16 text-gray">
          <HardDrive size={48} className="mx-auto mb-4 opacity-30" />
          <p>还没有媒体源</p>
          <p className="text-sm mt-1">点击上方按钮添加第一个媒体源</p>
        </div>
      ) : (
        <div className="space-y-3">
          {sources.map((src) => (
            <div
              key={src.id}
              className="bg-white rounded-xl border border-gray/20 p-4 flex items-center justify-between"
            >
              <div className="flex items-center gap-4">
                <div className={`w-2.5 h-2.5 rounded-full ${statusDot(src.scanStatus)}`} />
                <div>
                  <div className="flex items-center gap-2">
                    <span className="font-medium">{src.name}</span>
                    <span className="text-xs text-gray px-2 py-0.5 bg-bg rounded-full">
                      {SOURCE_TYPE_LABELS[src.type]}
                    </span>
                  </div>
                  <div className="flex items-center gap-3 mt-1 text-xs text-gray">
                    <span>{src.videoCount} 个视频</span>
                    {src.lastScanDate && (
                      <span>上次扫描: {new Date(src.lastScanDate).toLocaleString('zh-CN')}</span>
                    )}
                    {src.errorMessage && (
                      <span className="text-red-500">{src.errorMessage}</span>
                    )}
                  </div>
                </div>
              </div>
              <div className="flex items-center gap-2">
                <button
                  onClick={() => updateSource(src.id, { isEnabled: !src.isEnabled })}
                  className={`px-3 py-1 rounded-lg text-xs cursor-pointer ${
                    src.isEnabled ? 'bg-green-50 text-green-700' : 'bg-gray/10 text-gray'
                  }`}
                >
                  {src.isEnabled ? '已启用' : '已禁用'}
                </button>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => scanSource(src.id)}
                  disabled={src.scanStatus === 'scanning'}
                >
                  <RefreshCw size={14} className={src.scanStatus === 'scanning' ? 'animate-spin' : ''} />
                </Button>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => deleteSource(src.id)}
                >
                  <Trash2 size={14} className="text-red-500" />
                </Button>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
