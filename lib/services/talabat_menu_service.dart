import 'package:flutter/material.dart';

import 'menu_sync_service.dart';
import 'talabat_scraper_client.dart';

bool isWebUrl(String input) {
  final trimmed = input.trim().toLowerCase();
  return trimmed.startsWith('http://') || trimmed.startsWith('https://');
}

bool isTalabatMenuUrl(String input) {
  return isWebUrl(input) && input.trim().toLowerCase().contains('talabat');
}

final TalabatScraperClient _scraperClient = TalabatScraperClient();

/// Fetches live menu items (with images) from Talabat via Cloud Functions.
Future<List<Map<String, dynamic>>> fetchTalabatMenuItems({
  required String url,
}) async {
  if (!isTalabatMenuUrl(url)) {
    return [];
  }

  final result = await _scraperClient.scrapeMenu(url);
  return result.items;
}

/// Processes a Talabat menu URL and syncs items into Firestore.
Future<void> processAndSaveTalabatMenu({
  required String url,
  required void Function(String message) onProgress,
  required void Function(int added, int skipped, int updated) onComplete,
}) async {
  final normalizedUrl = url.trim();

  if (normalizedUrl.isEmpty) {
    onProgress('يرجى إدخال رابط صحيح أولاً');
    onComplete(0, 0, 0);
    return;
  }

  if (!isTalabatMenuUrl(normalizedUrl)) {
    onProgress('استخدم رابط Talabat (طلبات) الصحيح');
    onComplete(0, 0, 0);
    return;
  }

  try {
    onProgress('جاري سحب الأصناف والأسعار والوصف والصور من Talabat...');

    final result = await _scraperClient.scrapeMenu(normalizedUrl);
    if (result.items.isEmpty) {
      onProgress('لم يتم العثور على أصناف في هذا الرابط');
      onComplete(0, 0, 0);
      return;
    }

    final withImages =
        result.items.where((item) => (item['imageUrl'] ?? '').toString().isNotEmpty).length;

    onProgress(
      'تم جلب ${result.items.length} صنف ($withImages صورة) — جاري الحفظ السريع...',
    );

    var totalInMenu = 0;
    await syncAndAddNewItems(
      incomingItems: result.items,
      updateExisting: true,
      sourceUrl: normalizedUrl,
      onComplete: (added, skipped, updated) {
        onComplete(added, skipped, updated);
        onProgress('تم الحفظ بنجاح!');
      },
      onTotalCount: (total) => totalInMenu = total,
    );

    if (totalInMenu > 0 && totalInMenu < result.items.length) {
      onProgress(
        'تنبيه: وُجد ${result.items.length} صنف في Talabat لكن المنيو المحفوظ يحتوي $totalInMenu. '
        'أعد التعبئة أو احذف الأصناف القديمة ثم أعد الاستيراد.',
      );
    }
  } on TalabatScrapeException catch (error) {
    onProgress(error.message);
    onComplete(0, 0, 0);
  } catch (error) {
    debugPrint('Talabat import error: $error');
    onProgress('تعذر سحب المنيو. تأكد من نشر Cloud Functions');
    onComplete(0, 0, 0);
  }
}
