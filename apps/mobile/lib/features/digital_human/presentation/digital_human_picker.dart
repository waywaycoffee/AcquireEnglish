import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../settings/presentation/settings_provider.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../data/digital_human_catalog.dart';
import 'widgets/cartoon_coach_sprite.dart';

/// Home-page row: pick a near-real digital-human coach persona.
class DigitalHumanPicker extends ConsumerStatefulWidget {
  const DigitalHumanPicker({super.key});

  @override
  ConsumerState<DigitalHumanPicker> createState() => _DigitalHumanPickerState();
}

enum _PersonaFilter {
  all('全部'),
  women('女外教'),
  men('男外教'),
  children('儿童伙伴');

  const _PersonaFilter(this.label);
  final String label;

  bool matches(DigitalHumanPersona persona) => switch (this) {
    all => true,
    women => !persona.isChild && persona.isFemaleVoice,
    men => !persona.isChild && !persona.isFemaleVoice,
    children => persona.isChild,
  };
}

class _DigitalHumanPickerState extends ConsumerState<DigitalHumanPicker> {
  final ScrollController _personas = ScrollController();
  _PersonaFilter _filter = _PersonaFilter.all;

  @override
  void dispose() {
    _personas.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final LearningSettingsState settings = ref.watch(learningSettingsProvider);
    final DigitalHumanPersona selected = settings.selectedDigitalHuman;
    final List<DigitalHumanPersona> visible = digitalHumanCatalog
        .where(_filter.matches)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '选择数字人形象',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: AppDesignTokens.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '当前：${selected.displayName} · ${selected.tagline} · ${selected.voiceLabel}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppDesignTokens.textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        SegmentedButton<bool>(
          segments: const <ButtonSegment<bool>>[
            ButtonSegment<bool>(
              value: true,
              label: Text('卡通版'),
              icon: Icon(Icons.face),
            ),
            ButtonSegment<bool>(
              value: false,
              label: Text('真人版'),
              icon: Icon(Icons.portrait),
            ),
          ],
          selected: <bool>{settings.cartoonDigitalHuman},
          onSelectionChanged: (Set<bool> values) => ref
              .read(learningSettingsProvider.notifier)
              .setCartoonDigitalHuman(values.first),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: <Widget>[
            for (final _PersonaFilter filter in _PersonaFilter.values)
              ChoiceChip(
                label: Text(filter.label),
                selected: filter == _filter,
                onSelected: (bool selected) {
                  if (!selected) return;
                  if (_personas.hasClients) _personas.jumpTo(0);
                  setState(() => _filter = filter);
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        RawScrollbar(
          controller: _personas,
          thumbVisibility: true,
          trackVisibility: true,
          interactive: true,
          scrollbarOrientation: ScrollbarOrientation.bottom,
          thickness: 8,
          radius: const Radius.circular(8),
          thumbColor: AppDesignTokens.brandGreenDark,
          trackColor: AppDesignTokens.borderGray,
          child: SizedBox(
            height: 184,
            child: ListView.separated(
              controller: _personas,
              primary: false,
              padding: const EdgeInsets.only(bottom: 16),
              scrollDirection: Axis.horizontal,
              itemCount: visible.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (BuildContext context, int index) {
                final DigitalHumanPersona persona = visible[index];
                final bool active = persona.id == selected.id;
                return _PersonaCard(
                  persona: persona,
                  selected: active,
                  cartoon: settings.cartoonDigitalHuman,
                  onTap: () {
                    ref
                        .read(learningSettingsProvider.notifier)
                        .setDigitalHumanId(persona.id);
                  },
                );
              },
            ),
          ),
        ),
        Row(
          children: <Widget>[
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () => context.push('/digital-human'),
                icon: const Icon(Icons.record_voice_over_rounded),
                label: const Text('开始情景口语'),
              ),
            ),
            TextButton(
              onPressed: () {
                if (_personas.hasClients) {
                  _personas.animateTo(
                    _personas.position.maxScrollExtent,
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOut,
                  );
                }
              },
              child: const Text('更多 ›'),
            ),
          ],
        ),
      ],
    );
  }
}

class _PersonaCard extends StatelessWidget {
  const _PersonaCard({
    required this.persona,
    required this.selected,
    required this.cartoon,
    required this.onTap,
  });

  final DigitalHumanPersona persona;
  final bool selected;
  final bool cartoon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: 112,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppDesignTokens.appWhite.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppDesignTokens.brandGreenDark
                : AppDesignTokens.borderGray,
            width: selected ? 2.5 : 1,
          ),
          boxShadow: selected ? AppDesignTokens.toyCardShadow : null,
        ),
        child: Column(
          children: <Widget>[
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: cartoon && persona.hasCartoonAtlas
                    ? CartoonCoachSprite.portrait(
                        asset: persona.cartoonAssetPath,
                      )
                    : Image.asset(
                        persona.assetPath,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        errorBuilder: (_, __, ___) => ColoredBox(
                          color: AppDesignTokens.skyLight,
                          child: Icon(
                            Icons.face_retouching_natural_rounded,
                            color: AppDesignTokens.brandGreenDark,
                            size: 36,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              persona.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: selected
                    ? AppDesignTokens.brandGreenDark
                    : AppDesignTokens.textPrimary,
              ),
            ),
            Text(
              persona.voiceLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppDesignTokens.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
