import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../data/kuwait_governorates.dart';
import '../../models/cart_item.dart';
import '../../models/customer.dart';
import '../../models/customer_checkout_profile.dart';
import '../../models/delivery_address_details.dart';
import '../../models/delivery_zone.dart';
import '../../models/kitchen.dart';
import '../../models/menu_item.dart';
import '../../models/order.dart';
import '../../models/restaurant_settings.dart';
import '../../models/sales_platform_config.dart';
import '../../services/admin_auth_service.dart';
import '../../services/api_service.dart';
import '../../services/customer_checkout_cache_service.dart';
import '../../services/orders_service.dart';
import '../../services/orders_demo_service.dart';
import '../../services/pos_print_service.dart';
import '../../services/restaurant_settings_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/pos_receipt_html.dart';
import '../../utils/whatsapp_phone.dart';
import 'pos/pos_fast_modifiers_dialog.dart';
import 'pos/pos_kitchen_selector.dart';
import 'pos/pos_platform_selector.dart';
import 'pos/pos_theme.dart';
import 'pos/pos_ui_components.dart';

class AdminPosPanel extends StatefulWidget {
  const AdminPosPanel({
    super.key,
    this.onOrderSubmitted,
    this.onLogout,
  });

  final VoidCallback? onOrderSubmitted;
  final VoidCallback? onLogout;

  @override
  State<AdminPosPanel> createState() => _AdminPosPanelState();
}

class _PosPageData {
  const _PosPageData({
    required this.items,
    required this.zones,
    required this.topItemIds,
    required this.salesPlatforms,
  });

  final List<MenuItem> items;
  final List<DeliveryZone> zones;
  final List<int> topItemIds;
  final List<SalesPlatformConfig> salesPlatforms;
}

class _AdminPosPanelState extends State<AdminPosPanel> {
  static const _allCategory = 'الكل';
  static const _quickCategory = 'أصناف سريعة';
  static const _topCategory = 'الأكثر مبيعاً 🔥';

  late Future<_PosPageData> _pageFuture;
  final _formKey = GlobalKey<FormState>();
  final _searchFocus = FocusNode();
  final _searchController = TextEditingController();
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  final _blockController = TextEditingController();
  final _streetController = TextEditingController();
  final _avenueController = TextEditingController();
  final _houseController = TextEditingController();
  final _floorController = TextEditingController();
  final _externalOrderIdController = TextEditingController();

  final List<CartItem> _cart = [];
  List<MenuItem> _allItems = const [];
  List<SalesPlatformConfig> _salesPlatforms = SalesPlatformConfig.defaults();
  PosPlatformSelection _platformSelection = PosPlatformSelection(
    platform: SalesPlatformConfig.defaults().first,
  );
  Timer? _lookupDebounce;
  String? _lastLookupPhone;
  var _lookupInProgress = false;
  var _submitting = false;
  var _isPickup = true;
  var _showDeliveryDetails = false;
  String _selectedCategory = _allCategory;
  String _paymentMethod = 'كاش';
  String? _selectedGovernorate;
  DeliveryZone? _selectedZone;
  List<DeliveryZone> _zones = const [];
  List<Kitchen> _kitchens = const [];
  String? _selectedTargetKitchenId;
  String? _autoSuggestedKitchenId;
  List<Order> _recentOrders = const [];
  int _customerOrderCount = 0;
  RestaurantSettings? _restaurantSettings;

  String get _restaurantId =>
      AdminAuthService.instance.restaurantId ?? ApiService.defaultRestaurantId;

  String get _restaurantName =>
      AdminAuthService.instance.restaurantName ?? 'المطعم';

  double get _subtotal =>
      _cart.fold(0.0, (sum, item) => sum + item.totalPrice);

  double get _zoneDeliveryFee =>
      _isPickup ? 0 : (_selectedZone?.deliveryFee ?? 0);

  double get _deliveryFee {
    if (_isPickup) return 0;
    final settings = _restaurantSettings;
    if (settings == null) return _zoneDeliveryFee;
    return settings.effectiveDeliveryFee(
      subtotal: _subtotal,
      zoneDeliveryFee: _selectedZone?.deliveryFee ?? 0,
    );
  }

  double get _grandTotal => _subtotal + _deliveryFee;

