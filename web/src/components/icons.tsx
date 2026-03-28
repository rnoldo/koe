'use client'

import {
  Tv, Film, Music, Star, Heart, Smile, Sun, Moon, Cloud, Zap,
  Compass, Globe, BookOpen, Palette, Rocket, Gamepad2, Puzzle, Flower2,
  Settings, ChevronLeft, ChevronRight, ChevronUp, Plus, Trash2,
  GripVertical, Search, Play, Pause, X, Lock, Eye, EyeOff,
  RefreshCw, FolderOpen, HardDrive, Check, ArrowLeft, LayoutGrid,
  List, Volume2, Clock, Shield, LogOut, Edit,
  MonitorSmartphone, Server, Network, CloudCog, Database, Package, Clapperboard,
} from 'lucide-react'
import { LucideProps } from 'lucide-react'

const iconMap: Record<string, React.FC<LucideProps>> = {
  tv: Tv, film: Film, music: Music, star: Star, heart: Heart,
  smile: Smile, sun: Sun, moon: Moon, cloud: Cloud, zap: Zap,
  compass: Compass, globe: Globe, book: BookOpen, palette: Palette,
  rocket: Rocket, 'gamepad-2': Gamepad2, puzzle: Puzzle, 'flower-2': Flower2,
}

export function ChannelIcon({ name, color, size = 32 }: { name: string; color: string; size?: number }) {
  const Icon = iconMap[name] || Tv
  return <Icon size={size} color={color} />
}

// Source type icon map
import type { SourceType } from '@/types'

const sourceIconMap: Record<SourceType, React.FC<LucideProps>> = {
  local: FolderOpen,
  webdav: Globe,
  smb: MonitorSmartphone,
  aliyunDrive: CloudCog,
  baiduPan: Database,
  pan115: Package,
  emby: Clapperboard,
  jellyfin: Server,
}

export function SourceTypeIcon({ type, size = 18, className }: { type: SourceType; size?: number; className?: string }) {
  const Icon = sourceIconMap[type] || HardDrive
  return <Icon size={size} className={className} />
}

export {
  Settings, ChevronLeft, ChevronRight, ChevronUp, Plus, Trash2,
  GripVertical, Search, Play, Pause, X, Lock, Eye, EyeOff,
  RefreshCw, FolderOpen, HardDrive, Check, ArrowLeft, LayoutGrid,
  List, Volume2, Clock, Shield, LogOut, Edit, Tv, Network,
}
