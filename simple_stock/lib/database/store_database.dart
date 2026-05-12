import 'package:mysql1/mysql1.dart';

abstract class StoreDataSource {
  Future<void> initialize();
  Future<DashboardSnapshot> loadDashboard();
  Future<void> addProduct({
    required String name,
    required String category,
    required double price,
    required int stock,
    required int reorderLevel,
  });
  Future<void> registerSale({
    required int productId,
    required int quantity,
    required String customerName,
    required String channel,
  });
  Future<void> restockProduct({
    required int productId,
    required int quantity,
    required String note,
  });
}

class DatabaseConfig {
  const DatabaseConfig({
    this.host = const String.fromEnvironment(
      'DB_HOST',
      defaultValue: '127.0.0.1',
    ),
    this.port = const int.fromEnvironment('DB_PORT', defaultValue: 3306),
    this.user = const String.fromEnvironment('DB_USER', defaultValue: 'root'),
    this.password = const String.fromEnvironment(
      'DB_PASSWORD',
      defaultValue: 'root',
    ),
    this.database = const String.fromEnvironment(
      'DB_NAME',
      defaultValue: 'store_dashboard_db',
    ),
  });

  final String host;
  final int port;
  final String user;
  final String password;
  final String database;
}

class StoreDatabase implements StoreDataSource {
  const StoreDatabase({this.config = const DatabaseConfig()});

  final DatabaseConfig config;

  Future<MySqlConnection> _connect({bool useDatabase = true}) {
    return MySqlConnection.connect(
      ConnectionSettings(
        host: config.host,
        port: config.port,
        user: config.user,
        password: config.password,
        db: useDatabase ? config.database : null,
        useSSL: false,
        timeout: const Duration(seconds: 12),
      ),
    );
  }

  Future<T> _withConnection<T>(
    Future<T> Function(MySqlConnection conn) action, {
    bool useDatabase = true,
  }) async {
    final conn = await _connect(useDatabase: useDatabase);
    try {
      return await action(conn);
    } finally {
      await conn.close();
    }
  }

  @override
  Future<void> initialize() async {
    await _withConnection((conn) async {
      await conn.query(
        'CREATE DATABASE IF NOT EXISTS `${config.database}` '
        'CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
      );
    }, useDatabase: false);

    await _withConnection((conn) async {
      await _createTables(conn);
      await _seedIfEmpty(conn);
    });
  }

  Future<void> _createTables(MySqlConnection conn) async {
    await conn.query('''
      CREATE TABLE IF NOT EXISTS products (
        id INT AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(160) NOT NULL,
        category VARCHAR(90) NOT NULL,
        price DECIMAL(12,2) NOT NULL,
        stock INT NOT NULL DEFAULT 0,
        reorder_level INT NOT NULL DEFAULT 10,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
          ON UPDATE CURRENT_TIMESTAMP,
        INDEX idx_products_category (category),
        INDEX idx_products_stock (stock)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ''');

    await conn.query('''
      CREATE TABLE IF NOT EXISTS customers (
        id INT AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(160) NOT NULL,
        phone VARCHAR(40) NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY ux_customers_name (name)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ''');

    await conn.query('''
      CREATE TABLE IF NOT EXISTS sales_orders (
        id INT AUTO_INCREMENT PRIMARY KEY,
        customer_id INT NULL,
        channel VARCHAR(40) NOT NULL,
        status VARCHAR(40) NOT NULL DEFAULT 'جاهز',
        total DECIMAL(12,2) NOT NULL DEFAULT 0,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT fk_sales_customer FOREIGN KEY (customer_id)
          REFERENCES customers(id) ON DELETE SET NULL,
        INDEX idx_sales_created_at (created_at),
        INDEX idx_sales_channel (channel)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ''');

    await conn.query('''
      CREATE TABLE IF NOT EXISTS order_items (
        id INT AUTO_INCREMENT PRIMARY KEY,
        order_id INT NOT NULL,
        product_id INT NOT NULL,
        quantity INT NOT NULL,
        unit_price DECIMAL(12,2) NOT NULL,
        CONSTRAINT fk_items_order FOREIGN KEY (order_id)
          REFERENCES sales_orders(id) ON DELETE CASCADE,
        CONSTRAINT fk_items_product FOREIGN KEY (product_id)
          REFERENCES products(id),
        INDEX idx_items_product (product_id)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ''');

    await conn.query('''
      CREATE TABLE IF NOT EXISTS inventory_movements (
        id INT AUTO_INCREMENT PRIMARY KEY,
        product_id INT NOT NULL,
        quantity_delta INT NOT NULL,
        type VARCHAR(40) NOT NULL,
        note VARCHAR(255) NOT NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT fk_movements_product FOREIGN KEY (product_id)
          REFERENCES products(id) ON DELETE CASCADE,
        INDEX idx_movements_created_at (created_at)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ''');
  }

