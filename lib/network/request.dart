import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:eros_fe/common/controller/advance_search_controller.dart';
import 'package:eros_fe/common/controller/user_controller.dart';
import 'package:eros_fe/common/parser/eh_parser.dart';
import 'package:eros_fe/component/exception/error.dart';
import 'package:eros_fe/index.dart';
import 'package:eros_fe/pages/gallery/controller/archiver_controller.dart';
import 'package:eros_fe/pages/gallery/controller/torrent_controller.dart';
import 'package:eros_fe/pages/tab/fetch_list.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart' hide FormData, Response, MultipartFile;
import 'package:http_parser/http_parser.dart' as http_parser;

import 'api.dart';
import 'app_dio/pdio.dart';

Options getCacheOptions({
  bool refresh = false,
  bool forceCache = true,
}) {
  final options = Api.cacheOption
      .copyWith(
        policy: refresh ? CachePolicy.refresh : CachePolicy.request,
      )
      .toOptions();

  final forceCacheOptions = Api.cacheOption
      .copyWith(
        policy:
            refresh ? CachePolicy.refreshForceCache : CachePolicy.forceCache,
      )
      .toOptions();

  return forceCache ? forceCacheOptions : options;
}

Future<GalleryList?> getGallery({
  PageType? pageType,
  String? gid,
  String? jump,
  String? seek,
  String? search,
  int? page,
  int? cats,
  bool refresh = false,
  CancelToken? cancelToken,
  GalleryListType? galleryListType,
  String? toplist,
  String? favcat,
  ValueChanged<List<Favcat>>? favCatList,
  AdvanceSearch? advanceSearch,
  bool globalSearch = false,
}) async {
  final AdvanceSearchController searchController = Get.find();
  DioHttpClient dioHttpClient = DioHttpClient(dioConfig: globalDioConfig);

  logger.t('globalSearch $globalSearch');

  late final String _url;
  switch (galleryListType) {
    case GalleryListType.watched:
      _url = '/watched';
      break;
    case GalleryListType.toplist:
      _url = '${EHConst.EH_BASE_URL}/toplist.php';
      break;
    case GalleryListType.favorite:
      _url = '/favorites.php';
      break;
    case GalleryListType.popular:
      _url = '/popular';
      break;
    default:
      _url = '/';
  }

  final isTopList = galleryListType == GalleryListType.toplist;
  final isFav = galleryListType == GalleryListType.favorite;
  final isPopular = galleryListType == GalleryListType.popular;

  final gidOrTimeParams = <String, dynamic>{
    if (!isPopular) 'jump': jump,
    if (!isPopular) 'seek': seek,
    if (!isPopular && pageType != null && gid != null) pageType.value: gid,
  };

  final pageParams = <String, dynamic>{
    if (!isTopList && !isPopular) 'page': page ?? 0,
    if (isTopList) 'p': page ?? 0,
    if (!isTopList && !isPopular && gid != null) 'from': gid,
  };

  final Map<String, dynamic> _params = <String, dynamic>{
    if (!isTopList && !isPopular && !isFav) 'f_cats': cats,
    if (!isTopList && !isPopular && search != null) 'f_search': search,
    if (isTopList && toplist != null && toplist.isNotEmpty) 'tl': toplist,
    if (isFav && favcat != null && favcat != 'a' && favcat.isNotEmpty)
      'favcat': favcat,
  };

  if (page != null && page > -1) {
    logger.d('page $page');
    _params.addAll(pageParams);
  } else {
    _params.addAll(gidOrTimeParams);
  }

  logger.t('advanceSearch ${advanceSearch?.param}  refresh $refresh');

  /// 高级搜索处理
  if (advanceSearch != null) {
    if (advanceSearch.param.isNotEmpty && !isPopular) {
      _params['advsearch'] = 1;
      _params.addAll(advanceSearch.param);
    }
  } else if (globalSearch && searchController.enableAdvance) {
    _params['advsearch'] = 1;
    _params.addAll(searchController.advanceSearchMap);
  }

  if (search != null && isFav) {
    _params.addAll(searchController.favSearchMap);
  }

  logger.t('url:$_url $_params');

  DioHttpResponse httpResponse = await dioHttpClient.get(
    _url,
    queryParameters: _params,
    httpTransformer:
        isFav ? FavoriteListHttpTransformer() : GalleryListHttpTransformer(),
    options: getCacheOptions(refresh: refresh),
    cancelToken: cancelToken,
  );

  // 里站凭证失效：自动刷新 igneous 后重试一次（避免白屏）
  if (httpResponse.error is EhAuthFailedException &&
      Api.getBaseUrl().contains('exhentai')) {
    logger.d('ExHentai auth failed, refresh igneous and retry once');
    final bool healed = await refreshExIgneous();
    if (healed) {
      httpResponse = await dioHttpClient.get(
        _url,
        queryParameters: _params,
        httpTransformer: isFav
            ? FavoriteListHttpTransformer()
            : GalleryListHttpTransformer(),
        options: getCacheOptions(refresh: true),
        cancelToken: cancelToken,
      );
    }
  }

  if (httpResponse.error is ListDisplayModeException) {
    logger.d('ListDisplayModeException');
    logger.d(' inline_set dml');
    _params['inline_set'] = 'dm_l';

    httpResponse = await dioHttpClient.get(
      _url,
      queryParameters: _params,
      httpTransformer:
          isFav ? FavoriteListHttpTransformer() : GalleryListHttpTransformer(),
      options: getCacheOptions(refresh: true),
      cancelToken: cancelToken,
    );
  }

  if (httpResponse.error is FavOrderException) {
    final _order = (httpResponse.error as FavOrderException).order;
    _params['inline_set'] = _order;
    logger.e('FavOrderException, need change order inline_set=$_order');
    _params.removeWhere((key, value) => key == 'page');

    logger.d('ff $_url ${_params}');
    httpResponse = await dioHttpClient.get(
      _url,
      queryParameters: _params,
      httpTransformer:
          isFav ? FavoriteListHttpTransformer() : GalleryListHttpTransformer(),
      options: getCacheOptions(refresh: false)
        ..followRedirects = true
        ..validateStatus = (status) => (status ?? 0) < 500,
      cancelToken: cancelToken,
    );
  }

  if (httpResponse.ok && httpResponse.data is GalleryList) {
    return httpResponse.data as GalleryList;
  } else {
    logger.d('${httpResponse.error.runtimeType}');
    if (httpResponse.error is CancelException) {
      return const GalleryList();
    }
    throw httpResponse.error ?? EhError(error: 'getGallery error');
  }
}

