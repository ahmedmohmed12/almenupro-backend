import '../models/order.dart';
import '../models/pos_role.dart';
import '../utils/pos_receipt_html.dart';
import 'admin_auth_service.dart';
import 'pos_operations_service.dart';
import 'pos_print_service.dart';

/// Lightweight print helper for KDS and admin panels.
abstract final class PosPrintHelper {
  static bool get canPrint =>
      PosOperationsService.instance.allows(PosPermissionKeys.printInvoice) ||
      AdminAuthService.instance.isRestaurantAdmin ||
      AdminAuthService.instance.isSuperAdmin;

  static String get restaurantName {
    final name = AdminAuthService.instance.restaurantName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return 'AlMenuPro';
  }

  static Future<void> printOrder({
    required Order order,
    required PosReceiptKind kind,
  }) async {
    if (!canPrint) return;
    final html = PosReceiptHtml.build(
      order: order,
      restaurantName: restaurantName,
      kind: kind,
    );
    if (html.trim().isEmpty) return;
    printPosReceiptHtml(html);
  }
}
