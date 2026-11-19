/// Shared copy for registration user agreement & copyright notice.
class UserAgreement {
  UserAgreement._();

  static const String title = '用户协议与版权声明';
  static const String updatedAt = '2026-11-20';

  static const String shortConsent =
      '我已阅读并同意《用户协议》与《版权声明》。我确认：所有视频均由本人自行导入、自行学习；本软件不提供视频爬取功能。';

  static const String summaryBulletImport =
      '所有视频内容均由用户自行导入，仅供用户个人学习使用。';
  static const String summaryBulletNoCrawl =
      '本软件不提供视频爬取、批量抓取或未授权内容分发功能。';
  static const String summaryBulletCopyright =
      '用户对自行导入内容的合法性负责；相关版权归原权利人所有。';

  static const List<UserAgreementSection> sections = <UserAgreementSection>[
    UserAgreementSection(
      heading: '1. 服务说明',
      body:
          '爱快英语（Acquire English）提供基于真实视频的英语学习工具，包括字幕精听、跟读评测、听写、口语陪练、词卡复习及学习进度同步等。',
    ),
    UserAgreementSection(
      heading: '2. 账号注册',
      body: '您可通过手机号、邮箱或微信等方式注册。请妥善保管账号，并对账号下的行为负责。',
    ),
    UserAgreementSection(
      heading: '3. 视频内容与版权声明',
      body:
          '本软件中的所有视频内容，均属于用户自行导入，并由用户自行学习。软件仅提供学习辅助能力（如字幕显示、精听跟读、词卡等），不代替用户取得视频版权或使用许可。\n\n'
          '本软件不提供视频爬取功能，亦不以任何方式代用户从第三方平台批量抓取、下载或传播受版权保护的视频内容。\n\n'
          '您导入、上传或关联的视频、字幕及其他素材，版权仍归原权利人所有。您须确保已获得合法使用权或属于法律允许的个人学习使用范围；因违法导入或使用内容产生的责任，由您自行承担。',
    ),
    UserAgreementSection(
      heading: '4. 用户行为规范',
      body:
          '不得利用本服务从事违法违规活动；不得上传或导入侵犯他人权利的内容；不得攻击、干扰服务正常运行；不得利用本软件从事未授权的内容爬取或分发。',
    ),
    UserAgreementSection(
      heading: '5. 知识产权',
      body: '应用界面、商标、软件代码等归我们或相关权利人所有。用户自行导入内容的版权归属不受影响。',
    ),
    UserAgreementSection(
      heading: '6. 免责声明',
      body:
          '学习效果因人而异。对第三方平台内容、网络故障或不可抗力导致的服务中断，我们将在合理范围内尽力处理，但不承担超出法律规定的责任。',
    ),
    UserAgreementSection(
      heading: '7. 协议变更',
      body: '我们可能更新本协议，更新后继续注册或使用即视为接受修订内容。',
    ),
    UserAgreementSection(
      heading: '8. 联系方式',
      body: '如有疑问，请联系：support@curlhairai.com',
    ),
  ];
}

class UserAgreementSection {
  const UserAgreementSection({required this.heading, required this.body});

  final String heading;
  final String body;
}
