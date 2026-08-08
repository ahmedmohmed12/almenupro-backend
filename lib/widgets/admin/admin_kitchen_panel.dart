import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_strings.dart';
import '../../l10n/strings_admin.dart';
import '../../l10n/strings_pos.dart';
import '../../models/kitchen.dart';
import '../../models/order.dart';
import '../../services/admin_auth_service.dart';
import '../../services/api_service.dart';
import '../../services/admin_order_monitor_service.dart';
import '../../services/orders_service.dart';
import '../../services/pos_print_helper.dart';
import '../../utils/order_sound.dart';
import '../../utils/pos_receipt_html.dart';
import 'incoming_orders_alert_bar.dart';
import 'order_invoice_detail_dialog.dart';
import 'order_status_chip.dart';

/// Live kitchen queue — auto-refreshes with the shared 3s order monitor.
class AdminKitchenPanel extends StatefulWidget {
  const AdminKitchenPanel({super.key});

  @override
  State<AdminKitchenPanel> createState() => _AdminKitchenPanelState();
}

class _AdminKitchenPanelState extends State<AdminKitchenPanel> {
  final _ordersService = OrdersService.instance;
  final Set<String> _knownKitchenIds = {};
  var _initialized = false;
  List<Kitchen> _kitchens = const [];
  String? _filterKitchenId;
  var _loadingKitchens = true;

  @override
  void initState() {
    super.initState();
    _loadKitchens();
  }

  Future<void> _loadKitchens() async {
    try {
      final restaurantId =
          AdminAuthService.instance.restaurantId ?? ApiService.defaultRestaurantId;
      final kitchens = await ApiService.instance.fetchKitchens(
        restaurantId: restaurantId,
        allowCashier: true,
      );
      if (!mounted) return;
      setState(() {
        _kitchens = kitchens;
        _loadingKitchens = false;
        if (_filterKitchenId == null && kitchens.length == 1) {
          _filterKitchenId = kitchens.first.id;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingKitchens = false);
    }
  }

  Future<void> _updateStatus(Order order, OrderStatus status) async {
    try {
      await _ordersService.updateOrderStatus(order.id, status);
      if (!mounted) return;
      await AdminOrderMonitorService.instance.acknowledgeOrder(order.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم التحديث: ${status.arabicLabel}')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تحديث الطلب: $error')),
      );
    }
  }

