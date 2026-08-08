import 'package:flutter/material.dart';

import '../../../models/pos_role.dart';
import '../../../services/restaurant_settings_service.dart';
import 'admin_cashier_management_section.dart';

class PosStaffPage extends StatefulWidget {
  const PosStaffPage({super.key});

  @override
  State<PosStaffPage> createState() => _PosStaffPageState();
}

class _PosStaffPageState extends State<PosStaffPage> {
  List<PosRole> _roles = PosRole.defaults();

  @override
  void initState() {
    super.initState();
    _loadRoles();
  }

  Future<void> _loadRoles() async {
    try {
      final settings = await RestaurantSettingsService.instance.load();
      if (!mounted) return;
      setState(() => _roles = settings.resolvedPosRoles);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        AdminCashierManagementSection(
          roles: _roles,
        ),
      ],
    );
  }
}
