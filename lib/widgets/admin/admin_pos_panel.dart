import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/kuwait_governorates.dart';
import '../../models/cart_item.dart';
import '../../models/customer.dart';
import '../../models/customer_checkout_profile.dart';
import '../../models/delivery_address_details.dart';
import '../../models/delivery_zone.dart';
import '../../models/menu_item.dart';
import '../../models/order.dart';
import '../../services/admin_auth_service.dart';
import '../../services/api_service.dart';
import '../../services/customer_checkout_cache_service.dart';
import '../../services/orders_service.dart';
import '../../services/orders_demo_service.dart';
import '../../services/pos_print_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/pos_receipt_html.dart';
import '../../utils/whatsapp_phone.dart';
import '../menu/customization_dialog.dart';
import '../network_menu_image.dart';

class AdminPosPanel extends StatefulWidget {
  const AdminPosPanel({
    super.key,
    this.onOrderSubmitted,
  });

  final VoidCallback? onOrderSubmitted;

  @override
  State<AdminPosPanel> createState() => _AdminPosPanelState();
}

class _PosPageData {
  const _PosPageData({
    required this.items,
    required this.zones,
    required this.topItemIds,
  });

  final List<MenuItem> items;
  final List<DeliveryZone> zones;
  final List<int> topItemIds;
}

class _AdminPosPanelState extends State<AdminPosPanel> {
  static const _allCategory = 'الكل';
  static const _topCategory = 'الأكثر مبيعاً 🔥';

  late Future<_PosPageData> _pageFuture;
  final _formKey = GlobalKey<FormState>();
  final _searchController = TextEditingController();
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  final _blockController = TextEditingController();
  final _streetController = TextEditingController();
  final _avenueController = TextEditingController();
  final _houseController = TextEditingController();
  final _floorController = TextEditingController();

  final List<CartItem> _cart = [];
  Timer? _lookupDebounce;
  String? _lastLookupPhone;
  var _lookupInProgress = false;
  var _submitting = false;
  var _isPickup = false;
  String _selectedCategory = _allCategory;
  String _paymentMethod = 'كاش';
  String? _selectedGovernorate;
  DeliveryZone? _selectedZone;
  List<DeliveryZone> _zones = const [];
  List<Order> _recentOrders = const [];
  int _customerOrderCount = 0;

  String get _restaurantId =>
      AdminAuthService.instance.restaurantId ?? ApiService.defaultRestaurantId;

  String get _restaurantName =>
      AdminAuthService.instance.restaurantName ?? 'المطعم';

  double get _subtotal =>
      _cart.fold(0.0, (sum, item) => sum + item.totalPrice);

  double get _deliveryFee =>
      _isPickup ? 0 : (_selectedZone?.deliveryFee ?? 0);

  double get _grandTotal => _subtotal + _deliveryFee;

  @override
  void initState() {
    super.initState();
    _pageFuture = _loadPage();
    _phoneController.addListener(_onPhoneChanged);
  }

  @override
  void dispose() {
    _lookupDebounce?.cancel();
    _phoneController.removeListener(_onPhoneChanged);
    _searchController.dispose();
    _phoneController.dispose();
    _nameController.dispose();
    _blockController.dispose();
    _streetController.dispose();
    _avenueController.dispose();
    _houseController.dispose();
    _floorController.dispose();
    super.dispose();
  }

  Future<_PosPageData> _loadPage() async {
    final results = await Future.wait([
      ApiService.instance.fetchPublicItems(restaurantId: _restaurantId),
      ApiService.instance.fetchDeliveryZones(restaurantId: _restaurantId),
      ApiService.instance.fetchTopMenuItemIds(restaurantId: _restaurantId),
    ]);

    final items = (results[0] as List<MenuItem>)
        .where((item) => item.isAvailable)
        .toList();
    final zones = results[1] as List<DeliveryZone>;
    final topItemIds = results[2] as List<int>;

    _zones = zones;
    if (_selectedGovernorate == null && zones.isNotEmpty) {
      _selectedGovernorate = zones.first.governorate;
    }
    _syncDefaultArea();

    return _PosPageData(
      items: items,
      zones: zones,
      topItemIds: topItemIds,
    );
  }

  Future<void> _reload() async {
    setState(() => _pageFuture = _loadPage());
    await _pageFuture;
  }

  bool _isStaticPicksCategory(String category) {
    final value = category.trim().toLowerCase();
    return value.contains('ذوقك') || value.contains('picks for you');
  }