  Future<void> _seedIfEmpty(MySqlConnection conn) async {
    final count = _asInt(
        (await conn.query('SELECT COUNT(*) c FROM products')).first['c']);
    if (count > 0) return;

    final products = <({
      String name,
      String category,
      double price,
      int stock,
      int reorder
    })>[
      (
        name: 'قهوة مختصة 250غ',
        category: 'مشروبات',
        price: 2300,
        stock: 84,
        reorder: 24,
      ),
      (
        name: 'سماعات لاسلكية Pro',
        category: 'إلكترونيات',
        price: 7800,
        stock: 32,
        reorder: 10,
      ),
      (
        name: 'مجموعة عناية يومية',
        category: 'عناية',
        price: 3100,
        stock: 19,
        reorder: 20,
      ),
      (
        name: 'حقيبة سفر خفيفة',
        category: 'إكسسوارات',
        price: 6400,
        stock: 27,
        reorder: 8,
      ),
      (
        name: 'مشروب طاقة طبيعي',
        category: 'مشروبات',
        price: 420,
        stock: 12,
        reorder: 30,
      ),
      (
        name: 'كابل شحن سريع USB-C',
        category: 'إلكترونيات',
        price: 950,
        stock: 115,
        reorder: 40,
      ),
    ];

    for (final product in products) {
      final result = await conn.query(
        'INSERT INTO products (name, category, price, stock, reorder_level) '
        'VALUES (?, ?, ?, ?, ?)',
        [
          product.name,
          product.category,
          product.price,
          product.stock,
          product.reorder,
        ],
      );
      await conn.query(
        'INSERT INTO inventory_movements '
        '(product_id, quantity_delta, type, note) VALUES (?, ?, ?, ?)',
        [
          result.insertId,
          product.stock,
          'seed',
          'رصيد افتتاحي للصنف ${product.name}',
        ],
      );
    }

    await _seedSale(
      conn,
      productName: 'قهوة مختصة 250غ',
      customerName: 'سارة بن عمر',
      quantity: 4,
      channel: 'المتجر',
      status: 'جاهز',
    );
    await _seedSale(
      conn,
      productName: 'سماعات لاسلكية Pro',
      customerName: 'مؤسسة الهدى',
      quantity: 3,
      channel: 'أونلاين',
      status: 'قيد التجهيز',
    );
    await _seedSale(
      conn,
      productName: 'مجموعة عناية يومية',
      customerName: 'مريم قاسمي',
      quantity: 5,
      channel: 'واتساب',
      status: 'شحن',
    );
    await _seedSale(
      conn,
      productName: 'كابل شحن سريع USB-C',
      customerName: 'كريم ناصر',
      quantity: 12,
      channel: 'المتجر',
      status: 'جاهز',
    );
  }

  Future<void> _seedSale(
    MySqlConnection conn, {
    required String productName,
    required String customerName,
    required int quantity,
    required String channel,
    required String status,
  }) async {
    final products = await conn.query(
      'SELECT id, price FROM products WHERE name = ? LIMIT 1',
      [productName],
    );
    if (products.isEmpty) return;

    final product = products.first;
    final customerId = await _findOrCreateCustomer(conn, customerName);
    final price = _asDouble(product['price']);
    final total = price * quantity;
    final order = await conn.query(
      'INSERT INTO sales_orders (customer_id, channel, status, total) '
      'VALUES (?, ?, ?, ?)',
      [customerId, channel, status, total],
    );

    await conn.query(
      'INSERT INTO order_items (order_id, product_id, quantity, unit_price) '
      'VALUES (?, ?, ?, ?)',
      [order.insertId, product['id'], quantity, price],
    );
    await conn.query(
      'UPDATE products SET stock = stock - ? WHERE id = ?',
      [quantity, product['id']],
    );
    await conn.query(
      'INSERT INTO inventory_movements '
      '(product_id, quantity_delta, type, note) VALUES (?, ?, ?, ?)',
      [product['id'], -quantity, 'sale', 'بيع $quantity من $productName'],
    );
  }

