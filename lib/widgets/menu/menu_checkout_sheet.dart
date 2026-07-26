import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/kuwait_governorates.dart';
import '../../l10n/app_strings.dart';
import '../../models/customer_checkout_profile.dart';
import '../../models/customer_restaurant_context.dart';
import '../../models/delivery_address_details.dart';
import '../../models/delivery_zone.dart';
import '../../providers/cart_provider.dart';
import '../../providers/locale_provider.dart';
import '../../services/api_service.dart';
import '../../services/customer_checkout_cache_service.dart';
import '../../services/orders_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/whatsapp_launcher.dart';
import '../../utils/whatsapp_order_message.dart';
import '../../utils/whatsapp_phone.dart';

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
  final _scrollController = ScrollController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _blockController = TextEditingController();
  final _streetController = TextEditingController();
  final _avenueController = TextEditingController();
  final _houseController = TextEditingController();
  final _floorController = TextEditingController();

  final _nameFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _blockFocus = FocusNode();
  final _streetFocus = FocusNode();
  final _avenueFocus = FocusNode();
  final _houseFocus = FocusNode();
  final _floorFocus = FocusNode();

  var _paymentMethod = 'كاش';
  var _submitting = false;
  var _loadingZones = true;
  var _lookupInProgress = false;
  var _profileAutofilled = false;
  var _loadingWhatsapp = true;
  var _hasWhatsapp = false;

  String _whatsappNumber = '';

  Timer? _lookupDebounce;
  String? _lastLookupPhone;

  List<DeliveryZone> _zones = [];
  String? _selectedGovernorate;
  DeliveryZone? _selectedZone;

  String get _restaurantName =>
      widget.restaurantContext?.name ?? 'Molten Cookies';

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
    if (!currentIsValid) {
      _selectedZone = areas.first;
    }
  }

  void _showFeedback(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 88),
        backgroundColor: AppTheme.brandMaroon,
      ),
    );
  }

  void _scrollToAddressFields() {
    if (!_scrollController.hasClients) return;
    unawaited(
      _scrollController.animateTo(
        280,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
      ),
    );
  }

  bool _validateBeforeSubmit(AppStrings strings) {
    FocusScope.of(context).unfocus();

    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) {
      _showFeedback(strings.fillRequiredFields);
      _scrollToAddressFields();
      return false;
    }

    if (_zones.isNotEmpty) {
      if (_selectedGovernorate == null || _selectedGovernorate!.trim().isEmpty) {
        _showFeedback(strings.selectGovernorateAndArea);
        _scrollToAddressFields();
        return false;
      }

      if (_areasForGovernorate.isEmpty) {
        _showFeedback(strings.noAreasForGovernorate);
        _scrollToAddressFields();
        return false;
      }

      if (_selectedZone == null) {
        _showFeedback(strings.selectGovernorateAndArea);
        _scrollToAddressFields();
        return false;
      }
    }

    if (!_hasWhatsapp || _whatsappNumber.trim().isEmpty) {
      _showFeedback(strings.whatsappNotConfiguredCheckout);
      return false;
    }

    return true;
  }

  Future<void> _resolveWhatsappNumber() async {
    var number = widget.restaurantContext?.whatsappNumber ?? '';

    if (number.trim().isEmpty) {
      try {
        final settings = await ApiService.instance.fetchPublicSettings(
          slug: _restaurantSlug,
          restaurantId: _restaurantId,
        );
        number = settings.fullWhatsappNumber;
      } catch (error) {
        debugPrint('Failed to resolve restaurant WhatsApp: $error');
      }
    }

    if (!mounted) return;
    setState(() {
      _whatsappNumber = number.trim();
      _hasWhatsapp = _whatsappNumber.isNotEmpty;
      _loadingWhatsapp = false;
    });
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
    _phoneController.addListener(_onPhoneChanged);
    _whatsappNumber = widget.restaurantContext?.whatsappNumber ?? '';
    _hasWhatsapp = _whatsappNumber.trim().isNotEmpty;
    unawaited(_resolveWhatsappNumber());
    unawaited(_bootstrapCheckout());
  }

  Future<void> _bootstrapCheckout() async {
    await _loadDeliveryZones();
    final lastPhone =
        await CustomerCheckoutCacheService.instance.loadLastPhone(_restaurantId);
    if (!mounted || lastPhone == null || lastPhone.trim().isEmpty) return;
    if (_phoneController.text.trim().isNotEmpty) return;
    _phoneController.text = lastPhone.trim();
  }

  void _onPhoneChanged() {
    final digits = WhatsAppPhone.digitsOnly(_phoneController.text);
    if (digits.length < 8) {
      _lookupDebounce?.cancel();
      if (_profileAutofilled) {
        setState(() => _profileAutofilled = false);
      }
      return;
    }

    if (digits == _lastLookupPhone && _profileAutofilled) return;

    _lookupDebounce?.cancel();
    _lookupDebounce = Timer(const Duration(milliseconds: 600), () {
      unawaited(_lookupCustomerProfile(digits));
    });
  }

  Future<void> _lookupCustomerProfile(String normalizedPhone) async {
    if (_lookupInProgress && _lastLookupPhone == normalizedPhone) return;

    if (!mounted) return;
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
        slug: _restaurantSlug,
      );

      if (profile != null && profile.hasUsableData) {
        await CustomerCheckoutCacheService.instance.saveProfile(
          _restaurantId,
          profile,
        );
      }

      if (!mounted || profile == null || !profile.hasUsableData) return;

      final resolvedProfile = profile;
      setState(() => _applyProfile(resolvedProfile));
      _showFeedback(AppStrings.of(context).profileLoaded);
    } finally {
      if (mounted) {
        setState(() => _lookupInProgress = false);
      }
    }
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

    _profileAutofilled = true;
  }

  CustomerCheckoutProfile _currentProfile() {
    return CustomerCheckoutProfile(
      phone: _phoneController.text.trim(),
      customerName: _nameController.text.trim(),
      governorate: _selectedZone?.governorate ?? _selectedGovernorate ?? '',
      areaName: _selectedZone?.areaName ?? '',
      deliveryZoneId: _selectedZone?.id,
      addressDetails: _addressDetails,
      paymentMethod: _paymentMethod,
    );
  }

  Future<void> _persistProfile() async {
    await CustomerCheckoutCacheService.instance.saveProfile(
      _restaurantId,
      _currentProfile(),
    );
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
        _syncDefaultArea();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingZones = false);
    }
  }

  void _focusNext(FocusNode node) {
    FocusScope.of(context).requestFocus(node);
  }

  void _unfocusKeyboard() {
    FocusScope.of(context).unfocus();
  }

  @override
  void dispose() {
    _lookupDebounce?.cancel();
    _phoneController.removeListener(_onPhoneChanged);
    _nameController.dispose();
    _phoneController.dispose();
    _blockController.dispose();
    _streetController.dispose();
    _avenueController.dispose();
    _houseController.dispose();
    _floorController.dispose();
    _nameFocus.dispose();
    _phoneFocus.dispose();
    _blockFocus.dispose();
    _streetFocus.dispose();
    _avenueFocus.dispose();
    _houseFocus.dispose();
    _floorFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _submit(CartProvider cart, AppStrings strings) async {
    if (_submitting) return;
    if (!_validateBeforeSubmit(strings)) return;

    setState(() => _submitting = true);

    try {
      final subtotal = cart.totalPrice;
      final grandTotal = subtotal + _deliveryFee;
      final invoiceNumber =
          DateTime.now().millisecondsSinceEpoch.toString().substring(5);
      final now = DateTime.now();
      final orderTime =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      final addressArabic = _formattedAddressArabic();
      final addressEnglish = _formattedAddressEnglish();

      final message = WhatsAppOrderMessage.build(
        restaurantName: _restaurantName,
        invoiceNumber: invoiceNumber,
        customerName: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        paymentMethod: _paymentMethod,
        orderTime: orderTime,
        cartItems: cart.items,
        subtotal: subtotal,
        deliveryFee: _deliveryFee,
        grandTotal: grandTotal,
        addressArabic: addressArabic,
        addressEnglish: addressEnglish,
      );

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
            address: addressArabic,
            paymentMethod: _paymentMethod,
            invoiceNumber: invoiceNumber,
            restaurantId: _restaurantId,
            deliveryFee: _deliveryFee,
            governorate: _selectedZone?.governorate ?? _selectedGovernorate,
            areaName: _selectedZone?.areaName,
            deliveryZoneId: _selectedZone?.id,
            addressDetails: _addressDetails,
          );
          await _persistProfile();
        } catch (error) {
          debugPrint('Order backend sync failed: $error');
        }
      }

      if (!mounted) return;

      if (opened) {
        cart.clear();
        Navigator.pop(context);
        _showFeedback(strings.orderSentViaWhatsapp);
      } else {
        _showFeedback(strings.whatsappOpenFailed(_whatsappNumber));
      }
    } catch (error, stackTrace) {
      debugPrint('Checkout submit failed: $error\n$stackTrace');
      if (mounted) {
        _showFeedback(strings.orderSubmitFailed);
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Widget _buildTotals(CartProvider cart, AppStrings strings) {
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
          _TotalRow(
            label: strings.subtotal,
            value: subtotal,
            currency: strings.currency,
          ),
          const SizedBox(height: 6),
          _TotalRow(
            label: strings.deliveryFee,
            value: _deliveryFee,
            currency: strings.currency,
            highlight: _selectedZone != null,
          ),
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

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final locale = context.watch<LocaleProvider>();
    final strings = AppStrings(locale.localeCode);
    final grandTotal = cart.totalPrice + _deliveryFee;

    return Directionality(
      textDirection: locale.textDirection,
      child: Scaffold(
        backgroundColor: AppTheme.brandSurface,
        resizeToAvoidBottomInset: true,
        body: Padding(
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
                const Divider(),
                Expanded(
                  child: ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      ...cart.items.map(
                        (item) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            item.menuItem.localizedName(locale.localeCode),
                          ),
                          subtitle: Text(
                            '${item.unitPrice.toStringAsFixed(3)} ${strings.currency}',
                          ),
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
                      if (_loadingWhatsapp)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: LinearProgressIndicator(color: AppTheme.brandOrange),
                        )
                      else if (!_hasWhatsapp)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppTheme.brandMaroon.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.brandMaroon.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.info_outline,
                                color: AppTheme.brandMaroon,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  strings.whatsappNotConfiguredCheckout,
                                  style: const TextStyle(
                                    color: AppTheme.brandMaroon,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      TextFormField(
                        controller: _phoneController,
                        focusNode: _phoneFocus,
                        autofocus: true,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        onFieldSubmitted: (_) => _focusNext(_nameFocus),
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
                              : _profileAutofilled
                                  ? const Icon(
                                      Icons.check_circle,
                                      color: AppTheme.brandOrange,
                                    )
                                  : null,
                          helperText:
                              _lookupInProgress ? strings.lookingUpProfile : null,
                        ),
                        validator: (value) => value == null || value.trim().isEmpty
                            ? strings.required
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _nameController,
                        focusNode: _nameFocus,
                        textInputAction: TextInputAction.next,
                        onFieldSubmitted: (_) => _focusNext(_blockFocus),
                        decoration: InputDecoration(
                          labelText: strings.customerName,
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) => value == null || value.trim().isEmpty
                            ? strings.required
                            : null,
                      ),
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
                          key: ValueKey('gov-$_selectedGovernorate'),
                          initialValue: _selectedGovernorate,
                          decoration: InputDecoration(
                            labelText: strings.governorate,
                            border: const OutlineInputBorder(),
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
                              _syncDefaultArea();
                            });
                          },
                          validator: (value) {
                            if (_zones.isEmpty) return null;
                            return value == null || value.isEmpty
                                ? strings.required
                                : null;
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          key: ValueKey(
                            'area-${_selectedGovernorate ?? ''}-${_selectedZone?.id ?? 'none'}',
                          ),
                          initialValue: _selectedZone?.id,
                          decoration: InputDecoration(
                            labelText: strings.area,
                            border: const OutlineInputBorder(),
                            helperText: _areasForGovernorate.isEmpty &&
                                    _selectedGovernorate != null
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
                                    _selectedZone =
                                        _areasForGovernorate.firstWhere(
                                      (zone) => zone.id == value,
                                    );
                                  });
                                },
                          validator: (value) {
                            if (_zones.isEmpty) return null;
                            return value == null || value.isEmpty
                                ? strings.required
                                : null;
                          },
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _blockController,
                        focusNode: _blockFocus,
                        textInputAction: TextInputAction.next,
                        onFieldSubmitted: (_) => _focusNext(_streetFocus),
                        decoration: InputDecoration(
                          labelText: strings.block,
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) => value == null || value.trim().isEmpty
                            ? strings.required
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _streetController,
                        focusNode: _streetFocus,
                        textInputAction: TextInputAction.next,
                        onFieldSubmitted: (_) => _focusNext(_avenueFocus),
                        decoration: InputDecoration(
                          labelText: strings.street,
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) => value == null || value.trim().isEmpty
                            ? strings.required
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _avenueController,
                        focusNode: _avenueFocus,
                        textInputAction: TextInputAction.next,
                        onFieldSubmitted: (_) => _focusNext(_houseFocus),
                        decoration: InputDecoration(
                          labelText: strings.avenue,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _houseController,
                        focusNode: _houseFocus,
                        textInputAction: TextInputAction.next,
                        onFieldSubmitted: (_) => _focusNext(_floorFocus),
                        decoration: InputDecoration(
                          labelText: strings.houseNumber,
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) => value == null || value.trim().isEmpty
                            ? strings.required
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _floorController,
                        focusNode: _floorFocus,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _unfocusKeyboard(),
                        decoration: InputDecoration(
                          labelText: strings.floorApartment,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: _paymentMethod,
                        decoration: InputDecoration(
                          labelText: strings.paymentMethod,
                          border: const OutlineInputBorder(),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'كاش',
                            child: Text(strings.cash),
                          ),
                          DropdownMenuItem(
                            value: 'K-Net',
                            child: Text(strings.knet),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _paymentMethod = value);
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      _buildTotals(cart, strings),
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
                    onPressed: (_submitting || _loadingWhatsapp || !_hasWhatsapp)
                        ? null
                        : () => _submit(cart, strings),
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
    ),
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
          '${value.toStringAsFixed(3)} $currency',
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: isBold ? AppTheme.brandMaroon : Colors.black87,
          ),
        ),
      ],
    );
  }
}
