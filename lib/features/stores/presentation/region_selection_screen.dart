import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../domain/store_location.dart';
import '../domain/store_region.dart';

const regionSidoDropdownKey = ValueKey<String>('region-sido-dropdown');
const regionSigunguDropdownKey = ValueKey<String>('region-sigungu-dropdown');
const regionDongDropdownKey = ValueKey<String>('region-dong-dropdown');
const regionApplyButtonKey = ValueKey<String>('region-apply-button');
const regionCancelButtonKey = ValueKey<String>('region-cancel-button');
const regionClearButtonKey = ValueKey<String>('region-clear-button');

final class RegionSelectionResult {
  const RegionSelectionResult({required this.selection});

  final StoreRegionFilter? selection;
}

class RegionSelectionScreen extends StatefulWidget {
  const RegionSelectionScreen({
    super.key,
    required this.storesListenable,
    this.initialSelection,
  });

  final ValueListenable<List<StoreLocation>?> storesListenable;
  final StoreRegionFilter? initialSelection;

  @override
  State<RegionSelectionScreen> createState() => _RegionSelectionScreenState();
}

class _RegionSelectionScreenState extends State<RegionSelectionScreen> {
  static const _allValue = '__all__';

  late StoreRegionFilter? _draftSelection = widget.initialSelection;
  ModalRoute<Object?>? _ownRoute;

  @override
  void initState() {
    super.initState();
    widget.storesListenable.addListener(_dismissOutdatedMenu);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ownRoute = ModalRoute.of(context);
  }

