'use client'

import { useState } from 'react'
import { useStore } from '@/store'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Shield, Clock, Volume2, Check } from '@/components/icons'

export default function SettingsPage() {
  const settings = useStore((s) => s.settings)
  const updateSettings = useStore((s) => s.updateSettings)
  const getTodayWatchTime = useStore((s) => s.getTodayWatchTime)
  const [saved, setSaved] = useState(false)

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
    <div className="max-w-2xl">
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-xl font-medium">设置</h2>
        <Button onClick={handleSave}>
          {saved ? <><Check size={16} />已保存</> : '保存设置'}
        </Button>
      </div>

      <div className="space-y-6">
        {/* PIN */}
        <div className="bg-white rounded-xl border border-gray/20 p-5">
          <div className="flex items-center gap-3 mb-4">
            <Shield size={20} className="text-primary" />
            <h3 className="font-medium">家长 PIN 码</h3>
          </div>
          <div className="max-w-xs">
            <Input
              value={pin}
              onChange={(e) => setPin(e.target.value.replace(/\D/g, '').slice(0, 6))}
              placeholder="4-6 位数字"
              maxLength={6}
              type="password"
            />
            <p className="text-xs text-gray mt-1">用于进入管理后台和解锁儿童端</p>
          </div>
        </div>

        {/* Watch time */}
        <div className="bg-white rounded-xl border border-gray/20 p-5">
          <div className="flex items-center gap-3 mb-4">
            <Clock size={20} className="text-primary" />
            <h3 className="font-medium">观看时长控制</h3>
            <span className="text-sm text-gray ml-auto">今日已看 {todayMinutes} 分钟</span>
          </div>

          <div className="space-y-4">
            <div>
              <label className="block text-sm text-gray mb-2">
                每日限额: {dailyLimit ? `${dailyLimit} 分钟` : '不限制'}
              </label>
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
                  className="flex-1 accent-primary"
                />
                <button
                  onClick={() => setDailyLimit(null)}
                  className={`px-3 py-1 rounded text-xs cursor-pointer ${
                    dailyLimit === null ? 'bg-primary text-white' : 'bg-gray/10 text-gray'
                  }`}
                >
                  不限制
                </button>
              </div>
              <div className="flex justify-between text-xs text-gray mt-1">
                <span>15分钟</span>
                <span>1小时</span>
                <span>2小时</span>
                <span>4小时</span>
              </div>
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-sm text-gray mb-1">允许开始时间</label>
                <Input
                  type="time"
                  value={startTime}
                  onChange={(e) => setStartTime(e.target.value)}
                  placeholder="08:00"
                />
              </div>
              <div>
                <label className="block text-sm text-gray mb-1">允许结束时间</label>
                <Input
                  type="time"
                  value={endTime}
                  onChange={(e) => setEndTime(e.target.value)}
                  placeholder="20:00"
                />
              </div>
            </div>
            <p className="text-xs text-gray">留空表示不限制时间段。超时后儿童端将自动锁定。</p>
          </div>
        </div>

        {/* Volume */}
        <div className="bg-white rounded-xl border border-gray/20 p-5">
          <div className="flex items-center gap-3 mb-4">
            <Volume2 size={20} className="text-primary" />
            <h3 className="font-medium">全局音量限制</h3>
          </div>
          <div>
            <label className="block text-sm text-gray mb-2">
              最大音量: {maxVolume}%
            </label>
            <input
              type="range"
              min={10}
              max={100}
              step={5}
              value={maxVolume}
              onChange={(e) => setMaxVolume(Number(e.target.value))}
              className="w-full accent-primary max-w-sm"
            />
          </div>
        </div>
      </div>
    </div>
  )
}
