import type { Metadata } from 'next'
import './globals.css'

export const metadata: Metadata = {
  title: 'KidsTV Pad',
  description: 'KidsTV — A pure viewing environment controlled by parents',
}

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode
}>) {
  return (
    <html lang="en" className="h-full">
      <body className="h-full font-serif">{children}</body>
    </html>
  )
}