  @override
  Future<DashboardSnapshot> loadDashboard() async {
    return _withConnection((conn) async {
      final products = await _loadProducts(conn);
      final orders = await _loadOrders(conn);
      final topProducts = await _loadTopProducts(conn);
      final channels = await _loadChannels(conn);
      final activities = await _loadActivities(conn);
      final metrics = await _loadMetrics(conn);

      return DashboardSnapshot(
        metrics: metrics,
        products: products,
        orders: orders,
        topProducts: topProducts,
        channels: channels,
        activities: activities,
        generatedAt: DateTime.now(),
      );
    });
  }

  Future<DashboardMetrics> _loadMetrics(MySqlConnection conn) async {
    final sales = (await conn.query('''
      SELECT
        COALESCE(SUM(total), 0) today_revenue,
        COUNT(*) today_orders,
        COALESCE(AVG(total), 0) avg_basket
      FROM sales_orders
      WHERE DATE(created_at) = CURDATE()
    ''')).first;

    final lowStock = (await conn.query(
      'SELECT COUNT(*) c FROM products WHERE stock <= reorder_level',
    ))
        .first;
    final inventory = (await conn.query(
      'SELECT COALESCE(SUM(price * stock), 0) inventory_value FROM products',
    ))
        .first;

    return DashboardMetrics(
      todayRevenue: _asDouble(sales['today_revenue']),
      todayOrders: _asInt(sales['today_orders']),
      averageBasket: _asDouble(sales['avg_basket']),
      lowStockCount: _asInt(lowStock['c']),
      inventoryValue: _asDouble(inventory['inventory_value']),
    );
  }

  Future<List<ProductRecord>> _loadProducts(MySqlConnection conn) async {
    final rows = await conn.query('''
      SELECT id, name, category, price, stock, reorder_level
      FROM products
      ORDER BY (stock <= reorder_level) DESC, updated_at DESC
      LIMIT 50
    ''');

    return rows.map((row) {
      return ProductRecord(
        id: _asInt(row['id']),
        name: row['name'].toString(),
        category: row['category'].toString(),
        price: _asDouble(row['price']),
        stock: _asInt(row['stock']),
        reorderLevel: _asInt(row['reorder_level']),
      );
    }).toList();
  }

  Future<List<OrderRecord>> _loadOrders(MySqlConnection conn) async {
    final rows = await conn.query('''
      SELECT so.id, COALESCE(c.name, 'عميل غير معروف') customer_name,
             so.channel, so.status, so.total, so.created_at
      FROM sales_orders so
      LEFT JOIN customers c ON c.id = so.customer_id
      ORDER BY so.created_at DESC
      LIMIT 12
    ''');

    return rows.map((row) {
      return OrderRecord(
        id: _asInt(row['id']),
        customerName: row['customer_name'].toString(),
        channel: row['channel'].toString(),
        status: row['status'].toString(),
        total: _asDouble(row['total']),
        createdAt: _asDate(row['created_at']),
      );
    }).toList();
  }

  Future<List<TopProductRecord>> _loadTopProducts(MySqlConnection conn) async {
    final rows = await conn.query('''
      SELECT p.id, p.name, p.category,
             COALESCE(SUM(oi.quantity), 0) units,
             COALESCE(SUM(oi.quantity * oi.unit_price), 0) revenue,
             p.stock, p.reorder_level
      FROM products p
      LEFT JOIN order_items oi ON oi.product_id = p.id
      GROUP BY p.id, p.name, p.category, p.stock, p.reorder_level
      ORDER BY revenue DESC, units DESC
      LIMIT 6
    ''');

    return rows.map((row) {
      return TopProductRecord(
        id: _asInt(row['id']),
        name: row['name'].toString(),
        category: row['category'].toString(),
        units: _asInt(row['units']),
        revenue: _asDouble(row['revenue']),
        stock: _asInt(row['stock']),
        reorderLevel: _asInt(row['reorder_level']),
      );
    }).toList();
  }

  Future<List<ChannelRecord>> _loadChannels(MySqlConnection conn) async {
    final rows = await conn.query('''
      SELECT channel, COUNT(*) orders, COALESCE(SUM(total), 0) total
      FROM sales_orders
      GROUP BY channel
      ORDER BY total DESC
    ''');
    final totalOrders =
        rows.fold<int>(0, (sum, row) => sum + _asInt(row['orders']));

    return rows.map((row) {
      final orders = _asInt(row['orders']);
      return ChannelRecord(
        channel: row['channel'].toString(),
        orders: orders,
        total: _asDouble(row['total']),
        share: totalOrders == 0 ? 0 : orders / totalOrders,
      );
    }).toList();
  }