  void _handleKitchenSnapshot(List<Order> kitchenOrders) {
    final ids = kitchenOrders.map((o) => o.id).toSet();
    if (!_initialized) {
      _knownKitchenIds
        ..clear()
        ..addAll(ids);
      _initialized = true;
      return;
    }

    for (final order in kitchenOrders) {
      if (_knownKitchenIds.contains(order.id)) continue;
      _knownKitchenIds.add(order.id);
      playNewOrderSound();
      if (!mounted) continue;
      final s = AppStrings.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF6B1124),
          duration: const Duration(seconds: 4),
          content: Text(
            '🍲 ${s.newKitchenTicket} '
            '#${order.invoiceNumber ?? order.id.substring(0, 6)} — ${order.customerName}',
          ),
        ),
      );
    }

    _knownKitchenIds
      ..clear()
      ..addAll(ids);
  }

  List<Order> _kitchenQueue(List<Order> orders) {
    Iterable<Order> result = orders.where(
      (o) =>
          o.status == OrderStatus.preparing || o.status == OrderStatus.ready,
    );
    if (_filterKitchenId != null && _filterKitchenId!.isNotEmpty) {
      result = result.where(
        (o) => o.targetKitchenId == _filterKitchenId,
      );
    }
    return result.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  String _kitchenLabel(String? kitchenId, AppStrings s) {
    if (kitchenId == null || kitchenId.isEmpty) return s.unassignedKitchen;
    for (final kitchen in _kitchens) {
      if (kitchen.id == kitchenId) {
        return kitchen.localizedName(s.localeCode);
      }
    }
    return kitchenId;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final dateFormat = DateFormat('HH:mm');

    return StreamBuilder<List<Order>>(
      stream: _ordersService.watchOrders(),
      builder: (context, snapshot) {
        final orders = snapshot.data ?? [];
        final kitchenOrders = _kitchenQueue(orders);
        final pendingCount =
            orders.where((o) => o.status == OrderStatus.pending).length;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleKitchenSnapshot(kitchenOrders);
        });

        return ColoredBox(
          color: const Color(0xFFF4F6F8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              IncomingOrdersAlertBar(
                pendingCount: pendingCount,
                kitchenCount: kitchenOrders.length,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.kitchenMonitorTitle,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF6B1124),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      s.kitchenMonitorSubtitle,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    if (_kitchens.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilterChip(
                            label: Text(s.posAllKitchens),
                            selected: _filterKitchenId == null,
                            onSelected: _loadingKitchens
                                ? null
                                : (_) => setState(() => _filterKitchenId = null),
                            selectedColor:
                                const Color(0xFF6B1124).withValues(alpha: 0.15),
                            checkmarkColor: const Color(0xFF6B1124),
                          ),
                          ..._kitchens.map(
                            (kitchen) => FilterChip(
                              label: Text(kitchen.localizedName(s.localeCode)),
                              selected: _filterKitchenId == kitchen.id,
                              onSelected: _loadingKitchens
                                  ? null
                                  : (_) => setState(
                                        () => _filterKitchenId = kitchen.id,
                                      ),
                              selectedColor:
                                  const Color(0xFF6B1124).withValues(alpha: 0.15),
                              checkmarkColor: const Color(0xFF6B1124),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String?>(
                        value: _filterKitchenId,
                        decoration: InputDecoration(
                          labelText: s.posAllKitchens,
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text(s.posAllKitchens),
                          ),
                          ..._kitchens.map(
                            (kitchen) => DropdownMenuItem<String?>(
                              value: kitchen.id,
                              child: Text(kitchen.localizedName(s.localeCode)),
                            ),
                          ),
                        ],
                        onChanged: _loadingKitchens
                            ? null
                            : (value) => setState(() => _filterKitchenId = value),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: kitchenOrders.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.soup_kitchen_outlined,
                                size: 56,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                s.kitchenEmptyTitle,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF6B1124),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                s.kitchenEmptyHint,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: kitchenOrders.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final order = kitchenOrders[index];
                          return _KitchenTicketCard(
                            order: order,
                            timeLabel: dateFormat.format(order.createdAt.toLocal()),
                            strings: s,
                            onReady: () => _updateStatus(order, OrderStatus.ready),
                            onDelivered: () =>
                                _updateStatus(order, OrderStatus.delivered),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _KitchenTicketCard extends StatelessWidget {
  const _KitchenTicketCard({
    required this.order,
    required this.timeLabel,
    required this.strings,
    required this.onReady,
    required this.onDelivered,
  });

  final Order order;
  final String timeLabel;
  final AppStrings strings;
  final VoidCallback onReady;
  final VoidCallback onDelivered;

  @override
  Widget build(BuildContext context) {
    final items = order.items
        .map((item) => '${item.quantity}× ${item.name}')
        .join('\n');

    return Card(
      elevation: 2,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: order.status == OrderStatus.preparing
              ? const Color(0xFFD49A00)
              : Colors.green.shade400,
          width: 2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showOrderInvoiceDetailDialog(context, order: order),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '#${order.invoiceNumber ?? order.id.substring(0, 6)} — ${order.customerName}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  OrderStatusChip(status: order.status),
                  if (PosPrintHelper.canPrint)
                    IconButton(
                      tooltip: strings.quickPrintKitchen,
                      visualDensity: VisualDensity.compact,
                      onPressed: () async {
                        try {
                          await PosPrintHelper.printOrder(
                            order: order,
                            kind: PosReceiptKind.kitchen,
                          );
                        } catch (_) {}
                      },
                      icon: const Icon(Icons.print_outlined, size: 20),
                    ),
                ],
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _Chip(
                  label: order.orderType.labelAr,
                  color: const Color(0xFF6B1124),
                ),
                if (order.targetKitchenName != null &&
                    order.targetKitchenName!.isNotEmpty)
                  _Chip(
                    label: order.targetKitchenName!,
                    color: Colors.deepOrange.shade700,
                  ),
                _Chip(
                  label: order.sourceLabelAr,
                  color: const Color(0xFFD49A00),
                ),
                _Chip(label: timeLabel, color: Colors.blueGrey),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              items,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            ),
            for (final item in order.items)
              if ((item.specialNotes ?? '').trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'ملاحظة: ${item.specialNotes}',
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: () {},
              child: Row(
                children: [
                  if (order.status == OrderStatus.preparing)
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                          ),
                          onPressed: onReady,
                          child: Text(
                            strings.markReady,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (order.status == OrderStatus.preparing)
                    const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6B1124),
                        ),
                        onPressed: onDelivered,
                        child: Text(
                          strings.markDelivered,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
