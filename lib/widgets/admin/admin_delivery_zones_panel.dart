import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/kuwait_governorates.dart';
import '../../models/delivery_zone.dart';
import '../../services/admin_auth_service.dart';
import '../../services/api_service.dart';
import '../../services/super_admin_scope_service.dart';

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
  var _saving = false;
  List<DeliveryZone> _zones = [];
  String? _error;

  static const _burgundy = Color(0xFF6B1124);
  static const _gold = Color(0xFFD49A00);

  @override
  void initState() {
    super.initState();
    _loadZones();
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
      SuperAdminScopeService.instance.effectiveRestaurantId;

  String get _restaurantLabel {
    if (AdminAuthService.instance.isSuperAdmin) {
      return SuperAdminScopeService.instance.selectedRestaurantName ??
          _restaurantId;
    }
    return AdminAuthService.instance.restaurantName ?? _restaurantId;
  }

  Future<void> _loadZones() async {
    if (!widget.canManage) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _zones = [];
        _error = null;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final zones = await ApiService.instance.fetchDeliveryZones(
        restaurantId: _restaurantId,
      );
      if (!mounted) return;
      setState(() {
        _zones = zones
          ..sort((a, b) {
            final gov = a.governorate.compareTo(b.governorate);
            if (gov != 0) return gov;
            return a.areaName.compareTo(b.areaName);
          });
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _showZoneDialog({DeliveryZone? existing}) async {
    if (!widget.canManage) return;

    var selectedGovernorate = existing?.governorate.isNotEmpty == true
        ? existing!.governorate
        : kuwaitGovernorates.first;
    final areaController = TextEditingController(text: existing?.areaName ?? '');
    final feeController = TextEditingController(
      text: existing != null ? existing.deliveryFee.toStringAsFixed(3) : '',
    );
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'إضافة منطقة توصيل' : 'تعديل منطقة التوصيل'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: kuwaitGovernorates.contains(selectedGovernorate)
                      ? selectedGovernorate
                      : kuwaitGovernorates.first,
                  decoration: const InputDecoration(
                    labelText: 'المحافظة',
                    border: OutlineInputBorder(),
                  ),
                  items: kuwaitGovernorates
                      .map((gov) => DropdownMenuItem(value: gov, child: Text(gov)))
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
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
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
    );

    if (saved != true || !mounted) {
      areaController.dispose();
      feeController.dispose();
      return;
    }

    final areaName = areaController.text.trim();
    final deliveryFee = double.parse(feeController.text.trim());
    areaController.dispose();
    feeController.dispose();

    setState(() => _saving = true);
    try {
      final zone = DeliveryZone(
        id: existing?.id ?? '',
        governorate: selectedGovernorate,
        areaName: areaName,
        deliveryFee: deliveryFee,
        restaurantId: _restaurantId,
      );

      if (existing == null) {
        await ApiService.instance.createDeliveryZone(zone);
      } else {
        await ApiService.instance.updateDeliveryZone(zone);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(existing == null ? 'تمت إضافة المنطقة' : 'تم تحديث المنطقة'),
        ),
      );
      await _loadZones();
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف المنطقة')),
      );
      await _loadZones();
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
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'مناطق التوصيل ورسومها',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: _burgundy,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'عرض وتعديل رسوم التوصيل لكل محافظة ومنطقة في الكويت.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 12),
          if (!widget.canManage)
            Card(
              color: Colors.orange.shade50,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'اختر مطعماً من القائمة أعلاه لإدارة مناطق التوصيل الخاصة به.',
                  style: TextStyle(color: Colors.black87),
                ),
              ),
            )
          else ...[
            Text(
              'المطعم الحالي: $_restaurantLabel',
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: _burgundy),
                onPressed: _saving ? null : () => _showZoneDialog(),
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text('إضافة منطقة جديدة'),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (!widget.canManage) {
      return _statusCard(
        icon: Icons.store_outlined,
        message: 'يرجى اختيار مطعم أولاً لعرض مناطق التوصيل.',
      );
    }

    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: _burgundy),
      );
    }

    if (_error != null) {
      return _statusCard(
        icon: Icons.error_outline,
        message: 'تعذر تحميل مناطق التوصيل:\n$_error',
        action: OutlinedButton.icon(
          onPressed: _loadZones,
          icon: const Icon(Icons.refresh),
          label: const Text('إعادة المحاولة'),
        ),
      );
    }

    if (_zones.isEmpty) {
      return _statusCard(
        icon: Icons.map_outlined,
        message: 'لا توجد مناطق توصيل بعد.\nاضغط "إضافة منطقة جديدة" لبدء الإعداد.',
        action: FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: _burgundy),
          onPressed: _saving ? null : () => _showZoneDialog(),
          icon: const Icon(Icons.add),
          label: const Text('إضافة أول منطقة'),
        ),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 720) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: _buildZonesTable(),
              ),
            );
          }
          return ListView.separated(
            itemCount: _zones.length,
            separatorBuilder: (_, index) => const Divider(height: 1),
            itemBuilder: (context, index) => _buildZoneTile(_zones[index]),
          );
        },
      ),
    );
  }

  Widget _statusCard({
    required IconData icon,
    required String message,
    Widget? action,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: Colors.grey.shade500),
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

  Widget _buildZonesTable() {
    return DataTable(
      headingRowColor: WidgetStateProperty.all(_burgundy.withValues(alpha: 0.08)),
      columns: const [
        DataColumn(label: Text('المحافظة', style: TextStyle(fontWeight: FontWeight.bold))),
        DataColumn(label: Text('المنطقة', style: TextStyle(fontWeight: FontWeight.bold))),
        DataColumn(label: Text('رسوم التوصيل', style: TextStyle(fontWeight: FontWeight.bold))),
        DataColumn(label: Text('إجراءات', style: TextStyle(fontWeight: FontWeight.bold))),
      ],
      rows: _zones.map((zone) {
        return DataRow(
          cells: [
            DataCell(Text(zone.governorate)),
            DataCell(Text(zone.areaName)),
            DataCell(
              Text(
                '${zone.deliveryFee.toStringAsFixed(3)} د.ك',
                style: const TextStyle(fontWeight: FontWeight.bold, color: _gold),
              ),
            ),
            DataCell(
              Row(
                mainAxisSize: MainAxisSize.min,
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
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildZoneTile(DeliveryZone zone) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: _burgundy.withValues(alpha: 0.12),
        child: const Icon(Icons.location_on_outlined, color: _burgundy),
      ),
      title: Text(zone.areaName, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(zone.governorate),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${zone.deliveryFee.toStringAsFixed(3)} د.ك',
            style: const TextStyle(fontWeight: FontWeight.bold, color: _gold),
          ),
          IconButton(
            tooltip: 'تعديل',
            onPressed: _saving ? null : () => _showZoneDialog(existing: zone),
            icon: const Icon(Icons.edit_outlined),
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
