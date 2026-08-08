import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/kuwait_governorates.dart';
import '../../models/delivery_zone.dart';
import '../../models/kitchen.dart';
import '../../services/admin_auth_service.dart';
import '../../services/api_service.dart';
import '../../services/kitchen_catalog_service.dart';
import '../../services/super_admin_scope_service.dart';

/// Admin UI for managing per-restaurant delivery zones and fees.
class AdminDeliveryZonesPanel extends StatefulWidget {
  const AdminDeliveryZonesPanel({
    super.key,
    this.restaurantId,
    this.canManage = true,
  });

  final String? restaurantId;
  final bool canManage;

  @override
  State<AdminDeliveryZonesPanel> createState() => _AdminDeliveryZonesPanelState();
}

class _AdminDeliveryZonesPanelState extends State<AdminDeliveryZonesPanel> {
  var _loading = true;
  var _refreshing = false;
  var _saving = false;
  List<DeliveryZone> _zones = [];
  List<Kitchen> _kitchens = const [];
  String? _error;

  static const _burgundy = Color(0xFF6B1124);

  @override
  void initState() {
    super.initState();
    KitchenCatalogService.instance.addListener(_onKitchenCatalogChanged);
    _loadZones();
  }

  @override
  void dispose() {
    KitchenCatalogService.instance.removeListener(_onKitchenCatalogChanged);
    super.dispose();
  }

  void _onKitchenCatalogChanged() {
    if (!mounted) return;
    setState(() {
      _kitchens = KitchenCatalogService.instance.kitchens;
    });
  }

  Future<void> _refreshKitchensForDialog() async {
    try {
      final kitchens = await ApiService.instance.fetchKitchens(
        restaurantId: _restaurantId,
        includeInactive: true,
      );
      if (!mounted) return;
      setState(() => _kitchens = kitchens);
      KitchenCatalogService.instance.publish(kitchens);
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant AdminDeliveryZonesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.restaurantId != widget.restaurantId ||
        oldWidget.canManage != widget.canManage) {
      _loadZones();
    }
  }

  String get _restaurantId =>
      widget.restaurantId ??
      AdminAuthService.instance.restaurantId ??
      SuperAdminScopeService.instance.effectiveRestaurantId;

  String get _restaurantLabel {
    if (AdminAuthService.instance.isSuperAdmin) {
      return SuperAdminScopeService.instance.selectedRestaurantName ??
          _restaurantId;
    }
    return AdminAuthService.instance.restaurantName ?? _restaurantId;
  }

  int _compareZones(DeliveryZone a, DeliveryZone b) {
    final gov = a.governorate.compareTo(b.governorate);
    if (gov != 0) return gov;
    return a.areaName.compareTo(b.areaName);
  }

  List<DeliveryZone> _sortedZones(Iterable<DeliveryZone> zones) {
    return zones.toList()..sort(_compareZones);
  }

  void _applyZonesLocally(List<DeliveryZone> zones, {String? error}) {
    if (!mounted) return;
    setState(() {
      _zones = _sortedZones(zones);
      _loading = false;
      _refreshing = false;
      if (error != null) _error = error;
    });
  }

  void _upsertZoneLocally(DeliveryZone zone) {
    if (zone.id.isEmpty) return;
    final next = [
      ..._zones.where((existing) => existing.id != zone.id),
      zone,
    ];
    _applyZonesLocally(next);
  }

  void _removeZoneLocally(String zoneId) {
    if (zoneId.isEmpty) return;
    _applyZonesLocally(
      _zones.where((zone) => zone.id != zoneId).toList(),
    );
  }

  void _applyKitchensLocally(List<Kitchen> kitchens) {
    if (!mounted) return;
    setState(() => _kitchens = kitchens);
  }

