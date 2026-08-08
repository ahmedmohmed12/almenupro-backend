import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/kuwait_governorates.dart';
import '../../l10n/app_strings.dart';
import '../../models/customer_checkout_profile.dart';
import '../../models/customer_restaurant_context.dart';
import '../../models/delivery_address_details.dart';
import '../../models/delivery_zone.dart';
import '../../models/menu_item.dart';
import '../../models/restaurant_settings.dart';
import '../../models/smart_closing.dart';
import '../../models/upsell_recommendation.dart';
import '../../providers/cart_provider.dart';
import '../../providers/locale_provider.dart';
import '../../services/api_service.dart';
import '../../services/customer_checkout_cache_service.dart';
import '../../services/orders_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/image_url.dart';
import '../../utils/upsell_item_resolver.dart';
import '../../utils/whatsapp_launcher.dart';
import '../../utils/whatsapp_order_message.dart';
import '../../utils/whatsapp_phone.dart';
import '../../widgets/network_menu_image.dart';
import 'checkout_closing_banner.dart';
import 'checkout_impulse_bumps.dart';
import 'checkout_smart_recommendations.dart';
import 'free_delivery_progress_bar.dart';
import 'post_checkout_reward_sheet.dart';

enum _CheckoutStep { review, details }

class MenuCheckoutSheet extends StatefulWidget {
  const MenuCheckoutSheet({super.key, required this.restaurantContext});

  final CustomerRestaurantContext restaurantContext;

