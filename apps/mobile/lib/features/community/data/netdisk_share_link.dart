enum CommunityNetdiskProvider { baidu, quark, aliyun, pan115 }

CommunityNetdiskProvider? detectCommunityNetdiskProvider(String raw) {
  final Uri? uri = Uri.tryParse(raw.trim());
  if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty ||
      uri.pathSegments.where((String segment) => segment.isNotEmpty).isEmpty) {
    return null;
  }
  switch (uri.host.toLowerCase().replaceAll(RegExp(r'\.$'), '')) {
    case 'pan.baidu.com':
    case 'yun.baidu.com':
      return CommunityNetdiskProvider.baidu;
    case 'pan.quark.cn':
      return CommunityNetdiskProvider.quark;
    case 'alipan.com':
    case 'www.alipan.com':
    case 'aliyundrive.com':
    case 'www.aliyundrive.com':
      return CommunityNetdiskProvider.aliyun;
    case '115.com':
    case 'www.115.com':
      return CommunityNetdiskProvider.pan115;
  }
  return null;
}

extension CommunityNetdiskProviderLabel on CommunityNetdiskProvider {
  String get label => switch (this) {
    CommunityNetdiskProvider.baidu => '百度网盘',
    CommunityNetdiskProvider.quark => '夸克网盘',
    CommunityNetdiskProvider.aliyun => '阿里云盘',
    CommunityNetdiskProvider.pan115 => '115 网盘',
  };

  String get apiValue => name;
}