Future<void> cleanCookie(String name) async {
  final PersistCookieJar cookieJar = await Api.cookieJar;
  final List<Cookie> cookies =
      await cookieJar.loadForRequest(Uri.parse(Api.getBaseUrl()));
  cookies.removeWhere((element) => element.name == name);
  logger.d('after remove: \n${cookies.join('\n')}');
  await cookieJar.delete(Uri.parse(Api.getBaseUrl()));
  await cookieJar.saveFromResponse(Uri.parse(Api.getBaseUrl()), cookies);
  logger.d('showCookie: \n${cookies.join('\n')}');
}

Future<void> setCookie(String name, String value) async {
  final PersistCookieJar cookieJar = await Api.cookieJar;
  final List<Cookie> cookies =
      await cookieJar.loadForRequest(Uri.parse(Api.getBaseUrl()));
  final _cookie = cookies.firstWhereOrNull((element) => element.name == name);
  if (_cookie != null) {
    _cookie.value = value;
  } else {
    cookies.add(Cookie(name, value));
  }
  // logger.d('after remove: \n${cookies.join('\n')}');
  // await cookieJar.delete(Uri.parse(Api.getBaseUrl()));
  // await cookieJar.saveFromResponse(Uri.parse(Api.getBaseUrl()), cookies);
}

Future<String?> getCookieValue(String name) async {
  final PersistCookieJar cookieJar = await Api.cookieJar;
  final List<Cookie> cookies =
      await cookieJar.loadForRequest(Uri.parse(Api.getBaseUrl()));
  final _cookie = cookies.firstWhereOrNull((element) => element.name == name);
  return _cookie?.value;
}

Future<GalleryProvider?> getGalleryDetail({
  required String url,
  bool refresh = false,
  CancelToken? cancelToken,
}) async {
  DioHttpClient dioHttpClient = DioHttpClient(dioConfig: globalDioConfig);
  DioHttpResponse httpResponse = await dioHttpClient.get(
    url,
    httpTransformer: GalleryHttpTransformer(),
    options: getCacheOptions(refresh: refresh),
    cancelToken: cancelToken,
  );
  logger.t('httpResponse.ok ${httpResponse.ok}');
  if (httpResponse.ok && httpResponse.data is GalleryProvider) {
    return httpResponse.data as GalleryProvider;
  } else {
    // logger.e('${httpResponse.error}');
    if (httpResponse.error?.code == 404) {
      final errMsg = parseErrGallery(httpResponse.error?.data as String? ?? '');
      logger.d('errMsg: $errMsg');
      throw BadRequestException(
          code: httpResponse.error?.code, message: errMsg);
    }
    throw httpResponse.error ?? UnknownException();
  }
}

Future<GalleryImage?> fetchImageInfoByApi(
  String href, {
  String? showKey,
  bool refresh = false,
  String? sourceId,
  CancelToken? cancelToken,
}) async {
  final isMpv = regGalleryMpvPageUrl.hasMatch(href);

  // 如果 showKey 为空 或者换源重载（sourceId不为空） ，直接使用常规请求，解析html
  if (isMpv ||
      showKey == null ||
      showKey.isEmpty ||
      (sourceId?.isNotEmpty ?? false)) {
    logger.d(
        '使用常规请求，解析html: href $href,showKey $showKey, sourceId $sourceId, isMpv $isMpv, refresh $refresh');
    final resultImage = await fetchImageInfoByHtml(
      href,
      refresh: refresh,
      sourceId: sourceId,
      cancelToken: cancelToken,
    );
    logger.t('fetchImageInfoByApi html: resultImage ${resultImage?.toJson()}');
    logger.d('res sourceId ${resultImage?.sourceId}');
    return resultImage;
  }

  logger.t(
      'fetchImageInfoByApi: href $href, refresh $refresh, sourceId $sourceId, showKey $showKey');

  final RegExp regExp =
      RegExp(r'https://e[-x]hentai.org/s/([0-9a-z]+)/(\d+)-(\d+)');
  final RegExpMatch? regResult = regExp.firstMatch(href);
  final int gid = int.parse(regResult?.group(2) ?? '0');
  final String imgkey = regResult?.group(1) ?? '';
  final int page = int.parse(regResult?.group(3) ?? '0');

  final Map<String, Object> reqMap = {
    'method': 'showpage',
    'gid': gid,
    'page': page,
    'imgkey': imgkey,
    'showkey': showKey,
  };

  logger.t('fetchImageInfoByApi: reqMap $reqMap');

  final String reqJsonStr = jsonEncode(reqMap);

  // 请求api
  final response = await postEhApi(reqJsonStr,
      forceRefresh: refresh, bypassRateLimit: true);

  logger.t('fetchImageInfoByApi: response $response');

  final jsonMap = jsonDecode(response) as Map<String, dynamic>;

  if (jsonMap['error'] != null && jsonMap['error'] is String) {
    if (jsonMap['error'] == 'Key mismatch') {
      throw EhError(type: EhErrorType.keyMismatch, error: jsonMap['error']);
    }
    throw EhError(type: EhErrorType.parse, error: jsonMap['error']);
  }

  final image = paraShowPageJson(jsonMap);
  logger.t('fetchImageInfoByApi: image ${image.toJson()}');
  logger.d('res sourceId : ${image.sourceId}');
  if (RegExp(EHConst.REG_509_URL).hasMatch(image.imageUrl ?? '')) {
    throw EhError(type: EhErrorType.image509);
  }

  return image;
}

