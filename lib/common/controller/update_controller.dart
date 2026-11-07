import 'dart:math';

import 'package:eros_fe/index.dart';
import 'package:eros_fe/network/request.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher_string.dart';

const String kRepoOwnerRepo = 'ldwdg/Eros-EH-plus';

const String kGithubUrl =
    'https://api.github.com/repos/ldwdg/Eros-EH-plus/releases/latest';

class UpdateController extends GetxController {
  final _canUpdate = false.obs;
  bool get canUpdate => _canUpdate.value;

  final _isChecking = false.obs;
  bool get isChecking => _isChecking.value;
  set isChecking(bool val) => _isChecking.value = val;

  set canUpdate(bool val) => _canUpdate.value = val;

  final _isLatestVersion = true.obs;
  bool get isLatestVersion => _isLatestVersion.value;
  set isLatestVersion(bool val) => _isLatestVersion.value = val;

  final _latestVersion = ''.obs;
  String get latestVersion => _latestVersion.value;
  set latestVersion(String val) => _latestVersion.value = val;

  @override
  void onInit() {
    super.onInit();
    checkUpdate();
  }

  Future<void> checkUpdate({bool showDialog = false}) async {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;

    isChecking = true;
    try {
      final response = await getGithubApi(kGithubUrl);
      final tagName = (response['tag_name'] as String?)?.trim() ?? '';
      final body = (response['body'] as String?)?.trim() ?? '';
      final htmUrl = (response['html_url'] as String?)?.trim() ?? '';
      logger.d('tagName $tagName');
      logger.d('body\n$body');

      final regExpTagName = RegExp(r'^([vV])?(\d+\.\d+\.\d+)\+?(\d+)?');
      final match = regExpTagName.firstMatch(tagName);
      final remoteVersion = match?.group(2) ?? '';
      logger.d('remoteVersion $remoteVersion  , currentVersion $currentVersion');
      latestVersion = remoteVersion;

      // 远端版本号解析失败时无法判断更新，按「已是最新」处理，避免误触发下载。
      final bool hasValidRemoteVersion = remoteVersion.isNotEmpty;
      final int compare = hasValidRemoteVersion
          ? versionStringCompare(
              preVersion: currentVersion, latestVersion: remoteVersion)
          : 0;

      // 仅当远端【严格】比当前新时才允许更新；
      // 版本相同或当前更新时都不应弹出更新框，更不能触发下载。
      final bool hasUpdate = hasValidRemoteVersion && compare < 0;
      isLatestVersion = !hasUpdate;
      canUpdate = hasUpdate;

      if (!showDialog) {
        return;
      }

      if (!hasUpdate) {
        // 已是最新版（或无法解析远端版本）：只提示，不弹更新下载框。
        showToast(
          hasValidRemoteVersion
              ? '${L10n.of(Get.context!).latest_version} $remoteVersion'
              : '检查更新失败',
        );
        return;
      }

      _showUpdateDialog(
        remoteVersion: remoteVersion,
        body: body,
        htmlUrl: htmUrl,
      );
    } catch (e) {
      // 请求/解析失败时不能触发下载，也保持「已是最新」的判断，
      // 同时必须复位 isChecking，避免检查按钮一直转圈。
      isLatestVersion = true;
      canUpdate = false;
      logger.e('checkUpdate failed', error: e);
      if (showDialog) {
        showToast('检查更新失败');
      }
    } finally {
      isChecking = false;
    }
  }

  /// 显示当前安装版本的 Release 信息，并允许跳转到 GitHub 对应页面。
  Future<void> showReleaseInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;
    final buildNumber = packageInfo.buildNumber;
    final tag = 'v$currentVersion';

    Map? release;
    try {
      release = await getGithubApi(
        'https://api.github.com/repos/$kRepoOwnerRepo/releases/tags/$tag',
      );
    } catch (e) {
      // 该版本可能没有对应的 release（如测试构建），回退到 releases 页面。
      logger.d('fetch release $tag failed: $e');
    }

    if (Get.context == null) {
      return;
    }

