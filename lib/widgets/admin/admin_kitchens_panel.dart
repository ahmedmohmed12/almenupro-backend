import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../l10n/strings_admin.dart';
import '../../models/kitchen.dart';
import '../../services/admin_auth_service.dart';
import '../../services/api_service.dart';
import '../../services/kitchen_catalog_service.dart';
import '../../services/super_admin_scope_service.dart';

class AdminKitchensPanel extends StatefulWidget {
  const AdminKitchensPanel({
    super.key,
    this.restaurantId,
    this.canManage = true,
    this.onKitchensChanged,
  });

  final String? restaurantId;
  final bool canManage;
  final ValueChanged<List<Kitchen>>? onKitchensChanged;

  @override
  State<AdminKitchensPanel> createState() => _AdminKitchensPanelState();
}

class _AdminKitchensPanelState extends State<AdminKitchensPanel> {
  var _loading = true;
  var _refreshing = false;
  var _saving = false;
  List<Kitchen> _kitchens = const [];
  String? _error;

  static const _burgundy = Color(0xFF6B1124);

  String get _restaurantId =>
      widget.restaurantId ??
      AdminAuthService.instance.restaurantId ??
      SuperAdminScopeService.instance.effectiveRestaurantId;

  @override
  void initState() {
    super.initState();
    _load(silent: false);
  }

  void _publishKitchens(List<Kitchen> kitchens) {
    widget.onKitchensChanged?.call(kitchens);
    KitchenCatalogService.instance.publish(kitchens);
  }

  void _upsertKitchenLocally(Kitchen kitchen) {
    if (kitchen.id.isEmpty) return;
    final next = [
      ..._kitchens.where((existing) => existing.id != kitchen.id),
      kitchen,
    ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    if (!mounted) return;
    setState(() {
      _kitchens = next;
      _loading = false;
      _refreshing = false;
    });
    _publishKitchens(next);
  }

  Future<void> _load({required bool silent}) async {
    if (!widget.canManage) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _kitchens = const [];
      });
      _publishKitchens(const []);
      return;
    }

    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else if (mounted) {
      setState(() => _refreshing = true);
    }

    try {
      final kitchens = await ApiService.instance.fetchKitchens(
        restaurantId: _restaurantId,
        includeInactive: true,
      );
      if (!mounted) return;
      setState(() {
        _kitchens = kitchens;
        _loading = false;
        _refreshing = false;
        _error = null;
      });
      _publishKitchens(kitchens);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _loading = false;
        _refreshing = false;
      });
    }
  }

  Future<void> _showKitchenDialog({Kitchen? existing}) async {
    final s = AppStrings.of(context);
    final nameArController =
        TextEditingController(text: existing?.nameAr ?? existing?.name ?? '');
    final nameEnController = TextEditingController(text: existing?.nameEn ?? '');
    final codeController = TextEditingController(text: existing?.code ?? '');
    var isDefault = existing?.isDefault ?? false;
    var status = existing?.status ?? KitchenStatus.active;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? s.navKitchens : s.kitchensPanelTitle),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameArController,
                  decoration: const InputDecoration(
                    labelText: 'اسم المطبخ (عربي)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: nameEnController,
                  decoration: const InputDecoration(
                    labelText: 'Kitchen name (English)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: codeController,
                  decoration: const InputDecoration(
                    labelText: 'Code',
                    border: OutlineInputBorder(),
                    hintText: 'ARD',
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<KitchenStatus>(
                  initialValue: status,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    border: OutlineInputBorder(),
                  ),
                  items: KitchenStatus.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.apiValue),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setDialogState(() => status = value);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title:
                      Text(s.isArabic ? 'المطبخ الافتراضي' : 'Default kitchen'),
                  value: isDefault,
                  onChanged: (value) => setDialogState(() => isDefault = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(s.save),
            ),
          ],
        ),
      ),
    );

    final nameAr = nameArController.text.trim();
    final nameEn = nameEnController.text.trim();
    final code = codeController.text.trim();
    nameArController.dispose();
    nameEnController.dispose();
    codeController.dispose();

    if (saved != true || !mounted || nameAr.isEmpty) return;

    setState(() => _saving = true);
    try {
      final kitchen = Kitchen(
        id: existing?.id ?? '',
        name: nameAr,
        nameAr: nameAr,
        nameEn: nameEn,
        code: code,
        status: status,
        isDefault: isDefault,
        restaurantId: _restaurantId,
      );
      final savedKitchen = await ApiService.instance.saveKitchen(
        kitchen: kitchen,
        restaurantId: _restaurantId,
      );
      if (!mounted) return;
      _upsertKitchenLocally(savedKitchen);
      unawaited(_load(silent: true));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteKitchen(Kitchen kitchen) async {
    final s = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.delete),
        content: Text(s.deleteKitchenConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await ApiService.instance.deleteKitchen(kitchen.id);
      if (!mounted) return;
      setState(() {
        _kitchens = _kitchens.where((entry) => entry.id != kitchen.id).toList();
      });
      _publishKitchens(_kitchens);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.isArabic ? 'تم حذف المطبخ' : 'Kitchen deleted')),
      );
      unawaited(_load(silent: true));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          color: const Color(0xFF6B1124),
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.kitchensPanelTitle,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        s.kitchensPanelSubtitle,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
                      ),
                    ],
                  ),
                ),
                if (widget.canManage)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: _burgundy,
                    ),
                    onPressed: _saving ? null : () => _showKitchenDialog(),
                    icon: const Icon(Icons.add),
                    label: Text(s.isArabic ? 'إضافة مطبخ جديد' : 'Add new kitchen'),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_refreshing)
          const LinearProgressIndicator(minHeight: 2, color: _burgundy),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: MaterialBanner(
              backgroundColor: Colors.red.shade50,
              content: Text(_error!),
              actions: [
                TextButton(onPressed: () => _load(silent: false), child: Text(s.retry)),
              ],
            ),
          ),
        if (_loading)
          const Center(child: CircularProgressIndicator(color: _burgundy))
        else if (_kitchens.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.soup_kitchen_outlined,
                    size: 48,
                    color: _burgundy.withValues(alpha: 0.7),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    s.isArabic ? 'لا توجد مطابخ بعد' : 'No kitchens yet',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    s.isArabic
                        ? 'أنشئ مطبخك الأول لربطه بمناطق التوصيل وشاشة KDS'
                        : 'Create your first kitchen to link delivery zones and KDS',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 16),
                  if (widget.canManage)
                    FilledButton.icon(
                      onPressed: _saving ? null : () => _showKitchenDialog(),
                      icon: const Icon(Icons.add),
                      label: Text(s.isArabic ? 'إضافة مطبخ جديد' : 'Add new kitchen'),
                    ),
                ],
              ),
            ),
          )
        else
          ..._kitchens.map(
            (kitchen) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: _burgundy.withValues(alpha: 0.1),
                  child: Icon(
                    Icons.soup_kitchen,
                    color: _burgundy.withValues(alpha: 0.9),
                  ),
                ),
                title: Text(kitchen.localizedName(s.localeCode)),
                subtitle: Text(
                  '${kitchen.code.isNotEmpty ? '${kitchen.code} · ' : ''}'
                  '${kitchen.status.apiValue}'
                  '${kitchen.isDefault ? (s.isArabic ? ' · افتراضي' : ' · default') : ''}',
                ),
                trailing: widget.canManage
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: _saving
                                ? null
                                : () => _showKitchenDialog(existing: kitchen),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: _saving
                                ? null
                                : () => _deleteKitchen(kitchen),
                          ),
                        ],
                      )
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}