Future<GalleryImage?> fetchImageInfoByHtml(
  String href, {
  bool refresh = false,
  String? sourceId,
  CancelToken? cancelToken,
  String? debugLabel,
}) async {
  final Map<String, dynamic> params = {
    if (sourceId != null && sourceId.trim().isNotEmpty) 'nl': sourceId,
  };

  logger.t('fetchImageInfo: href $href, refresh $refresh, sourceId $sourceId, '
      'debugLabel $debugLabel');

  String mpvSer = '1';
  final isMpv = regGalleryMpvPageUrl.hasMatch(href);
  if (isMpv) {
    mpvSer = regGalleryMpvPageUrl.firstMatch(href)?.group(3) ?? '1';
  }

  logger.t('url $href  isMpv:$isMpv');

  DioHttpClient dioHttpClient = DioHttpClient(dioConfig: globalDioConfig);
  DioHttpResponse httpResponse = await dioHttpClient.get(
    href,
    queryParameters: params,
    httpTransformer: isMpv
        ? GalleryMpvImageHttpTransformer(mpvSer, sourceId: sourceId)
        : GalleryImageHttpTransformer(),
    options: getCacheOptions(refresh: refresh)
      ..extra = {'bypassRateLimit': true},
    cancelToken: cancelToken,
  );

  if (httpResponse.ok && httpResponse.data is GalleryImage) {
    logger.t('url $href, fetchImageInfo ok');
    return (httpResponse.data as GalleryImage).copyWith(href: href.oN);
  } else {
    // logger.d('error.runtimeType: ${httpResponse.error.runtimeType}');
    throw httpResponse.error ?? EhError(error: 'fetchImageInfo error');
  }
}

Future<List<GalleryImage>> getGalleryImageList(
  String inUrl, {
  int? page,
  bool refresh = false,
  bool bypassRateLimit = false,
  CancelToken? cancelToken,
}) async {
  logger.t('getGalleryImageList: $inUrl, page $page, refresh $refresh');
  final Map<String, dynamic> _params = {
    if (page != null) 'p': page,
  };
  DioHttpClient dioHttpClient = DioHttpClient(dioConfig: globalDioConfig);

  DioHttpResponse httpResponse = await dioHttpClient.get(
    inUrl,
    queryParameters: _params,
    httpTransformer: GalleryImageListHttpTransformer(),
    options: getCacheOptions(refresh: refresh)
      ..extra = {'bypassRateLimit': bypassRateLimit},
    cancelToken: cancelToken,
  );

  if (httpResponse.ok && httpResponse.data is List<GalleryImage>) {
    return httpResponse.data as List<GalleryImage>;
  } else {
    return [];
  }
}

// Future<ArchiverProvider> getArchiver(
//   String url, {
//   bool refresh = true,
// }) async {
//   DioHttpClient dioHttpClient = DioHttpClient(dioConfig: dioConfig);
//
//   DioHttpResponse httpResponse = await dioHttpClient.get(
//     url,
//     httpTransformer: GalleryArchiverHttpTransformer(),
//     options: getCacheOptions(forceRefresh: refresh),
//   );
//
//   if (httpResponse.ok && httpResponse.data is ArchiverProvider) {
//     return httpResponse.data as ArchiverProvider;
//   } else {
//     return ArchiverProvider();
//   }
// }

Future<String> postArchiverRemoteDownload(
  String url,
  String resolution,
) async {
  DioHttpClient dioHttpClient = DioHttpClient(dioConfig: globalDioConfig);

  final formData = FormData.fromMap({
    'hathdl_xres': resolution.trim(),
  });

  DioHttpResponse httpResponse = await dioHttpClient.post(
    url,
    data: formData,
    httpTransformer: GalleryArchiverRemoteDownloadResponseTransformer(),
    options: getCacheOptions(refresh: true),
  );

  if (httpResponse.ok && httpResponse.data is String) {
    return httpResponse.data as String;
  } else {
    return '';
  }
}

