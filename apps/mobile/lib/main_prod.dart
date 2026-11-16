import 'flavors/app_flavor.dart';
import 'features/subtitle_completion/subtitle_overlay_entry.dart';
import 'main.dart' as app;

Future<void> main(List<String> args) async {
  FlavorConfig.setFlavor(AppFlavor.prod);
  await app.bootstrap(args: args);
}

/// flutter_overlay_window looks up this name in the `-t` entry library.
@pragma('vm:entry-point')
void overlayMain() {
  runSubtitleOverlayApp();
}
