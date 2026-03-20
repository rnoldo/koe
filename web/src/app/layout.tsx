import type { Metadata } from 'next'
import './globals.css'

export const metadata: Metadata = {
  title: 'KidsTV Pad',
  description: '儿童电视 — 由家长掌控的纯净观看环境',
}

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode
}>) {
  return (
    <html lang="zh-CN" className="h-full">
      <body className="h-full font-serif">{children}</body>
    </html>
  )
}