  Future<List<ActivityRecord>> _loadActivities(MySqlConnection conn) async {
    final orderRows = await conn.query('''
      SELECT so.id, COALESCE(c.name, 'عميل غير معروف') customer_name,
             so.channel, so.total, so.created_at
      FROM sales_orders so
      LEFT JOIN customers c ON c.id = so.customer_id
      ORDER BY so.created_at DESC
      LIMIT 6
    ''');
    final movementRows = await conn.query('''
      SELECT im.type, im.note, im.quantity_delta, p.name product_name,
             im.created_at
      FROM inventory_movements im
      JOIN products p ON p.id = im.product_id
      ORDER BY im.created_at DESC
      LIMIT 6
    ''');

    final activities = <ActivityRecord>[
      for (final row in orderRows)
        ActivityRecord(
          kind: 'sale',
          title: 'فاتورة #${row['id']}',
          detail:
              '${row['customer_name']} · ${row['channel']} · ${formatMoney(_asDouble(row['total']))}',
          createdAt: _asDate(row['created_at']),
        ),
      for (final row in movementRows)
        ActivityRecord(
          kind: row['type'].toString(),
          title: row['product_name'].toString(),
          detail: row['note'].toString(),
          createdAt: _asDate(row['created_at']),
        ),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return activities.take(8).toList();
  }

  @override
  Future<void> addProduct({
    required String name,
    required String category,
    required double price,
    required int stock,
    required int reorderLevel,
  }) async {
    if (name.trim().isEmpty) throw ArgumentError('اسم المنتج مطلوب');
    if (category.trim().isEmpty) throw ArgumentError('التصنيف مطلوب');
    if (price <= 0) throw ArgumentError('السعر يجب أن يكون أكبر من صفر');
    if (stock < 0) throw ArgumentError('المخزون لا يمكن أن يكون سالبًا');
    if (reorderLevel < 0) throw ArgumentError('حد إعادة الطلب غير صالح');

    await _withConnection((conn) async {
      final result = await conn.query(
        'INSERT INTO products (name, category, price, stock, reorder_level) '
        'VALUES (?, ?, ?, ?, ?)',
        [name.trim(), category.trim(), price, stock, reorderLevel],
      );
      await conn.query(
        'INSERT INTO inventory_movements '
        '(product_id, quantity_delta, type, note) VALUES (?, ?, ?, ?)',
        [result.insertId, stock, 'create', 'إضافة منتج جديد: ${name.trim()}'],
      );
    });
  }

  @override
  Future<void> registerSale({
    required int productId,
    required int quantity,
    required String customerName,
    required String channel,
  }) async {
    if (quantity <= 0) throw ArgumentError('الكمية يجب أن تكون أكبر من صفر');
    if (customerName.trim().isEmpty) throw ArgumentError('اسم العميل مطلوب');

    await _withConnection((conn) async {
      await conn.query('START TRANSACTION');
      try {
        final products = await conn.query(
          'SELECT id, name, price, stock FROM products WHERE id = ? FOR UPDATE',
          [productId],
        );
        if (products.isEmpty) throw StateError('المنتج غير موجود');

        final product = products.first;
        final stock = _asInt(product['stock']);
        if (stock < quantity) {
          throw StateError('المخزون غير كاف. المتاح حاليًا: $stock');
        }

        final customerId =
            await _findOrCreateCustomer(conn, customerName.trim());
        final price = _asDouble(product['price']);
        final total = price * quantity;
        final order = await conn.query(
          'INSERT INTO sales_orders (customer_id, channel, status, total) '
          'VALUES (?, ?, ?, ?)',
          [customerId, channel, 'جاهز', total],
        );

        await conn.query(
          'INSERT INTO order_items (order_id, product_id, quantity, unit_price) '
          'VALUES (?, ?, ?, ?)',
          [order.insertId, productId, quantity, price],
        );
        await conn.query(
          'UPDATE products SET stock = stock - ? WHERE id = ?',
          [quantity, productId],
        );
        await conn.query(
          'INSERT INTO inventory_movements '
          '(product_id, quantity_delta, type, note) VALUES (?, ?, ?, ?)',
          [
            productId,
            -quantity,
            'sale',
            'بيع $quantity من ${product['name']} إلى ${customerName.trim()}',
          ],
        );
        await conn.query('COMMIT');
      } catch (_) {
        await conn.query('ROLLBACK');
        rethrow;
      }
    });
  }

  @override
  Future<void> restockProduct({
    required int productId,
    required int quantity,
    required String note,
  }) async {
    if (quantity <= 0) throw ArgumentError('الكمية يجب أن تكون أكبر من صفر');

    await _withConnection((conn) async {
      final products = await conn.query(
        'SELECT id, name FROM products WHERE id = ?',
        [productId],
      );
      if (products.isEmpty) throw StateError('المنتج غير موجود');

      await conn.query(
        'UPDATE products SET stock = stock + ? WHERE id = ?',
        [quantity, productId],
      );
      await conn.query(
        'INSERT INTO inventory_movements '
        '(product_id, quantity_delta, type, note) VALUES (?, ?, ?, ?)',
        [
          productId,
          quantity,
          'restock',
          note.trim().isEmpty
              ? 'تغذية مخزون ${products.first['name']}'
              : note.trim(),
        ],
      );
    });
  }

  Future<int> _findOrCreateCustomer(
    MySqlConnection conn,
    String customerName,
  ) async {
    await conn.query(
      'INSERT INTO customers (name) VALUES (?) '
      'ON DUPLICATE KEY UPDATE name = VALUES(name)',
      [customerName],
    );
    final rows = await conn.query(
      'SELECT id FROM customers WHERE name = ? LIMIT 1',
      [customerName],
    );
    return _asInt(rows.first['id']);
  }
}

class DashboardSnapshot {
  const DashboardSnapshot({
    required this.metrics,
    required this.products,
    required this.orders,
    required this.topProducts,
    required this.channels,
    required this.activities,
    required this.generatedAt,
  });

