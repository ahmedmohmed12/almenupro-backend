import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/restaurant.dart';
import '../../services/api_service.dart';
import '../../services/super_admin_scope_service.dart';
import '../../services/talabat_menu_service.dart';
import '../../utils/restaurant_route.dart';



class AdminSuperRestaurantsPanel extends StatefulWidget {

  const AdminSuperRestaurantsPanel({super.key});



  @override

  State<AdminSuperRestaurantsPanel> createState() =>

      _AdminSuperRestaurantsPanelState();

}



class _AdminSuperRestaurantsPanelState extends State<AdminSuperRestaurantsPanel> {

  static const burgundy = Color(0xFF6B1124);



  final _nameController = TextEditingController();

  final _slugController = TextEditingController();

  final _passwordController = TextEditingController();



  List<Restaurant> _restaurants = [];

  var _loading = true;

  var _creating = false;

  String? _errorMessage;



  @override

  void initState() {

    super.initState();

    _loadRestaurants();

  }



  @override

  void dispose() {

    _nameController.dispose();

    _slugController.dispose();

    _passwordController.dispose();

    super.dispose();

  }



  Future<void> _loadRestaurants() async {

    setState(() {

      _loading = true;

      _errorMessage = null;

    });



    try {

      _restaurants = await ApiService.instance.fetchRestaurants();

    } catch (error) {

      _errorMessage = error.toString().replaceFirst('Exception: ', '');

      _restaurants = [];

    }



    if (mounted) setState(() => _loading = false);

  }



  Future<void> _createRestaurant() async {

    final name = _nameController.text.trim();

    final slug = _slugController.text.trim();

    final password = _passwordController.text.trim();



    if (name.isEmpty || slug.isEmpty || password.isEmpty) {

      ScaffoldMessenger.of(context).showSnackBar(

        const SnackBar(content: Text('يرجى ملء جميع حقول المطعم الجديد')),

      );

      return;

    }



    setState(() => _creating = true);



    try {

      await ApiService.instance.createRestaurant(

        name: name,

        slug: slug,

        adminPassword: password,

      );



      _nameController.clear();

      _slugController.clear();

      _passwordController.clear();



      await _loadRestaurants();
      await SuperAdminScopeService.instance.refreshRestaurants();



      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(

        const SnackBar(content: Text('تم إنشاء المطعم بنجاح')),

      );

    } catch (error) {

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(

        SnackBar(content: Text('تعذر إنشاء المطعم: $error')),

      );

    } finally {

      if (mounted) setState(() => _creating = false);

    }

  }



  Future<void> _importTalabatForRestaurant(Restaurant restaurant) async {

    final urlController = TextEditingController();

    var isLoading = false;

    String? statusMessage;



    await showDialog<void>(

      context: context,

      builder: (ctx) {

        return StatefulBuilder(

          builder: (context, setDialogState) {

            return AlertDialog(

              title: Text('استيراد منيو ${restaurant.name}'),

              content: SingleChildScrollView(

                child: Column(

                  mainAxisSize: MainAxisSize.min,

                  children: [

                    const Text(

                      'أدخل رابط Talabat (طلبات) لسحب الأصناف والصور وربطها بهذا المطعم:',

                    ),

                    const SizedBox(height: 12),

                    TextField(

                      controller: urlController,

                      keyboardType: TextInputType.url,

                      decoration: const InputDecoration(

                        labelText: 'رابط المنيو',

                        border: OutlineInputBorder(),

                      ),

                    ),

                    if (statusMessage != null) ...[

                      const SizedBox(height: 12),

                      Text(statusMessage!),

                    ],

                  ],

                ),

              ),

              actions: [

                TextButton(

                  onPressed: isLoading ? null : () => Navigator.pop(ctx),

                  child: const Text('إلغاء'),

                ),

                ElevatedButton(

                  style: ElevatedButton.styleFrom(backgroundColor: burgundy),

                  onPressed: isLoading

                      ? null

                      : () async {

                          final url = urlController.text.trim();

                          if (url.isEmpty) return;



                          setDialogState(() {

                            isLoading = true;

                            statusMessage = 'جاري السحب...';

                          });



                          await processAndSaveTalabatMenu(

                            url: url,

                            restaurantId: restaurant.id,

                            onProgress: (msg) {

                              setDialogState(() => statusMessage = msg);

                            },

                            onComplete: (added, skipped, updated) {

                              setDialogState(() {

                                isLoading = false;

                                statusMessage =

                                    'تم: $added جديد، $updated محدّث، $skipped موجود';

                              });

                            },

                          );

                        },

                  child: Text(

                    isLoading ? 'جاري...' : 'بدء الاستيراد',

                    style: const TextStyle(color: Colors.white),

                  ),

                ),

              ],

            );

          },

        );

      },

    );



    urlController.dispose();

  }



