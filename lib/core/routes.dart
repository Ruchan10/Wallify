
import 'package:wallify/screens/nav_bar.dart';
import 'package:wallify/screens/splash_view.dart';

class AppRoute {
  AppRoute._();

  static const String splashRoute = '/splash';
  static const String navRoute = '/nav';

  static getAppRoutes() {
    return {
      splashRoute: (context) => const SplashView(),
      navRoute: (context) => const MainScaffold(),
    };
  }
}
