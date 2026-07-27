import 'package:flutter/material.dart';

import 'admin_sidebar.dart';

/// Live status reported by [AdminMenuPanel] to the dashboard shell.
class AdminMenuPanelStatus {
  const AdminMenuPanelStatus({
    required this.loading,
    required this.apiOnline,
    this.errorMessage,
    required this.savingOrder,
    required this.itemCount,
  });

  final bool loading;
  final bool apiOnline;
  final String? errorMessage;
  final bool savingOrder;
  final int itemCount;

  bool get isHealthy =>
      !loading && errorMessage == null && apiOnline && !savingOrder;

  @override
  bool operator ==(Object other) {
    return other is AdminMenuPanelStatus &&
        other.loading == loading &&
        other.apiOnline == apiOnline &&
        other.errorMessage == errorMessage &&
        other.savingOrder == savingOrder &&
        other.itemCount == itemCount;
  }

  @override
  int get hashCode => Object.hash(
        loading,
        apiOnline,
        errorMessage,
        savingOrder,
        itemCount,
      );
}

/// Compact menu status shown above the sidebar collapse control — only when needed.
class AdminMenuSidebarFooter extends StatelessWidget {
  const AdminMenuSidebarFooter({
    super.key,
    required this.status,
    required this.collapsed,
  });

  final AdminMenuPanelStatus status;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    if (status.isHealthy) return const SizedBox.shrink();

    final message = _messageForStatus();
    final icon = _iconForStatus();
    final accent = _accentForStatus();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        collapsed ? 8 : 12,
        0,
        collapsed ? 8 : 12,
        6,
      ),
      child: Material(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: collapsed ? 8 : 12,
            vertical: 10,
          ),
          child: collapsed
              ? Tooltip(
                  message: message,
                  child: Icon(icon, color: accent, size: 20),
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (status.loading || status.savingOrder)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: accent,
                          ),
                        ),
                      )
                    else
                      Icon(icon, color: accent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        message,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  String _messageForStatus() {
    if (status.savingOrder) {
      return 'جاري حفظ ترتيب الأصناف...';
    }
    if (status.loading) {
      return 'جاري تحميل المنيو من السيرفر...';
    }
    if (status.errorMessage != null) {
      return 'تعذر الاتصال: ${status.errorMessage!}';
    }
    if (!status.apiOnline) {
      return 'غير متصل بالسيرفر';
    }
    return 'متصل — ${status.itemCount} صنف';
  }

  IconData _iconForStatus() {
    if (status.savingOrder || status.loading) return Icons.sync;
    if (status.errorMessage != null || !status.apiOnline) {
      return Icons.cloud_off;
    }
    return Icons.cloud_done;
  }

  Color _accentForStatus() {
    if (status.savingOrder || status.loading) return AdminSidebar.activeGold;
    if (status.errorMessage != null || !status.apiOnline) {
      return const Color(0xFFFF8A80);
    }
    return const Color(0xFF81C784);
  }
}
