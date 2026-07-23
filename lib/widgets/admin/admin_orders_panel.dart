import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/order.dart';
import '../../services/firebase_service.dart';
import '../../utils/order_sound.dart';
import 'order_status_chip.dart';

class AdminOrdersPanel extends StatefulWidget {
  const AdminOrdersPanel({
    super.key,
    this.onPendingCountChanged,
  });

  final ValueChanged<int>? onPendingCountChanged;

  @override
  State<AdminOrdersPanel> createState() => _AdminOrdersPanelState();
}

class _AdminOrdersPanelState extends State<AdminOrdersPanel> {
  final _firebaseService = FirebaseService();
  final Set<String> _knownOrderIds = {};
  var _initialized = false;

  Future<void> _updateStatus(String orderId, OrderStatus status) async {
    try {
      await _firebaseService.updateOrderStatus(orderId, status);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم تحديث الحالة: ${status.arabicLabel}')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تحديث الطلب: $error')),
      );
    }
  }

  void _handleOrdersUpdate(List<Order> orders) {
    final pendingCount =
        orders.where((order) => order.status == OrderStatus.pending).length;
    widget.onPendingCountChanged?.call(pendingCount);

    if (!_initialized) {
      _knownOrderIds
        ..clear()
        ..addAll(orders.map((order) => order.id));
      _initialized = true;
      return;
    }

    for (final order in orders) {
      if (order.status != OrderStatus.pending) continue;
      if (_knownOrderIds.contains(order.id)) continue;

      _knownOrderIds.add(order.id);
      playNewOrderSound();

      if (!mounted) continue;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 4),
          content: Text(
            '🔔 طلب جديد #${order.invoiceNumber ?? order.id.substring(0, 6)} '
            'من ${order.customerName}',
          ),
        ),
      );
    }

    _knownOrderIds
      ..clear()
      ..addAll(orders.map((order) => order.id));
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('d/M • HH:mm');

    return StreamBuilder<List<Order>>(
      stream: _firebaseService.watchOrders(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('خطأ في تحميل الطلبات: ${snapshot.error}'));
        }

        final orders = snapshot.data ?? [];
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleOrdersUpdate(orders);
        });

        if (orders.isEmpty) {
          return const Center(
            child: Text(
              'لا توجد طلبات حتى الآن.\n'
              'ستظهر الطلبات هنا فور إرسال العميل عبر الواتساب.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: orders.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final order = orders[index];
            return _AdminOrderCard(
              order: order,
              dateFormat: dateFormat,
              onStatusChanged: _updateStatus,
            );
          },
        );
      },
    );
  }
}

class _AdminOrderCard extends StatelessWidget {
  const _AdminOrderCard({
    required this.order,
    required this.dateFormat,
    required this.onStatusChanged,
  });

  final Order order;
  final DateFormat dateFormat;
  final Future<void> Function(String orderId, OrderStatus status) onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final itemLines = order.items
        .map(
          (item) =>
              '${item.quantity}x ${item.name} (${item.lineTotal.toStringAsFixed(3)} د.ك)',
        )
        .join('\n');
    final nextStatus = order.status.nextStatus;
    final nextLabel = order.status.nextActionLabel;

    return Card(
      elevation: order.status == OrderStatus.pending ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: order.status == OrderStatus.pending
            ? BorderSide(color: Colors.green.shade400, width: 2)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.customerName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'فاتورة #${order.invoiceNumber ?? order.id.substring(0, 6)}',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
                OrderStatusChip(status: order.status),
              ],
            ),
            const SizedBox(height: 12),
            _InfoRow(icon: Icons.phone, text: order.phone),
            _InfoRow(icon: Icons.location_on, text: order.address),
            if (order.paymentMethod != null && order.paymentMethod!.isNotEmpty)
              _InfoRow(icon: Icons.payment, text: order.paymentMethod!),
            const SizedBox(height: 10),
            Text(
              itemLines,
              style: TextStyle(color: Colors.grey.shade800, height: 1.5),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '${order.totalPrice.toStringAsFixed(3)} د.ك',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.brown,
                  ),
                ),
                const Spacer(),
                Text(
                  dateFormat.format(order.createdAt.toLocal()),
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
            ),
            if (nextStatus != null && nextLabel != null) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _actionColor(order.status),
                  ),
                  onPressed: () => onStatusChanged(order.id, nextStatus),
                  icon: const Icon(Icons.check_circle, color: Colors.white),
                  label: Text(
                    nextLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _actionColor(OrderStatus status) {
    return switch (status) {
      OrderStatus.pending => Colors.green.shade700,
      OrderStatus.confirmed => Colors.orange.shade700,
      OrderStatus.preparing => Colors.blue.shade700,
      _ => Colors.brown,
    };
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.brown),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
