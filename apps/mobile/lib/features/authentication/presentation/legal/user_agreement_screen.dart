import 'package:flutter/material.dart';

import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../../domain/user_agreement.dart';

class UserAgreementScreen extends StatelessWidget {
  const UserAgreementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppDesignTokens.softWhite,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppDesignTokens.textPrimary,
        title: const Text(UserAgreement.title),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          children: <Widget>[
            Text(
              '更新日期：${UserAgreement.updatedAt}',
              style: TextStyle(
                fontSize: 13,
                color: AppDesignTokens.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E8),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFFD666)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '版权要点',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: AppDesignTokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _bullet(UserAgreement.summaryBulletImport),
                  _bullet(UserAgreement.summaryBulletNoCrawl),
                  _bullet(UserAgreement.summaryBulletCopyright),
                ],
              ),
            ),
            const SizedBox(height: 20),
            for (final UserAgreementSection section
                in UserAgreement.sections) ...<Widget>[
              Text(
                section.heading,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppDesignTokens.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                section.body,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.55,
                  color: AppDesignTokens.textSecondary,
                ),
              ),
              const SizedBox(height: 18),
            ],
          ],
        ),
      ),
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('•  ', style: TextStyle(fontWeight: FontWeight.w800)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                height: 1.4,
                color: AppDesignTokens.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
