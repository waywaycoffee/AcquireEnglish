import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../router/app_router.dart';
import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../../domain/user_agreement.dart';

/// Checkbox + legal links shown on register / auto-register flows.
class RegistrationAgreementCheckbox extends StatefulWidget {
  const RegistrationAgreementCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.errorText,
  });

  final bool value;
  final ValueChanged<bool?> onChanged;
  final String? errorText;

  @override
  State<RegistrationAgreementCheckbox> createState() =>
      _RegistrationAgreementCheckboxState();
}

class _RegistrationAgreementCheckboxState
    extends State<RegistrationAgreementCheckbox> {
  late final TapGestureRecognizer _openAgreement;

  @override
  void initState() {
    super.initState();
    _openAgreement = TapGestureRecognizer()..onTap = _openAgreementPage;
  }

  void _openAgreementPage() {
    if (!mounted) {
      return;
    }
    context.push(SGRoute.userAgreement.route);
  }

  @override
  void dispose() {
    _openAgreement.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: widget.value,
                onChanged: widget.onChanged,
                activeColor: AppDesignTokens.brandGreen,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: AppDesignTokens.textSecondary,
                  ),
                  children: <InlineSpan>[
                    const TextSpan(text: '我已阅读并同意'),
                    TextSpan(
                      text: '《用户协议与版权声明》',
                      style: TextStyle(
                        color: AppDesignTokens.primaryBlue,
                        fontWeight: FontWeight.w800,
                      ),
                      recognizer: _openAgreement,
                    ),
                    const TextSpan(
                      text:
                          '。确认所有视频均由本人自行导入、自行学习；本软件不提供视频爬取功能。',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (widget.errorText != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            widget.errorText!,
            style: const TextStyle(
              color: Color(0xFFC62828),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          UserAgreement.summaryBulletNoCrawl,
          style: TextStyle(
            fontSize: 12,
            height: 1.4,
            color: AppDesignTokens.textSecondary,
          ),
        ),
      ],
    );
  }
}