  List<String> _categories(List<MenuItem> items, List<int> topItemIds) {
    final categories = <String>[_allCategory];
    if (topItemIds.isNotEmpty) categories.add(_topCategory);
    for (final item in items) {
      final category = item.categoryName.trim();
      if (category.isEmpty || _isStaticPicksCategory(category)) continue;
      if (!categories.contains(category)) categories.add(category);
    }
    return categories;
  }

  List<MenuItem> _filteredMenuItems(
    List<MenuItem> items,
    List<int> topItemIds,
  ) {
    final query = _searchController.text.trim().toLowerCase();
    Iterable<MenuItem> result = items;

    if (_selectedCategory == _topCategory) {
      final byId = {for (final item in items) item.id: item};
      result = topItemIds.map((id) => byId[id]).whereType<MenuItem>();
    } else if (_selectedCategory != _allCategory) {
      result = items.where(
        (item) => item.categoryName.trim() == _selectedCategory,
      );
    }

    if (query.isNotEmpty) {
      result = result.where(
        (item) =>
            item.name.toLowerCase().contains(query) ||
            item.nameAr.toLowerCase().contains(query) ||
            item.nameEn.toLowerCase().contains(query),
      );
    }

    return result.toList();
  }

  List<String> get _availableGovernorates {
    if (_zones.isEmpty) return kuwaitGovernorates;
    return _zones.map((zone) => zone.governorate).toSet().toList()..sort();
  }

  List<DeliveryZone> get _areasForGovernorate {
    if (_selectedGovernorate == null) return const [];
    return _zones
        .where((zone) => zone.governorate == _selectedGovernorate)
        .toList()
      ..sort((a, b) => a.areaName.compareTo(b.areaName));
  }

  void _syncDefaultArea() {
    if (_zones.isEmpty) {
      _selectedZone = null;
      return;
    }
    final areas = _areasForGovernorate;
    if (areas.isEmpty) {
      _selectedZone = null;
      return;
    }
    final currentIsValid = _selectedZone != null &&
        areas.any((zone) => zone.id == _selectedZone!.id);
    if (!currentIsValid) _selectedZone = areas.first;
  }

  DeliveryAddressDetails get _addressDetails => DeliveryAddressDetails(
        block: _blockController.text.trim(),
        street: _streetController.text.trim(),
        avenue: _avenueController.text.trim(),
        houseNumber: _houseController.text.trim(),
        floorApartment: _floorController.text.trim(),
      );

  String _formattedAddress() {
    return _addressDetails.formatArabic(
      governorate: _selectedZone?.governorate ?? _selectedGovernorate ?? '',
      areaName: _selectedZone?.areaName ?? '',
    );
  }

  void _onPhoneChanged() {
    final digits = WhatsAppPhone.digitsOnly(_phoneController.text);
    if (digits.length < 8) {
      _lookupDebounce?.cancel();
      setState(() {
        _recentOrders = const [];
        _customerOrderCount = 0;
      });
      return;
    }
    if (digits == _lastLookupPhone) return;
    _lookupDebounce?.cancel();
    _lookupDebounce = Timer(const Duration(milliseconds: 600), () {
      unawaited(_lookupCustomer(digits));
    });
  }

  Future<void> _lookupCustomer(String normalizedPhone) async {
    if (_lookupInProgress && _lastLookupPhone == normalizedPhone) return;
    setState(() {
      _lookupInProgress = true;
      _lastLookupPhone = normalizedPhone;
    });

    try {
      var profile = await CustomerCheckoutCacheService.instance.loadProfile(
        _restaurantId,
        normalizedPhone,
      );
      profile ??= await ApiService.instance.fetchCustomerCheckoutProfile(
        phone: normalizedPhone,
        restaurantId: _restaurantId,
      );

      if (profile != null && profile.hasUsableData) {
        await CustomerCheckoutCacheService.instance.saveProfile(
          _restaurantId,
          profile,
        );
        _applyProfile(profile);
      }

      if (profile?.customerId != null && profile!.customerId!.isNotEmpty) {
        final detail = await ApiService.instance.fetchCustomerDetail(
          profile.customerId!,
          restaurantId: _restaurantId,
        );
        if (!mounted) return;
        setState(() {
          _recentOrders = _parseOrders(detail).take(5).toList();
          _customerOrderCount = detail.customer.totalOrders;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _recentOrders = const [];
          _customerOrderCount = 0;
        });
      }
    } finally {
      if (mounted) setState(() => _lookupInProgress = false);
    }
  }