    final String? nameRaw = release?['name'] as String?;
    final String title = (nameRaw != null && nameRaw.trim().isNotEmpty)
        ? nameRaw.trim()
        : 'Eros-EH+ $tag';
    final String body = (release?['body'] as String?)?.trim() ?? '';
    final String publishedAt =
        (release?['published_at'] as String?)?.trim() ?? '';
    final String? htmlRaw = release?['html_url'] as String?;
    final String htmlUrl = (htmlRaw != null && htmlRaw.trim().isNotEmpty)
        ? htmlRaw.trim()
        : 'https://github.com/$kRepoOwnerRepo/releases/tag/$tag';

    final String subText = <String>[
      tag,
      if (publishedAt.isNotEmpty) publishedAt.split('T').first,
    ].join('  ·  ');

    showCupertinoDialog<void>(
      context: Get.context!,
      builder: (dialogContext) {
        return CupertinoAlertDialog(
          title: Text(title),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${L10n.of(dialogContext).version} '
                  '$currentVersion ($buildNumber)',
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  subText,
                  style: const TextStyle(
                    fontSize: 12,
                    color: CupertinoColors.systemGrey,
                  ),
                ),
                if (body.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: SingleChildScrollView(
                      child: MarkdownBody(
                        data: body,
                        selectable: true,
                        styleSheetTheme: MarkdownStyleSheetBaseTheme.cupertino,
                        styleSheet: MarkdownStyleSheet(
                          a: const TextStyle(
                            color: CupertinoColors.activeBlue,
                            fontSize: 13,
                          ),
                          p: const TextStyle(fontSize: 13),
                          listBullet: const TextStyle(
                            fontSize: 13,
                            color: CupertinoColors.systemGrey,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: <Widget>[
            CupertinoDialogAction(
              child: Text(L10n.of(dialogContext).cancel),
              onPressed: () => Get.back(),
            ),
            CupertinoDialogAction(
              child: const Text('GitHub'),
              onPressed: () {
                Get.back();
                launchUrlString(
                  htmlUrl,
                  mode: LaunchMode.externalApplication,
                );
              },
            ),
          ],
        );
      },
    );
  }

  void _showUpdateDialog({
    required String remoteVersion,
    required String body,
    required String htmlUrl,
  }) {
    final BuildContext? context = Get.context;
    if (context == null) {
      return;
    }

    showSimpleEhDiglog(
      context: context,
      title: remoteVersion,
      // contentText: body,
      content: IntrinsicHeight(
        child: SizedBox(
          height: 300,
          child: SingleChildScrollView(
            child: MarkdownBody(
              data: body,
              selectable: true,
              styleSheetTheme: MarkdownStyleSheetBaseTheme.cupertino,
              styleSheet: MarkdownStyleSheet(
                a: const TextStyle(
                  color: CupertinoColors.activeBlue,
                  fontSize: 14,
                ),
                p: const TextStyle(
                  fontSize: 14,
                ),
                em: const TextStyle(
                  fontStyle: FontStyle.italic,
                  fontSize: 14,
                ),
                listBullet: const TextStyle(
                  fontSize: 14,
                  color: CupertinoColors.systemGrey,
                ),
                code: CupertinoTheme.of(context)
                    .textTheme
                    .textStyle
                    .copyWith(
                        backgroundColor: Colors.transparent,
                        color: CupertinoColors.systemPink,
                        fontSize: CupertinoTheme.of(context)
                                .textTheme
                                .textStyle
                                .fontSize! *
                            0.8,
                        fontFamilyFallback: EHConst.monoFontFamilyFallback),
              ),
            ),
          ),
        ),
      ),
      onOk: () {
        launchUrlString(
          htmlUrl,
          mode: LaunchMode.externalApplication,
        );
      },
    );
  }
}

int versionStringCompare({String preVersion = '', String latestVersion = ''}) {
  final sources = preVersion.split('.');
  final dests = latestVersion.split('.');
  final maxL = max(sources.length, dests.length);
  var result = 0;
  for (int i = 0; i < maxL; i++) {
    int preNum = sources.length > i ? int.tryParse(sources[i]) ?? 0 : 0;
    int lastNum = dests.length > i ? int.tryParse(dests[i]) ?? 0 : 0;
    if (preNum < lastNum) {
      result = -1;
      break;
    } else if (preNum > lastNum) {
      result = 1;
      break;
    }
  }
  return result;
}
