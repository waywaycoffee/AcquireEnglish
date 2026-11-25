import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../constants/assets.dart';
import '../../../router/app_router.dart';
import '../../authentication/presentation/auth_session.dart';
import 'auth_guide_keys.dart';
import 'auth_sources_settings_screen.dart';
import 'onboarding_provider.dart';

const Color _bg = Color(0xFF07090D);
const Color _green = Color(0xFF22C55E);
const Color _muted = Color(0xFF8B93A7);
const Color _body = Color(0xFFA7B0C0);
const Color _card = Color(0xFF121820);
const int _pageCount = 8;

/// First-open cinematic guide: real App screenshots + learning theory + auth.
class AuthSourceGuideScreen extends ConsumerStatefulWidget {
  const AuthSourceGuideScreen({super.key});

  @override
  ConsumerState<AuthSourceGuideScreen> createState() =>
      _AuthSourceGuideScreenState();
}

class _AuthSourceGuideScreenState extends ConsumerState<AuthSourceGuideScreen>
    with TickerProviderStateMixin {
  /// Cold-start 启动页: pick one of the eight cinematic pages at random.
  late final int _index;
  late final PageController _pages;
  late final AnimationController _loop;
  late final AnimationController _enter;

  @override
  void initState() {
    super.initState();
    _index = math.Random().nextInt(_pageCount);
    _pages = PageController(initialPage: _index);
    _loop = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
    _enter.forward();
  }

  @override
  void dispose() {
    _pages.dispose();
    _loop.dispose();
    _enter.dispose();
    super.dispose();
  }

  Future<void> _finish({bool openSettings = false}) async {
    await markAuthSourceGuideCompleted();
    if (!mounted) return;
    final bool signedIn = ref.read(authSessionProvider).isLoggedIn;
    final bool profileDone = readOnboardingCompletedSync();
    if (!signedIn) {
      context.go(SGRoute.login.route);
      return;
    }
    if (!profileDone) {
      context.go('/onboarding');
      return;
    }
    if (openSettings) {
      context.go(SGRoute.home.route);
      context.push(AuthSourcesSettingsScreen.route);
      return;
    }
    context.go(SGRoute.home.route);
  }

  Color get _accent => switch (_index) {
        1 => const Color(0xFF3B82F6),
        2 => const Color(0xFF14B8A6),
        3 => const Color(0xFFA78BFA),
        4 => const Color(0xFFF59E0B),
        5 => const Color(0xFFEC4899),
        6 => const Color(0xFFF5C16C),
        _ => _green,
      };

  @override
  Widget build(BuildContext context) {
    final bool onSources = _index == 7;
    return Scaffold(
      backgroundColor: _bg,
      body: AnimatedBuilder(
        animation: _loop,
        builder: (BuildContext context, Widget? child) {
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              _AuroraBackdrop(t: _loop.value, accent: _accent),
              SafeArea(
                child: Column(
                  children: <Widget>[
                    Expanded(
                      child: PageView(
                        controller: _pages,
                        physics: const NeverScrollableScrollPhysics(),
                        children: <Widget>[
                          _WelcomePage(t: _loop.value, enter: _enter),
                          _FeaturesPage(t: _loop.value, enter: _enter),
                          _ReadingInputPage(t: _loop.value, enter: _enter),
                          _FsrsMemoryPage(t: _loop.value, enter: _enter),
                          _ProgressVisiblePage(t: _loop.value, enter: _enter),
                          _CommunityBuddyPage(t: _loop.value, enter: _enter),
                          _WhyAuthPage(t: _loop.value, enter: _enter),
                          _SourcesPage(
                            t: _loop.value,
                            enter: _enter,
                            onManage: () => _finish(openSettings: true),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
                      child: Column(
                        children: <Widget>[
                          _PrimaryButton(
                            label: '进入爱快英语',
                            onPressed: _finish,
                          ),
                          if (onSources) ...<Widget>[
                            const SizedBox(height: 10),
                            TextButton(
                              onPressed: () => _finish(openSettings: true),
                              child: const Text(
                                '管理授权来源',
                                style: TextStyle(
                                  color: _muted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AuroraBackdrop extends StatelessWidget {
  const _AuroraBackdrop({required this.t, required this.accent});

  final double t;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final double a = math.sin(t * math.pi * 2) * 0.5 + 0.5;
    final double b = math.cos(t * math.pi * 2 * 0.7) * 0.5 + 0.5;
    return CustomPaint(
      painter: _AuroraPainter(a: a, b: b, accent: accent),
      child: const SizedBox.expand(),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter({required this.a, required this.b, required this.accent});

  final double a;
  final double b;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _bg);
    final Offset c1 = Offset(size.width * (0.35 + a * 0.2), size.height * 0.28);
    final Offset c2 =
        Offset(size.width * (0.72 - b * 0.18), size.height * 0.42);
    final Offset c3 =
        Offset(size.width * 0.2, size.height * (0.55 + a * 0.08));
    void blob(Offset c, double r, Color color) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: <Color>[color, color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    blob(c1, size.width * 0.55, accent.withValues(alpha: 0.28));
    blob(c2, size.width * 0.42,
        const Color(0xFF3B82F6).withValues(alpha: 0.16));
    blob(c3, size.width * 0.38, accent.withValues(alpha: 0.12));
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter oldDelegate) =>
      oldDelegate.a != a || oldDelegate.b != b || oldDelegate.accent != accent;
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: _green,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          'ACQUIRE',
          style: TextStyle(
            color: _green,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
        ),
        const Spacer(),
        Text(
          '${step.toString().padLeft(2, '0')} / ${_pageCount.toString().padLeft(2, '0')}',
          style: const TextStyle(
            color: _muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.index, required this.count});

  final int index;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(count, (int i) {
        final bool on = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: on ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: on ? _green : const Color(0xFF3A4252),
            borderRadius: BorderRadius.circular(99),
          ),
        );
      }),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _green,
          borderRadius: BorderRadius.circular(16),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: _green.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onPressed,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (label == '下一步') ...<Widget>[
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward_rounded,
                        color: Colors.white, size: 18),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WelcomePage extends StatelessWidget {
  const _WelcomePage({required this.t, required this.enter});

  final double t;
  final Animation<double> enter;

  @override
  Widget build(BuildContext context) {
    final double bob = math.sin(t * math.pi * 2) * 6;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
      child: FadeTransition(
        opacity: CurvedAnimation(parent: enter, curve: Curves.easeOut),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const _TopBar(step: 1),
            const SizedBox(height: 18),
            const Text(
              '欢迎来到爱快英语',
              style: TextStyle(
                color: Color(0xFFF4F7FB),
                fontSize: 30,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '首页、跟读、复习，都是现在手机里的真实界面。',
              style: TextStyle(
                color: _body,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  Positioned(
                    right: 8,
                    top: 28 + bob,
                    child: Transform.rotate(
                      angle: -0.1,
                      child: Opacity(
                        opacity: 0.92,
                        child: _PhoneFrame(
                          asset: Assets.onboardingStudy,
                          width: 168,
                          height: 346,
                          scale: 1.05 + math.sin(t * math.pi * 2) * 0.02,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    top: 8 - bob,
                    child: Transform.rotate(
                      angle: 0.04,
                      child: _PhoneFrame(
                        asset: Assets.onboardingHome,
                        width: 196,
                        height: 404,
                        scale: 1.06 + math.cos(t * math.pi * 2) * 0.02,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 18,
                    bottom: 18,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xE6121820),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: const Color(0x22FFFFFF)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(Icons.play_arrow_rounded,
                                  color: _green, size: 16),
                              SizedBox(width: 6),
                              Text(
                                '上次学到 0:03 · 继续播放',
                                style: TextStyle(
                                  color: Color(0xFFF4F7FB),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeaturesPage extends StatelessWidget {
  const _FeaturesPage({required this.t, required this.enter});

  final double t;
  final Animation<double> enter;

  @override
  Widget build(BuildContext context) {
    final List<({String kicker, String title, String body, String asset})>
        rows = <({String kicker, String title, String body, String asset})>[
      (
        kicker: '首页',
        title: '接着上次的视频',
        body: '打开就能继续播放，字幕停在上次的句子。',
        asset: Assets.onboardingHome,
      ),
      (
        kicker: '跟读',
        title: '一句一句开口',
        body: '原声、录音、双语字幕在同一条时间线上。',
        asset: Assets.onboardingShadow,
      ),
      (
        kicker: '复习',
        title: '收藏的句子会回来',
        body: '单词和短语进入每日复习，不用另开一本词书。',
        asset: Assets.onboardingReview,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _TopBar(step: 2),
          const SizedBox(height: 18),
          const Text(
            '学习就在这些画面里',
            style: TextStyle(
              color: Color(0xFFF4F7FB),
              fontSize: 30,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '视频来自哔哩哔哩、YouTube 和网盘。公开素材可先学，需要账号权限时再连接。',
            style: TextStyle(
              color: _body,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (BuildContext context, int i) {
                final ({String kicker, String title, String body, String asset})
                    item = rows[i];
                final Animation<double> local = CurvedAnimation(
                  parent: enter,
                  curve: Interval(0.12 * i, 0.55 + 0.12 * i,
                      curve: Curves.easeOutCubic),
                );
                return FadeTransition(
                  opacity: local,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.12),
                      end: Offset.zero,
                    ).animate(local),
                    child: _FeatureRow(
                      kicker: item.kicker,
                      title: item.title,
                      body: item.body,
                      asset: item.asset,
                      t: t,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.kicker,
    required this.title,
    required this.body,
    required this.asset,
    required this.t,
  });

  final String kicker;
  final String title;
  final String body;
  final String asset;
  final double t;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Row(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: 92,
              height: 156,
              child: Transform.scale(
                scale: 1.08 + math.sin(t * math.pi * 2) * 0.02,
                child: Image.asset(
                  asset,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const ColoredBox(
                    color: Color(0xFF1A2230),
                    child: Center(
                      child: Icon(Icons.image_not_supported_outlined,
                          color: _muted),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  kicker,
                  style: const TextStyle(
                    color: _green,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFFF4F7FB),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    color: _body,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadingInputPage extends StatelessWidget {
  const _ReadingInputPage({required this.t, required this.enter});

  final double t;
  final Animation<double> enter;

  @override
  Widget build(BuildContext context) {
    final double bob = math.sin(t * math.pi * 2) * 5;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
      child: FadeTransition(
        opacity: CurvedAnimation(parent: enter, curve: Curves.easeOut),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const _TopBar(step: 3),
            const SizedBox(height: 18),
            const Text(
              '阅读：可理解输入',
              style: TextStyle(
                color: Color(0xFFF4F7FB),
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '不是硬背词表，而是读得懂、听得进的真实内容。材料按 i+1 对齐你当前水平：大部分已认识，只留一点新信息。',
              style: TextStyle(
                color: _body,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: Stack(
                children: <Widget>[
                  Positioned(
                    left: 0,
                    top: 8 + bob,
                    child: Transform.rotate(
                      angle: -0.05,
                        child: _PhoneFrame(
                        asset: Assets.onboardingBookshelfOak,
                        width: 150,
                        height: 300,
                        scale: 1.04 + math.sin(t * math.pi * 2) * 0.015,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 28 - bob,
                    child: Transform.rotate(
                      angle: 0.06,
                      child: _PhoneFrame(
                        asset: Assets.onboardingReading,
                        width: 168,
                        height: 336,
                        scale: 1.05 + math.cos(t * math.pi * 2) * 0.015,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: const <Widget>[
                _TheoryChip(label: '可理解输入'),
                _TheoryChip(label: 'i+1 难度'),
                _TheoryChip(label: '书架 · 分级阅读'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FsrsMemoryPage extends StatelessWidget {
  const _FsrsMemoryPage({required this.t, required this.enter});

  final double t;
  final Animation<double> enter;

  @override
  Widget build(BuildContext context) {
    final List<({String title, String body, IconData icon})> items =
        <({String title, String body, IconData icon})>[
      (
        title: '不只背单词',
        body: '短语、句子、语法点，只要你标过「要记住」，都会进统一队列。',
        icon: Icons.layers_rounded,
      ),
      (
        title: 'FSRS 科学间隔',
        body: '快忘时再见面：听写没过、跟读不稳、阅读生词，都会回流复习。',
        icon: Icons.auto_graph_rounded,
      ),
      (
        title: '见过就要记得住',
        body: '收藏、错题、未达线句子，同一套记忆算法，不另开三本词书。',
        icon: Icons.psychology_alt_rounded,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
      child: FadeTransition(
        opacity: CurvedAnimation(parent: enter, curve: Curves.easeOut),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const _TopBar(step: 4),
            const SizedBox(height: 18),
            const Text(
              'FSRS 记住一切该记的',
              style: TextStyle(
                color: Color(0xFFF4F7FB),
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '单词 / 短语 / 句子 / 语法，统一进入间隔复习。不是词书流水线，是「见过就要记得住」。',
              style: TextStyle(
                color: _body,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SizedBox(
                    width: 132,
                    child: _PhoneFrame(
                      asset: Assets.onboardingFsrs,
                      width: 132,
                      height: 420,
                      scale: 1.06 + math.sin(t * math.pi * 2) * 0.02,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (BuildContext context, int i) {
                        final item = items[i];
                        final Animation<double> local = CurvedAnimation(
                          parent: enter,
                          curve: Interval(0.1 * i, 0.5 + 0.1 * i,
                              curve: Curves.easeOutCubic),
                        );
                        return FadeTransition(
                          opacity: local,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _card,
                              borderRadius: BorderRadius.circular(16),
                              border:
                                  Border.all(color: const Color(0x14FFFFFF)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Icon(item.icon, color: _green, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        item.title,
                                        style: const TextStyle(
                                          color: Color(0xFFF4F7FB),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        item.body,
                                        style: const TextStyle(
                                          color: _body,
                                          fontSize: 12,
                                          height: 1.4,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressVisiblePage extends StatelessWidget {
  const _ProgressVisiblePage({required this.t, required this.enter});

  final double t;
  final Animation<double> enter;

  @override
  Widget build(BuildContext context) {
    final double pulse = 0.5 + 0.5 * math.sin(t * math.pi * 2);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
      child: FadeTransition(
        opacity: CurvedAnimation(parent: enter, curve: Curves.easeOut),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const _TopBar(step: 5),
            const SizedBox(height: 18),
            const Text(
              '进步，全部看得见',
              style: TextStyle(
                color: Color(0xFFF4F7FB),
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '掌握的词汇量会越来越接近你的真实水平。等级、XP、句子与表达数量，每一次留下的痕迹都在成长页。',
              style: TextStyle(
                color: _body,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  Positioned(
                    left: 0,
                    top: 20,
                    child: Opacity(
                      opacity: 0.9,
                      child: Transform.rotate(
                        angle: -0.04,
                        child: _PhoneFrame(
                          asset: Assets.onboardingCollect,
                          width: 148,
                          height: 300,
                          scale: 1.04,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Transform.rotate(
                      angle: 0.05,
                      child: _PhoneFrame(
                        asset: Assets.onboardingGrowth,
                        width: 180,
                        height: 360,
                        scale: 1.05 + pulse * 0.02,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    bottom: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xE6121820),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Color.lerp(
                                const Color(0x3322C55E),
                                _green,
                                pulse,
                              ) ??
                              _green,
                        ),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '词汇量 → 真实水平',
                            style: TextStyle(
                              color: _green,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '句子 · 表达 · XP · 连续天数',
                            style: TextStyle(
                              color: Color(0xFFF4F7FB),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommunityBuddyPage extends StatelessWidget {
  const _CommunityBuddyPage({required this.t, required this.enter});

  final double t;
  final Animation<double> enter;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
      child: FadeTransition(
        opacity: CurvedAnimation(parent: enter, curve: Curves.easeOut),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const _TopBar(step: 6),
            const SizedBox(height: 18),
            const Text(
              '社区素材 · 学习搭子',
              style: TextStyle(
                color: Color(0xFFF4F7FB),
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '海量用户上传的学习素材可以拿来练；找学习搭子一起通关、互相鼓励，进度不再一个人扛。',
              style: TextStyle(
                color: _body,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: Column(
                children: <Widget>[
                  Expanded(
                    flex: 5,
                    child: _LabeledShot(
                      asset: Assets.onboardingCommunity,
                      label: '社区冒险广场',
                      t: t,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    flex: 4,
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: _LabeledShot(
                            asset: Assets.onboardingBuddy,
                            label: '学习搭子 · 同桌',
                            t: t,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: _card,
                              borderRadius: BorderRadius.circular(18),
                              border:
                                  Border.all(color: const Color(0x14FFFFFF)),
                            ),
                            child: const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Icon(Icons.groups_rounded,
                                    color: _green, size: 22),
                                SizedBox(height: 10),
                                Text(
                                  '一起变强',
                                  style: TextStyle(
                                    color: Color(0xFFF4F7FB),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  '素材包、跟读流、邀请同桌、本周一起通关。',
                                  style: TextStyle(
                                    color: _body,
                                    fontSize: 12,
                                    height: 1.4,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WhyAuthPage extends StatelessWidget {
  const _WhyAuthPage({required this.t, required this.enter});

  final double t;
  final Animation<double> enter;

  @override
  Widget build(BuildContext context) {
    final double bob = math.sin(t * math.pi * 2) * 5;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
      child: FadeTransition(
        opacity: CurvedAnimation(parent: enter, curve: Curves.easeOut),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const _TopBar(step: 7),
            const SizedBox(height: 18),
            const Text(
              '为什么要授权',
              style: TextStyle(
                color: Color(0xFFF4F7FB),
                fontSize: 30,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '公开视频和已有字幕可以直接使用，部分素材需要连接来源账号。',
              style: TextStyle(
                color: _body,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Column(
                children: <Widget>[
                  Expanded(
                    child: Center(
                      child: Transform.translate(
                        offset: Offset(0, bob),
                        child: _PhoneFrame(
                          asset: Assets.onboardingStudy,
                          width: 168,
                          height: 336,
                          scale: 1.05 + math.cos(t * math.pi * 2) * 0.015,
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xCC141C28),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0x55F5C16C)),
                    ),
                    child: const Text(
                      '连接账号可访问来源允许的课程和字幕。可以进入爱快英语后再按需连接。',
                      style: TextStyle(
                        color: Color(0xFFF4E7C4),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        height: 1.45,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final String line in <String>[
                    '每次授权都由你确认',
                    '可在设置里随时撤销',
                    '未授权也能学习公开素材和本地内容',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.check_rounded,
                              color: _green, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            line,
                            style: const TextStyle(
                              color: Color(0xFFF4F7FB),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourcesPage extends StatelessWidget {
  const _SourcesPage({
    required this.t,
    required this.enter,
    required this.onManage,
  });

  final double t;
  final Animation<double> enter;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
      child: FadeTransition(
        opacity: CurvedAnimation(parent: enter, curve: Curves.easeOut),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const _TopBar(step: 8),
            const SizedBox(height: 18),
            const Text(
              '授权与素材来源',
              style: TextStyle(
                color: Color(0xFFF4F7FB),
                fontSize: 30,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '管好来源之后，这些真实画面里的课、字幕和复习才会同步。',
              style: TextStyle(
                color: _body,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            _ShotCollage(t: t),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: <Widget>[
                  const _SourcePreviewTile(
                    name: '哔哩哔哩',
                    state: '可选连接 · 公开视频可直接学习',
                    color: Color(0xFFFB7299),
                  ),
                  const SizedBox(height: 8),
                  const _SourcePreviewTile(
                    name: 'YouTube',
                    state: '未授权 · 登录后导入视频',
                    color: Color(0xFFFF4E45),
                  ),
                  const SizedBox(height: 8),
                  const _SourcePreviewTile(
                    name: '网盘',
                    state: '未连接 · 授权后导入课件',
                    color: Color(0xFF3B82F6),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: onManage,
                      child: const Text(
                        '打开设置管理授权',
                        style: TextStyle(
                          color: _green,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShotCollage extends StatelessWidget {
  const _ShotCollage({required this.t});

  final double t;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 176,
      child: Column(
        children: <Widget>[
          Expanded(
            flex: 5,
            child: _LabeledShot(
              asset: Assets.onboardingOral,
              label: '数字人开口',
              t: t,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            flex: 4,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: _LabeledShot(
                    asset: Assets.onboardingWords,
                    label: '单词库',
                    t: t,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _LabeledShot(
                    asset: Assets.onboardingGrowth,
                    label: '成长之路',
                    t: t,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LabeledShot extends StatelessWidget {
  const _LabeledShot({
    required this.asset,
    required this.label,
    required this.t,
  });

  final String asset;
  final String label;
  final double t;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Transform.scale(
            scale: 1.06 + math.sin(t * math.pi * 2) * 0.015,
            child: Image.asset(
              asset,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const ColoredBox(
                color: Color(0xFF1A2230),
                child: Center(
                  child: Icon(Icons.image_not_supported_outlined,
                      color: _muted),
                ),
              ),
            ),
          ),
          Positioned(
            left: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xE607090D),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  color: Color(0xFFF4F7FB),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourcePreviewTile extends StatelessWidget {
  const _SourcePreviewTile({
    required this.name,
    required this.state,
    required this.color,
  });

  final String name;
  final String state;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  name,
                  style: const TextStyle(
                    color: Color(0xFFF4F7FB),
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  state,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const Text(
            '去授权',
            style: TextStyle(
              color: _green,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _TheoryChip extends StatelessWidget {
  const _TheoryChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x3322C55E),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x5522C55E)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: _green,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({
    required this.asset,
    required this.width,
    required this.height,
    this.scale = 1.05,
  });

  final String asset;
  final double width;
  final double height;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1016),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: const Color(0xFF3A4252), width: 2),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x99000000),
            blurRadius: 28,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Transform.scale(
          scale: scale,
          child: Image.asset(
            asset,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, __, ___) => const ColoredBox(
              color: Color(0xFF1A2230),
              child: Center(
                child: Icon(Icons.image_not_supported_outlined, color: _muted),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