Future<String> postArchiverLocalDownload(
  String url, {
  String? dltype,
  String? dlcheck,
}) async {
  final formData = FormData.fromMap({
    if (dltype != null) 'dltype': dltype.trim(),
    if (dlcheck != null) 'dlcheck': dlcheck.trim(),
  });
  DioHttpClient dioHttpClient = DioHttpClient(dioConfig: globalDioConfig);

  DioHttpResponse httpResponse = await dioHttpClient.post(
    url,
    data: formData,
    httpTransformer: GalleryArchiverLocalDownloadResponseTransformer(),
    options: getCacheOptions(refresh: true),
  );

  if (httpResponse.ok && httpResponse.data is String) {
    return httpResponse.data as String;
  } else {
    return '';
  }
}

Future<EhSettings?> getEhSettings(
    {bool refresh = false, String? selectProfile}) async {
  logger.t('getEhSettings ${ehDioConfig.baseUrl}');
  DioHttpClient dioHttpClient = DioHttpClient(dioConfig: globalDioConfig);
  const String url = '/uconfig.php';

  late DioHttpResponse httpResponse;
  for (int i = 0; i < 3; i++) {
    logger.t('getUconfig sp:$selectProfile idx:$i');
    httpResponse = await dioHttpClient.get(
      url,
      httpTransformer: UconfigHttpTransformer(),
      options: getCacheOptions(refresh: refresh || i > 0),
    );

    if (selectProfile == null) {
      break;
    }

    if (httpResponse.ok && httpResponse.data is EhSettings) {
      if (httpResponse.data.profileSelected == selectProfile) {
        break;
      }
    }
  }

  if (httpResponse.ok && httpResponse.data is EhSettings) {
    return httpResponse.data as EhSettings;
  }
  return null;
}

Future<EhMytags?> getMyTags(
    {bool refresh = false, String? selectTagset}) async {
  DioHttpClient dioHttpClient = DioHttpClient(dioConfig: globalDioConfig);
  final String url = '${Api.getBaseUrl()}/mytags';

  final Map<String, dynamic> _params = {
    if (selectTagset != null) 'tagset': selectTagset,
  };

  late DioHttpResponse httpResponse;
  for (int i = 0; i < 3; i++) {
    httpResponse = await dioHttpClient.get(
      url,
      queryParameters: _params,
      httpTransformer: MyTagsHttpTransformer(),
      options: getCacheOptions(refresh: refresh || i > 0),
    );

    if (selectTagset == null) {
      break;
    }

    if (httpResponse.ok && httpResponse.data is EhMytags) {
      break;
    }
  }

  if (httpResponse.ok && httpResponse.data is EhMytags) {
    return httpResponse.data as EhMytags;
  }
  return null;
}

Future<bool> actionDeleteUserTag({
  List<String> usertags = const [],
}) async {
  final dataMap = {
    'usertag_action': 'mass',
    'modify_usertags[]': usertags,
  };

  return await actionMytags(dataMap: dataMap);
}

Future<bool> actionRenameTagSet({
  required String tagsetname,
  String? tagset,
}) async {
  final dataMap = {
    'tagset_action': 'rename',
    'tagset_name': tagsetname,
  };

  return await actionMytags(
    dataMap: dataMap,
    queryParameters: {
      'tagset': tagset ?? '',
    },
  );
}

Future<bool> actionCreatTagSet({
  required String tagsetname,
}) async {
  final dataMap = {
    'tagset_action': 'create',
    'tagset_name': tagsetname,
  };

  return await actionMytags(dataMap: dataMap);
}

Future<bool> actionDeleteTagSet({
  String? tagset,
}) async {
  final dataMap = {
    'tagset_action': 'delete',
  };

  return await actionMytags(
    dataMap: dataMap,
    queryParameters: {
      'tagset': tagset ?? '',
    },
  );
}

Future<bool> actionNewUserTag({
  required String tagName,
  String? tagColor,
  String? tagWeight,
  bool? tagWatch,
  bool? tagHide,
  String? tagset,
}) async {
  final dataMap = {
    'usertag_action': 'add',
    'tagname_new': tagName,
    'tagcolor_new': tagColor ?? '',
    'tagweight_new': tagWeight ?? '',
    'tagwatch_new': tagWatch ?? false ? 'on' : '',
    'taghide_new': tagHide ?? false ? 'on' : '',
    'usertag_target': '0'
  };

  return await actionMytags(
    dataMap: dataMap,
    queryParameters: {
      'tagset': tagset ?? '',
    },
  );
}

Future<bool> actionMytags({
  required Map<String, Object> dataMap,
  Map<String, dynamic>? queryParameters,
}) async {
  const url = '/mytags';

  final formData = FormData.fromMap(dataMap);

  DioHttpClient dioHttpClient = DioHttpClient(dioConfig: globalDioConfig);

  DioHttpResponse httpResponse = await dioHttpClient.post(
    url,
    queryParameters: queryParameters,
    data: formData,
    httpTransformer: TagActionTransformer(),
    options: getCacheOptions(refresh: true)
      ..followRedirects = false
      ..validateStatus = (status) => (status ?? 0) < 500,
  );

  if (httpResponse.ok && httpResponse.data is bool) {
    return httpResponse.data as bool;
  } else {
    return false;
  }
}

