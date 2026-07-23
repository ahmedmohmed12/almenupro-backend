import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../firebase_options.dart';
import '../utils/firebase_config.dart';
import '../utils/image_url.dart';
import '../services/analytics_demo_service.dart';
import '../services/menu_storage_service.dart';
import '../services/talabat_menu_service.dart';
import '../widgets/admin/admin_menu_panel.dart';
import '../widgets/admin/admin_orders_panel.dart';
import '../widgets/admin/admin_sidebar.dart';
import '../widgets/admin/admin_top_header.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({Key? key}) : super(key: key);

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  static const _sidebarItems = [
    AdminSidebarItem(
      icon: Icons.restaurant_menu,
      label: 'إدارة المنيو والأصناف',
    ),
    AdminSidebarItem(
      icon: Icons.bar_chart,
      label: 'التحليلات والمبيعات',
    ),
    AdminSidebarItem(
      icon: Icons.store,
      label: 'إعدادات المحل والواتساب',
    ),
  ];

  bool _isAuthenticated = false;
  final _passwordController = TextEditingController();
  final String _adminPassword = '123456';
  String? _errorMessage;
  int _selectedIndex = 0;

  final _whatsappController = TextEditingController();
  bool _isSavingSettings = false;
  int _pendingOrdersCount = 0;
  var _showOrdersPanel = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _whatsappController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    if (kIsWeb &&
        (DefaultFirebaseOptions.web.apiKey.startsWith('YOUR_') ||
            DefaultFirebaseOptions.web.projectId.startsWith('YOUR_'))) {
      _whatsappController.text = '96594774950';
      if (mounted) setState(() {});
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('restaurant_info')
          .get();
      if (doc.exists && doc.data() != null) {
        _whatsappController.text =
            doc.data()?['whatsappNumber'] as String? ?? '96594774950';
      } else {
        _whatsappController.text = '96594774950';
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error loading settings: $e');
      _whatsappController.text = '96594774950';
    }
  }

  Future<void> _saveWhatsappNumber() async {
    if (_whatsappController.text.trim().isEmpty) return;
    setState(() => _isSavingSettings = true);

    if (!isFirebaseConfigured) {
      setState(() => _isSavingSettings = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تم حفظ الرقم محلياً. اربط Firebase لمزامنة الإعدادات بين الأجهزة.',
            ),
          ),
        );
      }
      return;
    }

    await FirebaseFirestore.instance
        .collection('settings')
        .doc('restaurant_info')
        .set({
      'whatsappNumber': _whatsappController.text.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    setState(() => _isSavingSettings = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ رقم الواتساب بنجاح!')),
      );
    }
  }

  void _login() {
    if (_passwordController.text == _adminPassword) {
      setState(() {
        _isAuthenticated = true;
        _errorMessage = null;
      });
    } else {
      setState(() {
        _errorMessage = 'كلمة المرور غير صحيحة!';
      });
    }
  }

  String _getDayName(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'الإثنين';
      case DateTime.tuesday:
        return 'الثلاثاء';
      case DateTime.wednesday:
        return 'الأربعاء';
      case DateTime.thursday:
        return 'الخميس';
      case DateTime.friday:
        return 'الجمعة';
      case DateTime.saturday:
        return 'السبت';
      case DateTime.sunday:
        return 'الأحد';
      default:
        return '';
    }
  }

  void _showItemDialog({MenuItemRecord? record}) {
    final isEditing = record != null;
    final Map<String, dynamic>? data = isEditing ? record.data : null;

    final nameController = TextEditingController(text: data?['name'] ?? '');
    final descController =
        TextEditingController(text: data?['description'] ?? '');
    final priceController = TextEditingController(
      text: data != null ? data['price'].toString() : '',
    );
    final categoryController = TextEditingController(
      text: data?['categoryName'] ?? 'أشهر الأصناف',
    );
    final imageUrlController = TextEditingController(
      text: normalizeMenuImageUrl(data?['imageUrl'] as String?),
    );
    var isAvailable = data?['isAvailable'] as bool? ?? true;

    showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(isEditing ? 'تعديل الصنف' : 'إضافة صنف جديد'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'اسم الوجبة / الصنف',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'الوصف',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: priceController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'السعر (د.ك)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: categoryController,
                      decoration: const InputDecoration(
                        labelText: 'اسم القسم / التصنيف',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: imageUrlController,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'مسار الصورة المحلية (اختياري)',
                        hintText: '/api/uploads/menu/123456.jpg',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('متوفر للطلب؟'),
                      value: isAvailable,
                      onChanged: (val) =>
                          setDialogState(() => isAvailable = val),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.brown,
                  ),
                  onPressed: () async {
                    if (nameController.text.isEmpty ||
                        priceController.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('يرجى ملء الاسم والسعر على الأقل'),
                        ),
                      );
                      return;
                    }

                    final itemMap = <String, dynamic>{
                      'name': nameController.text.trim(),
                      'description': descController.text.trim(),
                      'price': double.tryParse(priceController.text) ?? 0.0,
                      'categoryName': categoryController.text.trim(),
                      'categoryId': data?['categoryId'] ?? '',
                      'imageUrl': normalizeMenuImageUrl(imageUrlController.text.trim()),
                      'options': data?['options'] ?? <dynamic>[],
                      'isAvailable': isAvailable,
                    };

                    if (isEditing) {
                      await MenuStorageService.instance
                          .updateItem(record.id, itemMap);
                    } else {
                      itemMap['createdAt'] = DateTime.now().toIso8601String();
                      await MenuStorageService.instance.addItem(itemMap);
                    }

                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            isEditing
                                ? 'تم حفظ التعديلات في المنيو'
                                : 'تمت إضافة الصنف وحفظه',
                          ),
                        ),
                      );
                    }
                  },
                  child: Text(
                    isEditing ? 'حفظ التعديلات' : 'إضافة الصنف',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteItem(String docId) async {
    final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('تأكيد الحذف'),
            content: const Text(
              'هل أنت تأكد من رغبتك في حذف هذا الصنف من المنيو؟',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('حذف', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ) ??
        false;

    if (confirm) {
      await MenuStorageService.instance.deleteItem(docId);
    }
  }

  Future<void> _processAndSaveTalabatMenu({
    required String url,
    required void Function(String message) onProgress,
    required void Function(int added, int skipped, int updated) onComplete,
  }) {
    return processAndSaveTalabatMenu(
      url: url,
      onProgress: onProgress,
      onComplete: onComplete,
    );
  }

  void _showAutofillDialog() {
    final urlController = TextEditingController();
    var isLoading = false;
    String? statusMessage;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              title: const Row(
                children: [
                  Icon(Icons.cloud_download, color: Colors.brown),
                  SizedBox(width: 10),
                  Text(
                    'تعبئة المنيو تلقائياً',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'أدخل رابط Talabat لسحب الأصناف — سيتم حفظ الصور محلياً على السيرفر تلقائياً:',
                      style: TextStyle(fontSize: 13, color: Colors.black87),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: urlController,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'رابط المنيو (Talabat URL)',
                        hintText: 'https://www.talabat.com/...',
                        prefixIcon: Icon(Icons.link),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (statusMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        statusMessage!,
                        style: TextStyle(
                          color: statusMessage!.contains('نجاح') ||
                                  statusMessage!.contains('تمت')
                              ? Colors.green
                              : Colors.brown,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.pop(ctx),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.brown,
                  ),
                  icon: isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.download, color: Colors.white),
                  label: Text(
                    isLoading ? 'جاري السحب...' : 'بدء التعبئة',
                    style: const TextStyle(color: Colors.white),
                  ),
                  onPressed: isLoading
                      ? null
                      : () async {
                          final url = urlController.text.trim();
                          if (url.isEmpty) {
                            setDialogState(() {
                              statusMessage = 'يرجى إدخال رابط صحيح أولاً';
                            });
                            return;
                          }

                          setDialogState(() {
                            isLoading = true;
                            statusMessage = 'جاري الاتصال وسحب المنيو...';
                          });

                          await _processAndSaveTalabatMenu(
                            url: url,
                            onProgress: (msg) {
                              setDialogState(() => statusMessage = msg);
                            },
                            onComplete: (added, skipped, updated) {
                              setDialogState(() {
                                isLoading = false;
                                if (added > 0 || skipped > 0 || updated > 0) {
                                  final total = MenuStorageService
                                      .instance.currentItems.length;
                                  statusMessage =
                                      'تمت التعبئة! أُضيف $added، وتم تحديث $updated، وتجاهل $skipped. '
                                      'إجمالي المنيو الآن: $total صنف.';
                                } else {
                                  statusMessage =
                                      'لم تُضف أصناف جديدة. جرّب إعادة التعبئة لتحديث الأصناف الحالية.';
                                }
                              });
                            },
                          );
                        },
                ),
              ],
            );
          },
        );
      },
    ).then((_) => urlController.dispose());
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAuthenticated) {
      return Scaffold(
        backgroundColor: const Color(0xFFF4F6F8),
        body: Directionality(
          textDirection: TextDirection.rtl,
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.all(28),
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 16,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6B1124).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.admin_panel_settings,
                      size: 52,
                      color: Color(0xFF6B1124),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Almenupro',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6B1124),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'دخول لوحة الإدارة',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    onSubmitted: (_) => _login(),
                    decoration: InputDecoration(
                      labelText: 'كلمة المرور',
                      errorText: _errorMessage,
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.lock),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6B1124),
                      ),
                      onPressed: _login,
                      child: const Text(
                        'دخول',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F6F8),
        body: Row(
          children: [
            AdminSidebar(
              items: _sidebarItems,
              selectedIndex: _selectedIndex,
              onItemSelected: (index) {
                setState(() {
                  _selectedIndex = index;
                  _showOrdersPanel = false;
                });
              },
              onLogout: () {
                setState(() {
                  _isAuthenticated = false;
                  _passwordController.clear();
                  _selectedIndex = 0;
                  _showOrdersPanel = false;
                });
              },
            ),
            Expanded(
              child: Column(
                children: [
                  AdminTopHeader(
                    pendingOrdersCount: _pendingOrdersCount,
                    onNotificationsTap: () {
                      setState(() => _showOrdersPanel = true);
                    },
                  ),
                  if (_showOrdersPanel)
                    Material(
                      color: const Color(0xFF6B1124),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: () =>
                                  setState(() => _showOrdersPanel = false),
                              icon: const Icon(
                                Icons.arrow_forward,
                                color: Colors.white,
                              ),
                            ),
                            const Text(
                              'الطلبات الواردة',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Expanded(
                    child: _buildActiveTab(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveTab() {
    if (_showOrdersPanel) {
      return AdminOrdersPanel(
        onPendingCountChanged: (count) {
          if (_pendingOrdersCount != count && mounted) {
            setState(() => _pendingOrdersCount = count);
          }
        },
      );
    }

    switch (_selectedIndex) {
      case 1:
        return _buildAnalyticsTab();
      case 2:
        return _buildSettingsTab();
      case 0:
      default:
        return AdminMenuPanel(
          onAddItem: () => _showItemDialog(),
          onEditItem: (record) => _showItemDialog(record: record),
          onDeleteItem: _deleteItem,
          onAutofillTalabat: _showAutofillDialog,
        );
    }
  }

  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'إعدادات المحل والواتساب',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF6B1124),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'حدد رقم الهاتف الذي تود أن يستقبل طلبات وفواتير العملاء عبر الواتساب مباشرة:',
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _whatsappController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'رقم الواتساب بالصيغة الدولية (بدون +)',
                      hintText: 'مثال: 96594774950',
                      prefixIcon: Icon(Icons.phone, color: Colors.green),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 15),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.brown,
                      ),
                      onPressed:
                          _isSavingSettings ? null : _saveWhatsappNumber,
                      icon: _isSavingSettings
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.save, color: Colors.white),
                      label: const Text(
                        'حفظ الرقم الآن',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Analytics tab kept below

  Widget _buildAnalyticsTab() {
    if (!isFirebaseConfigured) {
      return FutureBuilder<AnalyticsSnapshot>(
        future: AnalyticsDemoService.load(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF6B1124)),
            );
          }

          return _buildAnalyticsDashboard(
            snapshot.data ?? AnalyticsDemoService.fallback(),
            showDemoBanner: true,
          );
        },
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('orders').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('خطأ: ${snapshot.error}'));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];
        var todaySales = 0.0;
        var lastWeekSales = 0.0;
        var lastMonthSales = 0.0;
        final itemSalesCount = <String, int>{};
        final hourlyOrders = <String, int>{};
        final dailyOrders = <String, int>{};

        final now = DateTime.now();
        final startOfToday = DateTime(now.year, now.month, now.day);
        final sevenDaysAgo = now.subtract(const Duration(days: 7));
        final thirtyDaysAgo = now.subtract(const Duration(days: 30));

        for (final doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          final price = (data['totalPrice'] ?? 0).toDouble();
          final timestamp = data['createdAt'] as Timestamp?;
          final orderDate =
              timestamp != null ? timestamp.toDate() : DateTime.now();

          if (orderDate.isAfter(startOfToday)) todaySales += price;
          if (orderDate.isAfter(sevenDaysAgo)) lastWeekSales += price;
          if (orderDate.isAfter(thirtyDaysAgo)) lastMonthSales += price;

          final hourKey = '${orderDate.hour}:00';
          hourlyOrders[hourKey] = (hourlyOrders[hourKey] ?? 0) + 1;

          final dayKey = _getDayName(orderDate.weekday);
          dailyOrders[dayKey] = (dailyOrders[dayKey] ?? 0) + 1;

          final items = data['items'] as List<dynamic>? ?? [];
          for (final item in items) {
            if (item is! Map) continue;
            final itemName = item['name'] as String? ?? 'صنف غير معروف';
            final qty = (item['quantity'] as num?)?.toInt() ?? 1;
            itemSalesCount[itemName] = (itemSalesCount[itemName] ?? 0) + qty;
          }
        }

        final sortedItems = itemSalesCount.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        return _buildAnalyticsDashboard(
          AnalyticsSnapshot(
            todaySales: todaySales,
            lastWeekSales: lastWeekSales,
            lastMonthSales: lastMonthSales,
            topItems: sortedItems,
            hourlyOrders: hourlyOrders,
            dailyOrders: dailyOrders,
          ),
        );
      },
    );
  }

  Widget _buildAnalyticsDashboard(
    AnalyticsSnapshot data, {
    bool showDemoBanner = false,
  }) {
    final todaySales = data.todaySales;
    final lastWeekSales = data.lastWeekSales;
    final lastMonthSales = data.lastMonthSales;
    final sortedItems = data.topItems;
    final hourlyOrders = data.hourlyOrders;
    final dailyOrders = data.dailyOrders;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showDemoBanner) _buildDemoAnalyticsBanner(),
                if (showDemoBanner) const SizedBox(height: 16),
                if (isWide)
                  Row(
                    children: [
                      _buildStatCard(
                        'مبيعات اليوم',
                        '${todaySales.toStringAsFixed(3)} د.ك',
                        Icons.today,
                        Colors.green,
                      ),
                      const SizedBox(width: 15),
                      _buildStatCard(
                        'مبيعات آخر 7 أيام',
                        '${lastWeekSales.toStringAsFixed(3)} د.ك',
                        Icons.date_range,
                        Colors.blue,
                      ),
                      const SizedBox(width: 15),
                      _buildStatCard(
                        'مبيعات آخر 30 يوم',
                        '${lastMonthSales.toStringAsFixed(3)} د.ك',
                        Icons.calendar_month,
                        Colors.orange,
                      ),
                    ],
                  )
                else
                  Column(
                    children: [
                      _buildStatCard(
                        'مبيعات اليوم',
                        '${todaySales.toStringAsFixed(3)} د.ك',
                        Icons.today,
                        Colors.green,
                        expanded: false,
                      ),
                      const SizedBox(height: 12),
                      _buildStatCard(
                        'مبيعات آخر 7 أيام',
                        '${lastWeekSales.toStringAsFixed(3)} د.ك',
                        Icons.date_range,
                        Colors.blue,
                        expanded: false,
                      ),
                      const SizedBox(height: 12),
                      _buildStatCard(
                        'مبيعات آخر 30 يوم',
                        '${lastMonthSales.toStringAsFixed(3)} د.ك',
                        Icons.calendar_month,
                        Colors.orange,
                        expanded: false,
                      ),
                    ],
                  ),
                const SizedBox(height: 25),
                if (isWide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildTopItemsCard(sortedItems)),
                      const SizedBox(width: 20),
                      Expanded(
                        child: _buildTimeCard(hourlyOrders, dailyOrders),
                      ),
                    ],
                  )
                else ...[
                  _buildTopItemsCard(sortedItems),
                  const SizedBox(height: 20),
                  _buildTimeCard(hourlyOrders, dailyOrders),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDemoAnalyticsBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD49A00).withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.insights_outlined, color: Color(0xFF6B1124)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'عرض تجريبي للتحليلات',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF6B1124),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'البيانات المعروضة تقديرية مبنية على المنيو الحالي. '
                  'لتتبع المبيعات والطلبات الحقيقية، اربط Firebase في firebase_options.dart.',
                  style: TextStyle(
                    color: Colors.brown.shade700,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopItemsCard(List<MapEntry<String, int>> sortedItems) {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'الأطباق وعدد الوجبات المباعة',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.brown,
              ),
            ),
            const Divider(),
            if (sortedItems.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('لا توجد مبيعات مسجلة بعد'),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: sortedItems.length,
                itemBuilder: (context, index) {
                  final entry = sortedItems[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      entry.key,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    trailing: Text(
                      '${entry.value} وجبة',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.brown,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeCard(
    Map<String, int> hourlyOrders,
    Map<String, int> dailyOrders,
  ) {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'تحليل أوقات الطلبات',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.brown,
              ),
            ),
            const Divider(),
            const Text(
              'أكثر الساعات طلباً:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: hourlyOrders.entries
                  .map(
                    (e) => Chip(
                      label: Text('الساعة ${e.key}: ${e.value} طلبات'),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 20),
            const Text(
              'الطلبات حسب أيام الأسبوع:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: dailyOrders.entries
                  .map((e) => Chip(label: Text('${e.key}: ${e.value} طلبات')))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color, {
    bool expanded = true,
  }) {
    final card = Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: color.withValues(alpha: 0.15),
              child: Icon(icon, color: color, size: 30),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (expanded) {
      return Expanded(child: card);
    }
    return card;
  }
}