  @override
  void didUpdateWidget(covariant RegionSelectionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storesListenable != widget.storesListenable) {
      oldWidget.storesListenable.removeListener(_dismissOutdatedMenu);
      widget.storesListenable.addListener(_dismissOutdatedMenu);
      _dismissOutdatedMenu();
    }
  }

  void _dismissOutdatedMenu() {
    // A DropdownButton popup keeps its own copy of the old catalog. Close it
    // whenever the public snapshot changes, including expiry and failures.
    final route = _ownRoute;
    if (mounted && route != null && !route.isCurrent && route.isActive) {
      Navigator.of(
        context,
      ).popUntil((candidate) => identical(candidate, route));
    }
  }

  @override
  void dispose() {
    widget.storesListenable.removeListener(_dismissOutdatedMenu);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('지역 선택')),
      body: SafeArea(
        top: false,
        child: ValueListenableBuilder<List<StoreLocation>?>(
          valueListenable: widget.storesListenable,
          builder: (context, stores, _) {
            final catalog = stores == null ? null : _RegionCatalog(stores);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    child: catalog == null
                        ? const _RegionUnavailableContent()
                        : _buildSelectionContent(context, catalog),
                  ),
                ),
                _buildActions(context, catalog),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSelectionContent(BuildContext context, _RegionCatalog catalog) {
    final selectedSido = catalog.sidoFor(_draftSelection);
    final selectedSigungu = catalog.sigunguFor(_draftSelection);
    final sigunguOptions = selectedSido == null
        ? const <StoreRegion>[]
        : catalog.sigunguForSido(selectedSido.sidoCode);
    final dongOptions = selectedSigungu == null
        ? const <StoreRegion>[]
        : catalog.dongForSigungu(
            selectedSigungu.sidoCode,
            selectedSigungu.sigunguCode,
          );
    final canonicalSelection = catalog.canonical(_draftSelection);
    final unavailableSelection =
        _draftSelection != null && canonicalSelection == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '원하는 범위까지만 선택할 수 있습니다.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 20),
        _RegionDropdown(
          key: regionSidoDropdownKey,
          label: '시·도',
          value: _sidoValue(catalog),
          hint: unavailableSelection ? '현재 선택을 확인할 수 없습니다' : null,
          items: [
            const DropdownMenuItem(value: _allValue, child: Text('전국 전체')),
            for (final region in catalog.sido)
              DropdownMenuItem(
                value: region.sidoCode,
                child: Text(region.sidoName),
              ),
          ],
          onChanged: (value) => _selectSido(catalog, value),
        ),
        const SizedBox(height: 16),
        _RegionDropdown(
          key: regionSigunguDropdownKey,
          label: '시·군·구',
          value: _sigunguValue(catalog, sigunguOptions),
          hint: selectedSido == null
              ? '시·도를 먼저 선택하세요'
              : unavailableSelection
              ? '현재 선택을 확인할 수 없습니다'
              : null,
          items: [
            if (selectedSido != null)
              DropdownMenuItem(
                value: _allValue,
                child: Text('${selectedSido.sidoName} 전체'),
              ),
            for (final region in sigunguOptions)
              DropdownMenuItem(
                value: _sigunguKey(region),
                child: Text(
                  region.sigunguName.trim().isEmpty
                      ? '시·군·구 구분 없음'
                      : region.sigunguName,
                ),
              ),
          ],
          onChanged: selectedSido == null
              ? null
              : (value) => _selectSigungu(selectedSido, sigunguOptions, value),
        ),
        const SizedBox(height: 16),
        _RegionDropdown(
          key: regionDongDropdownKey,
          label: '읍·면·동',
          value: _dongValue(catalog, dongOptions),
          hint: selectedSigungu == null
              ? '시·군·구를 먼저 선택하세요'
              : unavailableSelection
              ? '현재 선택을 확인할 수 없습니다'
              : null,
          items: [
            if (selectedSigungu != null)
              DropdownMenuItem(
                value: _allValue,
                child: Text(
                  '${selectedSigungu.sigunguName.trim().isEmpty ? selectedSigungu.sidoName : selectedSigungu.sigunguName} 전체',
                ),
              ),
            for (final region in dongOptions)
              DropdownMenuItem(
                value: _dongKey(region),
                child: Text(region.dongName),
              ),
          ],
          onChanged: selectedSigungu == null
              ? null
              : (value) => _selectDong(selectedSigungu, dongOptions, value),
        ),
        if (unavailableSelection) ...[
          const SizedBox(height: 16),
          _Notice(
            icon: Icons.info_outline,
            message:
                '${_draftSelection!.pathLabel}은(는) 현재 매장 목록에서 선택할 수 없습니다. 다른 지역을 선택하거나 지역을 해제해 주세요.',
          ),
        ],
        if (catalog.missingRegionCount > 0) ...[
          const SizedBox(height: 16),
          _Notice(
            icon: Icons.location_off_outlined,
            message:
                '지역 미분류 매장 ${catalog.missingRegionCount}곳은 전체에서 확인할 수 있습니다.',
          ),
        ],
        if (catalog.sido.isEmpty) ...[
          const SizedBox(height: 16),
          const _Notice(
            icon: Icons.info_outline,
            message: '현재 선택 가능한 지역이 없습니다.',
          ),
        ],
      ],
    );
  }

  Widget _buildActions(BuildContext context, _RegionCatalog? catalog) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton(
                key: regionClearButtonKey,
                onPressed: () => Navigator.of(
                  context,
                ).pop(const RegionSelectionResult(selection: null)),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                child: const Text('지역 해제'),
              ),
              OutlinedButton(
                key: regionCancelButtonKey,
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(48, 48),
                ),
                child: const Text('취소'),
              ),
              FilledButton(
                key: regionApplyButtonKey,
                onPressed: catalog != null && _canApply(catalog)
                    ? () => _apply(context, catalog)
                    : null,
                style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                child: const Text('적용'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _sidoValue(_RegionCatalog catalog) {
    final selection = _draftSelection;
    if (selection == null) {
      return _allValue;
    }
    return catalog.sido.any(
          (region) => region.sidoCode == selection.region.sidoCode,
        )
        ? selection.region.sidoCode
        : null;
  }

  String? _sigunguValue(_RegionCatalog catalog, List<StoreRegion> options) {
    final selection = _draftSelection;
    if (selection == null || catalog.sidoFor(selection) == null) {
      return null;
    }
    if (selection.level == StoreRegionFilterLevel.sido) {
      return _allValue;
    }
    return options.any(
          (region) =>
              region.sigunguCode == selection.region.sigunguCode &&
              region.sidoCode == selection.region.sidoCode,
        )
        ? _sigunguKey(selection.region)
        : null;
  }

  String? _dongValue(_RegionCatalog catalog, List<StoreRegion> options) {
    final selection = _draftSelection;
    if (selection == null || catalog.sigunguFor(selection) == null) {
      return null;
    }
    if (selection.level == StoreRegionFilterLevel.sigungu) {
      return _allValue;
    }
    if (selection.level == StoreRegionFilterLevel.sido) {
      return null;
    }
    return options.any(
          (region) =>
              region.sidoCode == selection.region.sidoCode &&
              region.sigunguCode == selection.region.sigunguCode &&
              region.dongCode == selection.region.dongCode,
        )
        ? _dongKey(selection.region)
        : null;
  }

  void _selectSido(_RegionCatalog catalog, String? value) {
    if (value == null) {
      return;
    }
    setState(() {
      _draftSelection = value == _allValue
          ? null
          : StoreRegionFilter.sido(
              catalog.sido.firstWhere((region) => region.sidoCode == value),
            );
    });
  }

  void _selectSigungu(
    StoreRegion selectedSido,
    List<StoreRegion> options,
    String? value,
  ) {
    if (value == null) {
      return;
    }
    setState(() {
      _draftSelection = value == _allValue
          ? StoreRegionFilter.sido(selectedSido)
          : StoreRegionFilter.sigungu(
              options.firstWhere((region) => _sigunguKey(region) == value),
            );
    });
  }

  void _selectDong(
    StoreRegion selectedSigungu,
    List<StoreRegion> options,
    String? value,
  ) {
    if (value == null) {
      return;
    }
    setState(() {
      _draftSelection = value == _allValue
          ? StoreRegionFilter.sigungu(selectedSigungu)
          : StoreRegionFilter.dong(
              options.firstWhere((region) => _dongKey(region) == value),
            );
    });
  }

  bool _canApply(_RegionCatalog catalog) {
    return _draftSelection == null ||
        catalog.canonical(_draftSelection) != null;
  }

  void _apply(BuildContext context, _RegionCatalog catalog) {
    final selection = _draftSelection == null
        ? null
        : catalog.canonical(_draftSelection);
    Navigator.of(context).pop(RegionSelectionResult(selection: selection));
  }
}

class _RegionUnavailableContent extends StatelessWidget {
  const _RegionUnavailableContent();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Notice(
          icon: Icons.refresh,
          message: '매장 정보가 확인되면 지역을 선택할 수 있습니다. 조회 오류가 있으면 돌아가서 다시 시도해 주세요.',
        ),
        SizedBox(height: 20),
        _RegionDropdown(
          key: regionSidoDropdownKey,
          label: '시·도',
          hint: '지역 정보를 확인할 수 없습니다',
          items: [],
        ),
        SizedBox(height: 16),
        _RegionDropdown(
          key: regionSigunguDropdownKey,
          label: '시·군·구',
          hint: '지역 정보를 확인할 수 없습니다',
          items: [],
        ),
        SizedBox(height: 16),
        _RegionDropdown(
          key: regionDongDropdownKey,
          label: '읍·면·동',
          hint: '지역 정보를 확인할 수 없습니다',
          items: [],
        ),
      ],
    );
  }
}

