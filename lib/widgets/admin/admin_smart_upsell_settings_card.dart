import 'package:flutter/material.dart';

import '../../services/restaurant_settings_service.dart';
import '../../services/super_admin_scope_service.dart';

class AdminSmartUpsellSettingsCard extends StatefulWidget {
  const AdminSmartUpsellSettingsCard({super.key});

  @override
  State<AdminSmartUpsellSettingsCard> createState() =>
      _AdminSmartUpsellSettingsCardState();
}

class _AdminSmartUpsellSettingsCardState
    extends State<AdminSmartUpsellSettingsCard> {
  static const burgundy = Color(0xFF6B1124);

  final _thresholdController = TextEditingController();
  final _maxPriceController = TextEditingController();
  var _enabled = true;
  var _loading = true;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _thresholdController.dispose();
    _maxPriceController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final settings = await RestaurantSettingsService.instance.load(
        restaurantId: SuperAdminScopeService.instance.effectiveRestaurantId,
      );
      _enabled = settings.smartUpsellEnabled;
      _thresholdController.text = settings.freeDeliveryThreshold > 0
          ? settings.freeDeliveryThreshold.toStringAsFixed(3)
          : '';
      _maxPriceController.text = settings.impulseBumpMaxPrice.toStringAsFixed(3);
    } catch (_) {
      _enabled = true;
      _thresholdController.clear();
      _maxPriceController.text = '2.000';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final threshold = double.tryParse(_thresholdController.text.trim()) ?? 0;
      final maxPrice = double.tryParse(_maxPriceController.text.trim()) ?? 2;

      await RestaurantSettingsService.instance.saveUpsellSettings(
        smartUpsellEnabled: _enabled,
        freeDeliveryThreshold: threshold,
        impulseBumpMaxPrice: maxPrice,
        restaurantId: SuperAdminScopeService.instance.effectiveRestaurantId,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ إعدادات البياع الشاطر')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر الحفظ: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: burgundy))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'البياع الشاطر — المرحلة 1',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: burgundy,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'اضبط حد التوصيل المجاني واقتراحات اللحظة الأخيرة في شاشة الدفع.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF666666)),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('تفعيل البياع الشاطر'),
                    value: _enabled,
                    onChanged: (value) => setState(() => _enabled = value),
                  ),
                  TextField(
                    controller: _thresholdController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'حد التوصيل المجاني (د.ك)',
                      helperText: 'اتركه فارغاً أو 0 لتعطيل شريط التقدم',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _maxPriceController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'أقصى سعر لاقتراحات الدفع السريع (د.ك)',
                      helperText:
                          'يُستخدم لاختيار مشروبات/صوصات تلقائياً إذا لم تُحدد أصنافاً',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: burgundy),
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('حفظ إعدادات البياع الشاطر'),
                  ),
                ],
              ),
      ),
    );
  }
}
