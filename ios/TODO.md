# KidsTV — Implement All Remote Source Types

## Phase 1: Foundation
- [x] Fix VideoPlayerView — remove fileExists guard for remote URLs, add auth header support
- [x] Create SourceScanner protocol + StreamableMedia
- [x] Create HTTPClient (URLSession wrapper)
- [x] Create KeychainHelper (secure token storage)
- [x] Create ScannerRegistry + wire into AppStore.scanSource()
- [x] Update models: SourceConfig (tokens, cookies) + Video (remoteItemId)
- [x] Add resolvePlaybackURL() to AppStore, update KidsView to use it

## Phase 2: Emby + Jellyfin
- [x] EmbyScanner — scan via REST API, stream via /Videos/{id}/stream
- [x] JellyfinScanner — reuse EmbyScanner

## Phase 3: WebDAV
- [x] WebDAVScanner — PROPFIND + Basic Auth + XML parsing

## Phase 4: Cloud Drives (OAuth)
- [x] OAuthManager — ASWebAuthenticationSession flow + token refresh
- [x] Update AddSourceView — OAuth sign-in UI for cloud drives
- [x] AliyunDriveScanner — Aliyun Open API
- [x] BaiduPanScanner — Baidu Pan API

## Phase 5: Harder Sources
- [x] Pan115Scanner — cookie auth, reverse-engineered API
- [x] SMBScanner — AMSMB2 dependency, file enumeration, download-to-temp playback

## Status: All source types implemented and building successfully ✅
