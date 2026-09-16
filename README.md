# Eros-EH+

English | [简体中文](README_cn.md)

## Introduction

An unofficial [e-hentai](https://e-hentai.org) / [exhentai](https://exhentai.org) client built with Flutter.

This is a **personal fork** of [erosTeam/eros_fe](https://github.com/erosTeam/eros_fe), rebranded as **Eros-EH+** (`com.ldwdg.erosehentai`, v1.0.1).

## What's New in This Fork

- **Rebranded**: app name `Eros-EH+`, Android package `com.ldwdg.erosehentai`, version `1.0.1`
- **Removed** sentry_flutter (error reporting) and system_network_proxy (broken Linux plugin) — desktop proxy now reads `http_proxy`/`HTTPS_PROXY` env vars
- **Isar** upgraded to 3.3.0 stable (compatible with Ubuntu 22.04 / glibc 2.35)
- **Linux desktop support** added (upstream only shipped android/ios/macos/windows)
- **Bug fixes**:
  - ExHentai thumbnail redirect to ehgt.org not working (upstream issue #17) — regex rewritten for current URL format
  - Home page parser crash when not logged in
  - Download: fixed stuck-at-last-image (completion-count race), no-retry on transient network errors, silent truncation/black-image (buffer write pollution + missing completeness check), and Cronet "Too many receivers" crash
- `lib/config/config.dart` maintained locally as plaintext (upstream git-crypt encrypted file cannot compile without key)

## Features

- [x] Popular, Watch, Home, Favorites
- [x] List view / waterfall view switch
- [x] Gallery information view
- [x] Gallery image view
- [x] Automatically turn pages
- [x] eh/ex switch
- [x] Tag search
- [x] Login (account / cookie)
- [x] Search & advanced search
- [x] Save and share images
- [x] Cache optimization
- [x] Advanced settings
- [x] Post comments, vote up/down
- [x] Watched and user tags
- [x] Download

## Screenshot

### Home Page List

<img width="200" src="./screenshot/home.png" >

### Settings

<img width="200" src="./screenshot/setting.png" >

### Gallery

<img width="200" src="./screenshot/gallery1.png" > <img width="200" src="./screenshot/gallery2.png" >

### Search

<img width="200" src="./screenshot/search1.png" > <img width="200" src="./screenshot/search2.png" >

### Read

<img width="200" src="./screenshot/read1.png" > <img width="200" src="./screenshot/read2.png" >

## Build

Requirements: Flutter stable (3.44.8+), Dart 3.12+

```bash
# 1. Prepare local config
cp lib/config/config.dart.sample lib/config/config.dart
#    (edit it with your own credentials if needed; it is gitignored)

# 2. Get dependencies (China mirror optional)
flutter pub get

# 3a. Run on Linux desktop
flutter run -d linux
#     requires: clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev

# 3b. Build Android release APK (signed)
flutter build apk --release
#     output: build/app/outputs/flutter-apk/app-release.apk
```

> Note: upstream README mentions `firebase_options.dart` — it is no longer required in this fork.

## Development Workflow

Before submitting changes, run `flutter analyze` (must report 0 errors) and verify a release build with `flutter build apk --release`.

## Thanks

The code and logic of the following projects are used and referenced for development

- [E-HentaiViewer](https://github.com/kayanouriko/E-HentaiViewer)
- [EhViewer](https://github.com/seven332/EhViewer)
- [erosTeam/eros_fe](https://github.com/erosTeam/eros_fe) (upstream)

EhTagTranslation: [EhTagTranslation/Database](https://github.com/EhTagTranslation/Database)

## License

Apache-2.0 (same as upstream)
