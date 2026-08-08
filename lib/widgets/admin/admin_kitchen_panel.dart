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

/// Kitchen operational view (KDS) — pending + completed orders per kitchen.
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

  static const _activeStatuses = {
    OrderStatus.pending,
    OrderStatus.confirmed,
    OrderStatus.preparing,
    OrderStatus.ready,
  };

  static const _completedStatuses = {
    OrderStatus.delivered,
    OrderStatus.cancelled,
  };

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
        if (_filterKitchenId == null && kitchens.isNotEmpty) {
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

  bool _matchesKitchen(Order order) {
    if (_filterKitchenId == null || _filterKitchenId!.isEmpty) return false;
    return order.targetKitchenId == _filterKitchenId;
  }

  List<Order> _filterOrders(List<Order> orders, Set<OrderStatus> statuses) {
    return orders
        .where((order) => statuses.contains(order.status) && _matchesKitchen(order))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<Order> _pendingOrders(List<Order> orders) {
    final active = orders
        .where((order) => _activeStatuses.contains(order.status) && _matchesKitchen(order))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return active;
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
        final pendingOrders = _pendingOrders(orders);
        final completedOrders = _filterOrders(orders, _completedStatuses);
        final pendingCount =
            orders.where((o) => o.status == OrderStatus.pending).length;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleKitchenSnapshot(pendingOrders);
        });

        if (_loadingKitchens) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF6B1124)),
          );
        }

        if (_kitchens.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                s.kitchenSetupRequired,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 16),
              ),
            ),
          );
        }

        return ColoredBox(
          color: const Color(0xFFF4F6F8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              IncomingOrdersAlertBar(
                pendingCount: pendingCount,
                kitchenCount: pendingOrders.length,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.kitchenMonitorTitle,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF6B1124),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      s.kitchenMonitorSubtitle,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _filterKitchenId,
                      decoration: InputDecoration(
                        labelText: s.kitchenSelectLabel,
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      items: _kitchens
                          .map(
                            (kitchen) => DropdownMenuItem<String>(
                              value: kitchen.id,
                              child: Text(kitchen.localizedName(s.localeCode)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => _filterKitchenId = value),
                    ),
                    if (_filterKitchenId != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${s.kitchenActiveLabel}: ${_kitchenLabel(_filterKitchenId, s)}',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: _filterKitchenId == null
                    ? Center(child: Text(s.kitchenSelectPrompt))
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        children: [
                          _SectionHeader(
                            title: s.kitchenPendingTitle,
                            count: pendingOrders.length,
                            color: const Color(0xFFD49A00),
                          ),
                          if (pendingOrders.isEmpty)
                            _EmptySection(message: s.kitchenPendingEmpty)
                          else
                            ...pendingOrders.map(
                              (order) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _KitchenTicketCard(
                                  order: order,
                                  timeLabel:
                                      dateFormat.format(order.createdAt.toLocal()),
                                  strings: s,
                                  onStatus: _updateStatus,
                                ),
                              ),
                            ),
                          const SizedBox(height: 20),
                          _SectionHeader(
                            title: s.kitchenCompletedTitle,
                            count: completedOrders.length,
                            color: Colors.green.shade700,
                          ),
                          if (completedOrders.isEmpty)
                            _EmptySection(message: s.kitchenCompletedEmpty)
                          else
                            ...completedOrders.take(40).map(
                              (order) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _KitchenTicketCard(
                                  order: order,
                                  timeLabel:
                                      dateFormat.format(order.createdAt.toLocal()),
                                  strings: s,
                                  readOnly: true,
                                  onStatus: _updateStatus,
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    required this.color,
  });

  final String title;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 22,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Color(0xFF6B1124),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 12,
            backgroundColor: color.withValues(alpha: 0.15),
            child: Text(
              '$count',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptySection extends StatelessWidget {
  const _EmptySection({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey.shade600),
      ),
    );
  }
}

class _KitchenTicketCard extends StatelessWidget {
  const _KitchenTicketCard({
    required this.order,
    required this.timeLabel,
    required this.strings,
    required this.onStatus,
    this.readOnly = false,
  });

  final Order order;
  final String timeLabel;
  final AppStrings strings;
  final Future<void> Function(Order order, OrderStatus status) onStatus;
  final bool readOnly;

  OrderStatus? get _nextStatus {
    return switch (order.status) {
      OrderStatus.pending => OrderStatus.confirmed,
      OrderStatus.confirmed => OrderStatus.preparing,
      OrderStatus.preparing => OrderStatus.ready,
      OrderStatus.ready => OrderStatus.delivered,
      _ => null,
    };
  }

  String? get _nextLabel {
    return switch (order.status) {
      OrderStatus.pending => strings.kitchenAcceptOrder,
      OrderStatus.confirmed => strings.kitchenStartPrep,
      OrderStatus.preparing => strings.markReady,
      OrderStatus.ready => strings.markDelivered,
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final items = order.items
        .map((item) => '${item.quantity}× ${item.name}')
        .join('\n');
    final nextStatus = _nextStatus;
    final nextLabel = _nextLabel;

    return Card(
      elevation: readOnly ? 0 : 2,
      color: readOnly ? Colors.grey.shade50 : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: readOnly
              ? Colors.grey.shade300
              : order.status == OrderStatus.preparing
                  ? const Color(0xFFD49A00)
                  : Colors.green.shade400,
          width: readOnly ? 1 : 2,
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
                  if (!readOnly && PosPrintHelper.canPrint)
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
                  _Chip(
                    label: '${strings.kitchenCashierLabel}: ${order.receivedByLabel}',
                    color: const Color(0xFF475569),
                  ),
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
              if (!readOnly && nextStatus != null && nextLabel != null) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6B1124),
                    ),
                    onPressed: () => onStatus(order, nextStatus),
                    child: Text(
                      nextLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
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