  final DashboardMetrics metrics;
  final List<ProductRecord> products;
  final List<OrderRecord> orders;
  final List<TopProductRecord> topProducts;
  final List<ChannelRecord> channels;
  final List<ActivityRecord> activities;
  final DateTime generatedAt;

  List<ProductRecord> get lowStockProducts {
    return products.where((product) => product.isLowStock).toList();
  }
}

class DashboardMetrics {
  const DashboardMetrics({
    required this.todayRevenue,
    required this.todayOrders,
    required this.averageBasket,
    required this.lowStockCount,
    required this.inventoryValue,
  });

  final double todayRevenue;
  final int todayOrders;
  final double averageBasket;
  final int lowStockCount;
  final double inventoryValue;
}

class ProductRecord {
  const ProductRecord({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.stock,
    required this.reorderLevel,
  });

  final int id;
  final String name;
  final String category;
  final double price;
  final int stock;
  final int reorderLevel;

  bool get isLowStock => stock <= reorderLevel;

  double get stockRatio {
    final target = (reorderLevel * 3).clamp(1, 999999);
    return (stock / target).clamp(0, 1).toDouble();
  }
}

class OrderRecord {
  const OrderRecord({
    required this.id,
    required this.customerName,
    required this.channel,
    required this.status,
    required this.total,
    required this.createdAt,
  });

  final int id;
  final String customerName;
  final String channel;
  final String status;
  final double total;
  final DateTime createdAt;
}

class TopProductRecord {
  const TopProductRecord({
    required this.id,
    required this.name,
    required this.category,
    required this.units,
    required this.revenue,
    required this.stock,
    required this.reorderLevel,
  });

  final int id;
  final String name;
  final String category;
  final int units;
  final double revenue;
  final int stock;
  final int reorderLevel;

  double get performance {
    if (revenue <= 0) return .08;
    return (revenue / 90000).clamp(.08, 1).toDouble();
  }
}

class ChannelRecord {
  const ChannelRecord({
    required this.channel,
    required this.orders,
    required this.total,
    required this.share,
  });

  final String channel;
  final int orders;
  final double total;
  final double share;
}

class ActivityRecord {
  const ActivityRecord({
    required this.kind,
    required this.title,
    required this.detail,
    required this.createdAt,
  });

  final String kind;
  final String title;
  final String detail;
  final DateTime createdAt;
}

String formatMoney(double value) {
  final rounded = value.round();
  final text = rounded.toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (_) => ',',
      );
  return 'دج $text';
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is BigInt) return value.toInt();
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}

double _asDouble(Object? value) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

DateTime _asDate(Object? value) {
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString()) ?? DateTime.now();
}
