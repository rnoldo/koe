import en from './locales/en'
import zh from './locales/zh'
import { useStore } from '@/store'

export type Locale = 'en' | 'zh'
export type TranslationKey = keyof typeof en

const translations: Record<Locale, Record<string, string>> = { en, zh }

export function t(key: TranslationKey, params?: Record<string, string | number>): string {
  const locale = useStore.getState().locale
  let text = translations[locale]?.[key] || translations.en[key] || key
  if (params) {
    Object.entries(params).forEach(([k, v]) => {
      text = text.replace(`{${k}}`, String(v))
    })
  }
  return text
}

export function useT() {
  const locale = useStore((s) => s.locale)
  return (key: TranslationKey, params?: Record<string, string | number>): string => {
    let text = translations[locale]?.[key] || translations.en[key] || key
    if (params) {
      Object.entries(params).forEach(([k, v]) => {
        text = text.replace(`{${k}}`, String(v))
      })
    }
    return text
  }
}

export function getSourceTypeLabel(type: string): string {
  const key = `sourceType.${type}` as TranslationKey
  return t(key)
}
