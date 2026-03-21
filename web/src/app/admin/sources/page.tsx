'use client'

import { useState } from 'react'
import { useStore } from '@/store'
import { useT } from '@/i18n'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Plus, Trash2, RefreshCw, HardDrive, X, Check, Eye, EyeOff } from '@/components/icons'
import { SOURCE_CONFIG_FIELDS, OAUTH_SOURCE_TYPES, SOURCE_TYPES, SourceType } from '@/types'
import type { TranslationKey } from '@/i18n'

function OAuthFlow({ type, onComplete }: { type: SourceType; onComplete: () => void }) {
  const [step, setStep] = useState<'idle' | 'waiting' | 'done'>('idle')
  const t = useT()

  const oauthNames: Record<string, string> = {
    aliyunDrive: t('sourceType.aliyunDrive'),
    baiduPan: t('sourceType.baiduPan'),
    pan115: t('sourceType.pan115'),
  }

  const descs: Record<string, string> = {
    aliyunDrive: t('oauth.aliyunDesc'),
    baiduPan: t('oauth.baiduDesc'),
    pan115: t('oauth.pan115Desc'),
  }

  const name = oauthNames[type] || ''
  const desc = descs[type] || ''
  const action = type === 'pan115' ? t('oauth.pan115Action') : t('oauth.authorize', { name })

  const startOAuth = () => {
    setStep('waiting')
    setTimeout(() => {
      setStep('done')
      onComplete()
    }, 3000)
  }

  return (
    <div className="border border-border rounded-lg p-4 bg-bg/50">
      {step === 'idle' && (
        <div className="flex flex-col items-center gap-3 py-2">
          <p className="text-sm text-foreground-secondary text-center">{desc}</p>
          <Button onClick={startOAuth} size="md">
            {action}
          </Button>
        </div>
      )}
      {step === 'waiting' && (
        <div className="flex flex-col items-center gap-3 py-4">
          <div className="w-8 h-8 border-2 border-primary border-t-transparent rounded-full animate-spin" />
          <p className="text-sm text-foreground-secondary oauth-scanning">{t('oauth.waiting')}</p>
          <p className="text-xs text-gray">{t('oauth.waitingHint')}</p>
        </div>
      )}
      {step === 'done' && (
        <div className="flex items-center gap-2 justify-center py-2 text-green-600">
          <Check size={16} />
          <span className="text-sm font-medium">{t('oauth.success')}</span>
        </div>
      )}
    </div>
  )
}

function ConfigForm({
  type,
  config,
  onChange,
}: {
  type: SourceType
  config: Record<string, string>
  onChange: (config: Record<string, string>) => void
}) {
  const fields = SOURCE_CONFIG_FIELDS[type]
  const isOAuth = OAUTH_SOURCE_TYPES.includes(type)
  const [oauthDone, setOauthDone] = useState(false)
  const [showPasswords, setShowPasswords] = useState<Record<string, boolean>>({})
  const t = useT()

  return (
    <div className="space-y-3">
      {isOAuth && (
        <OAuthFlow type={type} onComplete={() => setOauthDone(true)} />
      )}
      {isOAuth && !oauthDone && fields.length > 0 && (
        <p className="text-xs text-gray">{t('sources.authComplete')}</p>
      )}
      {fields.map((field) => {
        const label = t(field.labelKey as TranslationKey)
        const placeholder = field.placeholder.startsWith('config.')
          ? t(field.placeholder as TranslationKey)
          : field.placeholder
        return (
          <div key={field.key}>
            <label className="block text-xs text-foreground-secondary mb-1">
              {label}
              {field.required && <span className="text-primary ml-0.5">*</span>}
            </label>
            <div className="relative">
              <Input
                type={field.type === 'password' && !showPasswords[field.key] ? 'password' : 'text'}
                value={config[field.key] || ''}
                onChange={(e) => onChange({ ...config, [field.key]: e.target.value })}
                placeholder={placeholder}
                disabled={isOAuth && !oauthDone && field.required}
              />
              {field.type === 'password' && (
                <button
                  type="button"
                  onClick={() => setShowPasswords((s) => ({ ...s, [field.key]: !s[field.key] }))}
                  className="absolute right-2.5 top-1/2 -translate-y-1/2 text-gray hover:text-foreground-secondary cursor-pointer"
                >
                  {showPasswords[field.key] ? <EyeOff size={14} /> : <Eye size={14} />}
                </button>
              )}
            </div>
          </div>
        )
      })}
    </div>
  )
}

const SOURCE_TYPE_ICONS: Record<SourceType, string> = {
  local: '📁', webdav: '🌐', smb: '🖥️', aliyunDrive: '☁️',
  baiduPan: '💾', pan115: '📦', emby: '🎬', jellyfin: '🪼',
}

