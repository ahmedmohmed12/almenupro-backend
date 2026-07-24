import 'package:flutter/material.dart';

import 'api_service.dart';
import 'talabat_scraper_client.dart';

bool isWebUrl(String input) {
  final trimmed = input.trim().toLowerCase();
  return trimmed.startsWith('http://') || trimmed.startsWith('https://');
}

bool isTalabatMenuUrl(String input) {
  return isWebUrl(input) && input.trim().toLowerCase().contains('talabat');
}

final TalabatScraperClient _scraperClient = TalabatScraperClient();

Future<List<Map<String, dynamic>>> fetchTalabatMenuItems({
  required String url,
}) async {
  if (!isTalabatMenuUrl(url)) {
    return [];
  }

  final result = await _scraperClient.scrapeMenu(url);
  return result.items;
}

Future<void> processAndSaveTalabatMenu({
  required String url,
  required void Function(String message) onProgress,
  required void Function(int added, int skipped, int updated) onComplete,
  String? restaurantId,
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

  final targetRestaurantId = restaurantId ?? ApiService.defaultRestaurantId;

  try {
    onProgress('جاري سحب الأصناف والأسعار والوصف والصور من Talabat...');

    final result = await _scraperClient.scrapeMenu(normalizedUrl);
    if (result.items.isEmpty) {
      onProgress('لم يتم العثور على أصناف في هذا الرابط');
      onComplete(0, 0, 0);
      return;
    }

    final withImages = result.items
        .where((item) => (item['imageUrl'] ?? '').toString().isNotEmpty)
        .length;

    onProgress(
      'تم جلب ${result.items.length} صنف ($withImages صورة) — جاري الحفظ على السيرفر...',
    );

    final apiItems = result.items
        .map(
          (item) => {
            'name': item['name'],
            'description': item['description'] ?? '',
            'price': item['price'] ?? 0.0,
            'categoryName': item['categoryName'] ?? item['category_name'] ?? 'عام',
            'isAvailable': item['isAvailable'] ?? true,
            'imageUrl': item['imageUrl'] ?? '',
            'talabatId': item['talabatId'] ?? item['talabat_id'],
            'source': item['source'] ?? 'Talabat',
          },
        )
        .toList();

    final synced = await ApiService.instance.syncMenuItems(
      apiItems,
      restaurantId: targetRestaurantId,
    );

    if (!synced) {
      onProgress('فشل حفظ المنيو على السيرفر. تأكد من صلاحيات Super Admin.');
      onComplete(0, 0, 0);
      return;
    }

    onProgress('تم الحفظ بنجاح!');
    onComplete(result.items.length, 0, 0);
  } on TalabatScrapeException catch (error) {
    onProgress(error.message);
    onComplete(0, 0, 0);
  } catch (error) {
    debugPrint('Talabat import error: $error');
    onProgress('تعذر سحب المنيو. تأكد من نشر Cloud Functions');
    onComplete(0, 0, 0);
  }
}
