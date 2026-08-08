import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/order.dart';
import 'order_status_chip.dart';

Future<void> showOrderInvoiceDetailDialog(
  BuildContext context, {
  required Order order,
  VoidCallback? onChanged,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('فاتورة #${order.invoiceNumber ?? order.id.substring(0, 6)}'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${order.customerName} — ${order.phone}'),
            const SizedBox(height: 8),
            OrderStatusChip(status: order.status),
            if (order.targetKitchenName != null &&
                order.targetKitchenName!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('المطبخ: ${order.targetKitchenName}'),
            ],
            const SizedBox(height: 12),
            ...order.items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('${item.quantity}× ${item.name}'),
              ),
            ),
            const Divider(height: 20),
            Text(
              'الإجمالي: ${order.totalPrice.toStringAsFixed(3)} د.ك',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              DateFormat('yyyy-MM-dd HH:mm').format(order.createdAt.toLocal()),
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إغلاق'),
        ),
      ],
    ),
  );
}
