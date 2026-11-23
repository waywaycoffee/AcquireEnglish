import 'package:flutter/material.dart';

import 'coach_avatar_stage.dart';

/// Video-call style stage for standalone AI 外教 sessions only.
///
/// Large coach tile + self-camera PiP + bottom call chrome.
class OralCallStage extends StatelessWidget {
  const OralCallStage({
    required this.pulse,
    required this.speaking,
    required this.listening,
    required this.statusLabel,
    required this.displayName,
    required this.onHangUp,
    required this.onSwapCoach,
    required this.onToggleMic,
    required this.onToggleSelfCam,
    this.imageAsset,
    this.spriteAsset,
    this.encouraging = false,
    this.liveVideo,
    this.selfPreview,
    this.selfCamOn = false,
    this.micMuted = false,
    this.swapCoachEnabled = true,
    this.micEnabled = true,
    super.key,
  });

  final Animation<double> pulse;
  final bool speaking;
  final bool listening;
  final String statusLabel;
  final String displayName;
  final String? imageAsset;
  final String? spriteAsset;
  final bool encouraging;
  final Widget? liveVideo;
  final Widget? selfPreview;
  final bool selfCamOn;
  final bool micMuted;
  final bool swapCoachEnabled;
  final bool micEnabled;
  final VoidCallback onHangUp;
  final VoidCallback? onSwapCoach;
  final VoidCallback? onToggleMic;
  final VoidCallback? onToggleSelfCam;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          CoachAvatarStage(
            pulse: pulse,
            speaking: speaking,
            listening: listening,
            label: '',
            imageAsset: imageAsset,
            spriteAsset: spriteAsset,
            encouraging: encouraging,
            displayName: displayName,
            liveVideo: liveVideo,
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Color(0x44000000),
                  Color(0x00000000),
                  Color(0xCC0B1220),
                ],
                stops: <double>[0, 0.5, 1],
              ),
            ),
          ),
          Positioned(
            left: 12,
            top: 12,
            right: 132,
            child: Row(
              children: <Widget>[
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x990F172A),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Text(
                      '$displayName · $statusLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: 12,
            top: 12,
            child: _SelfPip(
              preview: selfPreview,
              active: selfCamOn,
              onTap: onToggleSelfCam,
            ),
          ),
          Positioned(
            left: 10,
            right: 10,
            bottom: 10,
            child: _CallBar(
              micMuted: micMuted,
              micEnabled: micEnabled,
              swapCoachEnabled: swapCoachEnabled,
              onHangUp: onHangUp,
              onSwapCoach: onSwapCoach,
              onToggleMic: onToggleMic,
              onToggleSelfCam: onToggleSelfCam,
              selfCamOn: selfCamOn,
            ),
          ),
        ],
      ),
    );
  }
}

class _SelfPip extends StatelessWidget {
  const _SelfPip({required this.active, this.preview, this.onTap});

  final Widget? preview;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 148,
        height: 198,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active
                ? const Color(0xFF34D399)
                : Colors.white.withValues(alpha: 0.55),
            width: 2,
          ),
          boxShadow: const <BoxShadow>[
            BoxShadow(color: Color(0x66000000), blurRadius: 12),
          ],
          color: const Color(0xFF111827),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (preview != null)
              preview!
            else
              const Center(
                child: Icon(
                  Icons.videocam_off_rounded,
                  color: Colors.white54,
                  size: 28,
                ),
              ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                color: const Color(0xAA0F172A),
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  active ? '我' : '摄像头关',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallBar extends StatelessWidget {
  const _CallBar({
    required this.micMuted,
    required this.micEnabled,
    required this.swapCoachEnabled,
    required this.selfCamOn,
    required this.onHangUp,
    this.onSwapCoach,
    this.onToggleMic,
    this.onToggleSelfCam,
  });

  final bool micMuted;
  final bool micEnabled;
  final bool swapCoachEnabled;
  final bool selfCamOn;
  final VoidCallback onHangUp;
  final VoidCallback? onSwapCoach;
  final VoidCallback? onToggleMic;
  final VoidCallback? onToggleSelfCam;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xCC0F172A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: <Widget>[
          _CallBarButton(
            icon: selfCamOn
                ? Icons.videocam_rounded
                : Icons.videocam_off_rounded,
            label: '视频',
            onTap: onToggleSelfCam,
          ),
          _CallBarButton(
            icon: micMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
            label: micMuted ? '取消静音' : '静音',
            onTap: micEnabled ? onToggleMic : null,
          ),
          _CallBarButton(
            icon: Icons.swap_horiz_rounded,
            label: '换教练',
            onTap: swapCoachEnabled ? onSwapCoach : null,
          ),
          _CallBarButton(
            icon: Icons.call_end_rounded,
            label: '挂断',
            danger: true,
            onTap: onHangUp,
          ),
        ],
      ),
    );
  }
}

class _CallBarButton extends StatelessWidget {
  const _CallBarButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final Color fill = danger
        ? const Color(0xFFB42318)
        : Colors.white.withValues(alpha: 0.12);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Material(
          color: fill,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 46,
              height: 46,
              child: Icon(icon, color: Colors.white, size: 22),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.78),
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
