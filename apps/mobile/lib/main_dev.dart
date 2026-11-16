import 'flavors/app_flavor.dart';
import 'main.dart' as app;

Future<void> main(List<String> args) async {
  FlavorConfig.setFlavor(AppFlavor.dev);
  await app.bootstrap(args: args);
}

@pragma('vm:entry-point')
void overlayMain() {
  app.overlayMain();
}
