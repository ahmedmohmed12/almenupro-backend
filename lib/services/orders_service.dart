import '../models/cart_item.dart';
import '../models/delivery_address_details.dart';
import '../models/delivery_notification.dart';
import '../models/order.dart';
import '../models/order_platform.dart';
import '../models/smart_closing.dart';
import '../utils/firebase_config.dart';
import 'firebase_service.dart';
import 'orders_demo_service.dart';
import 'admin_auth_service.dart';
import 'api_service.dart';
import 'pos_operations_service.dart';

/// Unified orders access for admin dashboard and checkout.
class OrdersService {
  OrdersService._();

  static final OrdersService instance = OrdersService._();

  final FirebaseService _firebase = FirebaseService();

  bool get usesFirebase => isFirebaseConfigured;
  bool get isDemoMode => !usesFirebase && OrdersDemoService.isDemoData;

  Stream<List<Order>> watchOrders() {
    if (usesFirebase) return _firebase.watchOrders();
    return OrdersDemoService.watchOrders();
  }

  Future<OrderStatusUpdateResult?> updateOrderStatus(
    String orderId,
    OrderStatus status,
  ) async {
    if (usesFirebase) {
      await _firebase.updateOrderStatus(orderId, status);
      return OrderStatusUpdateResult(orderId: orderId);
    }
    return OrdersDemoService.updateOrderStatus(orderId, status);
  }

  Future<SmartClosingPayload?> submitOrderFromCart({
    required List<CartItem> cartItems,
    required String customerName,
    required String phone,
    required String address,
    required String paymentMethod,
    required String invoiceNumber,
    required String restaurantId,
    String? restaurantSlug,
    double deliveryFee = 0,
    String? governorate,
    String? areaName,
    String? deliveryZoneId,
    DeliveryAddressDetails addressDetails = const DeliveryAddressDetails(),
    String orderSource = 'pos',
    OrderType orderType = OrderType.delivery,
    PlatformOrderMeta? platformMeta,
    String? promoCode,
    double promoDiscount = 0,
    double walletAmount = 0,
    double walletDiscount = 0,
    String? targetKitchenId,
    String? targetKitchenName,
    String? cashierId,
    String? cashierName,
  }) async {
    final auth = AdminAuthService.instance;
    final cashier = PosOperationsService.instance.cashierSession;
    final resolvedCashierId =
        cashierId ?? auth.session?.staffId ?? cashier?.staff.id;
    final resolvedCashierName =
        cashierName ?? auth.session?.staffName ?? cashier?.staff.name;

    final meta = platformMeta ?? const PlatformOrderMeta();
    final order = OrdersDemoService.orderFromCart(
      cartItems: cartItems,
      customerName: customerName,
      phone: phone,
      address: address,
      paymentMethod: paymentMethod,
      invoiceNumber: invoiceNumber,
      deliveryFee: deliveryFee,
      governorate: governorate,
      areaName: areaName,
      deliveryZoneId: deliveryZoneId,
      addressDetails: addressDetails,
      orderSource: orderSource,
      orderType: orderType,
      externalOrderId: meta.externalOrderId,
      platformGrossTotal: meta.platformGrossTotal,
      platformCommission: meta.platformCommission,
      platformCommissionPercent: meta.platformCommissionPercent,
      promoCode: promoCode,
      promoDiscount: promoDiscount,
      walletAmount: walletAmount,
      walletDiscount: walletDiscount,
      targetKitchenId: targetKitchenId,
      targetKitchenName: targetKitchenName,
      cashierId: resolvedCashierId,
      cashierName: resolvedCashierName,
    );

    if (usesFirebase) {
      await _firebase.addOrder(order);
      return null;
    }

    final result = await ApiService.instance.createOrder(
      order,
      restaurantId: restaurantId,
      restaurantSlug: restaurantSlug,
    );
    await OrdersDemoService.registerOrder(result.order);
    await OrdersDemoService.refreshFromApi();
    return result.smartClosing;
  }

  Future<void> refreshOrders() async {
    if (usesFirebase) return;
    await OrdersDemoService.refreshFromApi();
  }
}
