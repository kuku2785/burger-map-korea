import 'package:url_launcher/url_launcher.dart' as url_launcher;

abstract interface class ExternalUriLauncher {
  Future<bool> launch(Uri uri);
}

typedef UrlLaunchOperation =
    Future<bool> Function(Uri uri, url_launcher.LaunchMode mode);

final class UrlLauncherExternalUriLauncher implements ExternalUriLauncher {
  const UrlLauncherExternalUriLauncher({this.launchOperation = _launchUrl});

  final UrlLaunchOperation launchOperation;

  @override
  Future<bool> launch(Uri uri) async {
    try {
      final launchedInMapApp = await launchOperation(
        uri,
        url_launcher.LaunchMode.externalNonBrowserApplication,
      );
      if (launchedInMapApp) {
        return true;
      }
    } on Object {
      // A universal HTTPS fallback remains available when no map app handles it.
    }

    return launchOperation(uri, url_launcher.LaunchMode.externalApplication);
  }
}

Future<bool> _launchUrl(Uri uri, url_launcher.LaunchMode mode) {
  return url_launcher.launchUrl(uri, mode: mode);
}