Future<EhSettings?> postEhProfile({
  String? profileSet,
  String? action,
  String? name,
  Map<String, dynamic>? paramMap,
  bool refresh = true,
}) async {
  final dataMap = {
    if (action != null) 'profile_action': action,
    if (name != null) 'profile_name': name,
    if (profileSet != null) 'profile_set': profileSet.trim(),
  };

  final formData = FormData.fromMap(paramMap ?? dataMap);
  DioHttpClient dioHttpClient = DioHttpClient(dioConfig: globalDioConfig);
  const String url = '/uconfig.php';

  DioHttpResponse httpResponse = await dioHttpClient.post(
    url,
    data: formData,
    // data: _dataString,
    httpTransformer: UconfigHttpTransformer(),
    options: getCacheOptions(refresh: refresh),
  );

  if (httpResponse.ok && httpResponse.data is EhSettings) {
    return httpResponse.data as EhSettings;
  }
  return null;
}

Future<EhSettings?> changeEhProfile(String profileSet,
    {bool refresh = true}) async {
  // await cleanCookie('sp');
  return await postEhProfile(
    profileSet: profileSet,
    action: '',
    refresh: refresh,
  );
}

Future<EhSettings?> deleteEhProfile(String profileSet,
    {bool refresh = true}) async {
  // await cleanCookie('sp');
  return await postEhProfile(
    profileSet: profileSet,
    action: 'delete',
    refresh: refresh,
  );
}

Future<EhSettings?> createEhProfile(String name, {bool refresh = true}) async {
  // await cleanCookie('sp');
  return await postEhProfile(
    action: 'create',
    name: name,
    refresh: refresh,
  );
}

Future<EhSettings?> renameEhProfile(String profileSet, String name,
    {bool refresh = true}) async {
  return await postEhProfile(
    action: 'rename',
    profileSet: profileSet,
    name: name,
    refresh: refresh,
  );
}

Future<EhSettings?> setDefauleEhProfile(String profileSet,
    {bool refresh = true}) async {
  return await postEhProfile(
    profileSet: profileSet,
    action: 'default',
    refresh: refresh,
  );
}

Future<EhSettings?> applyEhProfile(Map<String, dynamic> paramMap) async {
  return await postEhProfile(
    paramMap: paramMap,
  );
}

Future<T?> getEhApi<T>({
  required String data,
  bool refresh = false,
  HttpTransformer? httpTransformer,
}) async {
  const String url = '/api.php';
  DioHttpClient dioHttpClient = DioHttpClient(dioConfig: globalDioConfig);

  DioHttpResponse httpResponse = await dioHttpClient.post(
    url,
    data: data,
    httpTransformer: httpTransformer,
    options: getCacheOptions(refresh: refresh),
  );

  if (httpResponse.ok && httpResponse.data is T) {
    return httpResponse.data as T;
  }
  return null;
}

Future<GalleryImage?> mpvLoadImageDispatch({
  required int gid,
  required String mpvkey,
  required int page,
  required String imgkey,
  String? sourceId,
}) async {
  final Map reqMap = {
    'imgkey': imgkey,
    'method': 'imagedispatch',
    'gid': gid,
    'page': page,
    'mpvkey': mpvkey,
    if (sourceId != null) 'nl': sourceId,
  };
  final String reqJsonStr = jsonEncode(reqMap);

  return await getEhApi<GalleryImage>(
    data: reqJsonStr,
    httpTransformer: ImageDispatchTransformer(),
  );
}

Future<void> ehDownload({
  required String url,
  String? savePath,
  SavePathBuild? savePathBuilder,
  CancelToken? cancelToken,
  bool? errToast,
  bool deleteOnError = true,
  bool validateImage = false,
  VoidCallback? onDownloadComplete,
  ProgressCallback? progressCallback,
}) async {
  assert(savePath != null || savePathBuilder != null);

  late final String downloadUrl;
  DioHttpClient dioHttpClient = DioHttpClient(dioConfig: globalDioConfig);
  if (!url.startsWith(RegExp(r'https?://'))) {
    downloadUrl = '${Api.getBaseUrl()}/$url';
  } else {
    downloadUrl = url;
  }
  logger.d('download start: $downloadUrl');

  late final DioSavePath dioSavePath;
  if (savePath != null) {
    dioSavePath = savePath.toDioSavePath;
  } else if (savePathBuilder != null) {
    dioSavePath = DioSavePath(pathBuilder: savePathBuilder);
  } else {
    throw ArgumentError('savePath and savePathBuild is null');
  }

  // 1. 绕开 dio.download 的流式包装，手动读取大 buffer
  final Options options = getCacheOptions(refresh: false, forceCache: false)
      .copyWith(responseType: ResponseType.stream);

  File? tempFile;
  try {
    final Response<ResponseBody> response = await dioHttpClient.dio.get<ResponseBody>(
      downloadUrl,
      options: options,
      cancelToken: cancelToken,
    );

    if (response.statusCode == null || response.statusCode! >= 400) {
      throw BadResponseException(response.data?.toString());
    }

    final ResponseBody body = response.data!;

    // 根据响应头确定最终保存路径
    final String filePath = dioSavePath.path(response.headers);
    tempFile = File(filePath);
    if (!tempFile.parent.existsSync()) {
      tempFile.parent.createSync(recursive: true);
    }

    final IOSink sink = tempFile.openWrite();
    final Uint8List buffer = Uint8List(256 * 1024);
    int bufferLen = 0;
    int total = 0;
    final int? contentLength = body.contentLength;

    try {
      await for (final Uint8List chunk in body.stream) {
        if (total == 0) {
          logger.d('download first chunk received: $downloadUrl');
        }

        // 累积到 256KB 缓冲区后写入，减少文件系统调用
        // 注意：sink.add 传入的是引用/视图而非拷贝，必须用 fromList 复制，
        // 否则下一个 chunk 用 setRange 覆盖 buffer 时会把已排队的数据污染
        if (chunk.length >= buffer.length) {
          if (bufferLen > 0) {
            sink.add(Uint8List.fromList(buffer.sublist(0, bufferLen)));
            bufferLen = 0;
          }
          sink.add(chunk);
        } else {
          if (bufferLen + chunk.length > buffer.length) {
            sink.add(Uint8List.fromList(buffer.sublist(0, bufferLen)));
            bufferLen = 0;
          }
          buffer.setRange(bufferLen, bufferLen + chunk.length, chunk);
          bufferLen += chunk.length;
          if (bufferLen == buffer.length) {
            sink.add(Uint8List.fromList(buffer));
            bufferLen = 0;
          }
        }

        total += chunk.length;
        progressCallback?.call(total, contentLength ?? -1);

        if (cancelToken?.isCancelled ?? false) {
          throw CancelException('download canceled');
        }
      }

      if (bufferLen > 0) {
        sink.add(Uint8List.fromList(buffer.sublist(0, bufferLen)));
      }
    } finally {
      await sink.flush();
      await sink.close();
    }

    // 完整性校验：期望字节数已知时，实际收到的不足 → 截断，抛错触发重试
    if (contentLength != null && total < contentLength) {
      throw DioException(
        requestOptions: RequestOptions(path: downloadUrl),
        type: DioExceptionType.unknown,
        error: 'Incomplete download: received $total/$contentLength bytes',
      );
    }

    // 图片校验：魔数 + 解码（与渲染器同款解码器），坏图抛错触发换源重下
    if (validateImage) {
      await _validateImageFile(tempFile!);
    }

    logger.d('download completed: $downloadUrl, total: $total');
    onDownloadComplete?.call();
  } catch (e) {
    logger.e('download error: $downloadUrl, error: $e');
    if (deleteOnError && tempFile != null && tempFile.existsSync()) {
      try {
        await tempFile.delete();
      } catch (_) {}
    }
    rethrow;
  }
}

