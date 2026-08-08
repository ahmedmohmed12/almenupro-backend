import 'dart:html' as html;

void listenToAdminHistory(void Function() onPop) {
  html.window.onPopState.listen((_) => onPop());
}
