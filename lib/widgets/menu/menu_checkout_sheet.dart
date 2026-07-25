import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/kuwait_governorates.dart';
import '../../models/customer_restaurant_context.dart';
import '../../models/delivery_address_details.dart';
import '../../models/delivery_zone.dart';
import '../../providers/cart_provider.dart';
import '../../services/api_service.dart';
import '../../services/orders_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/whatsapp_launcher.dart';

class MenuCheckoutSheet extends StatefulWidget {
  const MenuCheckoutSheet({super.key, this.restaurantContext});

  final CustomerRestaurantContext? restaurantContext;

  static Future<void> show(
    BuildContext context, {
    CustomerRestaurantContext? restaurantContext,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.brandSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => MenuCheckoutSheet(restaurantContext: restaurantContext),
    );
  }

  @override
  State<MenuCheckoutSheet> createState() => _MenuCheckoutSheetState();
}

class _MenuCheckoutSheetState extends State<MenuCheckoutSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _blockController = TextEditingController();
  final _streetController = TextEditingController();
  final _avenueController = TextEditingController();
  final _houseController = TextEditingController();
  final _floorController = TextEditingController();

  var _paymentMethod = 'كاش';
  var _submitting = false;
  var _loadingZones = true;

  List<DeliveryZone> _zones = [];
  String? _selectedGovernorate;
  DeliveryZone? _selectedZone;

  static const _defaultWhatsappNumber = '96594774950';

  String get _restaurantName =>
      widget.restaurantContext?.name ?? 'Molten Cookies';

  String get _whatsappNumber =>
      widget.restaurantContext?.whatsappNumber ?? _defaultWhatsappNumber;

  String get _restaurantId =>
      widget.restaurantContext?.id ?? ApiService.defaultRestaurantId;

  String? get _restaurantSlug => widget.restaurantContext?.slug;

  double get _deliveryFee => _selectedZone?.deliveryFee ?? 0;

  List<String> get _availableGovernorates {
    if (_zones.isEmpty) return kuwaitGovernorates;
    final fromZones = _zones.map((zone) => zone.governorate).toSet().toList()
      ..sort();
    return fromZones;
  }

  List<DeliveryZone> get _areasForGovernorate {
    if (_selectedGovernorate == null) return const [];
    return _zones
        .where((zone) => zone.governorate == _selectedGovernorate)
        .toList()
      ..sort((a, b) => a.areaName.compareTo(b.areaName));
  }

  DeliveryAddressDetails get _addressDetails => DeliveryAddressDetails(
        block: _blockController.text.trim(),
        street: _streetController.text.trim(),
        avenue: _avenueController.text.trim(),
        houseNumber: _houseController.text.trim(),
        floorApartment: _floorController.text.trim(),
      );

  String get _formattedAddress {
    if (_selectedZone != null) {
      return _addressDetails.formatArabic(
        governorate: _selectedZone!.governorate,
        areaName: _selectedZone!.areaName,
      );
    }
    return _addressDetails.formatArabic(
      governorate: _selectedGovernorate ?? '',
      areaName: '',
    );
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadDeliveryZones());
  }

  Future<void> _loadDeliveryZones() async {
    try {
      final zones = await ApiService.instance.fetchDeliveryZones(
        slug: _restaurantSlug,
        restaurantId: _restaurantId,
      );
      if (!mounted) return;
      setState(() {
        _zones = zones;
        _loadingZones = false;
        if (_availableGovernorates.isNotEmpty) {
          _selectedGovernorate ??= _availableGovernorates.first;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingZones = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _blockController.dispose();
    _streetController.dispose();
    _avenueController.dispose();
    _houseController.dispose();
    _floorController.dispose();
    super.dispose();
  }

  Future<void> _submit(CartProvider cart) async {
    if (!_formKey.currentState!.validate()) return;
    if (_zones.isNotEmpty && _selectedZone == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار المحافظة والمنطقة')),
      );
      return;
    }

    setState(() => _submitting = true);

    final subtotal = cart.totalPrice;
    final grandTotal = subtotal + _deliveryFee;
    final invoiceNumber = DateTime.now().millisecondsSinceEpoch.toString().substring(5);
    final now = DateTime.now();
    final orderTime =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final expected = now.add(const Duration(minutes: 45));
    final expectedTime =
        '${expected.hour.toString().padLeft(2, '0')}:${expected.minute.toString().padLeft(2, '0')}';

    final itemsDetails = StringBuffer();
    for (final item in cart.items) {
      itemsDetails.writeln(
        '• ${item.menuItem.name} x${item.quantity} (${item.totalPrice.toStringAsFixed(3)} د.ك)',
      );
    }

    final address = _formattedAddress;
    final message = '''
🧾 *فاتورة طلب جديدة - $_restaurantName*
----------------------------------
📌 *رقم الفاتورة:* #$invoiceNumber
👤 *اسم العميل:* ${_nameController.text.trim()}
📞 *رقم الهاتف:* ${_phoneController.text.trim()}
📍 *عنوان التوصيل:* $address
🚚 *رسوم التوصيل:* ${_deliveryFee.toStringAsFixed(3)} د.ك
💳 *طريقة الدفع:* $_paymentMethod

🕒 *وقت الطلب:* $orderTime
⏳ *الوقت المتوقع للتوصيل:* $expectedTime

🛒 *تفاصيل الطلب:*
$itemsDetails
----------------------------------
🧮 *المجموع الفرعي:* ${subtotal.toStringAsFixed(3)} د.ك
🚚 *التوصيل:* ${_deliveryFee.toStringAsFixed(3)} د.ك
💰 *الإجمالي النهائي:* ${grandTotal.toStringAsFixed(3)} د.ك
----------------------------------
شكراً لطلبكم من $_restaurantName! ❤️
''';

    final opened = await openWhatsAppChat(
      phone: _whatsappNumber,
      message: message,
    );

    if (opened) {
      try {
        await OrdersService.instance.submitOrderFromCart(
          cartItems: List.from(cart.items),
          customerName: _nameController.text.trim(),
          phone: _phoneController.text.trim(),
          address: address,
          paymentMethod: _paymentMethod,
          invoiceNumber: invoiceNumber,
          restaurantId: _restaurantId,
          deliveryFee: _deliveryFee,
          governorate: _selectedZone?.governorate ?? _selectedGovernorate,
          areaName: _selectedZone?.areaName,
          deliveryZoneId: _selectedZone?.id,
          addressDetails: _addressDetails,
        );
      } catch (error) {
        debugPrint('Order backend sync failed: $error');
      }
    }

    if (!mounted) return;

    setState(() => _submitting = false);

    if (opened) {
      cart.clear();
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إرسال الطلب عبر الواتساب')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تعذر فتح الواتساب. رقم المطعم: $_whatsappNumber',
          ),
        ),
      );
    }
  }

  Widget _buildTotals(CartProvider cart) {
    final subtotal = cart.totalPrice;
    final grandTotal = subtotal + _deliveryFee;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          _TotalRow(label: 'المجموع الفرعي', value: subtotal),
          const SizedBox(height: 6),
          _TotalRow(
            label: 'رسوم التوصيل',
            value: _deliveryFee,
            highlight: _selectedZone != null,
          ),
          const Divider(height: 20),
          _TotalRow(
            label: 'الإجمالي النهائي',
            value: grandTotal,
            isBold: true,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final grandTotal = cart.totalPrice + _deliveryFee;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.92,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'إتمام الطلب',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.brandMaroon,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    ...cart.items.map(
                      (item) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(item.menuItem.name),
                        subtitle: Text('${item.unitPrice.toStringAsFixed(3)} د.ك'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: () => cart.updateQuantity(
                                item.id,
                                item.quantity - 1,
                              ),
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                            Text('${item.quantity}'),
                            IconButton(
                              onPressed: () => cart.updateQuantity(
                                item.id,
                                item.quantity + 1,
                              ),
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 32),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'اسم العميل',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty ? 'مطلوب' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'رقم الهاتف',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty ? 'مطلوب' : null,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'عنوان التوصيل',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.brandMaroon,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_loadingZones)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: LinearProgressIndicator(),
                      )
                    else ...[
                      DropdownButtonFormField<String>(
                        initialValue: _selectedGovernorate,
                        decoration: const InputDecoration(
                          labelText: 'المحافظة',
                          border: OutlineInputBorder(),
                        ),
                        items: _availableGovernorates
                            .map(
                              (gov) => DropdownMenuItem(
                                value: gov,
                                child: Text(gov),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedGovernorate = value;
                            _selectedZone = null;
                          });
                        },
                        validator: (value) {
                          if (_zones.isEmpty) return null;
                          return value == null || value.isEmpty ? 'مطلوب' : null;
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedZone?.id,
                        decoration: InputDecoration(
                          labelText: 'المنطقة',
                          border: const OutlineInputBorder(),
                          helperText: _areasForGovernorate.isEmpty &&
                                  _selectedGovernorate != null
                              ? 'لا توجد مناطق لهذه المحافظة'
                              : null,
                        ),
                        items: _areasForGovernorate
                            .map(
                              (zone) => DropdownMenuItem(
                                value: zone.id,
                                child: Text(
                                  '${zone.areaName} (${zone.deliveryFee.toStringAsFixed(3)} د.ك)',
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: _areasForGovernorate.isEmpty
                            ? null
                            : (value) {
                                setState(() {
                                  _selectedZone = _areasForGovernorate.firstWhere(
                                    (zone) => zone.id == value,
                                  );
                                });
                              },
                        validator: (value) {
                          if (_zones.isEmpty) return null;
                          return value == null || value.isEmpty ? 'مطلوب' : null;
                        },
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _blockController,
                      decoration: const InputDecoration(
                        labelText: 'القطعة (Block)',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty ? 'مطلوب' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _streetController,
                      decoration: const InputDecoration(
                        labelText: 'الشارع (Street)',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty ? 'مطلوب' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _avenueController,
                      decoration: const InputDecoration(
                        labelText: 'الجادة (Avenue) — اختياري',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _houseController,
                      decoration: const InputDecoration(
                        labelText: 'رقم البيت / المبنى',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty ? 'مطلوب' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _floorController,
                      decoration: const InputDecoration(
                        labelText: 'الطابق / الشقة — اختياري',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _paymentMethod,
                      decoration: const InputDecoration(
                        labelText: 'طريقة الدفع',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'كاش', child: Text('كاش')),
                        DropdownMenuItem(value: 'K-Net', child: Text('K-Net')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _paymentMethod = value);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildTotals(cart),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.brandMaroon,
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: _submitting ? null : () => _submit(cart),
                  child: _submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'إرسال الطلب ${grandTotal.toStringAsFixed(3)} د.ك',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.value,
    this.isBold = false,
    this.highlight = false,
  });

  final String label;
  final double value;
  final bool isBold;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: highlight ? AppTheme.brandMaroon : Colors.black87,
            ),
          ),
        ),
        Text(
          '${value.toStringAsFixed(3)} د.ك',
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: isBold ? AppTheme.brandMaroon : Colors.black87,
          ),
        ),
      ],
    );
  }
}