/// 校验下载完成的图片文件是否完整可用（魔数 + 解码）
Future<void> _validateImageFile(File file) async {
  final Uint8List bytes = await file.readAsBytes();
  if (!_isValidImageMagic(bytes)) {
    throw const FormatException('Downloaded file is not a valid image');
  }
  // 用与渲染器同款解码器解一遍，截断/损坏会在这里抛错
  final ui.Codec codec = await ui.instantiateImageCodec(bytes);
  try {
    await codec.getNextFrame();
  } finally {
    codec.dispose();
  }
}

/// 检查常见图片格式的魔数（WebP/JPEG/PNG/GIF）
bool _isValidImageMagic(Uint8List bytes) {
  if (bytes.length < 12) return false;
  // WebP: "RIFF"...."WEBP"
  if (bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return true;
  }
  // JPEG: FF D8
  if (bytes[0] == 0xFF && bytes[1] == 0xD8) return true;
  // PNG: 89 50 4E 47
  if (bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return true;
  }
  // GIF: GIF87a / GIF89a
  if (bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x38) {
    return true;
  }
  return false;
}

Future<User?> userLogin(String username, String passwd) async {
  const String url = 'https://forums.e-hentai.org/index.php';

  DioHttpClient dioHttpClient = DioHttpClient(dioConfig: globalDioConfig);

  final FormData formData = FormData.fromMap({
    'UserName': username,
    'PassWord': passwd,
    'submit': 'Log me in',
    'temporary_https': 'off',
    'CookieDate': '365',
  });

  DioHttpResponse httpResponse = await dioHttpClient.post(
    url,
    queryParameters: {'act': 'Login', 'CODE': '01'},
    data: formData,
    httpTransformer: UserLoginTransformer(),
    options: getCacheOptions(refresh: true)
      ..headers?['referer'] =
          'https://forums.e-hentai.org/index.php?act=Login&CODE=00',
  );

  if (httpResponse.ok && httpResponse.data is User) {
    return httpResponse.data as User;
  } else {
    throw httpResponse.error ?? HttpException('login error');
  }
}

Future<User?> getUserInfo(String userId, {bool forceRefresh = true}) async {
  const String url = 'https://forums.e-hentai.org/index.php';

  DioHttpClient dioHttpClient = DioHttpClient(dioConfig: globalDioConfig);

  DioHttpResponse httpResponse = await dioHttpClient.get(
    url,
    queryParameters: {'showuser': userId},
    httpTransformer: UserInfoPageTransformer(),
    options: getCacheOptions(refresh: forceRefresh)
      ..headers?['referer'] = 'https://forums.e-hentai.org/index.php',
  );

  if (httpResponse.ok && httpResponse.data is User) {
    return httpResponse.data as User;
  } else {
    throw httpResponse.error ?? HttpException('get user info error');
  }
}

