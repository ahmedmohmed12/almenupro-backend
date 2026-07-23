import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/cart_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/whatsapp_launcher.dart';

class MenuCheckoutSheet extends StatefulWidget {
  const MenuCheckoutSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.brandSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const MenuCheckoutSheet(),
    );
  }

  @override
  State<MenuCheckoutSheet> createState() => _MenuCheckoutSheetState();
}

class _MenuCheckoutSheetState extends State<MenuCheckoutSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  var _paymentMethod = 'كاش';
  var _submitting = false;

  static const _whatsappNumber = '96594774950';

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _submit(CartProvider cart) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);

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

    final message = '''
🧾 *فاتورة طلب جديدة - Molten Cookies*
----------------------------------
📌 *رقم الفاتورة:* #$invoiceNumber
👤 *اسم العميل:* ${_nameController.text.trim()}
📞 *رقم الهاتف:* ${_phoneController.text.trim()}
📍 *عنوان التوصيل:* ${_addressController.text.trim()}
💳 *طريقة الدفع:* $_paymentMethod

🕒 *وقت الطلب:* $orderTime
⏳ *الوقت المتوقع للتوصيل:* $expectedTime

🛒 *تفاصيل الطلب:*
$itemsDetails
----------------------------------
💰 *الإجمالي النهائي:* ${cart.totalPrice.toStringAsFixed(3)} د.ك
----------------------------------
شكراً لطلبكم من مولتن كوكيز! ❤️
''';

    final opened = await openWhatsAppChat(
      phone: _whatsappNumber,
      message: message,
    );

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

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
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
                        'سلة المشتريات',
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
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _addressController,
                      decoration: const InputDecoration(
                        labelText: 'عنوان التوصيل',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty ? 'مطلوب' : null,
                    ),
                    const SizedBox(height: 12),
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
                          'إرسال الطلب ${cart.totalPrice.toStringAsFixed(3)} د.ك',
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
