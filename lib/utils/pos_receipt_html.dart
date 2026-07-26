import 'package:intl/intl.dart';

import '../models/order.dart';

enum PosReceiptKind { kitchen, customer }

class PosReceiptHtml {
  static String build({
    required Order order,
    required String restaurantName,
    required PosReceiptKind kind,
  }) {
    final time = DateFormat('yyyy-MM-dd HH:mm').format(order.createdAt.toLocal());
    final title = kind == PosReceiptKind.kitchen
        ? 'تذكرة المطبخ / Kitchen Ticket'
        : 'فاتورة العميل / Customer Receipt';
    final rows = order.items
        .map(
          (item) => '''
        <tr>
          <td>${item.quantity}x</td>
          <td>${_escape(item.name)}</td>
          <td>${item.lineTotal.toStringAsFixed(3)}</td>
        </tr>''',
        )
        .join();

    final subtotal = order.subtotal ?? order.totalPrice;
    final deliveryFee = order.deliveryFee ?? 0;

    return '''
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="UTF-8">
  <title>$title</title>
  <style>
    @page { margin: 4mm; }
    body {
      font-family: Arial, sans-serif;
      font-size: 12px;
      color: #111;
      max-width: 80mm;
      margin: 0 auto;
    }
    h1 { font-size: 16px; margin: 0 0 4px; text-align: center; }
    h2 { font-size: 13px; margin: 0 0 8px; text-align: center; color: #6B1124; }
    .meta { margin-bottom: 8px; line-height: 1.5; }
    table { width: 100%; border-collapse: collapse; margin-top: 8px; }
    th, td { padding: 4px 2px; border-bottom: 1px dashed #ccc; text-align: right; }
    th { font-size: 11px; }
    .totals { margin-top: 10px; line-height: 1.6; }
    .grand { font-size: 14px; font-weight: bold; margin-top: 6px; }
    .footer { margin-top: 12px; text-align: center; font-size: 11px; color: #666; }
  </style>
</head>
<body>
  <h1>${_escape(restaurantName)}</h1>
  <h2>$title</h2>
  <div class="meta">
    <div>رقم الفاتورة: ${_escape(order.invoiceNumber ?? order.id)}</div>
    <div>الوقت: $time</div>
    <div>العميل: ${_escape(order.customerName)}</div>
    <div>الهاتف: ${_escape(order.phone)}</div>
    ${kind == PosReceiptKind.kitchen ? '' : '<div>العنوان: ${_escape(order.address)}</div>'}
    <div>الدفع: ${_escape(order.paymentMethod ?? 'كاش')}</div>
    ${order.orderSource == 'pos' ? '<div>المصدر: نقطة البيع POS</div>' : ''}
  </div>
  <table>
    <thead>
      <tr>
        <th>الكمية</th>
        <th>الصنف</th>
        <th>المبلغ</th>
      </tr>
    </thead>
    <tbody>
      $rows
    </tbody>
  </table>
  <div class="totals">
    <div>المجموع الفرعي: ${subtotal.toStringAsFixed(3)} د.ك</div>
    <div>رسوم التوصيل: ${deliveryFee.toStringAsFixed(3)} د.ك</div>
    <div class="grand">الإجمالي: ${order.totalPrice.toStringAsFixed(3)} د.ك</div>
  </div>
  <div class="footer">Almenupro POS</div>
  <script>window.onload = function(){ window.print(); };</script>
</body>
</html>''';
  }

  static String _escape(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }
}
