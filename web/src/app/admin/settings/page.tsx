'use client'

import { useState } from 'react'
import { useStore } from '@/store'
import { useT } from '@/i18n'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Shield, Clock, Volume2, Check } from '@/components/icons'

export default function SettingsPage() {
  const settings = useStore((s) => s.settings)
  const updateSettings = useStore((s) => s.updateSettings)
  const getTodayWatchTime = useStore((s) => s.getTodayWatchTime)
  const [saved, setSaved] = useState(false)
  const t = useT()

  const [pin, setPin] = useState(settings.pin)
  const [dailyLimit, setDailyLimit] = useState(settings.dailyLimitMinutes)
  const [startTime, setStartTime] = useState(settings.allowedStartTime || '')
  const [endTime, setEndTime] = useState(settings.allowedEndTime || '')
  const [maxVolume, setMaxVolume] = useState(settings.maxVolume)

  const handleSave = () => {
    updateSettings({
      pin,
      dailyLimitMinutes: dailyLimit,
      allowedStartTime: startTime || null,
      allowedEndTime: endTime || null,
      maxVolume,
    })
    setSaved(true)
    setTimeout(() => setSaved(false), 2000)
  }

  const todayMinutes = Math.floor(getTodayWatchTime() / 60)

  return (
    <div className="max-w-xl">
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-lg font-medium tracking-tight">{t('settings.title')}</h2>
        <Button onClick={handleSave}>
          {saved ? <><Check size={14} />{t('settings.saved')}</> : t('settings.saveSettings')}
        </Button>
      </div>

      <div className="space-y-4">
        {/* PIN */}
        <div className="bg-surface rounded-xl border border-border p-5">
          <div className="flex items-center gap-2.5 mb-4">
            <div className="w-7 h-7 rounded-lg bg-primary/8 flex items-center justify-center">
              <Shield size={14} className="text-primary" />
            </div>
            <h3 className="text-sm font-medium">{t('settings.parentPin')}</h3>
          </div>
          <div className="max-w-48">
            <Input
              value={pin}
              onChange={(e) => setPin(e.target.value.replace(/\D/g, '').slice(0, 6))}
              placeholder={t('settings.pinPlaceholder')}
              maxLength={6}
              type="password"
            />
            <p className="text-[11px] text-gray mt-1.5">{t('settings.pinHint')}</p>
          </div>
        </div>

        {/* Watch time */}
        <div className="bg-surface rounded-xl border border-border p-5">
          <div className="flex items-center gap-2.5 mb-4">
            <div className="w-7 h-7 rounded-lg bg-primary/8 flex items-center justify-center">
              <Clock size={14} className="text-primary" />
            </div>
            <h3 className="text-sm font-medium">{t('settings.watchTimeControl')}</h3>
            <span className="text-[11px] text-gray ml-auto px-2 py-0.5 bg-bg rounded-md">
              {t('settings.todayWatched', { count: todayMinutes })}
            </span>
          </div>

          <div className="space-y-5">
            <div>
              <div className="flex items-center justify-between mb-2">
                <label className="text-xs text-foreground-secondary">{t('settings.dailyLimit')}</label>
                <span className="text-xs text-foreground font-medium">
                  {dailyLimit ? t('settings.minutesLabel', { count: dailyLimit }) : t('settings.noLimit')}
                </span>
              </div>
              <div className="flex items-center gap-3">
                <input
                  type="range"
                  min={0}
                  max={240}
                  step={15}
                  value={dailyLimit || 0}
                  onChange={(e) => {
                    const v = Number(e.target.value)
                    setDailyLimit(v === 0 ? null : v)
                  }}
                  className="flex-1"
                />
                <button
                  onClick={() => setDailyLimit(null)}
                  className={`px-2.5 py-1 rounded-md text-[11px] cursor-pointer transition-all ${
                    dailyLimit === null ? 'bg-primary text-white shadow-sm' : 'bg-bg text-gray hover:text-foreground-secondary'
                  }`}
                >
                  {t('settings.noLimit')}
                </button>
              </div>
              <div className="flex justify-between text-[10px] text-gray-light mt-1 px-0.5">
                <span>{t('settings.15min')}</span>
                <span>{t('settings.1hour')}</span>
                <span>{t('settings.2hours')}</span>
                <span>{t('settings.4hours')}</span>
              </div>
            </div>

            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="block text-xs text-foreground-secondary mb-1">{t('settings.allowedStart')}</label>
                <Input
                  type="time"
                  value={startTime}
                  onChange={(e) => setStartTime(e.target.value)}
                  placeholder="08:00"
                />
              </div>
              <div>
                <label className="block text-xs text-foreground-secondary mb-1">{t('settings.allowedEnd')}</label>
                <Input
                  type="time"
                  value={endTime}
                  onChange={(e) => setEndTime(e.target.value)}
                  placeholder="20:00"
                />
              </div>
            </div>
            <p className="text-[11px] text-gray">{t('settings.timeHint')}</p>
          </div>
        </div>

        {/* Volume */}
        <div className="bg-surface rounded-xl border border-border p-5">
          <div className="flex items-center gap-2.5 mb-4">
            <div className="w-7 h-7 rounded-lg bg-primary/8 flex items-center justify-center">
              <Volume2 size={14} className="text-primary" />
            </div>
            <h3 className="text-sm font-medium">{t('settings.globalVolume')}</h3>
          </div>
          <div className="max-w-xs">
            <div className="flex items-center justify-between mb-2">
              <label className="text-xs text-foreground-secondary">{t('settings.maxVolume')}</label>
              <span className="text-xs text-foreground font-medium">{maxVolume}%</span>
            </div>
            <input
              type="range"
              min={10}
              max={100}
              step={5}
              value={maxVolume}
              onChange={(e) => setMaxVolume(Number(e.target.value))}
              className="w-full"
            />
          </div>
        </div>
      </div>
    </div>
  )
}