  static Future<void> show(
    BuildContext context, {
    required CustomerRestaurantContext restaurantContext,
  }) {
    final cart = context.read<CartProvider>();
    if (!cart.matchesRestaurant(
      restaurantId: restaurantContext.id,
      slug: restaurantContext.slug,
    )) {
      cart.setRestaurantScope(
        restaurantId: restaurantContext.id,
        slug: restaurantContext.slug,
      );
    }

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
  final _promoCodeController = TextEditingController();
  final _walletAmountController = TextEditingController();
  final _notesController = TextEditingController();

  _CheckoutStep _step = _CheckoutStep.review;
  var _paymentMethod = 'كاش';
  var _submitting = false;
  var _loadingZones = true;
  var _lookupInProgress = false;
  var _validatingPromo = false;
  var _validatingWallet = false;
  var _profileLoadedNotice = false;

  String? _lastLookupPhone;
  String? _resolvedLookupPhone;
  String? _appliedPromoCode;
  double _appliedPromoDiscount = 0;
  double _appliedWalletDiscount = 0;
  double _walletBalanceAvailable = 0;
  var _walletCoversFullOrder = false;
  var _normalizedPhoneDigits = '';
  var _phoneLookupGeneration = 0;
  var _closingPreviewGeneration = 0;
  var _lastClosingPreviewKey = '';
  Timer? _lookupDebounce;
  Timer? _closingDebounce;

  List<DeliveryZone> _zones = [];
  String? _selectedGovernorate;
  DeliveryZone? _selectedZone;

  RestaurantSettings? _settings;
  List<MenuItem> _menuItems = [];
  SmartClosingPayload? _closingPreview;
  var _loadingClosing = false;

  CustomerRestaurantContext get _ctx => widget.restaurantContext;

  String get _restaurantName => _ctx.name;

  String get _whatsappNumber => _ctx.whatsappNumber;

  String get _restaurantId => _ctx.id;

  String get _restaurantSlug => _ctx.slug;

  String get _restaurantDescription => _ctx.description;

  double get _zoneDeliveryFee => _selectedZone?.deliveryFee ?? 0;

  double _deliveryFeeFor(double subtotal) {
    final settings = _settings;
    if (settings == null) return _zoneDeliveryFee;
    return settings.effectiveDeliveryFee(
      subtotal: subtotal,
      zoneDeliveryFee: _zoneDeliveryFee,
    );
  }

  bool _hasFreeDeliveryFor(double subtotal) =>
      _settings?.qualifiesForFreeDelivery(subtotal) == true;

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

  String _formattedAddressArabic() {
    final governorate = _selectedZone?.governorate ?? _selectedGovernorate ?? '';
    final areaName = _selectedZone?.areaName ?? '';
    return _addressDetails.formatArabic(
      governorate: governorate,
      areaName: areaName,
    );
  }

  String _formattedAddressEnglish() {
    final governorate = _selectedZone?.governorate ?? _selectedGovernorate ?? '';
    final areaName = _selectedZone?.areaName ?? '';
    return _addressDetails.formatEnglish(
      governorate: governorate,
      areaName: areaName,
    );
  }

  @override
  void initState() {
    super.initState();
    _settings = _ctx.settings;
    unawaited(_loadDeliveryZones());
    unawaited(_prefillLastPhone());
    _phoneController.addListener(_onPhoneControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadUpsellContext());
    });
  }

  Future<void> _prefillLastPhone() async {
    final lastPhone = await CustomerCheckoutCacheService.instance.loadLastPhone(
      _restaurantId,
    );
    if (!mounted || lastPhone == null || lastPhone.trim().isEmpty) return;
    _phoneController.text = lastPhone.trim();
  }

  Future<void> _loadUpsellContext() async {
    try {
      final settings = await ApiService.instance.fetchPublicSettings(
        slug: _restaurantSlug,
      );
      final items = await ApiService.instance.fetchPublicItems(
        slug: _restaurantSlug,
      );
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _menuItems = items;
      });
      final cartCount = context.read<CartProvider>().itemCount;
      await _refreshClosingPreview(cartItemCount: cartCount);
    } catch (_) {}
  }

  void _onPhoneControllerChanged() {
    _syncPhoneLookupState();
    _scheduleClosingRefresh();
  }

  bool _isPhoneLookupReady(String digits) => digits.length >= 8;

  bool get _hasPhoneWalletState =>
      _profileLoadedNotice ||
      _lastLookupPhone != null ||
      _resolvedLookupPhone != null ||
      _lookupInProgress ||
      _walletBalanceAvailable > 0 ||
      _appliedWalletDiscount > 0;

  void _syncPhoneLookupState() {
    final digits = WhatsAppPhone.digitsOnly(_phoneController.text);
    if (digits == _normalizedPhoneDigits) return;
    _normalizedPhoneDigits = digits;

    if (!_isPhoneLookupReady(digits)) {
      _lookupDebounce?.cancel();
      _phoneLookupGeneration++;
      _resetPhoneWalletStateIfNeeded();
      return;
    }

    if (digits == _resolvedLookupPhone) return;
    if (_lookupInProgress && digits == _lastLookupPhone) return;

    _lookupDebounce?.cancel();
    final scheduledDigits = digits;
    _lookupDebounce = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      final currentDigits = WhatsAppPhone.digitsOnly(_phoneController.text);
      if (!_isPhoneLookupReady(currentDigits)) return;
      if (currentDigits != scheduledDigits) return;
      if (currentDigits == _resolvedLookupPhone) return;
      unawaited(_lookupCustomer(currentDigits));
    });
  }

  void _resetPhoneWalletStateIfNeeded() {
    if (!_hasPhoneWalletState) return;
    if (!mounted) return;
    setState(() {
      _profileLoadedNotice = false;
      _lastLookupPhone = null;
      _resolvedLookupPhone = null;
      _lookupInProgress = false;
      _resetWalletLookupFields();
    });
  }

  void _scheduleClosingRefresh() {
    if (_step != _CheckoutStep.details) return;
    if (!_isPhoneLookupReady(_normalizedPhoneDigits)) return;
    _closingDebounce?.cancel();
    _closingDebounce = Timer(const Duration(milliseconds: 450), () {
      if (!mounted || _step != _CheckoutStep.details) return;
      _refreshClosingPreview(
        cartItemCount: context.read<CartProvider>().itemCount,
      );
    });
  }

  Future<void> _lookupCustomer(String normalizedPhone) async {
    if (!_isPhoneLookupReady(normalizedPhone)) return;
    if (normalizedPhone == _resolvedLookupPhone) return;
    if (_lookupInProgress && _lastLookupPhone == normalizedPhone) return;

    final generation = ++_phoneLookupGeneration;
    if (!mounted) return;
    setState(() {
      _lookupInProgress = true;
      _lastLookupPhone = normalizedPhone;
      _profileLoadedNotice = false;
    });

    CustomerCheckoutProfile? profile;
    try {
      profile = await CustomerCheckoutCacheService.instance.loadProfile(
        _restaurantId,
        normalizedPhone,
      );
      profile ??= await ApiService.instance.fetchCustomerCheckoutProfile(
        phone: normalizedPhone,
        restaurantId: _restaurantId,
        slug: _restaurantSlug,
      );
    } catch (_) {
      profile = null;
    }

    if (!mounted || generation != _phoneLookupGeneration) return;

    if (profile != null) {
      final resolvedProfile = profile;
      await CustomerCheckoutCacheService.instance.saveProfile(
        _restaurantId,
        resolvedProfile.copyWithPhone(normalizedPhone),
      );
      if (!mounted || generation != _phoneLookupGeneration) return;

      _applyProfileFields(resolvedProfile);
      setState(() {
        _profileLoadedNotice =
            resolvedProfile.hasUsableData || resolvedProfile.hasWalletBalance;
        _walletBalanceAvailable = resolvedProfile.walletBalance;
        _appliedWalletDiscount = 0;
        _walletCoversFullOrder = false;
        _lookupInProgress = false;
        _resolvedLookupPhone = normalizedPhone;
      });
      _scheduleClosingRefresh();
      return;
    }

    setState(() {
      _resetWalletLookupFields();
      _lookupInProgress = false;
      _resolvedLookupPhone = normalizedPhone;
    });
  }

  void _applyProfileFields(CustomerCheckoutProfile profile) {
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
    }

    if (profile.paymentMethod.trim().isNotEmpty) {
      _paymentMethod = profile.paymentMethod.trim();
    }

    if (profile.hasActivePromo && _appliedPromoCode == null) {
      _promoCodeController.text = profile.personalPromoCode.trim();
    }

    _walletAmountController.clear();
  }

  Future<void> _refreshClosingPreview({required int cartItemCount}) async {
    if (_settings?.smartClosingEnabled != true) {
      if (!mounted) return;
      if (_closingPreview == null && !_loadingClosing) return;
      setState(() {
        _closingPreview = null;
        _loadingClosing = false;
      });
      return;
    }

    final cart = context.read<CartProvider>();
    final previewKey =
        '${_normalizedPhoneDigits}|$cartItemCount|${cart.totalPrice}|$_appliedPromoDiscount|${_deliveryFeeFor(cart.totalPrice)}';
    if (previewKey == _lastClosingPreviewKey &&
        !_loadingClosing &&
        _closingPreview != null) {
      return;
    }

    final generation = ++_closingPreviewGeneration;
    if (!mounted) return;
    if (!_loadingClosing) {
      setState(() => _loadingClosing = true);
    }
    try {
      final preview = await ApiService.instance.fetchCheckoutClosingPreview(
        subtotal: cart.totalPrice,
        deliveryFee: _deliveryFeeFor(cart.totalPrice),
        cartItemCount: cartItemCount,
        phone: _phoneController.text.trim(),
        restaurantId: _restaurantId,
        slug: _restaurantSlug,
      );
      if (!mounted || generation != _closingPreviewGeneration) return;
      _lastClosingPreviewKey = previewKey;
      setState(() {
        _closingPreview = preview;
        _loadingClosing = false;
      });
    } catch (_) {
      if (!mounted || generation != _closingPreviewGeneration) return;
      setState(() => _loadingClosing = false);
    }
  }

  List<UpsellRecommendation> _smartRecommendationsFor(CartProvider cart) {
    final settings = _settings;
    if (settings == null) return const [];
    final cartItemIds = cart.items.map((item) => item.menuItem.id).toSet();
    return UpsellItemResolver.smartRecommendations(
      allItems: _menuItems,
      cartItems: cart.items.map((e) => e.menuItem).toList(),
      settings: settings,
      cartItemIds: cartItemIds,
      subtotal: cart.totalPrice,
    );
  }

  List<UpsellRecommendation> _impulseBumpsFor(CartProvider cart) {
    final settings = _settings;
    if (settings == null) return const [];
    final cartItemIds = cart.items.map((item) => item.menuItem.id).toSet();
    return UpsellItemResolver.impulseBumpRecommendations(
      allItems: _menuItems,
      settings: settings,
      cartItemIds: cartItemIds,
    );
  }

  void _addUpsellItem(UpsellRecommendation recommendation, CartProvider cart) {
    cart.addMenuItem(
      recommendation.item,
      restaurantId: _restaurantId,
      restaurantSlug: _restaurantSlug,
    );
    _refreshClosingPreview(cartItemCount: cart.itemCount);
  }

  Future<void> _loadDeliveryZones() async {
    try {
      final zones = await ApiService.instance.fetchDeliveryZones(
        slug: _restaurantSlug,
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

  Future<void> _validatePromoCode(CartProvider cart, AppStrings strings) async {
    final code = _promoCodeController.text.trim();
    if (code.isEmpty) return;
    final phone = WhatsAppPhone.digitsOnly(_phoneController.text);
    if (phone.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.phoneFirstHint)),
      );
      return;
    }

    setState(() => _validatingPromo = true);
    try {
      final subtotal = cart.totalPrice;
      final deliveryFee = _deliveryFeeFor(subtotal);
      final result = await ApiService.instance.validatePromoCode(
        phone: phone,
        promoCode: code,
        subtotal: subtotal,
        deliveryFee: deliveryFee,
        restaurantId: _restaurantId,
        slug: _restaurantSlug,
      );
      if (!mounted) return;
      if (result.valid && result.discount > 0) {
        setState(() {
          _appliedPromoCode = result.promoCode.isNotEmpty ? result.promoCode : code;
          _appliedPromoDiscount = result.discount;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.promoApplied)),
        );
      } else {
        setState(() {
          _appliedPromoCode = null;
          _appliedPromoDiscount = 0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.promoInvalid)),
        );
      }
    } finally {
      if (mounted) setState(() => _validatingPromo = false);
    }
  }

  void _clearPromo() {
    setState(() {
      _appliedPromoCode = null;
      _appliedPromoDiscount = 0;
    });
  }

  void _resetWalletLookupFields() {
    _walletBalanceAvailable = 0;
    _appliedWalletDiscount = 0;
    _walletCoversFullOrder = false;
    if (_walletAmountController.text.isNotEmpty) {
      _walletAmountController.clear();
    }
  }

  void _clearWalletApplied() {
    if (_appliedWalletDiscount <= 0 && !_walletCoversFullOrder) return;
    setState(() {
      _appliedWalletDiscount = 0;
      _walletCoversFullOrder = false;
    });
  }

  double _orderTotalBeforeWallet(double subtotal) {
    final deliveryFee = _deliveryFeeFor(subtotal);
    return (subtotal + deliveryFee - _appliedPromoDiscount)
        .clamp(0.0, double.infinity)
        .toDouble();
  }

  double? _parseWalletAmountInput() {
    final raw = _walletAmountController.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  Future<void> _applyWalletAmount(CartProvider cart, AppStrings strings) async {
    final amount = _parseWalletAmountInput();
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.walletAmountRequired)),
      );
      return;
    }
    final phone = _normalizedPhoneDigits;
    if (!_isPhoneLookupReady(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.phoneFirstHint)),
      );
      return;
    }
    if (_walletBalanceAvailable <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.walletEmpty)),
      );
      return;
    }

    setState(() => _validatingWallet = true);
    try {
      final subtotal = cart.totalPrice;
      final deliveryFee = _deliveryFeeFor(subtotal);
      final result = await ApiService.instance.validateWalletAmount(
        phone: phone,
        walletAmount: amount,
        subtotal: subtotal,
        deliveryFee: deliveryFee,
        promoDiscount: _appliedPromoDiscount,
        restaurantId: _restaurantId,
        slug: _restaurantSlug,
      );
      if (!mounted) return;
      if (result.valid && result.discount > 0) {
        setState(() {
          _appliedWalletDiscount = result.discount;
          _walletBalanceAvailable = result.remainingBalance > 0
              ? result.remainingBalance
              : (result.walletBalance - result.discount).clamp(0.0, double.infinity);
          _walletCoversFullOrder = result.coversFullOrder;
          _walletAmountController.text = result.discount.toStringAsFixed(3);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.walletApplied)),
        );
      } else {
        _clearWalletApplied();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.walletInvalid)),
        );
      }
    } finally {
      if (mounted) setState(() => _validatingWallet = false);
    }
  }

  void _useFullWalletBalance(CartProvider cart, AppStrings strings) {
    if (_walletBalanceAvailable <= 0) return;
    final orderDue = _orderTotalBeforeWallet(cart.totalPrice);
    if (orderDue <= 0) return;
    final amount = _walletBalanceAvailable < orderDue
        ? _walletBalanceAvailable
        : orderDue;
    _walletAmountController.text = amount.toStringAsFixed(3);
    unawaited(_applyWalletAmount(cart, strings));
  }

  void _goToDetailsStep(CartProvider cart, AppStrings strings) {
    if (cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.emptyCartCheckout)),
      );
      return;
    }
    if (!cart.matchesRestaurant(
      restaurantId: _restaurantId,
      slug: _restaurantSlug,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('سلة التسوق لا تتطابق مع هذا المطعم — أعد إضافة الأصناف'),
        ),
      );
      return;
    }
    setState(() => _step = _CheckoutStep.details);
    _ensurePhoneWalletLookup();
    _refreshClosingPreview(cartItemCount: cart.itemCount);
  }

  void _ensurePhoneWalletLookup() {
    final digits = WhatsAppPhone.digitsOnly(_phoneController.text);
    if (digits != _normalizedPhoneDigits) {
      _normalizedPhoneDigits = digits;
    }
    if (!_isPhoneLookupReady(digits)) return;
    if (digits == _resolvedLookupPhone || _lookupInProgress) return;

    _lookupDebounce?.cancel();
    unawaited(_lookupCustomer(digits));
  }

  @override
  void dispose() {
    _lookupDebounce?.cancel();
    _closingDebounce?.cancel();
    _phoneLookupGeneration++;
    _closingPreviewGeneration++;
    _phoneController.removeListener(_onPhoneControllerChanged);
    _nameController.dispose();
    _phoneController.dispose();
    _blockController.dispose();
    _streetController.dispose();
    _avenueController.dispose();
    _houseController.dispose();
    _floorController.dispose();
    _promoCodeController.dispose();
    _walletAmountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  double _computeGrandTotal(double subtotal) {
    final deliveryFee = _deliveryFeeFor(subtotal);
    return (subtotal + deliveryFee - _appliedPromoDiscount - _appliedWalletDiscount)
        .clamp(0.0, double.infinity)
        .toDouble();
  }

  String _effectivePaymentMethod(double subtotal) {
    if (_walletCoversFullOrder && _appliedWalletDiscount > 0) {
      return 'محفظة';
    }
    return _paymentMethod;
  }

  Future<void> _submit(CartProvider cart, AppStrings strings) async {
    if (!_formKey.currentState!.validate()) return;
    if (!cart.matchesRestaurant(
      restaurantId: _restaurantId,
      slug: _restaurantSlug,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('سلة التسوق لا تتطابق مع هذا المطعم — أعد إضافة الأصناف'),
        ),
      );
      return;
    }
    if (_whatsappNumber.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('رقم واتساب المطعم غير مُعد')),
      );
      return;
    }
    if (_zones.isNotEmpty && _selectedZone == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.selectGovernorateAndArea)),
      );
      return;
    }

    setState(() => _submitting = true);

    final subtotal = cart.totalPrice;
    final deliveryFee = _deliveryFeeFor(subtotal);
    final promoDiscount = _appliedPromoDiscount;
    final walletDiscount = _appliedWalletDiscount;
    final grandTotal = _computeGrandTotal(subtotal);
    final paymentMethod = _effectivePaymentMethod(subtotal);
    final invoiceNumber =
        DateTime.now().millisecondsSinceEpoch.toString().substring(5);
    final now = DateTime.now();
    final orderTime =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final addressArabic = _formattedAddressArabic();
    final addressEnglish = _formattedAddressEnglish();
    final phone = _phoneController.text.trim();

    final message = WhatsAppOrderMessage.build(
      restaurantName: _restaurantName,
      invoiceNumber: invoiceNumber,
      customerName: _nameController.text.trim(),
      phone: phone,
      paymentMethod: paymentMethod,
      orderTime: orderTime,
      cartItems: cart.items,
      subtotal: subtotal,
      deliveryFee: deliveryFee,
      grandTotal: grandTotal,
      addressArabic: addressArabic,
      addressEnglish: addressEnglish,
      promoDiscount: promoDiscount,
      promoCodeApplied: _appliedPromoCode,
      walletDiscount: walletDiscount,
      orderNotes: _notesController.text.trim(),
    );

    final opened = await openWhatsAppChat(
      phone: _whatsappNumber,
      message: message,
    );

    if (opened) {
      SmartClosingPayload? smartClosing;
      try {
        smartClosing = await OrdersService.instance.submitOrderFromCart(
          cartItems: List.from(cart.items),
          customerName: _nameController.text.trim(),
          phone: phone,
          address: addressArabic,
          paymentMethod: paymentMethod,
          invoiceNumber: invoiceNumber,
          restaurantId: _restaurantId,
          restaurantSlug: _restaurantSlug,
          deliveryFee: deliveryFee,
          governorate: _selectedZone?.governorate ?? _selectedGovernorate,
          areaName: _selectedZone?.areaName,
          deliveryZoneId: _selectedZone?.id,
          addressDetails: _addressDetails,
          orderSource: 'menu_checkout',
          promoCode: _appliedPromoCode,
          promoDiscount: promoDiscount,
          walletAmount: walletDiscount,
          walletDiscount: walletDiscount,
        );

        await CustomerCheckoutCacheService.instance.saveProfile(
          _restaurantId,
          CustomerCheckoutProfile(
            phone: phone,
            customerName: _nameController.text.trim(),
            governorate: _selectedZone?.governorate ?? _selectedGovernorate ?? '',
            areaName: _selectedZone?.areaName ?? '',
            deliveryZoneId: _selectedZone?.id,
            addressDetails: _addressDetails,
            paymentMethod: _paymentMethod,
          ),
        );
      } catch (error) {
        debugPrint('Order backend sync failed: $error');
      }

      if (!mounted) return;

      final grantedPromo = smartClosing?.rewards.personalPromoCode ?? '';
      final grantedDiscount = smartClosing?.rewards.personalPromoDiscount ??
          smartClosing?.rewards.welcomeDiscountForNextOrder ??
          0;

      if (grantedPromo.isNotEmpty && grantedDiscount > 0) {
        final enrichedMessage = WhatsAppOrderMessage.build(
          restaurantName: _restaurantName,
          invoiceNumber: invoiceNumber,
          customerName: _nameController.text.trim(),
          phone: phone,
          paymentMethod: paymentMethod,
          orderTime: orderTime,
          cartItems: cart.items,
          subtotal: subtotal,
          deliveryFee: deliveryFee,
          grandTotal: grandTotal,
          addressArabic: addressArabic,
          addressEnglish: addressEnglish,
          promoDiscount: promoDiscount,
          promoCodeApplied: _appliedPromoCode,
          walletDiscount: walletDiscount,
          personalPromoCodeGranted: grantedPromo,
          personalPromoDiscount: grantedDiscount,
          orderNotes: _notesController.text.trim(),
        );
        await openWhatsAppChat(phone: _whatsappNumber, message: enrichedMessage);
      }

      if (!mounted) return;

      setState(() => _submitting = false);
      cart.clear();
      Navigator.pop(context);

      final closing = smartClosing ?? _closingPreview;
      if (!mounted) return;
      if (_settings?.smartClosingEnabled == true && closing != null) {
        await PostCheckoutRewardSheet.show(
          context,
          closing: closing,
          strings: strings,
          localeCode: context.read<LocaleProvider>().localeCode,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.orderSentViaWhatsapp)),
        );
      }
    } else {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.whatsappOpenFailed(_whatsappNumber))),
      );
    }
  }

  Widget _buildStepIndicator(AppStrings strings) {
    final onReview = _step == _CheckoutStep.review;
    final onDetails = _step == _CheckoutStep.details;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: _StepChip(
              label: '1. ${strings.checkoutStepReview}',
              active: onReview,
              completed: onDetails,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StepChip(
              label: '2. ${strings.checkoutStepDetails}',
              active: onDetails,
              completed: false,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWalletSection(
    CartProvider cart,
    AppStrings strings,
    double grandTotal, {
    bool compactTop = false,
  }) {
    final phoneReady = _isPhoneLookupReady(_normalizedPhoneDigits);
    final walletResolved = _resolvedLookupPhone == _normalizedPhoneDigits;

    if (!phoneReady && !_lookupInProgress) {
      return const SizedBox.shrink();
    }

    if (_lookupInProgress) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!compactTop) const SizedBox(height: 16),
          InputDecorator(
            decoration: InputDecoration(
              labelText: strings.loyaltyWalletLabel,
              border: const OutlineInputBorder(),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    strings.walletLoadingBalance,
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (!walletResolved) {
      return const SizedBox.shrink();
    }

    if (_walletBalanceAvailable <= 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!compactTop) const SizedBox(height: 16),
          InputDecorator(
            decoration: InputDecoration(
              labelText: strings.loyaltyWalletLabel,
              border: const OutlineInputBorder(),
            ),
            child: Text(
              strings.walletEmpty,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 14,
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!compactTop) const SizedBox(height: 16),
        InputDecorator(
          decoration: InputDecoration(
            labelText: strings.loyaltyWalletLabel,
            border: const OutlineInputBorder(),
          ),
          child: Text(
            strings.walletAvailableBalance(
              _walletBalanceAvailable.toStringAsFixed(3),
            ),
            style: TextStyle(
              color: Colors.green.shade700,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _walletAmountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: strings.walletAmountLabel,
                  hintText: strings.walletAmountHint,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => _clearWalletApplied(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: _validatingWallet
                  ? null
                  : () => _applyWalletAmount(cart, strings),
              child: _validatingWallet
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(strings.applyWalletAmount),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.tonal(
            onPressed: _validatingWallet
                ? null
                : () => _useFullWalletBalance(cart, strings),
            child: Text(strings.useFullWalletBalance),
          ),
        ),
        if (_appliedWalletDiscount > 0) ...[
          const SizedBox(height: 8),
          Text(
            '${strings.walletDiscountLabel}: -${_appliedWalletDiscount.toStringAsFixed(3)} ${strings.currency}',
            style: TextStyle(
              color: Colors.green.shade700,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          if (_walletCoversFullOrder)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                strings.walletCoversFullOrder,
                style: TextStyle(
                  color: Colors.green.shade700,
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildPaymentSection(
    CartProvider cart,
    AppStrings strings,
    double grandTotal,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Text(
          strings.paymentSectionTitle,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppTheme.brandMaroon,
          ),
        ),
        const SizedBox(height: 12),
        _buildWalletSection(cart, strings, grandTotal, compactTop: true),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _paymentMethod,
          decoration: InputDecoration(
            labelText: strings.paymentMethod,
            border: const OutlineInputBorder(),
            helperText: _walletCoversFullOrder && _appliedWalletDiscount > 0
                ? strings.walletCoversFullOrder
                : _appliedWalletDiscount > 0 && grandTotal > 0
                    ? strings.walletPayRemainderHint(grandTotal.toStringAsFixed(3))
                    : null,
          ),
          items: [
            DropdownMenuItem(value: 'كاش', child: Text(strings.cash)),
            DropdownMenuItem(value: 'K-Net', child: Text(strings.knet)),
          ],
          onChanged: _walletCoversFullOrder && _appliedWalletDiscount > 0
              ? null
              : (value) {
                  if (value != null) setState(() => _paymentMethod = value);
                },
        ),
      ],
    );
  }

  Widget _buildPaymentBlock(
    CartProvider cart,
    AppStrings strings,
    double grandTotal,
  ) {
    return _buildPaymentSection(cart, strings, grandTotal);
  }

  Widget _buildTotals(CartProvider cart, AppStrings strings) {
    final subtotal = cart.totalPrice;
    final deliveryFee = _deliveryFeeFor(subtotal);
    final promoDiscount = _appliedPromoDiscount;
    final grandTotal = _computeGrandTotal(subtotal);
    final freeDelivery = _hasFreeDeliveryFor(subtotal);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          _TotalRow(
            label: strings.subtotal,
            value: subtotal,
            currency: strings.currency,
          ),
          const SizedBox(height: 6),
          _TotalRow(
            label: freeDelivery
                ? '${strings.deliveryFee} (${strings.freeDeliveryUnlocked})'
                : strings.deliveryFee,
            value: deliveryFee,
            currency: strings.currency,
            highlight: freeDelivery || _selectedZone != null,
          ),
          if (promoDiscount > 0) ...[
            const SizedBox(height: 6),
            _TotalRow(
              label: strings.promoDiscountLabel,
              value: -promoDiscount,
              currency: strings.currency,
              highlight: true,
            ),
          ],
          if (_appliedWalletDiscount > 0) ...[
            const SizedBox(height: 6),
            _TotalRow(
              label: strings.walletDiscountLabel,
              value: -_appliedWalletDiscount,
              currency: strings.currency,
              highlight: true,
            ),
          ],
          const Divider(height: 20),
          _TotalRow(
            label: strings.grandTotal,
            value: grandTotal,
            currency: strings.currency,
            isBold: true,
          ),
        ],
      ),
    );
  }

  Widget _buildReviewStep(CartProvider cart, AppStrings strings, String localeCode) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        _CheckoutRestaurantHeader(
          name: _restaurantName,
          description: _restaurantDescription,
          logoUrl: _ctx.logoUrl,
        ),
        const SizedBox(height: 16),
        ...cart.items.map(
          (item) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(item.menuItem.localizedName(localeCode)),
            subtitle: Text(
              '${item.unitPrice.toStringAsFixed(3)} ${strings.currency}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: () => cart.updateQuantity(item.id, item.quantity - 1),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('${item.quantity}'),
                IconButton(
                  onPressed: () => cart.updateQuantity(item.id, item.quantity + 1),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 32),
        if (_settings != null && _settings!.hasFreeDeliveryGoal)
          FreeDeliveryProgressBar(
            subtotal: cart.totalPrice,
            threshold: _settings!.freeDeliveryThreshold,
            baseDeliveryFee: _zoneDeliveryFee,
            strings: strings,
          ),
        CheckoutSmartRecommendations(
          recommendations: _smartRecommendationsFor(cart),
          localeCode: localeCode,
          strings: strings,
          onAddItem: (rec) => _addUpsellItem(rec, cart),
        ),
        CheckoutImpulseBumps(
          recommendations: _impulseBumpsFor(cart),
          localeCode: localeCode,
          strings: strings,
          onAddItem: (rec) => _addUpsellItem(rec, cart),
        ),
        const SizedBox(height: 8),
        _buildTotals(cart, strings),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildDetailsStep(CartProvider cart, AppStrings strings, String localeCode) {
    final grandTotal = _computeGrandTotal(cart.totalPrice);
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        Text(
          strings.phoneFirstHint,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          autofocus: true,
          decoration: InputDecoration(
            labelText: strings.phone,
            border: const OutlineInputBorder(),
            suffixIcon: _lookupInProgress
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
          validator: (value) =>
              value == null || value.trim().isEmpty ? strings.required : null,
        ),
        if (_profileLoadedNotice) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.check_circle, size: 16, color: Colors.green.shade600),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  strings.profileLoaded,
                  style: TextStyle(fontSize: 12, color: Colors.green.shade700),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        TextFormField(
          controller: _nameController,
          decoration: InputDecoration(
            labelText: strings.customerName,
            border: const OutlineInputBorder(),
          ),
          validator: (value) =>
              value == null || value.trim().isEmpty ? strings.required : null,
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _promoCodeController,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: strings.promoCodeLabel,
                  hintText: strings.promoCodeHint,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => _clearPromo(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: _validatingPromo
                  ? null
                  : () => _validatePromoCode(cart, strings),
              child: _validatingPromo
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(strings.applyPromoCode),
            ),
          ],
        ),
        if (_appliedPromoDiscount > 0) ...[
          const SizedBox(height: 8),
          Text(
            '${strings.promoApplied}: -${_appliedPromoDiscount.toStringAsFixed(3)} ${strings.currency}',
            style: TextStyle(
              color: Colors.green.shade700,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          strings.deliveryAddress,
          style: const TextStyle(
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
            decoration: InputDecoration(
              labelText: strings.governorate,
              border: const OutlineInputBorder(),
            ),
            items: _availableGovernorates
                .map(
                  (gov) => DropdownMenuItem(value: gov, child: Text(gov)),
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
              return value == null || value.isEmpty ? strings.required : null;
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _selectedZone?.id,
            decoration: InputDecoration(
              labelText: strings.area,
              border: const OutlineInputBorder(),
              helperText: _areasForGovernorate.isEmpty && _selectedGovernorate != null
                  ? strings.noAreasForGovernorate
                  : null,
            ),
            items: _areasForGovernorate
                .map(
                  (zone) => DropdownMenuItem(
                    value: zone.id,
                    child: Text(
                      '${zone.areaName} (${zone.deliveryFee.toStringAsFixed(3)} ${strings.currency})',
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
                    _refreshClosingPreview(cartItemCount: cart.itemCount);
                  },
            validator: (value) {
              if (_zones.isEmpty) return null;
              return value == null || value.isEmpty ? strings.required : null;
            },
          ),
        ],
        const SizedBox(height: 12),
        TextFormField(
          controller: _blockController,
          decoration: InputDecoration(
            labelText: strings.block,
            border: const OutlineInputBorder(),
          ),
          validator: (value) =>
              value == null || value.trim().isEmpty ? strings.required : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _streetController,
          decoration: InputDecoration(
            labelText: strings.street,
            border: const OutlineInputBorder(),
          ),
          validator: (value) =>
              value == null || value.trim().isEmpty ? strings.required : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _avenueController,
          decoration: InputDecoration(
            labelText: strings.avenue,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _houseController,
          decoration: InputDecoration(
            labelText: strings.houseNumber,
            border: const OutlineInputBorder(),
          ),
          validator: (value) =>
              value == null || value.trim().isEmpty ? strings.required : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _floorController,
          decoration: InputDecoration(
            labelText: strings.floorApartment,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _notesController,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: strings.orderNotesLabel,
            hintText: strings.orderNotesHint,
            border: const OutlineInputBorder(),
          ),
        ),
        _buildPaymentBlock(cart, strings, grandTotal),
        const SizedBox(height: 16),
        if (_settings?.smartClosingEnabled == true && _closingPreview != null) ...[
          CheckoutClosingBanner(
            closing: _closingPreview!,
            localeCode: localeCode,
          ),
          CheckoutEtaCard(
            closing: _closingPreview!,
            strings: strings,
            localeCode: localeCode,
          ),
          const SizedBox(height: 12),
        ] else if (_settings?.smartClosingEnabled == true && _loadingClosing)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: LinearProgressIndicator(),
          ),
        _buildTotals(cart, strings),
        const SizedBox(height: 12),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final locale = context.watch<LocaleProvider>();
    final strings = AppStrings(locale.localeCode);
    final subtotal = cart.totalPrice;
    final grandTotal = _computeGrandTotal(subtotal);

    return Directionality(
      textDirection: locale.textDirection,
      child: Padding(
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
                      if (_step == _CheckoutStep.details)
                        IconButton(
                          onPressed: () => setState(() => _step = _CheckoutStep.review),
                          icon: const Icon(Icons.arrow_back),
                        ),
                      Expanded(
                        child: Text(
                          strings.checkoutTitle,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.brandMaroon,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: locale.isArabic ? 'English' : 'العربية',
                        onPressed: () => context.read<LocaleProvider>().toggle(),
                        icon: Text(
                          locale.isArabic ? 'EN' : 'ع',
                          style: const TextStyle(
                            color: AppTheme.brandOrange,
                            fontWeight: FontWeight.bold,
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
                _buildStepIndicator(strings),
                const Divider(),
                Expanded(
                  child: _step == _CheckoutStep.review
                      ? _buildReviewStep(cart, strings, locale.localeCode)
                      : _buildDetailsStep(cart, strings, locale.localeCode),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: _step == _CheckoutStep.review
                      ? FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.brandMaroon,
                            minimumSize: const Size.fromHeight(52),
                          ),
                          onPressed: cart.isEmpty
                              ? null
                              : () => _goToDetailsStep(cart, strings),
                          child: Text(
                            strings.continueToDetails,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      : FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.brandMaroon,
                            minimumSize: const Size.fromHeight(52),
                          ),
                          onPressed: _submitting ? null : () => _submit(cart, strings),
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
                                  strings.sendOrder(grandTotal.toStringAsFixed(3)),
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
      ),
    );
  }
}

extension _CustomerCheckoutProfileCopy on CustomerCheckoutProfile {
  CustomerCheckoutProfile copyWithPhone(String phone) {
    return CustomerCheckoutProfile(
      phone: phone,
      customerName: customerName,
      governorate: governorate,
      areaName: areaName,
      deliveryZoneId: deliveryZoneId,
      addressDetails: addressDetails,
      paymentMethod: paymentMethod,
      customerId: customerId,
      personalPromoCode: personalPromoCode,
      personalPromoDiscount: personalPromoDiscount,
      walletBalance: walletBalance,
      walletPromoCode: walletPromoCode,
    );
  }
}

class _StepChip extends StatelessWidget {
  const _StepChip({
    required this.label,
    required this.active,
    required this.completed,
  });

  final String label;
  final bool active;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? AppTheme.brandMaroon
        : completed
            ? Colors.green.shade600
            : Colors.grey.shade400;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: active ? AppTheme.brandMaroon.withValues(alpha: 0.08) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: active ? AppTheme.brandMaroon.withValues(alpha: 0.35) : Colors.grey.shade300,
        ),
      ),
      child: Row(
        children: [
          Icon(
            completed ? Icons.check_circle : Icons.circle,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? AppTheme.brandMaroon : Colors.grey.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckoutRestaurantHeader extends StatelessWidget {
  const _CheckoutRestaurantHeader({
    required this.name,
    required this.description,
    required this.logoUrl,
  });

  final String name;
  final String description;
  final String logoUrl;

  @override
  Widget build(BuildContext context) {
    final previewUrl = logoUrl.isNotEmpty ? resolvePreviewImageUrl(logoUrl) : '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: previewUrl.isNotEmpty
                ? NetworkMenuImage(
                    imageUrl: previewUrl,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _logoPlaceholder(),
                  )
                : _logoPlaceholder(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.brandMaroon,
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _logoPlaceholder() {
    return Container(
      width: 56,
      height: 56,
      color: AppTheme.brandOrange.withValues(alpha: 0.12),
      child: const Icon(Icons.storefront, color: AppTheme.brandOrange),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.value,
    required this.currency,
    this.isBold = false,
    this.highlight = false,
  });

  final String label;
  final double value;
  final String currency;
  final bool isBold;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final prefix = value < 0 ? '' : '';
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
          '$prefix${value.toStringAsFixed(3)} $currency',
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: isBold ? AppTheme.brandMaroon : Colors.black87,
          ),
        ),
      ],
    );
  }
}
