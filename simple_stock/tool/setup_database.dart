import 'package:store_dashboard/database/store_database.dart';

Future<void> main() async {
  const database = StoreDatabase();
  await database.initialize();
  final snapshot = await database.loadDashboard();

  print('Database is ready.');
  print('Products: ${snapshot.products.length}');
  print('Orders: ${snapshot.orders.length}');
  print('Today revenue: ${formatMoney(snapshot.metrics.todayRevenue)}');
}