class _RegionDropdown extends StatelessWidget {
  const _RegionDropdown({
    super.key,
    required this.label,
    required this.items,
    this.value,
    this.hint,
    this.onChanged,
  });

  final String label;
  final String? value;
  final String? hint;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        constraints: const BoxConstraints(minHeight: 56),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: hint == null ? null : Text(hint!),
          isExpanded: true,
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

final class _RegionCatalog {
  _RegionCatalog(List<StoreLocation> stores)
    : missingRegionCount = stores.where((store) => store.region == null).length,
      _regions = _uniqueRegions(stores);

  final int missingRegionCount;
  final List<StoreRegion> _regions;

  List<StoreRegion> get sido {
    final byCode = <String, StoreRegion>{};
    for (final region in _regions) {
      byCode.putIfAbsent(region.sidoCode, () => region);
    }
    return byCode.values.toList(growable: false)
      ..sort((left, right) => left.sidoName.compareTo(right.sidoName));
  }

  List<StoreRegion> sigunguForSido(String sidoCode) {
    final byPath = <String, StoreRegion>{};
    for (final region in _regions.where(
      (region) => region.sidoCode == sidoCode,
    )) {
      byPath.putIfAbsent(_sigunguKey(region), () => region);
    }
    return byPath.values.toList(growable: false)..sort((left, right) {
      final leftName = left.sigunguName.trim().isEmpty
          ? left.sidoName
          : left.sigunguName;
      final rightName = right.sigunguName.trim().isEmpty
          ? right.sidoName
          : right.sigunguName;
      return leftName.compareTo(rightName);
    });
  }

  List<StoreRegion> dongForSigungu(String sidoCode, String sigunguCode) {
    final byPath = <String, StoreRegion>{};
    for (final region in _regions.where(
      (region) =>
          region.sidoCode == sidoCode && region.sigunguCode == sigunguCode,
    )) {
      byPath.putIfAbsent(_dongKey(region), () => region);
    }
    return byPath.values.toList(growable: false)
      ..sort((left, right) => left.dongName.compareTo(right.dongName));
  }

  StoreRegion? sidoFor(StoreRegionFilter? selection) {
    if (selection == null) {
      return null;
    }
    return _firstWhereOrNull(
      sido,
      (region) => region.sidoCode == selection.region.sidoCode,
    );
  }

  StoreRegion? sigunguFor(StoreRegionFilter? selection) {
    if (selection == null || selection.level == StoreRegionFilterLevel.sido) {
      return null;
    }
    return _firstWhereOrNull(
      sigunguForSido(selection.region.sidoCode),
      (region) => region.sigunguCode == selection.region.sigunguCode,
    );
  }

  StoreRegionFilter? canonical(StoreRegionFilter? selection) {
    if (selection == null) {
      return null;
    }
    final match = _firstWhereOrNull(_regions, selection.matches);
    if (match == null) {
      return null;
    }
    return switch (selection.level) {
      StoreRegionFilterLevel.sido => StoreRegionFilter.sido(match),
      StoreRegionFilterLevel.sigungu => StoreRegionFilter.sigungu(match),
      StoreRegionFilterLevel.dong => StoreRegionFilter.dong(match),
    };
  }

  static List<StoreRegion> _uniqueRegions(List<StoreLocation> stores) {
    final byPath = <String, StoreRegion>{};
    for (final store in stores) {
      final region = store.region;
      if (region != null) {
        byPath.putIfAbsent(_dongKey(region), () => region);
      }
    }
    return List<StoreRegion>.unmodifiable(byPath.values);
  }
}

String _sigunguKey(StoreRegion region) =>
    '${region.sidoCode}/${region.sigunguCode}';

String _dongKey(StoreRegion region) =>
    '${region.sidoCode}/${region.sigunguCode}/${region.dongCode}';

T? _firstWhereOrNull<T>(Iterable<T> values, bool Function(T value) test) {
  for (final value in values) {
    if (test(value)) {
      return value;
    }
  }
  return null;
}
