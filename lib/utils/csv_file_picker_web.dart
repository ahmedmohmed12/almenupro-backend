import 'dart:html' as html;

/// Triggers a CSV file download in the browser.
void downloadCsvFile({required String filename, required String content}) {
  final bytes = html.Blob([content], 'text/csv;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(bytes);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}

/// Opens a native file picker and returns the selected CSV/Excel text content.
Future<String?> pickCsvFileContent() async {
  final input = html.FileUploadInputElement()
    ..accept = '.csv,.txt,text/csv,application/vnd.ms-excel'
    ..multiple = false;

  input.click();
  await input.onChange.first;
  final file = input.files?.first;
  if (file == null) return null;
  final reader = html.FileReader();
  reader.readAsText(file, 'utf-8');
  await reader.onLoad.first;
  return reader.result?.toString();
}
