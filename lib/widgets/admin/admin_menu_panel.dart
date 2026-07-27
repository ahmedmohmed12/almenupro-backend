import 'package:flutter/material.dart';

import '../../models/menu_item.dart';
import '../../services/api_service.dart';
import '../../services/menu_storage_service.dart';
import '../network_menu_image.dart';
import 'admin_menu_panel_status.dart';

class AdminMenuPanel extends StatefulWidget {
  const AdminMenuPanel({
    super.key,
    required this.onAddItem,
    required this.onEditItem,
    required this.onDeleteItem,
    this.onAutofillTalabat,
    this.canImportTalabat = false,
    this.canManageItems = true,
    this.onStatusChanged,
  });

  final Future<void> Function() onAddItem;
  final Future<void> Function(MenuItemRecord record) onEditItem;
  final void Function(String id) onDeleteItem;
  final VoidCallback? onAutofillTalabat;
  final bool canImportTalabat;
  final bool canManageItems;
  final ValueChanged<AdminMenuPanelStatus>? onStatusChanged;

  @override
  State<AdminMenuPanel> createState() => _AdminMenuPanelState();
}

class _AdminMenuPanelState extends State<AdminMenuPanel> {
  static const burgundy = Color(0xFF6B1124);

  List<MenuItem> _apiItems = [];
  var _loading = true;
  var _savingOrder = false;
  var _apiOnline = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadFromApi();
  }

  void _emitStatus() {
    widget.onStatusChanged?.call(
      AdminMenuPanelStatus(
        loading: _loading,
        apiOnline: _apiOnline,
        errorMessage: _errorMessage,
        savingOrder: _savingOrder,
        itemCount: _apiItems.length,
      ),
    );
  }

  Future<void> _loadFromApi() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    _emitStatus();

    try {
      final items = await ApiService.instance.fetchMenuItems();
      items.sort((a, b) {
        final order = a.displayOrder.compareTo(b.displayOrder);
        if (order != 0) return order;
        return a.name.compareTo(b.name);
      });
      _apiItems = items;
      _apiOnline = true;
      _errorMessage = null;
    } catch (error) {
      _apiItems = [];
      _apiOnline = false;
      _errorMessage = error.toString().replaceFirst('Exception: ', '');
    }

    if (mounted) {
      setState(() => _loading = false);
      _emitStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildToolbar(),
          const SizedBox(height: 16),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'قائمة الأصناف الحالية',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _loading ? null : _loadFromApi,
                icon: const Icon(Icons.refresh),
                label: const Text('تحديث من السيرفر'),
              ),
              if (widget.canImportTalabat && widget.onAutofillTalabat != null) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: widget.onAutofillTalabat,
                  icon: const Icon(Icons.cloud_download),
                  label: const Text('تعبئة منيو Talabat'),
                ),
              ],
              const SizedBox(height: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: burgundy),
                onPressed: () async {
                  await widget.onAddItem();
                  await _loadFromApi();
                },
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text(
                  'إضافة صنف جديد',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          );
        }

        return Row(
          children: [
            const Expanded(
              child: Text(
                'قائمة الأصناف الحالية',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
            Flexible(
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _loadFromApi,
                    icon: const Icon(Icons.refresh),
                    label: const Text('تحديث من السيرفر'),
                  ),
                  if (widget.canImportTalabat && widget.onAutofillTalabat != null)
                    OutlinedButton.icon(
                      onPressed: widget.onAutofillTalabat,
                      icon: const Icon(Icons.cloud_download),
                      label: const Text('تعبئة Talabat'),
                    ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: burgundy),
                    onPressed: () async {
                      await widget.onAddItem();
                      await _loadFromApi();
                    },
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: const Text(
                      'إضافة صنف جديد',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: burgundy),
            SizedBox(height: 16),
            Text('جاري جلب الأصناف من السيرفر...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return _buildErrorState(
        message: _errorMessage!,
        onRetry: _loadFromApi,
      );
    }

    if (_apiItems.isNotEmpty) {
      return _buildApiTable(_apiItems);
    }

    return StreamBuilder<List<MenuItemRecord>>(
      stream: MenuStorageService.instance.watchItems(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildErrorState(
            message: 'خطأ في التخزين المحلي: ${snapshot.error}',
            onRetry: _loadFromApi,
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: burgundy),
          );
        }

        final records = snapshot.data ?? [];
        if (records.isEmpty) {
          return _buildErrorState(
            message: 'لا توجد أصناف على السيرفر أو في التخزين المحلي.',
            onRetry: _loadFromApi,
            showTalabatButton: true,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'عرض ${records.length} صنف من التخزين المحلي (السيرفر فارغ)',
                style: TextStyle(color: Colors.orange.shade900, fontSize: 13),
              ),
            ),
            Expanded(child: _buildLocalList(records)),
          ],
        );
      },
    );
  }

  Widget _buildErrorState({
    required String message,
    required VoidCallback onRetry,
    bool showTalabatButton = false,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 56,
              color: Colors.grey.shade500,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: burgundy),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, color: Colors.white),
              label: const Text(
                'إعادة المحاولة',
                style: TextStyle(color: Colors.white),
              ),
            ),
            if (showTalabatButton &&
                widget.canImportTalabat &&
                widget.onAutofillTalabat != null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: widget.onAutofillTalabat,
                icon: const Icon(Icons.cloud_download),
                label: const Text('تعبئة منيو Talabat'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildApiTable(List<MenuItem> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (compact)
              Expanded(
                child: widget.canManageItems
                    ? ReorderableListView.builder(
                        buildDefaultDragHandles: false,
                        onReorderItem: _onReorderItem,
                        itemCount: items.length,
                        itemBuilder: (context, index) =>
                            _apiItemCard(items[index], index),
                      )
                    : ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (context, index) =>
                            _apiItemCard(items[index], index),
                      ),
              )
            else ...[
              _buildWideTableHeader(),
              const Divider(height: 1),
              Expanded(
                child: widget.canManageItems
                    ? ReorderableListView.builder(
                        buildDefaultDragHandles: false,
                        onReorderItem: _onReorderItem,
                        itemCount: items.length,
                        itemBuilder: (context, index) =>
                            _buildWideTableRow(items[index], index),
                      )
                    : ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (context, index) =>
                            _buildWideTableRow(items[index], index),
                      ),
              ),
            ],
          ],
        );
      },
    );
  }

  MenuItemRecord _toRecord(MenuItem item) {
    return MenuItemRecord(
      id: item.id.toString(),
      data: item.toMap(),
    );
  }

  Future<void> _onReorderItem(int oldIndex, int newIndex) async {
    if (!widget.canManageItems || _savingOrder) return;

    setState(() {
      final moved = _apiItems.removeAt(oldIndex);
      _apiItems.insert(newIndex, moved);
    });

    await _saveDisplayOrder();
  }

  Future<void> _moveItemByStep(int index, int delta) async {
    final target = index + delta;
    if (target < 0 || target >= _apiItems.length) return;
    await _onReorderItem(index, target);
  }

  Future<void> _saveDisplayOrder() async {
    if (!widget.canManageItems) return;

    setState(() => _savingOrder = true);
    _emitStatus();
    try {
      final orderedIds = _apiItems.map((item) => item.id.toString()).toList();
      await ApiService.instance.reorderMenuItems(orderedIds);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر حفظ الترتيب: $error')),
        );
      }
      await _loadFromApi();
    } finally {
      if (mounted) {
        setState(() => _savingOrder = false);
        _emitStatus();
      }
    }
  }

  Widget _buildOrderControls(int index) {
    if (!widget.canManageItems) {
      return Text('${index + 1}');
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ReorderableDragStartListener(
          index: index,
          child: Tooltip(
            message: 'اسحب لإعادة الترتيب',
            child: Icon(Icons.drag_handle, color: Colors.grey.shade600),
          ),
        ),
        IconButton(
          tooltip: 'تحريك لأعلى',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          icon: Icon(
            Icons.arrow_upward,
            size: 18,
            color: index > 0 ? burgundy : Colors.grey.shade400,
          ),
          onPressed: (!_savingOrder && index > 0)
              ? () => _moveItemByStep(index, -1)
              : null,
        ),
        Text(
          '${index + 1}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        IconButton(
          tooltip: 'تحريك لأسفل',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          icon: Icon(
            Icons.arrow_downward,
            size: 18,
            color: index < _apiItems.length - 1 ? burgundy : Colors.grey.shade400,
          ),
          onPressed: (!_savingOrder && index < _apiItems.length - 1)
              ? () => _moveItemByStep(index, 1)
              : null,
        ),
      ],
    );
  }

  Widget _buildWideTableHeader() {
    const headerStyle = TextStyle(
      fontWeight: FontWeight.bold,
      color: burgundy,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          if (widget.canManageItems)
            const SizedBox(width: 96, child: Text('الترتيب', style: headerStyle)),
          const SizedBox(width: 72, child: Text('الصورة', style: headerStyle)),
          const Expanded(
            flex: 3,
            child: Text('الاسم', style: headerStyle),
          ),
          const Expanded(
            flex: 2,
            child: Text('القسم', style: headerStyle),
          ),
          const Expanded(
            child: Text('السعر', style: headerStyle),
          ),
          const SizedBox(width: 110, child: Text('الحالة', style: headerStyle)),
          if (widget.canManageItems)
            const SizedBox(width: 156, child: Text('إجراءات', style: headerStyle)),
        ],
      ),
    );
  }

  Widget _buildWideTableRow(MenuItem item, int index) {
    return Material(
      key: ValueKey(item.id),
      color: index.isEven ? Colors.grey.shade50 : Colors.white,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (widget.canManageItems)
                  SizedBox(width: 96, child: _buildOrderControls(index)),
                SizedBox(width: 72, height: 56, child: _itemThumb(item.imageUrl)),
                Expanded(
                  flex: 3,
                  child: Text(
                    item.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(item.categoryName),
                ),
                Expanded(
                  child: Text('${item.price.toStringAsFixed(3)} د.ك'),
                ),
                SizedBox(
                  width: 110,
                  child: Chip(
                    label: Text(item.isAvailable ? 'متوفر' : 'غير متوفر'),
                    backgroundColor:
                        item.isAvailable ? Colors.green.shade50 : Colors.red.shade50,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                if (widget.canManageItems)
                  SizedBox(width: 156, child: _apiItemActions(item)),
              ],
            ),
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }

  Widget _apiItemActions(MenuItem item) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'تعديل',
          icon: const Icon(Icons.edit, color: Colors.blue),
          onPressed: _savingOrder
              ? null
              : () async {
                  await widget.onEditItem(_toRecord(item));
                  await _loadFromApi();
                },
        ),
        IconButton(
          tooltip: item.isAvailable ? 'تعطيل' : 'تفعيل',
          icon: Icon(
            item.isAvailable ? Icons.toggle_on : Icons.toggle_off,
            color: item.isAvailable ? Colors.green : Colors.grey,
          ),
          onPressed: _savingOrder ? null : () => _toggleAvailability(item),
        ),
        IconButton(
          tooltip: 'حذف',
          icon: const Icon(Icons.delete, color: Colors.red),
          onPressed: _savingOrder ? null : () => _deleteApiItem(item),
        ),
      ],
    );
  }

  Future<void> _toggleAvailability(MenuItem item) async {
    try {
      await ApiService.instance.setMenuItemAvailability(
        item.id.toString(),
        !item.isAvailable,
      );
      await _loadFromApi();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تحديث الحالة: $error')),
      );
    }
  }

  Future<void> _deleteApiItem(MenuItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('حذف "${item.name}" من المنيو؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await ApiService.instance.deleteMenuItem(item.id.toString());
      await _loadFromApi();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر الحذف: $error')),
      );
    }
  }

  Widget _apiItemCard(MenuItem item, int index) {
    return Card(
      key: ValueKey(item.id),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            if (widget.canManageItems) _buildOrderControls(index),
            SizedBox(
              width: 56,
              height: 56,
              child: _itemThumb(item.imageUrl),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${item.categoryName} • ${item.price.toStringAsFixed(3)} د.ك',
                  ),
                ],
              ),
            ),
            if (widget.canManageItems)
              _apiItemActions(item)
            else
              Icon(
                item.isAvailable ? Icons.check_circle : Icons.cancel,
                color: item.isAvailable ? Colors.green : Colors.red,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalList(List<MenuItemRecord> records) {
    return ListView.builder(
      itemCount: records.length,
      itemBuilder: (context, index) {
        final record = records[index];
        final data = record.data;
        final imageUrl = data['imageUrl'] as String? ?? '';

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                SizedBox(width: 72, height: 72, child: _itemThumb(imageUrl)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _bilingualItemTitle(data),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      if (_bilingualItemSubtitle(data).isNotEmpty)
                        Text(
                          _bilingualItemSubtitle(data),
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 13,
                          ),
                        ),
                      Text('${data['price']} د.ك'),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue),
                  onPressed: () => widget.onEditItem(record),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => widget.onDeleteItem(record.id),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _itemThumb(String imageUrl) {
    if (imageUrl.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: burgundy.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.restaurant, color: burgundy),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: NetworkMenuImage(
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            const Icon(Icons.broken_image, color: Colors.grey),
      ),
    );
  }
}

String _bilingualItemTitle(Map<String, dynamic> data) {
  final nameAr =
      (data['nameAr'] ?? data['name_ar'] ?? data['name'] ?? '').toString().trim();
  final nameEn = (data['nameEn'] ?? data['name_en'] ?? '').toString().trim();
  if (nameAr.isNotEmpty && nameEn.isNotEmpty) return '$nameAr / $nameEn';
  return nameAr.isNotEmpty ? nameAr : nameEn;
}

String _bilingualItemSubtitle(Map<String, dynamic> data) {
  final descAr = (data['descriptionAr'] ??
          data['description_ar'] ??
          data['description'] ??
          '')
      .toString()
      .trim();
  final descEn =
      (data['descriptionEn'] ?? data['description_en'] ?? '').toString().trim();
  if (descAr.isNotEmpty && descEn.isNotEmpty) return '$descAr / $descEn';
  return descAr.isNotEmpty ? descAr : descEn;
}