  Future<void> _loadZones({bool silent = false}) async {
    if (!widget.canManage) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _zones = [];
        _kitchens = const [];
        _error = null;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      if (silent) {
        _refreshing = true;
      } else {
        _loading = true;
        _error = null;
      }
    });

    try {
      List<DeliveryZone> zones = const [];
      List<Kitchen> kitchens = const [];
      Object? zonesError;
      Object? kitchensError;

      try {
        zones = await ApiService.instance.fetchDeliveryZones(
          restaurantId: _restaurantId,
          bustCache: true,
        );
      } catch (error) {
        zonesError = error;
      }

      try {
        kitchens = await ApiService.instance.fetchKitchens(
          restaurantId: _restaurantId,
          includeInactive: true,
        );
      } catch (error) {
        kitchensError = error;
      }

      if (!mounted) return;
      setState(() {
        if (zonesError == null) {
          _zones = _sortedZones(zones);
          _error = null;
        } else {
          _error = zonesError.toString().replaceFirst('Exception: ', '');
        }
        _kitchens = kitchens;
      });
      if (kitchens.isNotEmpty) {
        KitchenCatalogService.instance.publish(kitchens);
      }
      if (kitchensError != null && zonesError == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تعذر تحميل المطابخ — يمكنك إضافة مطبخ جديد أو إعادة المحاولة',
            ),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
      });
    }
  }

  Future<void> _showZoneDialog({DeliveryZone? existing}) async {
    if (!widget.canManage) return;

    await _refreshKitchensForDialog();

    var selectedGovernorate = existing?.governorate.isNotEmpty == true
        ? existing!.governorate
        : kuwaitGovernorates.first;
    final areaController = TextEditingController(text: existing?.areaName ?? '');
    final feeController = TextEditingController(
      text: existing != null ? existing.deliveryFee.toStringAsFixed(3) : '',
    );
    var selectedKitchenId = existing?.defaultKitchenId;
    if ((selectedKitchenId == null || selectedKitchenId.isEmpty) &&
        _kitchens.isNotEmpty) {
      selectedKitchenId = _kitchens
          .firstWhere(
            (kitchen) => kitchen.isDefault,
            orElse: () => _kitchens.first,
          )
          .id;
    }
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            existing == null ? 'إضافة منطقة توصيل' : 'تعديل منطقة التوصيل',
          ),
          content: SizedBox(
            width: 420,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: kuwaitGovernorates.contains(selectedGovernorate)
                        ? selectedGovernorate
                        : kuwaitGovernorates.first,
                    decoration: const InputDecoration(
                      labelText: 'المحافظة',
                      border: OutlineInputBorder(),
                    ),
                    items: kuwaitGovernorates
                        .map(
                          (gov) => DropdownMenuItem(value: gov, child: Text(gov)),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) selectedGovernorate = value;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: areaController,
                    decoration: const InputDecoration(
                      labelText: 'اسم المنطقة',
                      border: OutlineInputBorder(),
                      hintText: 'مثال: السالمية',
                    ),
                    validator: (value) =>
                        value == null || value.trim().isEmpty ? 'مطلوب' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: feeController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d{0,3}'),
                      ),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'رسوم التوصيل (د.ك)',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return 'مطلوب';
                      final parsed = double.tryParse(value.trim());
                      if (parsed == null || parsed < 0) return 'قيمة غير صالحة';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  if (_kitchens.isEmpty)
                    TextFormField(
                      enabled: false,
                      decoration: InputDecoration(
                        labelText: 'المطبخ *',
                        border: const OutlineInputBorder(),
                        helperText:
                            'أضف مطبخاً أولاً من تبويب المطبخ → إدارة المطابخ',
                        helperStyle: TextStyle(color: Colors.red.shade700),
                      ),
                    )
                  else
                    DropdownButtonFormField<String>(
                      value: _kitchens.any((kitchen) => kitchen.id == selectedKitchenId)
                          ? selectedKitchenId
                          : _kitchens.first.id,
                      decoration: const InputDecoration(
                        labelText: 'المطبخ *',
                        border: OutlineInputBorder(),
                      ),
                      items: _kitchens
                          .map(
                            (kitchen) => DropdownMenuItem<String>(
                              value: kitchen.id,
                              child: Text(
                                kitchen.nameAr.isNotEmpty
                                    ? kitchen.nameAr
                                    : kitchen.name,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setDialogState(() => selectedKitchenId = value),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'يجب اختيار مطبخ';
                        }
                        return null;
                      },
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() != true) return;
                Navigator.pop(context, true);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    if (saved != true || !mounted) {
      areaController.dispose();
      feeController.dispose();
      return;
    }

    if (_kitchens.isEmpty ||
        selectedKitchenId == null ||
        selectedKitchenId!.isEmpty) {
      areaController.dispose();
      feeController.dispose();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يجب إضافة مطبخ وربطه بالمنطقة قبل الحفظ'),
        ),
      );
      return;
    }

    final areaName = areaController.text.trim();
    final deliveryFee = double.parse(feeController.text.trim());
    areaController.dispose();
    feeController.dispose();

    setState(() => _saving = true);
    try {
      final draft = DeliveryZone(
        id: existing?.id ?? '',
        governorate: selectedGovernorate,
        areaName: areaName,
        deliveryFee: deliveryFee,
        restaurantId: _restaurantId,
        defaultKitchenId: selectedKitchenId,
      );

      final savedZone = existing == null
          ? await ApiService.instance.createDeliveryZone(draft)
          : await ApiService.instance.updateDeliveryZone(draft);

      if (!mounted) return;
      _upsertZoneLocally(savedZone);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            existing == null ? 'تمت إضافة المنطقة' : 'تم تحديث المنطقة',
          ),
        ),
      );
      unawaited(_loadZones(silent: true));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر حفظ المنطقة: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteZone(DeliveryZone zone) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف منطقة التوصيل'),
        content: Text('هل تريد حذف "${zone.areaName}" (${zone.governorate})؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await ApiService.instance.deleteDeliveryZone(zone.id);
      if (!mounted) return;
      _removeZoneLocally(zone.id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف المنطقة')),
      );
      unawaited(_loadZones(silent: true));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر حذف المنطقة: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keep scroll content outside Expanded (prevents blank panel on Flutter web).
    return ColoredBox(
      color: const Color(0xFFF4F6F8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight > 0 ? constraints.maxHeight - 48 : 400,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeaderCard(),
                  const SizedBox(height: 8),
                  const Text(
                    'عرض وتعديل رسوم التوصيل لكل محافظة ومنطقة في الكويت. '
                    'يجب ربط كل منطقة بمطبخ من تبويب المطبخ.',
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 16),
                  if (!widget.canManage)
                    _messageCard(
                      color: Colors.orange.shade50,
                      icon: Icons.store_outlined,
                      message:
                          'اختر مطعماً من القائمة أعلاه لإدارة مناطق التوصيل الخاصة به.',
                    )
                  else ...[
                    if (_refreshing)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: LinearProgressIndicator(minHeight: 2, color: _burgundy),
                      ),
                    _buildZonesSection(),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Card(
      color: _burgundy,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'مناطق التوصيل ورسومها',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.canManage
                        ? 'المطعم: $_restaurantLabel'
                        : 'اختر مطعماً لإدارة مناطق التوصيل',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                    ),
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
                onPressed: _saving ? null : () => _showZoneDialog(),
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text('Add New Zone'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildZonesSection() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator(color: _burgundy)),
      );
    }

    if (_error != null) {
      return _messageCard(
        icon: Icons.error_outline,
        message: 'تعذر تحميل مناطق التوصيل:\n$_error',
        action: OutlinedButton.icon(
          onPressed: () => _loadZones(),
          icon: const Icon(Icons.refresh),
          label: const Text('إعادة المحاولة'),
        ),
      );
    }

    if (_zones.isEmpty) {
      return _messageCard(
        icon: Icons.map_outlined,
        message:
            'لا توجد مناطق توصيل بعد.\nاضغط "إضافة منطقة جديدة" لبدء الإعداد.',
        action: FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: _burgundy),
          onPressed: _saving ? null : () => _showZoneDialog(),
          icon: const Icon(Icons.add),
          label: const Text('إضافة أول منطقة'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            for (var i = 0; i < _zones.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              _buildZoneTile(_zones[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _messageCard({
    Color? color,
    required IconData icon,
    required String message,
    Widget? action,
  }) {
    return Card(
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(icon, size: 48, color: Colors.grey.shade600),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (action != null) ...[
              const SizedBox(height: 16),
              action,
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildZoneTile(DeliveryZone zone) {
    String? kitchenLabel;
    for (final kitchen in _kitchens) {
      if (kitchen.id == zone.defaultKitchenId) {
        kitchenLabel =
            kitchen.nameAr.isNotEmpty ? kitchen.nameAr : kitchen.name;
        break;
      }
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      leading: CircleAvatar(
        backgroundColor: _burgundy.withOpacity(0.12),
        child: const Icon(Icons.location_on_outlined, color: _burgundy, size: 22),
      ),
      title: Text(zone.areaName, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(
        [
          zone.governorate,
          '${zone.deliveryFee.toStringAsFixed(3)} د.ك',
          if (kitchenLabel != null) kitchenLabel,
        ].join(' • '),
      ),
      trailing: Wrap(
        spacing: 0,
        children: [
          IconButton(
            tooltip: 'تعديل',
            onPressed: _saving ? null : () => _showZoneDialog(existing: zone),
            icon: const Icon(Icons.edit_outlined, color: _burgundy),
          ),
          IconButton(
            tooltip: 'حذف',
            onPressed: _saving ? null : () => _deleteZone(zone),
            icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
          ),
        ],
      ),
    );
  }
}