  @override

  Widget build(BuildContext context) {

    return Padding(

      padding: const EdgeInsets.all(24),

      child: Column(

        crossAxisAlignment: CrossAxisAlignment.stretch,

        children: [

          const Text(

            'إدارة المطاعم — AlMenuPro',

            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: burgundy),

          ),

          const SizedBox(height: 8),

          const Text(

            'الشركة الأم فقط يمكنها إنشاء مطاعم جديدة واستيراد المنيو من رابط الطلبات.',

          ),

          const SizedBox(height: 20),

          Card(

            child: Padding(

              padding: const EdgeInsets.all(20),

              child: Column(

                crossAxisAlignment: CrossAxisAlignment.start,

                children: [

                  const Text(

                    'إنشاء مطعم جديد',

                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),

                  ),

                  const SizedBox(height: 12),

                  TextField(

                    controller: _nameController,

                    decoration: const InputDecoration(

                      labelText: 'اسم المطعم',

                      border: OutlineInputBorder(),

                    ),

                  ),

                  const SizedBox(height: 12),

                  TextField(

                    controller: _slugController,

                    decoration: const InputDecoration(

                      labelText: 'المعرف (slug) — للدخول',

                      hintText: 'molton-cookies',

                      border: OutlineInputBorder(),

                    ),

                  ),

                  const SizedBox(height: 12),

                  TextField(

                    controller: _passwordController,

                    obscureText: true,

                    decoration: const InputDecoration(

                      labelText: 'كلمة مرور مدير المطعم',

                      border: OutlineInputBorder(),

                    ),

                  ),

                  const SizedBox(height: 16),

                  ElevatedButton.icon(

                    style: ElevatedButton.styleFrom(backgroundColor: burgundy),

                    onPressed: _creating ? null : _createRestaurant,

                    icon: _creating

                        ? const SizedBox(

                            width: 18,

                            height: 18,

                            child: CircularProgressIndicator(

                              color: Colors.white,

                              strokeWidth: 2,

                            ),

                          )

                        : const Icon(Icons.add_business, color: Colors.white),

                    label: Text(

                      _creating ? 'جاري الإنشاء...' : 'إنشاء المطعم',

                      style: const TextStyle(color: Colors.white),

                    ),

                  ),

                ],

              ),

            ),

          ),

          const SizedBox(height: 20),

          Expanded(

            child: _loading

                ? const Center(child: CircularProgressIndicator(color: burgundy))

                : _errorMessage != null

                    ? Center(child: Text(_errorMessage!))

                    : ListView.separated(

                        itemCount: _restaurants.length,

                        separatorBuilder: (_, __) => const SizedBox(height: 10),

                        itemBuilder: (context, index) {

                          final restaurant = _restaurants[index];
                          final menuPath = RestaurantRoute.menuPathForSlug(restaurant.slug);
                          final menuUrl = kIsWeb
                              ? '${Uri.base.origin}$menuPath'
                              : menuPath;

                          return Card(
                            child: ListTile(
                              leading: const Icon(Icons.store, color: burgundy),
                              title: Text(
                                restaurant.name,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                'slug: ${restaurant.slug}\nرابط العملاء: $menuUrl',
                              ),
                              isThreeLine: true,

                              trailing: OutlinedButton.icon(

                                onPressed: () => _importTalabatForRestaurant(restaurant),

                                icon: const Icon(Icons.cloud_download),

                                label: const Text('استيراد Talabat'),

                              ),

                            ),

                          );

                        },

                      ),

          ),

        ],

      ),

    );

  }

}


