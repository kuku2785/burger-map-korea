import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;

import '../../stores/data/external_uri_launcher.dart';

const appInfoSupportLinkKey = ValueKey<String>('app-info-support-link');
const appInfoPrivacyPolicyLinkKey = ValueKey<String>(
  'app-info-privacy-policy-link',
);
const appInfoLicensesLinkKey = ValueKey<String>('app-info-licenses-link');

/// Opens information-screen links in the user's external application.
final class AppInfoExternalUriLauncher implements ExternalUriLauncher {
  const AppInfoExternalUriLauncher();

  @override
  Future<bool> launch(Uri uri) {
    return url_launcher.launchUrl(
      uri,
      mode: url_launcher.LaunchMode.externalApplication,
    );
  }
}

class AppInfoScreen extends StatefulWidget {
  const AppInfoScreen({
    super.key,
    this.supportUrl = '',
    this.privacyPolicyUrl = '',
    this.operatorName = '',
    this.externalUriLauncher = const AppInfoExternalUriLauncher(),
    this.externalLaunchTimeout = const Duration(seconds: 10),
  });

  final String supportUrl;
  final String privacyPolicyUrl;
  final String operatorName;
  final ExternalUriLauncher externalUriLauncher;
  final Duration externalLaunchTimeout;

  @override
  State<AppInfoScreen> createState() => _AppInfoScreenState();
}

class _AppInfoScreenState extends State<AppInfoScreen> {
  bool _isOpeningLink = false;

  Uri? get _supportUri => _parseSupportUri(widget.supportUrl);

  Uri? get _privacyPolicyUri => _parseHttpsUri(widget.privacyPolicyUrl);

  Future<void> _openExternalUri(Uri uri, String failureMessage) async {
    if (_isOpeningLink) {
      return;
    }

    setState(() => _isOpeningLink = true);
    var didLaunch = false;
    try {
      didLaunch = await widget.externalUriLauncher
          .launch(uri)
          .timeout(widget.externalLaunchTimeout);
    } on Object {
      didLaunch = false;
    } finally {
      if (mounted) {
        setState(() => _isOpeningLink = false);
      }
    }

    if (!didLaunch && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failureMessage)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final supportUri = _supportUri;
    final privacyPolicyUri = _privacyPolicyUri;
    final operatorName = widget.operatorName.trim();

    return Scaffold(
      appBar: AppBar(title: const Text('정보 및 지원')),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _InformationSection(
                icon: Icons.location_city_outlined,
                title: '용산구 우선 안내',
                children: [
                  Text('버거맵 코리아는 서울 용산구의 버거 매장을 우선 안내합니다.'),
                  SizedBox(height: 8),
                  Text(
                    '검수 완료 표시는 등록 정보의 확인 상태이며 방문 시점의 영업을 보증하지 않습니다. '
                    '방문 전 매장에 직접 확인해 주세요.',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const _InformationSection(
                icon: Icons.shield_outlined,
                title: '기기 데이터와 위치',
                children: [
                  Text('즐겨찾기에는 매장 식별자만 이 기기에 저장됩니다.'),
                  SizedBox(height: 8),
                  Text(
                    '현재 위치는 사용자가 위치 기능을 선택한 경우에만 전경에서 사용합니다. '
                    '위치 표시와 기기 안 거리 계산을 위해 메모리에서 처리하며 좌표를 영구 저장하지 않습니다.',
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Google Maps 등 외부 SDK에는 해당 서비스의 개인정보 처리 기준이 적용될 수 있습니다.',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _InformationSection(
                icon: Icons.privacy_tip_outlined,
                title: '개인정보처리방침',
                children: [
                  if (privacyPolicyUri == null)
                    const _UnavailableNotice(
                      message: '개인정보처리방침 연결이 아직 준비되지 않았습니다.',
                    )
                  else
                    _ExternalLinkTile(
                      key: appInfoPrivacyPolicyLinkKey,
                      icon: Icons.open_in_new,
                      label: '개인정보처리방침 열기',
                      enabled: !_isOpeningLink,
                      onTap: () => _openExternalUri(
                        privacyPolicyUri,
                        '개인정보처리방침을 열 수 없습니다. 잠시 후 다시 시도해 주세요.',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _InformationSection(
                icon: Icons.support_agent_outlined,
                title: '지원',
                children: [
                  if (operatorName.isEmpty)
                    const Text('운영자 정보가 아직 준비되지 않았습니다.')
                  else
                    Text('운영자: $operatorName'),
                  const SizedBox(height: 8),
                  const Text(
                    '매장 정보 오류를 알려주실 때 매장명과 수정할 내용을 적어 주세요. '
                    '현재 위치 좌표는 문의에 자동으로 포함되지 않습니다.',
                  ),
                  const SizedBox(height: 8),
                  if (supportUri == null)
                    const _UnavailableNotice(message: '지원 경로가 아직 준비되지 않았습니다.')
                  else
                    _ExternalLinkTile(
                      key: appInfoSupportLinkKey,
                      icon: supportUri.scheme == 'mailto'
                          ? Icons.email_outlined
                          : Icons.open_in_new,
                      label: '지원 문의 열기',
                      enabled: !_isOpeningLink,
                      onTap: () => _openExternalUri(
                        supportUri,
                        '지원 경로를 열 수 없습니다. 잠시 후 다시 시도해 주세요.',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _InformationSection(
                icon: Icons.code,
                title: '오픈소스',
                children: [
                  _ExternalLinkTile(
                    key: appInfoLicensesLinkKey,
                    icon: Icons.article_outlined,
                    label: '오픈소스 라이선스 보기',
                    onTap: () => showLicensePage(
                      context: context,
                      applicationName: '버거맵 코리아',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InformationSection extends StatelessWidget {
  const _InformationSection({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(title, style: textTheme.titleMedium),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _ExternalLinkTile extends StatelessWidget {
  const _ExternalLinkTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minTileHeight: 48,
      leading: Icon(icon),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right),
      enabled: enabled,
      onTap: enabled ? onTap : null,
    );
  }
}

class _UnavailableNotice extends StatelessWidget {
  const _UnavailableNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(padding: const EdgeInsets.all(12), child: Text(message)),
    );
  }
}

Uri? _parseHttpsUri(String value) {
  final normalized = value.trim();
  final uri = Uri.tryParse(normalized);
  if (uri == null ||
      _containsAsciiWhitespaceOrControl(normalized) ||
      uri.scheme.toLowerCase() != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri;
}

Uri? _parseSupportUri(String value) {
  final normalized = value.trim();
  final uri = Uri.tryParse(normalized);
  if (uri == null || _containsAsciiWhitespaceOrControl(normalized)) {
    return null;
  }
  if (uri.scheme.toLowerCase() == 'https' &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty) {
    return uri;
  }
  if (uri.scheme.toLowerCase() == 'mailto' &&
      !uri.hasAuthority &&
      _isSingleEmailAddress(uri.path) &&
      !uri.hasFragment) {
    return uri;
  }
  return null;
}

bool _containsAsciiWhitespaceOrControl(String value) {
  return value.codeUnits.any(
    (codeUnit) => codeUnit <= 0x20 || codeUnit == 0x7F,
  );
}

bool _isSingleEmailAddress(String value) {
  try {
    value = Uri.decodeComponent(value);
  } on FormatException {
    return false;
  }
  if (_containsAsciiWhitespaceOrControl(value) ||
      value.contains(',') ||
      value.contains(';')) {
    return false;
  }
  final separator = value.indexOf('@');
  return separator > 0 &&
      separator == value.lastIndexOf('@') &&
      separator < value.length - 1;
}
