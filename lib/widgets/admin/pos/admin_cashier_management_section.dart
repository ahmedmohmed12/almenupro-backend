import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/pos_role.dart';
import '../../../models/staff_user.dart';
import '../../../services/pos_operations_service.dart';
import '../admin_corner_toast.dart';
import 'pos_add_staff_dialog.dart';

/// Persistent cashier management UI: compact add/edit form + staff list with actions.
class AdminCashierManagementSection extends StatefulWidget {
  const AdminCashierManagementSection({
    super.key,
    this.roles = const [],
    this.onStaffChanged,
  });

  final List<PosRole> roles;
  final VoidCallback? onStaffChanged;

  @override
  State<AdminCashierManagementSection> createState() =>
      _AdminCashierManagementSectionState();
}

class _AdminCashierManagementSectionState
    extends State<AdminCashierManagementSection> {
  static const burgundy = Color(0xFF6B1124);

  final _nameController = TextEditingController();
  final _pinController = TextEditingController();
  final _formKey = GlobalKey();
  var _role = PosStaffFormRole.cashier;
  var _loadingList = true;
  var _submitting = false;
  var _deletingId = '';
  String? _editingStaffId;
  String? _formError;
  List<StaffUser> _staff = const [];

  bool get _isEditing => _editingStaffId != null;

  @override
  void initState() {
    super.initState();
    _refreshStaff(showSpinner: true);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _refreshStaff({bool showSpinner = false}) async {
    if (showSpinner && mounted) {
      setState(() => _loadingList = true);
    }
    try {
      final staff = await PosOperationsService.instance.fetchStaffUsers();
      if (!mounted) return;
      setState(() {
        _staff = staff;
        _loadingList = false;
      });
      widget.onStaffChanged?.call();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingList = false);
    }
  }

  void _clearForm() {
    _nameController.clear();
    _pinController.clear();
    setState(() {
      _role = PosStaffFormRole.cashier;
      _editingStaffId = null;
      _formError = null;
    });
  }

  void _startEdit(StaffUser member) {
    final matchedRole = PosStaffFormRole.values
        .where((entry) => entry.roleId == member.roleId)
        .firstOrNull;
    setState(() {
      _editingStaffId = member.id;
      _nameController.text = member.name;
      _pinController.clear();
      _role = matchedRole ?? PosStaffFormRole.cashier;
      _formError = null;
    });
    final ctx = _formKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 250),
        alignment: 0.05,
      );
    }
  }

  Future<void> _submitInline() async {
    final name = _nameController.text.trim();
    final pin = _pinController.text.trim();

    if (name.isEmpty) {
      setState(() => _formError = 'أدخل اسم الكاشير');
      return;
    }
    if (!_isEditing && pin.length < 4) {
      setState(() => _formError = 'كلمة المرور / PIN يجب أن تكون 4 أرقام على الأقل');
      return;
    }
    if (_isEditing && pin.isNotEmpty && pin.length < 4) {
      setState(() => _formError = 'كلمة المرور الجديدة يجب أن تكون 4 أرقام على الأقل');
      return;
    }

    setState(() {
      _submitting = true;
      _formError = null;
    });

    try {
      if (_isEditing) {
        await PosOperationsService.instance.updateStaffUser(
          _editingStaffId!,
          name: name,
          roleId: _role.roleId,
          pin: pin.isEmpty ? null : pin,
        );
        if (!mounted) return;
        AdminCornerToast.success(context, 'تم تحديث بيانات الكاشير');
      } else {
        await PosOperationsService.instance.createStaffUser(
          name: name,
          roleId: _role.roleId,
          pin: pin,
        );
        if (!mounted) return;
        AdminCornerToast.success(context, 'تم إضافة الكاشير بنجاح');
      }
      if (!mounted) return;
      _clearForm();
      setState(() => _submitting = false);
      await _refreshStaff();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _formError = error.toString().replaceFirst('Exception: ', '');
      });
      AdminCornerToast.error(
        context,
        _isEditing ? 'تعذر تحديث الكاشير' : 'تعذر إضافة الكاشير',
      );
    }
  }

  Future<void> _confirmDelete(StaffUser member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف الكاشير'),
        content: Text(
          'هل أنت متأكد من حذف الكاشير "${member.name}"؟\nلا يمكن التراجع عن هذا الإجراء.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deletingId = member.id);
    try {
      await PosOperationsService.instance.deleteStaffUser(member.id);
      if (!mounted) return;
      if (_editingStaffId == member.id) {
        _clearForm();
      }
      AdminCornerToast.success(context, 'تم حذف الكاشير');
      await _refreshStaff();
    } catch (error) {
      if (!mounted) return;
      AdminCornerToast.error(
        context,
        error.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) setState(() => _deletingId = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeyedSubtree(key: _formKey, child: _buildAddFormCard()),
        const SizedBox(height: 10),
        _buildStaffListCard(),
      ],
    );
  }

  Widget _buildAddFormCard() {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: const Color(0xFFFFF8F6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: burgundy.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _isEditing ? 'تعديل بيانات الكاشير' : 'إضافة كاشير جديد',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (_isEditing)
                  TextButton.icon(
                    onPressed: _submitting ? null : _clearForm,
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('إلغاء'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                IconButton(
                  tooltip: 'تحديث القائمة',
                  visualDensity: VisualDensity.compact,
                  onPressed:
                      _loadingList ? null : () => _refreshStaff(showSpinner: true),
                  icon: _loadingList
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 6),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 720;
                final nameField = TextField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  enabled: !_submitting,
                  decoration: const InputDecoration(
                    labelText: 'اسم الكاشير',
                    hintText: 'مثال: أحمد',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                  ),
                );
                final pinField = TextField(
                  controller: _pinController,
                  obscureText: true,
                  enabled: !_submitting,
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: _isEditing
                        ? 'كلمة مرور جديدة (اختياري)'
                        : 'كلمة المرور / PIN',
                    hintText:
                        _isEditing ? 'اتركه فارغاً للإبقاء' : '4 أرقام على الأقل',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                    counterText: '',
                    isDense: true,
                  ),
                  onSubmitted: (_) => _submitInline(),
                );
                final roleField = DropdownButtonFormField<PosStaffFormRole>(
                  key: ValueKey('role-$_role-$_editingStaffId'),
                  initialValue: _role,
                  decoration: const InputDecoration(
                    labelText: 'الصلاحية',
                    prefixIcon: Icon(Icons.badge_outlined),
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                  ),
                  items: PosStaffFormRole.values
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry,
                          child: Text(entry.labelAr),
                        ),
                      )
                      .toList(),
                  onChanged: _submitting
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() => _role = value);
                        },
                );
                final submit = FilledButton.icon(
                  onPressed: _submitting ? null : _submitInline,
                  style: FilledButton.styleFrom(
                    backgroundColor: burgundy,
                    minimumSize: const Size.fromHeight(44),
                  ),
                  icon: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(_isEditing ? Icons.save : Icons.person_add_alt_1),
                  label: Text(
                    _submitting
                        ? 'جاري الحفظ...'
                        : _isEditing
                            ? 'حفظ التعديل'
                            : 'حفظ الكاشير',
                  ),
                );

                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: nameField),
                      const SizedBox(width: 8),
                      Expanded(flex: 2, child: pinField),
                      const SizedBox(width: 8),
                      Expanded(flex: 2, child: roleField),
                      const SizedBox(width: 8),
                      SizedBox(width: 150, child: submit),
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    nameField,
                    const SizedBox(height: 8),
                    pinField,
                    const SizedBox(height: 8),
                    roleField,
                    const SizedBox(height: 10),
                    submit,
                  ],
                );
              },
            ),
            if (_formError != null) ...[
              const SizedBox(height: 6),
              Text(
                _formError!,
                style: TextStyle(color: Colors.red.shade700, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStaffListCard() {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'قائمة الكاشير',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
                Text(
                  '${_staff.length} موظف',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_loadingList && _staff.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: CircularProgressIndicator(color: burgundy, strokeWidth: 2),
              ),
            )
          else if (_staff.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'لا يوجد كاشير بعد — استخدم النموذج أعلاه للإضافة',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _staff.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final member = _staff[index];
                final isDeleting = _deletingId == member.id;
                final isSelected = _editingStaffId == member.id;
                return ListTile(
                  dense: true,
                  selected: isSelected,
                  selectedTileColor: burgundy.withValues(alpha: 0.06),
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: burgundy.withValues(alpha: 0.12),
                    foregroundColor: burgundy,
                    child: Text(
                      member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(
                    member.name,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  subtitle: Text(
                    '${roleLabelForStaff(member, roles: widget.roles)} • كلمة المرور: ${member.maskedPin}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Chip(
                        label: Text(
                          member.isActive ? 'نشط' : 'موقوف',
                          style: const TextStyle(fontSize: 11),
                        ),
                        backgroundColor: member.isActive
                            ? Colors.green.shade50
                            : Colors.grey.shade200,
                        side: BorderSide.none,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'تعديل',
                        visualDensity: VisualDensity.compact,
                        onPressed: (_submitting || isDeleting)
                            ? null
                            : () => _startEdit(member),
                        icon: Icon(
                          Icons.edit_outlined,
                          color: burgundy.withValues(alpha: 0.9),
                          size: 20,
                        ),
                      ),
                      IconButton(
                        tooltip: 'حذف',
                        visualDensity: VisualDensity.compact,
                        onPressed: (_submitting || isDeleting)
                            ? null
                            : () => _confirmDelete(member),
                        icon: isDeleting
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.red.shade700,
                                ),
                              )
                            : Icon(
                                Icons.delete_outline,
                                color: Colors.red.shade700,
                                size: 20,
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
