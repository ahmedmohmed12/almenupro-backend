import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/kuwait_governorates.dart';
import '../../models/delivery_zone.dart';
import '../../services/api_service.dart';
import '../../services/super_admin_scope_service.dart';
import 'admin_breakpoints.dart';

class AdminDeliveryZonesPanel extends StatefulWidget {
  const AdminDeliveryZonesPanel({super.key});

  @override
  State<AdminDeliveryZonesPanel> createState() => _AdminDeliveryZonesPanelState();
}

class _AdminDeliveryZonesPanelState extends State<AdminDeliveryZonesPanel> {
  var _loading = true;
  var _saving = false;
  List<DeliveryZone> _zones = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadZones();
    SuperAdminScopeService.instance.addListener(_onScopeChanged);
  }

  @override
  void dispose() {
    SuperAdminScopeService.instance.removeListener(_onScopeChanged);
    super.dispose();
  }

  void _onScopeChanged() {
    _loadZones();
  }

  Future<void> _loadZones() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final zones = await ApiService.instance.fetchDeliveryZones();
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
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _showZoneDialog({DeliveryZone? existing}) async {
    final governorateController = TextEditingController(text: existing?.governorate ?? '');
    final areaController = TextEditingController(text: existing?.areaName ?? '');
    final feeController = TextEditingController(
      text: existing != null ? existing.deliveryFee.toStringAsFixed(3) : '',
    );
    var selectedGovernorate = existing?.governorate.isNotEmpty == true
        ? existing!.governorate
        : kuwaitGovernorates.first;
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
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
                        .map(
                          (gov) => DropdownMenuItem(value: gov, child: Text(gov)),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        selectedGovernorate = value;
                        governorateController.text = value;
                      }
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
        );
      },
    );

    if (saved != true || !mounted) {
      governorateController.dispose();
      areaController.dispose();
      feeController.dispose();
      return;
    }

    setState(() => _saving = true);
    try {
      final zone = DeliveryZone(
        id: existing?.id ?? '',
        governorate: selectedGovernorate,
        areaName: areaController.text.trim(),
        deliveryFee: double.parse(feeController.text.trim()),
        restaurantId: ApiService.defaultRestaurantId,
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
      governorateController.dispose();
      areaController.dispose();
      feeController.dispose();
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
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
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
    final padding = AdminBreakpoints.pagePadding(context);

    return Padding(
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'مناطق التوصيل ورسومها',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF6B1124),
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'حدد المحافظة والمنطقة ورسوم التوصيل لكل منطقة في الكويت.',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _saving ? null : () => _showZoneDialog(),
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text('إضافة منطقة'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : _zones.isEmpty
                        ? const Center(
                            child: Text(
                              'لا توجد مناطق توصيل بعد. أضف المحافظة والمنطقة ورسوم التوصيل.',
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.separated(
                            itemCount: _zones.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final zone = _zones[index];
                              return Card(
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor:
                                        const Color(0xFF6B1124).withValues(alpha: 0.12),
                                    child: const Icon(
                                      Icons.location_on_outlined,
                                      color: Color(0xFF6B1124),
                                    ),
                                  ),
                                  title: Text(
                                    zone.areaName,
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Text(zone.governorate),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '${zone.deliveryFee.toStringAsFixed(3)} د.ك',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFFD49A00),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'تعديل',
                                        onPressed: _saving
                                            ? null
                                            : () => _showZoneDialog(existing: zone),
                                        icon: const Icon(Icons.edit_outlined),
                                      ),
                                      IconButton(
                                        tooltip: 'حذف',
                                        onPressed:
                                            _saving ? null : () => _deleteZone(zone),
                                        icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
