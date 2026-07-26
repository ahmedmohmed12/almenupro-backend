import 'dart:html' as html;

void printPosReceiptHtml(String htmlContent) {
  final iframe = html.IFrameElement()
    ..style.border = 'none'
    ..style.width = '0'
    ..style.height = '0';

  html.document.body?.append(iframe);
  final doc = iframe.contentWindow?.document;
  if (doc == null) return;

  doc.open();
  doc.write(htmlContent);
  doc.close();

  iframe.contentWindow?.print();
  iframe.remove();
}
