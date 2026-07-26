import 'dart:html' as html;

void printPosReceiptHtml(String htmlContent) {
  final popup = html.window.open('about:blank', '_blank');
  if (popup == null) return;

  // Legacy DOM APIs vary across Dart web SDK versions — use dynamic access.
  final dynamic win = popup;
  win.document.open();
  win.document.write(htmlContent);
  win.document.close();
  win.focus();
  win.print();
}