export default function SourcesPage() {
  const sources = useStore((s) => s.sources)
  const addSource = useStore((s) => s.addSource)
  const deleteSource = useStore((s) => s.deleteSource)
  const scanSource = useStore((s) => s.scanSource)
  const updateSource = useStore((s) => s.updateSource)
  const locale = useStore((s) => s.locale)
  const [showAdd, setShowAdd] = useState(false)
  const [newName, setNewName] = useState('')
  const [newType, setNewType] = useState<SourceType>('local')
  const [newConfig, setNewConfig] = useState<Record<string, string>>({})
  const t = useT()

  const handleAdd = () => {
    if (!newName.trim()) return
    addSource({ name: newName, type: newType, config: newConfig, isEnabled: true })
    setNewName('')
    setNewConfig({})
    setShowAdd(false)
  }

  const handleTypeChange = (type: SourceType) => {
    setNewType(type)
    setNewConfig({})
  }

  const statusIndicator = (status: string) => {
    if (status === 'scanning') return 'bg-amber-400 animate-pulse'
    if (status === 'error') return 'bg-red-400'
    return 'bg-emerald-400'
  }

  const sourceTypeLabel = (type: SourceType) => t(`sourceType.${type}` as TranslationKey)

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <div>
          <h2 className="text-lg font-medium tracking-tight">{t('sources.title')}</h2>
          <p className="text-sm text-foreground-secondary mt-0.5">{t('sources.subtitle')}</p>
        </div>
        <Button onClick={() => setShowAdd(true)}>
          <Plus size={14} />
          {t('sources.addSource')}
        </Button>
      </div>

      {/* Add source panel */}
      {showAdd && (
        <div className="mb-6 bg-surface rounded-xl border border-border p-5">
          <div className="flex items-center justify-between mb-5">
            <h3 className="text-sm font-medium">{t('sources.addSourceTitle')}</h3>
            <button onClick={() => setShowAdd(false)} className="text-gray hover:text-foreground cursor-pointer">
              <X size={16} />
            </button>
          </div>
          <div className="space-y-5">
            <div>
              <label className="block text-xs text-foreground-secondary mb-1">{t('common.name')}</label>
              <Input
                value={newName}
                onChange={(e) => setNewName(e.target.value)}
                placeholder={t('sources.namePlaceholder')}
              />
            </div>

            <div>
              <label className="block text-xs text-foreground-secondary mb-2">{t('common.type')}</label>
              <div className="grid grid-cols-4 gap-1.5">
                {SOURCE_TYPES.map((type) => (
                  <button
                    key={type}
                    onClick={() => handleTypeChange(type)}
                    className={`flex items-center gap-2 px-3 py-2.5 rounded-lg text-sm border transition-all cursor-pointer ${
                      newType === type
                        ? 'border-primary bg-primary/5 text-primary shadow-sm'
                        : 'border-border hover:border-gray-light bg-surface'
                    }`}
                  >
                    <span className="text-base">{SOURCE_TYPE_ICONS[type]}</span>
                    <span>{sourceTypeLabel(type)}</span>
                  </button>
                ))}
              </div>
            </div>

            <div>
              <label className="block text-xs text-foreground-secondary mb-2">{t('sources.connectionConfig')}</label>
              <ConfigForm type={newType} config={newConfig} onChange={setNewConfig} />
            </div>

            <div className="flex justify-end gap-2 pt-2 border-t border-border">
              <Button variant="secondary" onClick={() => setShowAdd(false)}>{t('common.cancel')}</Button>
              <Button onClick={handleAdd} disabled={!newName.trim()}>{t('common.add')}</Button>
            </div>
          </div>
        </div>
      )}

      {/* Source list */}
      {sources.length === 0 ? (
        <div className="text-center py-20 text-gray">
          <HardDrive size={40} className="mx-auto mb-3 opacity-20" />
          <p className="text-sm">{t('sources.noSources')}</p>
          <p className="text-xs mt-1 text-gray-light">{t('sources.noSourcesHint')}</p>
        </div>
      ) : (
        <div className="space-y-2">
          {sources.map((src) => (
            <div
              key={src.id}
              className="bg-surface rounded-xl border border-border p-4 flex items-center justify-between hover:shadow-sm transition-shadow"
            >
              <div className="flex items-center gap-3.5">
                <div className="relative">
                  <span className="text-xl">{SOURCE_TYPE_ICONS[src.type]}</span>
                  <div className={`absolute -bottom-0.5 -right-0.5 w-2 h-2 rounded-full ring-2 ring-surface ${statusIndicator(src.scanStatus)}`} />
                </div>
                <div>
                  <div className="flex items-center gap-2">
                    <span className="text-sm font-medium">{src.name}</span>
                    <span className="text-[11px] text-foreground-secondary px-1.5 py-0.5 bg-bg rounded">
                      {sourceTypeLabel(src.type)}
                    </span>
                  </div>
                  <div className="flex items-center gap-2.5 mt-0.5 text-[11px] text-gray">
                    <span>{t('common.videos', { count: src.videoCount })}</span>
                    {src.lastScanDate && (
                      <span>{t('sources.lastScan')} {new Date(src.lastScanDate).toLocaleString(locale === 'zh' ? 'zh-CN' : 'en-US', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' })}</span>
                    )}
                    {src.errorMessage && (
                      <span className="text-red-500">{src.errorMessage}</span>
                    )}
                  </div>
                </div>
              </div>
              <div className="flex items-center gap-1.5">
                <button
                  onClick={() => updateSource(src.id, { isEnabled: !src.isEnabled })}
                  className={`px-2 py-0.5 rounded text-[11px] cursor-pointer transition-colors ${
                    src.isEnabled
                      ? 'bg-emerald-50 text-emerald-600'
                      : 'bg-bg-secondary text-gray'
                  }`}
                >
                  {src.isEnabled ? t('common.enabled') : t('common.disabled')}
                </button>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => scanSource(src.id)}
                  disabled={src.scanStatus === 'scanning'}
                >
                  <RefreshCw size={13} className={src.scanStatus === 'scanning' ? 'animate-spin' : ''} />
                </Button>
                <Button variant="ghost" size="sm" onClick={() => deleteSource(src.id)}>
                  <Trash2 size={13} className="text-red-400" />
                </Button>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
