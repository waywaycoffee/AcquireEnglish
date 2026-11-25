/// Legal / About copy for App Store & WeChat Pay 尾页.
/// [companyName] must match the WeChat Pay merchant 主体 / 营业执照全称.
class AppLegalInfo {
  const AppLegalInfo._();

  static const String appDisplayName = '爱快英语';
  static const String appEnglishName = 'Acquire English';
  static const String packageName = 'com.acquire.english';

  /// 开发公司全称（微信支付尾页 / 应用市场开发者信息须一致）。
  /// 若与营业执照不一致，请只改这一处。
  static const String companyName = '广州柯海智能科技有限公司';

  static const String supportEmail = 'support@curlhairai.com';
  static const String supportWechat = 'youyoufairytale';

  static const String privacyUrl =
      'https://acquireenglish.curlhairai.com/privacy.html';
  static const String termsUrl =
      'https://acquireenglish.curlhairai.com/terms.html';

  /// APP 备案号（工信部下发后填入；未备案前可留空，关于页会隐藏该项）。
  static const String icpFilingNumber = '';

  static const String icpQueryUrl = 'https://beian.miit.gov.cn/';
}