Future<bool?> postComment({
  required String gid,
  required String token,
  required String comment,
  String? commentId,
  bool isEdit = false,
  GalleryProvider? inGalleryItem,
}) async {
  if (utf8.encode(comment).length < 10) {
    showToast('Your comment is too short.');
    throw EhError(type: EhErrorType.def, error: 'Your comment is too short.');
  }

  final String url = '/g/$gid/$token';
  DioHttpClient dioHttpClient = DioHttpClient(dioConfig: globalDioConfig);

  final data = FormData.fromMap({
    isEdit ? 'commenttext_edit' : 'commenttext_new': comment,
    if (isEdit && commentId != null) 'edit_comment': int.parse(commentId),
  });

  DioHttpResponse httpResponse = await dioHttpClient.post(
    url,
    data: data,
    httpTransformer: HttpTransformerBuilder(
      (response) {
        logger.d('statusCode ${response.statusCode}');
        return DioHttpResponse<bool>.success(response.statusCode == 200 ||
            response.statusCode == 302 ||
            response.statusCode == 303);
      },
    ),
    options: getCacheOptions(refresh: true)
      ..followRedirects = true
      ..validateStatus = (status) => (status ?? 0) < 500,
  );

  if (httpResponse.ok && httpResponse.data is bool) {
    return httpResponse.data as bool;
  } else {
    throw httpResponse.error ?? HttpException('error');
  }
}

Future<void> galleryAddFavorite(
  String gid,
  String token, {
  String favcat = 'favdel',
  String favnote = '',
}) async {
  const String url = '/gallerypopups.php';
  DioHttpClient dioHttpClient = DioHttpClient(dioConfig: globalDioConfig);

  final Map<String, dynamic> _params = {
    'gid': gid,
    't': token,
    'act': 'addfav',
  };

  final FormData formData = FormData.fromMap({
    'favcat': favcat,
    'favnote': favnote,
    // e-hentai 表单按钮字段名是 "apply"（对齐现代版 FooIbar EhViewer 的 modifyFavorites）
    'apply': 'Apply Changes',
    'update': '1',
  });

  DioHttpResponse httpResponse = await dioHttpClient.post(
    url,
    queryParameters: _params,
    data: formData,
    // e-hentai 表单 POST 有 CSRF 校验，缺 Referer 会返回 400
    options: getCacheOptions(refresh: true)
      ..headers?['referer'] = globalDioConfig.baseUrl,
  );

  // 检查响应，失败抛错（否则本地已移除但服务端未生效）
  if (!httpResponse.ok) {
    throw httpResponse.error ?? HttpException('add fav error');
  }
}

Future<FavAdd> galleryGetFavorite(
  String gid,
  String token,
) async {
  const String url = '/gallerypopups.php';
  DioHttpClient dioHttpClient = DioHttpClient(dioConfig: globalDioConfig);

  final Map<String, dynamic> _params = {
    'gid': gid,
    't': token,
    'act': 'addfav',
  };

  DioHttpResponse httpResponse = await dioHttpClient.get(
    url,
    queryParameters: _params,
    options: getCacheOptions(refresh: true),
    httpTransformer: HttpTransformerBuilder(
      (response) async {
        final favAdd = await compute(parserAddFavPage, response.data as String);
        return DioHttpResponse<FavAdd>.success(favAdd);
      },
    ),
  );

  if (httpResponse.ok && httpResponse.data is FavAdd) {
    return httpResponse.data as FavAdd;
  } else {
    throw httpResponse.error ?? HttpException('get fav add error');
  }
}

Future<Map> getGithubApi(String url) async {
  DioHttpClient dioHttpClient = DioHttpClient(dioConfig: globalDioConfig);
  DioHttpResponse httpResponse =
      await dioHttpClient.get(url, options: getCacheOptions(refresh: true));
  if (httpResponse.ok && httpResponse.data is Map) {
    return httpResponse.data as Map;
  } else {
    throw httpResponse.error ?? HttpException('getTranslateTagDBInfo error');
  }
}

/// 里站凭证自愈：先删除过期的 igneous，再重新获取（GET uconfig.php 会下发新值）。
/// 返回是否成功拿到新的 igneous。
Future<bool> refreshExIgneous() async {
  try {
    final UserController userController = Get.find();
    await userController.removeIgneous();
    await getExIgneous();
    final String? igneous = userController.user.value.igneous;
    final bool ok = igneous != null && igneous.isNotEmpty;
    logger.d('refreshExIgneous ok=$ok');
    return ok;
  } catch (e) {
    logger.e('refreshExIgneous failed: $e');
    return false;
  }
}

/// 获取里站cookie
Future<void> getExIgneous() async {
  const String url = '${EHConst.EX_BASE_URL}/uconfig.php';
  DioHttpClient dioHttpClient = DioHttpClient(dioConfig: globalDioConfig);
  DioHttpResponse httpResponse = await dioHttpClient.get(
    url,
    options: getCacheOptions(refresh: true),
  );
  if (!httpResponse.ok) {
    throw httpResponse.error ?? HttpException('getExIgneous error');
  }
}

Future<String> getTorrentToken(
  String gid,
  String gtoken, {
  bool refresh = false,
}) async {
  DioHttpClient dioHttpClient = DioHttpClient(dioConfig: globalDioConfig);
  const url = '/gallerytorrents.php';
  final Map<String, dynamic> _params = {
    'gid': gid,
    't': gtoken,
  };

  DioHttpResponse httpResponse = await dioHttpClient.get(
    url,
    queryParameters: _params,
    options: getCacheOptions(refresh: refresh),
    httpTransformer: HttpTransformerBuilder(
      (response) {
        final RegExp rTorrentTk =
            RegExp(r'http://ehtracker.org/(\d{7})/announce');
        final String torrentToken =
            rTorrentTk.firstMatch(response.data as String)?.group(1) ?? '';
        return DioHttpResponse<String>.success(torrentToken);
      },
    ),
  );

  if (httpResponse.ok && httpResponse.data is String) {
    return httpResponse.data as String;
  } else {
    throw httpResponse.error ?? HttpException('get Torrent Token error');
  }
}

