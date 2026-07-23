import 'package:cloud_firestore/cloud_firestore.dart' hide Order;

import '../models/menu_item.dart';
import '../models/order.dart';

class FirebaseService {
  FirebaseService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String menuItemsCollection = 'menu_items';
  static const String itemsCollection = 'items';
  static const String ordersCollection = 'orders';

  CollectionReference<Map<String, dynamic>> get _menuItemsRef =>
      _firestore.collection(menuItemsCollection);

  CollectionReference<Map<String, dynamic>> get _itemsRef =>
      _firestore.collection(itemsCollection);

  CollectionReference<Map<String, dynamic>> get _ordersRef =>
      _firestore.collection(ordersCollection);

  Stream<List<MenuItem>> watchMenuItems({bool availableOnly = true}) {
    return _itemsRef.orderBy('categoryName').snapshots().asyncMap(
      (itemsSnapshot) async {
        if (itemsSnapshot.docs.isNotEmpty) {
          return _mapItemDocs(itemsSnapshot.docs, availableOnly);
        }

        Query<Map<String, dynamic>> query =
            _menuItemsRef.orderBy('category');

        if (availableOnly) {
          query = query.where('isAvailable', isEqualTo: true);
        }

        final legacySnapshot = await query.get();
        return legacySnapshot.docs
            .map((doc) => MenuItem.fromMap(doc.id, doc.data()))
            .toList();
      },
    );
  }

  List<MenuItem> _mapItemDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    bool availableOnly,
  ) {
    return docs
        .where((doc) {
          if (!availableOnly) {
            return true;
          }
          return doc.data()['isAvailable'] as bool? ?? true;
        })
        .map(
          (doc) => MenuItem.fromMap(
            doc.id,
            {
              ...doc.data(),
              'category': doc.data()['categoryName'] ?? '',
            },
          ),
        )
        .toList();
  }

  Future<String> addOrder(Order order) async {
    final docRef = await _ordersRef.add(order.toMap());
    return docRef.id;
  }

  Stream<List<Order>> watchOrders() {
    return _ordersRef
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Order.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  Future<void> updateOrderStatus(String orderId, OrderStatus status) async {
    await _ordersRef.doc(orderId).update({'status': status.name});
  }
}