  int get _cartCount => _cart.fold(0, (sum, item) => sum + item.quantity);

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
    _searchFocus.dispose();
    _searchController.dispose();
    _phoneController.dispose();
    _nameController.dispose();
    _blockController.dispose();
    _streetController.dispose();
    _avenueController.dispose();
    _houseController.dispose();
    _floorController.dispose();
    _externalOrderIdController.dispose();
    super.dispose();
  }

  Future<_PosPageData> _loadPage() async {
    final results = await Future.wait([
      ApiService.instance.fetchPublicItems(restaurantId: _restaurantId),
      ApiService.instance.fetchDeliveryZones(restaurantId: _restaurantId),
      ApiService.instance.fetchTopMenuItemIds(restaurantId: _restaurantId),
      RestaurantSettingsService.instance.load(restaurantId: _restaurantId),
      ApiService.instance.fetchKitchens(
        restaurantId: _restaurantId,
        allowCashier: true,
      ),
    ]);

    final items = (results[0] as List<MenuItem>)
        .where((item) => item.isAvailable)
        .toList();
    final zones = results[1] as List<DeliveryZone>;
    final topItemIds = results[2] as List<int>;
    final settings = results[3] as RestaurantSettings;
    final kitchens = results[4] as List<Kitchen>;
    _restaurantSettings = settings;
    final platforms = settings.resolvedSalesPlatforms;

    _allItems = items;
    _zones = zones;
    _kitchens = kitchens;
    _salesPlatforms = platforms;
    if (_platformSelection.platform.id.isEmpty ||
        !platforms.any((p) => p.id == _platformSelection.platform.id)) {
      _platformSelection = PosPlatformSelection(
        platform: platforms.firstWhere(
          (p) => p.isLocal,
          orElse: () => platforms.first,
        ),
      );
    }
    if (_selectedGovernorate == null && zones.isNotEmpty) {
      _selectedGovernorate = zones.first.governorate;
    }
    _syncDefaultArea();

    return _PosPageData(
      items: items,
      zones: zones,
      topItemIds: topItemIds,
      salesPlatforms: platforms,
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
    final categories = <String>[_quickCategory, _allCategory];
    if (topItemIds.isNotEmpty) categories.add(_topCategory);
    for (final item in items) {
      final category = item.categoryName.trim();
      if (category.isEmpty || _isStaticPicksCategory(category)) continue;
      if (!categories.contains(category)) categories.add(category);
    }
    return categories;
  }

  List<MenuItem> _quickItems(List<MenuItem> items, List<int> topItemIds) {
    final byId = {for (final item in items) item.id: item};
    final fromTop =
        topItemIds.map((id) => byId[id]).whereType<MenuItem>().toList();
    if (fromTop.isNotEmpty) return fromTop.take(12).toList();
    return items.take(12).toList();
  }

  List<MenuItem> _filteredMenuItems(
    List<MenuItem> items,
    List<int> topItemIds,
  ) {
    final query = _searchController.text.trim();
    Iterable<MenuItem> result = items;

    if (_selectedCategory == _quickCategory) {
      result = _quickItems(items, topItemIds);
    } else if (_selectedCategory == _topCategory) {
      final byId = {for (final item in items) item.id: item};
      result = topItemIds.map((id) => byId[id]).whereType<MenuItem>();
    } else if (_selectedCategory != _allCategory) {
      result = items.where(
        (item) => item.categoryName.trim() == _selectedCategory,
      );
    }

    if (query.isNotEmpty) {
      result = result.where((item) => posMatchesSearch(item, query));
    }

    return result.toList();
  }

  void _onSearchChanged(String value) {
    setState(() {});

    final barcodeMatch = posFindBarcodeMatch(_allItems, value);
    if (barcodeMatch != null) {
      _searchController.clear();
      unawaited(_handleMenuItemTap(barcodeMatch));
    }
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
    _applyKitchenSuggestion(_selectedZone);
  }

  Kitchen? _defaultKitchen() {
    if (_kitchens.isEmpty) return null;
    return _kitchens.firstWhere(
      (kitchen) => kitchen.isDefault,
      orElse: () => _kitchens.first,
    );
  }

  void _applyKitchenSuggestion(DeliveryZone? zone) {
    final suggested = zone?.defaultKitchenId?.trim();
    if (suggested != null &&
        suggested.isNotEmpty &&
        _kitchens.any((kitchen) => kitchen.id == suggested)) {
      _autoSuggestedKitchenId = suggested;
      _selectedTargetKitchenId = suggested;
      return;
    }
    final fallback = _defaultKitchen();
    _autoSuggestedKitchenId = fallback?.id;
    _selectedTargetKitchenId = fallback?.id;
  }

  String? get _selectedTargetKitchenName {
    final id = _selectedTargetKitchenId;
    if (id == null) return null;
    for (final kitchen in _kitchens) {
      if (kitchen.id == id) return kitchen.localizedName('ar');
    }
    return null;
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
      _isPickup = false;
      _showDeliveryDetails = true;
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
      final cartItem = await showPosFastModifiersDialog(context, item);
      if (cartItem != null && mounted) {
        setState(() => _cart.add(cartItem));
      }
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

  void _clearSearch() {
    _searchController.clear();
    setState(() {});
  }

  void _focusSearch() {
    _searchFocus.requestFocus();
    _searchController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _searchController.text.length,
    );
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
    if (!_isPickup &&
        _kitchens.isNotEmpty &&
        (_selectedTargetKitchenId == null ||
            _selectedTargetKitchenId!.trim().isEmpty)) {
      _showMessage('يرجى اختيار المطبخ المستهدف');
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
      final orderSource = _platformSelection.platform.id;
      final platformMeta = _platformSelection.metaForTotal(_grandTotal);
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
        addressDetails:
            _isPickup ? const DeliveryAddressDetails() : _addressDetails,
        orderSource: orderSource,
        orderType: _isPickup ? OrderType.pickup : OrderType.delivery,
        platformMeta: platformMeta,
        targetKitchenId: _isPickup ? null : _selectedTargetKitchenId,
        targetKitchenName: _isPickup ? null : _selectedTargetKitchenName,
      );

      await CustomerCheckoutCacheService.instance.saveProfile(
        _restaurantId,
        CustomerCheckoutProfile(
          phone: _phoneController.text.trim(),
          customerName: _nameController.text.trim(),
          governorate: _selectedZone?.governorate ?? _selectedGovernorate ?? '',
          areaName: _selectedZone?.areaName ?? '',
          deliveryZoneId: _selectedZone?.id,
          addressDetails:
              _isPickup ? const DeliveryAddressDetails() : _addressDetails,
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
        addressDetails:
            _isPickup ? const DeliveryAddressDetails() : _addressDetails,
        orderSource: orderSource,
        orderType: _isPickup ? OrderType.pickup : OrderType.delivery,
        externalOrderId: platformMeta?.externalOrderId,
        platformGrossTotal: platformMeta?.platformGrossTotal,
        platformCommission: platformMeta?.platformCommission,
        platformCommissionPercent: platformMeta?.platformCommissionPercent,
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
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.f2): PosSubmitIntent(),
        SingleActivator(LogicalKeyboardKey.f4): PosFocusSearchIntent(),
        SingleActivator(LogicalKeyboardKey.f8): PosClearCartIntent(),
        SingleActivator(LogicalKeyboardKey.escape): PosClearSearchIntent(),
      },
      child: Actions(
        actions: {
          PosSubmitIntent: CallbackAction<PosSubmitIntent>(
            onInvoke: (_) {
              if (!_submitting) unawaited(_submitOrder());
              return null;
            },
          ),
          PosFocusSearchIntent: CallbackAction<PosFocusSearchIntent>(
            onInvoke: (_) {
              _focusSearch();
              return null;
            },
          ),
          PosClearCartIntent: CallbackAction<PosClearCartIntent>(
            onInvoke: (_) {
              if (_cart.isNotEmpty) _clearCart();
              return null;
            },
          ),
          PosClearSearchIntent: CallbackAction<PosClearSearchIntent>(
            onInvoke: (_) {
              _clearSearch();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: FutureBuilder<_PosPageData>(
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
                      FilledButton(
                        onPressed: _reload,
                        child: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                );
              }

              final page = snapshot.data!;
              final categories = _categories(page.items, page.topItemIds);
              final menuItems = _filteredMenuItems(page.items, page.topItemIds);

              return LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= PosTheme.breakpoint;
                  final menuSection = _buildMenuSection(
                    categories: categories,
                    menuItems: menuItems,
                    wide: wide,
                  );
                  final cartSection = _buildStickyCart();

                  if (!wide) {
                    return Column(
                      children: [
                        Expanded(flex: 6, child: menuSection),
                        SizedBox(height: 400, child: cartSection),
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: menuSection),
                      SizedBox(width: PosTheme.cartWidth, child: cartSection),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildMenuSection({
    required List<String> categories,
    required List<MenuItem> menuItems,
    required bool wide,
  }) {
    return ColoredBox(
      color: PosTheme.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSearchBar(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (wide)
                  SizedBox(
                    width: PosTheme.categorySidebarWidth,
                    child: _buildCategorySidebar(categories),
                  ),
                Expanded(
                  child: menuItems.isEmpty
                      ? const Center(child: Text('لا توجد أصناف مطابقة'))
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(10, 6, 12, 12),
                          gridDelegate:
                              SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: wide ? 210 : 170,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: wide ? 0.78 : 0.74,
                          ),
                          itemCount: menuItems.length,
                          itemBuilder: (context, index) {
                            final item = menuItems[index];
                            return PosMenuItemCard(
                              item: item,
                              onTap: () => unawaited(_handleMenuItemTap(item)),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          if (!wide) _buildCategoryChips(categories),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocus,
              decoration: InputDecoration(
                hintText: 'بحث فوري — اسم أو باركود (F4)',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchController.text.isEmpty
                    ? const Icon(
                        Icons.qr_code_scanner,
                        color: PosTheme.textMuted,
                        size: 20,
                      )
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: _clearSearch,
                      ),
                filled: true,
                fillColor: PosTheme.surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: PosTheme.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: PosTheme.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: PosTheme.accent,
                    width: 1.5,
                  ),
                ),
                isDense: true,
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          if (_cartCount > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: PosTheme.accent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$_cartCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ],
          IconButton(
            tooltip: 'تحديث المنيو',
            visualDensity: VisualDensity.compact,
            onPressed: _reload,
            icon: const Icon(Icons.refresh, size: 22),
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySidebar(List<String> categories) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 4, 6, 10),
      children: categories
          .map(
            (category) => PosCategoryTile(
              label: category,
              icon: posCategoryIcon(category),
              selected: category == _selectedCategory,
              onTap: () => setState(() => _selectedCategory = category),
            ),
          )
          .toList(),
    );
  }

  Widget _buildCategoryChips(List<String> categories) {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = categories[index];
          final selected = category == _selectedCategory;
          return FilterChip(
            avatar: Icon(
              posCategoryIcon(category),
              size: 16,
              color: selected ? Colors.white : PosTheme.textMuted,
            ),
            label: Text(category),
            selected: selected,
            onSelected: (_) => setState(() => _selectedCategory = category),
            selectedColor: PosTheme.accent,
            checkmarkColor: Colors.white,
            labelStyle: TextStyle(
              color: selected ? Colors.white : AppTheme.brandBlack,
              fontWeight: FontWeight.w600,
            ),
          );
        },
      ),
    );
  }

  Widget _buildStickyCart() {
    return ColoredBox(
      color: PosTheme.surface,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: PosTheme.border)),
              ),
              child: Row(
                children: [
                  const Text(
                    'السلة',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  if (_cartCount > 0) ...[
                    const SizedBox(width: 6),
                    Text(
                      '($_cartCount)',
                      style: const TextStyle(
                        color: PosTheme.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (_cart.isNotEmpty)
                    TextButton(
                      onPressed: _clearCart,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: const Text('تفريغ F8', style: TextStyle(fontSize: 12)),
                    ),
                  if (widget.onLogout != null)
                    IconButton(
                      tooltip: 'تسجيل الخروج',
                      visualDensity: VisualDensity.compact,
                      onPressed: widget.onLogout,
                      icon: const Icon(Icons.logout, size: 20),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildCustomerFields(),
                  const SizedBox(height: 8),
                  PosPlatformSelector(
                    platforms: _salesPlatforms,
                    selection: _platformSelection,
                    orderTotal: _grandTotal,
                    externalOrderIdController: _externalOrderIdController,
                    onChanged: (next) =>
                        setState(() => _platformSelection = next),
                    dense: true,
                  ),
                  const SizedBox(height: 8),
                  _buildCompactOrderPaymentControls(),
                  if (!_isPickup && _showDeliveryDetails) ...[
                    const SizedBox(height: 8),
                    _buildDeliveryFields(),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 6),
            const Divider(height: 1, color: PosTheme.border),
            Expanded(
              child: _cart.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'السلة فارغة — اختر أصنافاً من المنيو',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: PosTheme.textMuted),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      itemCount: _cart.length,
                      itemBuilder: (context, index) {
                        final item = _cart[index];
                        return PosCartLine(
                          item: item,
                          onIncrease: () =>
                              _updateCartQuantity(item.id, item.quantity + 1),
                          onDecrease: () =>
                              _updateCartQuantity(item.id, item.quantity - 1),
                        );
                      },
                    ),
            ),
            _buildCheckoutFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactOrderPaymentControls() {
    return Column(
      children: [
        Row(
          children: [
            PosPaymentChip(
              label: 'استلام',
              icon: Icons.storefront,
              selected: _isPickup,
              onTap: () => setState(() {
                _isPickup = true;
                _showDeliveryDetails = false;
              }),
            ),
            const SizedBox(width: 6),
            PosPaymentChip(
              label: 'توصيل',
              icon: Icons.delivery_dining,
              selected: !_isPickup,
              onTap: () => setState(() {
                _isPickup = false;
                _showDeliveryDetails = true;
              }),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            PosPaymentChip(
              label: 'كاش',
              icon: Icons.payments_outlined,
              selected: _paymentMethod == 'كاش',
              onTap: () => setState(() => _paymentMethod = 'كاش'),
            ),
            const SizedBox(width: 6),
            PosPaymentChip(
              label: 'K-Net',
              icon: Icons.credit_card,
              selected: _paymentMethod == 'K-Net',
              onTap: () => setState(() => _paymentMethod = 'K-Net'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCustomerFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'الهاتف',
                  isDense: true,
                  suffixIcon: _lookupInProgress
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : const Icon(Icons.person_search, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                validator: (value) =>
                    (value == null || value.trim().length < 8) ? 'مطلوب' : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'اسم العميل',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'مطلوب' : null,
              ),
            ),
          ],
        ),
        if (_customerOrderCount > 0) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: PosTheme.card(color: PosTheme.accentSoft),
            child: Text(
              'عميل مسجّل — $_customerOrderCount طلب سابق',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDeliveryFields() {
    return Column(
      children: [
        DropdownButtonFormField<String>(
          value: _availableGovernorates.contains(_selectedGovernorate)
              ? _selectedGovernorate
              : (_availableGovernorates.isNotEmpty
                  ? _availableGovernorates.first
                  : null),
          decoration: InputDecoration(
            labelText: 'المحافظة',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          items: _availableGovernorates
              .map((gov) => DropdownMenuItem(value: gov, child: Text(gov)))
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
          decoration: InputDecoration(
            labelText: 'المنطقة',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
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
          onChanged: (value) => setState(() {
            _selectedZone = value;
            _applyKitchenSuggestion(value);
          }),
        ),
        if (_kitchens.isNotEmpty) ...[
          const SizedBox(height: 8),
          PosKitchenSelector(
            kitchens: _kitchens,
            selectedId: _selectedTargetKitchenId,
            autoSuggestedId: _autoSuggestedKitchenId,
            onChanged: (kitchenId) =>
                setState(() => _selectedTargetKitchenId = kitchenId),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _blockController,
                decoration: InputDecoration(
                  labelText: 'القطعة',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: _streetController,
                decoration: InputDecoration(
                  labelText: 'الشارع',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCheckoutFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: const BoxDecoration(
        color: PosTheme.surfaceAlt,
        border: Border(top: BorderSide(color: PosTheme.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PosTotalRow(label: 'المجموع الفرعي', value: _subtotal),
          if (!_isPickup)
            PosTotalRow(label: 'التوصيل', value: _deliveryFee),
          PosTotalRow(
            label: 'الإجمالي',
            value: _grandTotal,
            bold: true,
            large: true,
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: PosTheme.success,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
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
                : const Icon(Icons.flash_on),
            label: const Text(
              'إتمام الدفع F2',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _submitting
                      ? null
                      : () => _completeAndPrint(PosReceiptKind.kitchen),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    minimumSize: const Size.fromHeight(36),
                  ),
                  icon: const Icon(Icons.print, size: 16),
                  label: const Text('مطبخ', style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _submitting
                      ? null
                      : () => _completeAndPrint(PosReceiptKind.customer),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    minimumSize: const Size.fromHeight(36),
                  ),
                  icon: const Icon(Icons.receipt, size: 16),
                  label: const Text('فاتورة', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