  List<Order> _parseOrders(CustomerDetailData detail) {
    return detail.rawOrders
        .map(
          (raw) => Order.fromMap(
            raw['id']?.toString() ?? '',
            raw,
          ),
        )
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  void _applyProfile(CustomerCheckoutProfile profile) {
    if (profile.customerName.trim().isNotEmpty) {
      _nameController.text = profile.customerName.trim();
    }
    _blockController.text = profile.addressDetails.block;
    _streetController.text = profile.addressDetails.street;
    _avenueController.text = profile.addressDetails.avenue;
    _houseController.text = profile.addressDetails.houseNumber;
    _floorController.text = profile.addressDetails.floorApartment;

    if (profile.governorate.trim().isNotEmpty) {
      _selectedGovernorate = profile.governorate.trim();
    }

    DeliveryZone? matchedZone;
    final zoneId = profile.deliveryZoneId?.trim();
    if (zoneId != null && zoneId.isNotEmpty) {
      for (final zone in _zones) {
        if (zone.id == zoneId) {
          matchedZone = zone;
          break;
        }
      }
    }

    if (matchedZone == null && profile.areaName.trim().isNotEmpty) {
      for (final zone in _zones) {
        final sameArea = zone.areaName.trim() == profile.areaName.trim();
        final sameGov = profile.governorate.isEmpty ||
            zone.governorate.trim() == profile.governorate.trim();
        if (sameArea && sameGov) {
          matchedZone = zone;
          break;
        }
      }
    }

    if (matchedZone != null) {
      _selectedGovernorate = matchedZone.governorate;
      _selectedZone = matchedZone;
    } else {
      _syncDefaultArea();
    }

    if (profile.paymentMethod.trim().isNotEmpty) {
      _paymentMethod = profile.paymentMethod.trim();
    }

    setState(() {});
  }

  Future<void> _handleMenuItemTap(MenuItem item) async {
    if (item.hasCustomizations) {
      await showCustomizationDialog(
        context,
        item,
        onAdd: (cartItem) {
          setState(() => _cart.add(cartItem));
        },
      );
      return;
    }
    _addToCart(item);
  }

  void _addToCart(MenuItem item) {
    setState(() {
      final index = _cart.indexWhere(
        (entry) =>
            entry.menuItem.id == item.id && entry.selectedOptions.isEmpty,
      );
      if (index >= 0) {
        final existing = _cart[index];
        _cart[index] = existing.copyWith(quantity: existing.quantity + 1);
      } else {
        _cart.add(
          CartItem(
            id: '${item.id}_${DateTime.now().microsecondsSinceEpoch}',
            menuItem: item,
            selectedOptions: const [],
            quantity: 1,
          ),
        );
      }
    });
  }

  void _updateCartQuantity(String cartItemId, int quantity) {
    setState(() {
      if (quantity <= 0) {
        _cart.removeWhere((item) => item.id == cartItemId);
        return;
      }
      final index = _cart.indexWhere((item) => item.id == cartItemId);
      if (index == -1) return;
      _cart[index] = _cart[index].copyWith(quantity: quantity);
    });
  }

  void _clearCart() {
    setState(_cart.clear);
  }

  bool _validateOrder() {
    if (_cart.isEmpty) {
      _showMessage('أضف أصنافاً إلى الطلب أولاً');
      return false;
    }
    if (!(_formKey.currentState?.validate() ?? false)) {
      _showMessage('يرجى إدخال اسم العميل ورقم الهاتف');
      return false;
    }
    if (!_isPickup && _zones.isNotEmpty && _selectedZone == null) {
      _showMessage('يرجى اختيار منطقة التوصيل');
      return false;
    }
    return true;
  }

  Future<Order?> _submitOrder() async {
    if (!_validateOrder()) return null;
    setState(() => _submitting = true);

    try {
      final invoiceNumber =
          DateTime.now().millisecondsSinceEpoch.toString().substring(5);
      await OrdersService.instance.submitOrderFromCart(
        cartItems: List.from(_cart),
        customerName: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        address: _isPickup ? 'استلام من المحل' : _formattedAddress(),
        paymentMethod: _paymentMethod,
        invoiceNumber: invoiceNumber,
        restaurantId: _restaurantId,
        deliveryFee: _deliveryFee,
        governorate: _isPickup ? null : _selectedZone?.governorate,
        areaName: _isPickup ? null : _selectedZone?.areaName,
        deliveryZoneId: _isPickup ? null : _selectedZone?.id,
        addressDetails: _isPickup ? const DeliveryAddressDetails() : _addressDetails,
        orderSource: 'pos',
        orderType: _isPickup ? OrderType.pickup : OrderType.delivery,
      );

      await CustomerCheckoutCacheService.instance.saveProfile(
        _restaurantId,
        CustomerCheckoutProfile(
          phone: _phoneController.text.trim(),
          customerName: _nameController.text.trim(),
          governorate: _selectedZone?.governorate ?? _selectedGovernorate ?? '',
          areaName: _selectedZone?.areaName ?? '',
          deliveryZoneId: _selectedZone?.id,
          addressDetails: _isPickup ? const DeliveryAddressDetails() : _addressDetails,
          paymentMethod: _paymentMethod,
        ),
      );

      final order = OrdersDemoService.orderFromCart(
        cartItems: List.from(_cart),
        customerName: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        address: _isPickup ? 'استلام من المحل' : _formattedAddress(),
        paymentMethod: _paymentMethod,
        invoiceNumber: invoiceNumber,
        deliveryFee: _deliveryFee,
        governorate: _isPickup ? null : _selectedZone?.governorate,
        areaName: _isPickup ? null : _selectedZone?.areaName,
        deliveryZoneId: _isPickup ? null : _selectedZone?.id,
        addressDetails: _isPickup ? const DeliveryAddressDetails() : _addressDetails,
        orderSource: 'pos',
        orderType: _isPickup ? OrderType.pickup : OrderType.delivery,
      );

      _clearCart();
      widget.onOrderSubmitted?.call();
      _showMessage('تم حفظ الطلب بنجاح');
      return order;
    } catch (error) {
      _showMessage('تعذر حفظ الطلب: $error');
      return null;
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _completeAndPrint(PosReceiptKind kind) async {
    final order = await _submitOrder();
    if (order == null || !mounted) return;
    final html = PosReceiptHtml.build(
      order: order,
      restaurantName: _restaurantName,
      kind: kind,
    );
    printPosReceiptHtml(html);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_PosPageData>(
      future: _pageFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.brandOrange),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('تعذر تحميل بيانات POS: ${snapshot.error}'),
                const SizedBox(height: 12),
                FilledButton(onPressed: _reload, child: const Text('إعادة المحاولة')),
              ],
            ),
          );
        }

