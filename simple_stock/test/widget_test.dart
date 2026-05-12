import 'package:flutter_test/flutter_test.dart';
import 'package:store_dashboard/database/store_database.dart';
import 'package:store_dashboard/main.dart';

void main() {
  testWidgets('dashboard loads the store overview', (tester) async {
    await tester
        .pumpWidget(StoreDashboardApp(dataSource: _FakeStoreDataSource()));
    await tester.pumpAndSettle();

    expect(find.text('لوحة تشغيل متجر الرحمة'), findsOneWidget);
    expect(find.text('إيراد اليوم'), findsOneWidget);
    expect(find.text('الطلبات النشطة'), findsOneWidget);
  });
}

class _FakeStoreDataSource implements StoreDataSource {
  @override
  Future<void> initialize() async {}

  @override
  Future<DashboardSnapshot> loadDashboard() async {
    final now = DateTime(2026, 5, 12, 10, 42);
    return DashboardSnapshot(
      metrics: const DashboardMetrics(
        todayRevenue: 12500,
        todayOrders: 3,
        averageBasket: 4166,
        lowStockCount: 1,
        inventoryValue: 98400,
      ),
      products: const [
        ProductRecord(
          id: 1,
          name: 'قهوة مختصة',
          category: 'مشروبات',
          price: 2300,
          stock: 8,
          reorderLevel: 10,
        ),
      ],
      orders: [
        OrderRecord(
          id: 1,
          customerName: 'عميل تجريبي',
          channel: 'المتجر',
          status: 'جاهز',
          total: 4600,
          createdAt: now,
        ),
      ],
      topProducts: const [
        TopProductRecord(
          id: 1,
          name: 'قهوة مختصة',
          category: 'مشروبات',
          units: 2,
          revenue: 4600,
          stock: 8,
          reorderLevel: 10,
        ),
      ],
      channels: const [
        ChannelRecord(channel: 'المتجر', orders: 1, total: 4600, share: 1),
      ],
      activities: [
        ActivityRecord(
          kind: 'sale',
          title: 'فاتورة #1',
          detail: 'عملية بيع تجريبية',
          createdAt: now,
        ),
      ],
      generatedAt: now,
    );
  }

  @override
  Future<void> addProduct({
    required String name,
    required String category,
    required double price,
    required int stock,
    required int reorderLevel,
  }) async {}

  @override
  Future<void> registerSale({
    required int productId,
    required int quantity,
    required String customerName,
    required String channel,
  }) async {}

  @override
  Future<void> restockProduct({
    required int productId,
    required int quantity,
    required String note,
  }) async {}
}