Future<TorrentProvider> getTorrent(
  String url, {
  bool refresh = true,
}) async {
  DioHttpClient dioHttpClient = DioHttpClient(dioConfig: globalDioConfig);
  DioHttpResponse httpResponse = await dioHttpClient.get(
    url,
    options: getCacheOptions(refresh: refresh),
    httpTransformer: HttpTransformerBuilder(
      (response) async {
        final torrentProvider =
            await compute(parseTorrent, response.data as String);
        return DioHttpResponse<TorrentProvider>.success(torrentProvider);
      },
    ),
  );
  if (httpResponse.ok && httpResponse.data is TorrentProvider) {
    return httpResponse.data as TorrentProvider;
  } else {
    throw httpResponse.error ?? HttpException('get Torrent error');
  }
}

Future<ArchiverProvider> getArchiver(
  String url, {
  bool refresh = true,
}) async {
  DioHttpClient dioHttpClient = DioHttpClient(dioConfig: globalDioConfig);
  DioHttpResponse httpResponse = await dioHttpClient.get(
    url,
    options: getCacheOptions(refresh: refresh),
    httpTransformer: HttpTransformerBuilder(
      (response) async {
        final archiverProvider =
            await compute(parseArchiver, response.data as String);
        return DioHttpResponse<ArchiverProvider>.success(archiverProvider);
      },
    ),
  );
  if (httpResponse.ok && httpResponse.data is ArchiverProvider) {
    return httpResponse.data as ArchiverProvider;
  } else {
    throw httpResponse.error ?? HttpException('get Archiver error');
  }
}

Future<String> postEhApi(
  String data, {
  bool forceRefresh = true,
  bool bypassRateLimit = false,
}) async {
  const String url = '/api.php';
  DioHttpClient dioHttpClient = DioHttpClient(
      dioConfig: globalDioConfig.copyWith(
    contentType: Headers.jsonContentType,
  ));
  DioHttpResponse httpResponse = await dioHttpClient.post(
    url,
    data: data,
    options: getCacheOptions(refresh: forceRefresh)
      ..extra = {'bypassRateLimit': bypassRateLimit},
  );
  if (httpResponse.ok && httpResponse.data is String) {
    return httpResponse.data as String;
  } else {
    throw httpResponse.error ?? HttpException('postEhApi error');
  }
}

Future<GalleryList?> searchImage(
  String imageFilepath, {
  bool? similar,
  bool? covers,
  bool? exp,
  CancelToken? cancelToken,
}) async {
  final String url = 'https://upld.${Api.getBaseHost()}/image_lookup.php';
  DioHttpClient dioHttpClient = DioHttpClient(dioConfig: globalDioConfig);

  final FormData formData = FormData.fromMap({
    'sfile': await MultipartFile.fromFile(imageFilepath,
        contentType: http_parser.MediaType('image', 'jpeg'), filename: 'a.jpg'),
    if (similar ?? true) 'fs_similar': MultipartFile.fromString('on'), // 相似搜索
    if (covers ?? false) 'fs_covers': MultipartFile.fromString('on'), // 仅封面
    if (exp ?? false) 'fs_exp': MultipartFile.fromString('on'), // 搜索被删除
    'f_sfile': MultipartFile.fromString('File Search'),
  });

  logger.d('searchImage url: $url');

  DioHttpResponse httpResponse = await dioHttpClient.post(
    url,
    data: formData,
    cancelToken: cancelToken,
    httpTransformer: HttpTransformerBuilder(
      (response) {
        logger.d('statusCode ${response.statusCode}');
        logger.d('location ${response.headers['location']}');
        return DioHttpResponse<String>.success(
            response.headers['location']?.first ?? '');
      },
    ),
    options: getCacheOptions(
      refresh: true,
    )
      ..followRedirects = false
      ..validateStatus = (status) => (status ?? 0) < 500,
  );

  late String location;
  if (httpResponse.ok && httpResponse.data is String) {
    location = httpResponse.data as String;
  } else {
    throw httpResponse.error ?? HttpException('searchImage error');
  }

  httpResponse = await dioHttpClient.get(
    location,
    httpTransformer: GalleryListHttpTransformer(),
    options: getCacheOptions(refresh: true),
    cancelToken: cancelToken,
  );

  if (httpResponse.ok && httpResponse.data is GalleryList) {
    return httpResponse.data as GalleryList;
  } else {
    logger.e('${httpResponse.error.runtimeType}');
    throw httpResponse.error ?? EhError(error: 'searchImage error');
  }
}

Future<EhHome?> getEhHome({bool refresh = false}) async {
  DioHttpClient dioHttpClient = DioHttpClient(dioConfig: globalDioConfig);
  const String url = '${EHConst.EH_BASE_URL}/home.php';

  final DioHttpResponse httpResponse = await dioHttpClient.get(
    url,
    httpTransformer: HttpTransformerBuilder(
      (response) async {
        final ehHome = parserEhHome(response.data as String);
        return DioHttpResponse<EhHome>.success(ehHome);
      },
    ),
    options: getCacheOptions(refresh: refresh),
  );

  if (httpResponse.ok && httpResponse.data is EhHome) {
    return httpResponse.data as EhHome;
  } else {
    logger.e('${httpResponse.error.runtimeType}');
    throw httpResponse.error ?? EhError(error: 'getEhHome error');
  }
}