        final page = snapshot.data!;
        final categories = _categories(page.items, page.topItemIds);
        final menuItems = _filteredMenuItems(page.items, page.topItemIds);

        return LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 1100;
            final menuPane = _buildMenuPane(
              categories: categories,
              menuItems: menuItems,
            );
            final checkoutPane = _buildCheckoutPane();

            if (stacked) {
              return Column(
                children: [
                  Expanded(flex: 5, child: menuPane),
                  const Divider(height: 1),
                  Expanded(flex: 4, child: checkoutPane),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: menuPane),
                const VerticalDivider(width: 1),
                Expanded(flex: 2, child: checkoutPane),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildMenuPane({
    required List<String> categories,
    required List<MenuItem> menuItems,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              const Icon(Icons.point_of_sale, color: AppTheme.brandMaroon),
              const SizedBox(width: 8),
              const Text(
                'نقطة البيع POS',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'تحديث المنيو',
                onPressed: _reload,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'بحث عن صنف...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final category = categories[index];
              final selected = category == _selectedCategory;
              return FilterChip(
                label: Text(category),
                selected: selected,
                onSelected: (_) => setState(() => _selectedCategory = category),
                selectedColor: AppTheme.brandOrange,
                checkmarkColor: Colors.white,
                labelStyle: TextStyle(
                  color: selected ? Colors.white : AppTheme.brandBlack,
                  fontWeight: FontWeight.w600,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: menuItems.isEmpty
              ? const Center(child: Text('لا توجد أصناف مطابقة'))
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    mainAxisExtent: 210,
                  ),
                  itemCount: menuItems.length,
                  itemBuilder: (context, index) {
                    final item = menuItems[index];
                    return _PosMenuTile(
                      item: item,
                      onTap: () => unawaited(_handleMenuItemTap(item)),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCheckoutPane() {
    return ColoredBox(
      color: const Color(0xFFF8F5F2),
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'بيانات العميل',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'رقم الهاتف',
                suffixIcon: _lookupInProgress
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : const Icon(Icons.person_search),
                border: const OutlineInputBorder(),
              ),
              validator: (value) =>
                  (value == null || value.trim().length < 8) ? 'مطلوب' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'اسم العميل',
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'مطلوب' : null,
            ),
            if (_customerOrderCount > 0 || _recentOrders.isNotEmpty) ...[
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'عميل مسجّل — $_customerOrderCount طلب سابق',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (_recentOrders.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        ..._recentOrders.map(
                          (order) => Text(
                            '• ${DateFormat('dd/MM HH:mm').format(order.createdAt.toLocal())} — ${order.totalPrice.toStringAsFixed(3)} د.ك',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('استلام من المحل (بدون توصيل)'),
              value: _isPickup,
              onChanged: (value) => setState(() => _isPickup = value),
            ),
            if (!_isPickup) ...[
              DropdownButtonFormField<String>(
                value: _availableGovernorates.contains(_selectedGovernorate)
                    ? _selectedGovernorate
                    : (_availableGovernorates.isNotEmpty
                        ? _availableGovernorates.first
                        : null),
                decoration: const InputDecoration(
                  labelText: 'المحافظة',
                  border: OutlineInputBorder(),
                ),
                items: _availableGovernorates
                    .map(
                      (gov) => DropdownMenuItem(value: gov, child: Text(gov)),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedGovernorate = value;
                    _syncDefaultArea();
                  });
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<DeliveryZone>(
                value: _selectedZone,
                decoration: const InputDecoration(
                  labelText: 'منطقة التوصيل',
                  border: OutlineInputBorder(),
                ),
                items: _areasForGovernorate
                    .map(
                      (zone) => DropdownMenuItem(
                        value: zone,
                        child: Text(
                          '${zone.areaName} (${zone.deliveryFee.toStringAsFixed(3)} د.ك)',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _selectedZone = value),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _blockController,
                      decoration: const InputDecoration(
                        labelText: 'القطعة',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _streetController,
                      decoration: const InputDecoration(
                        labelText: 'الشارع',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _houseController,
                      decoration: const InputDecoration(
                        labelText: 'المبنى',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _floorController,
                      decoration: const InputDecoration(
                        labelText: 'الطابق/الشقة',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _paymentMethod,
              decoration: const InputDecoration(
                labelText: 'طريقة الدفع',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'كاش', child: Text('كاش')),
                DropdownMenuItem(value: 'K-Net', child: Text('K-Net')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _paymentMethod = value);
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text(
                  'السلة',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_cart.isNotEmpty)
                  TextButton(onPressed: _clearCart, child: const Text('تفريغ')),
              ],
            ),
            if (_cart.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('لم تُضف أصناف بعد'),
              )
            else
              ..._cart.map(
                (item) {
                  final addons = item.selectedOptions
                      .map(
                        (option) =>
                            '${option.group}: ${option.name} (+${option.price.toStringAsFixed(3)} د.ك)',
                      )
                      .join('\n');

                  return Card(
                    child: ListTile(
                      title: Text(item.menuItem.name),
                      subtitle: Text(
                        [
                          '${item.unitPrice.toStringAsFixed(3)} × ${item.quantity}',
                          if (addons.isNotEmpty) addons,
                          if (item.specialNotes?.trim().isNotEmpty ?? false)
                            'ملاحظة: ${item.specialNotes!.trim()}',
                        ].join('\n'),
                      ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () =>
                              _updateCartQuantity(item.id, item.quantity - 1),
                        ),
                        Text('${item.quantity}'),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () =>
                              _updateCartQuantity(item.id, item.quantity + 1),
                        ),
                      ],
                    ),
                  ),
                );
                },
              ),
            const SizedBox(height: 8),
            _TotalRow(label: 'المجموع الفرعي', value: _subtotal),
            _TotalRow(label: 'رسوم التوصيل', value: _deliveryFee),
            _TotalRow(
              label: 'الإجمالي',
              value: _grandTotal,
              bold: true,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.brandMaroon,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: _submitting ? null : () => unawaited(_submitOrder()),
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_circle),
              label: const Text('إتمام الطلب وحفظه'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _submitting
                  ? null
                  : () => _completeAndPrint(PosReceiptKind.kitchen),
              icon: const Icon(Icons.print),
              label: const Text('حفظ + طباعة تذكرة المطبخ'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _submitting
                  ? null
                  : () => _completeAndPrint(PosReceiptKind.customer),
              icon: const Icon(Icons.receipt_long),
              label: const Text('حفظ + طباعة فاتورة العميل'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PosMenuTile extends StatelessWidget {
  const _PosMenuTile({required this.item, required this.onTap});

  final MenuItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: NetworkMenuImage(
                imageUrl: item.imageUrl,
                fit: BoxFit.cover,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${item.price.toStringAsFixed(3)} د.ك',
                    style: const TextStyle(
                      color: AppTheme.brandMaroon,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

  final String label;
  final double value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.bold : FontWeight.w500,
      fontSize: bold ? 16 : 14,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label, style: style),
          const Spacer(),
          Text('${value.toStringAsFixed(3)} د.ك', style: style),
        ],
      ),
    );
  }
}
