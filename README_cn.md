# Eros-EH+

[English](README.md) | 简体中文

## 简介

基于 Flutter 的非官方 [e-hentai](https://e-hentai.org) / [exhentai](https://exhentai.org) 客户端。

这是 [erosTeam/eros_fe](https://github.com/erosTeam/eros_fe) 的**个人定制 fork**，更名为 **Eros-EH+**（包名 `com.ldwdg.erosehentai`，版本 v1.0.1）。

## 本 fork 的新变化

- **更名**：应用名 `Eros-EH+`，Android 包名 `com.ldwdg.erosehentai`，版本 `1.0.1`
- **移除** sentry_flutter（错误上报）与 system_network_proxy（Linux 插件不可用）——桌面端代理改为读取 `http_proxy`/`HTTPS_PROXY` 环境变量
- **Isar** 升级到 3.3.0 正式版（兼容 Ubuntu 22.04 / glibc 2.35）
- **新增 Linux 桌面支持**（上游只有 android/ios/macos/windows）
- **Bug 修复**：
  - 里站缩略图重定向到 ehgt.org 失效（上游 issue #17）——按当前 URL 格式重写正则
  - 未登录时首页解析崩溃
  - 下载：修复卡最后一张（完成计数竞态）、瞬时网络错误不重试、静默截断/黑图（缓冲写入引用污染 + 缺失完整性校验）、Cronet "Too many receivers" 闪退
- `lib/config/config.dart` 本地明文维护（上游 git-crypt 加密文件无密钥无法编译）

## 功能

- [x] Popular / Watch / Home / Favorites
- [x] 列表/瀑布流视图切换
- [x] 画廊详情页
- [x] 画廊图片浏览
- [x] 自动翻页
- [x] 表站/里站切换
- [x] 标签搜索
- [x] 登录（账号 / Cookie）
- [x] 搜索 & 高级搜索
- [x] 保存与分享图片
- [x] 缓存优化
- [x] 高级设置
- [x] 评论、顶/踩
- [x] 已看与用户标签
- [x] 下载

## 截图

### 首页列表

<img width="200" src="./screenshot/home.png" >

### 设置

<img width="200" src="./screenshot/setting.png" >

### 画廊

<img width="200" src="./screenshot/gallery1.png" > <img width="200" src="./screenshot/gallery2.png" >

### 搜索

<img width="200" src="./screenshot/search1.png" > <img width="200" src="./screenshot/search2.png" >

### 阅读

<img width="200" src="./screenshot/read1.png" > <img width="200" src="./screenshot/read2.png" >

## 编译

环境要求：Flutter stable（3.44.8+）、Dart 3.12+

```bash
# 1. 准备本地配置
cp lib/config/config.dart.sample lib/config/config.dart
#    （按需填入自己的凭据；该文件已被 .gitignore 排除）

# 2. 拉取依赖（国内可配镜像）
flutter pub get

# 3a. Linux 桌面运行
flutter run -d linux
#     依赖：clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev

# 3b. 构建 Android release 包（已签名）
flutter build apk --release
#     产物：build/app/outputs/flutter-apk/app-release.apk
```

> 注：上游 README 提到的 `firebase_options.dart` 在本 fork 中已不再需要。

## 开发方式

提交改动前请先运行 `flutter analyze`（必须 0 error），并用 `flutter build apk --release` 做一次 release 构建验证。

## 致谢

以下项目的代码与逻辑被参考使用：

- [E-HentaiViewer](https://github.com/kayanouriko/E-HentaiViewer)
- [EhViewer](https://github.com/seven332/EhViewer)
- [erosTeam/eros_fe](https://github.com/erosTeam/eros_fe)（上游）

EhTagTranslation：[EhTagTranslation/Database](https://github.com/EhTagTranslation/Database)

## 许可证

Apache-2.0（与上游一致）
