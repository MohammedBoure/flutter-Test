import 'package:flutter/material.dart';

import 'database/store_database.dart';

void main() {
  runApp(const StoreDashboardApp());
}

class StoreDashboardApp extends StatelessWidget {
  const StoreDashboardApp({
    super.key,
    this.dataSource = const StoreDatabase(),
  });

  final StoreDataSource dataSource;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Store Dashboard',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _AppColors.primary),
        scaffoldBackgroundColor: _AppColors.canvas,
        dividerColor: _AppColors.line,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _AppColors.line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _AppColors.line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _AppColors.primary, width: 1.4),
          ),
        ),
      ),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: StoreHomePage(dataSource: dataSource),
      ),
    );
  }
}

class StoreHomePage extends StatefulWidget {
  const StoreHomePage({super.key, required this.dataSource});

  final StoreDataSource dataSource;

  @override
  State<StoreHomePage> createState() => _StoreHomePageState();
}

class _StoreHomePageState extends State<StoreHomePage> {
  late Future<DashboardSnapshot> _future;
  bool _operationBusy = false;

  @override
  void initState() {
    super.initState();
    _future = _initializeAndLoad();
  }

  Future<DashboardSnapshot> _initializeAndLoad() async {
    await widget.dataSource.initialize();
    return widget.dataSource.loadDashboard();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = widget.dataSource.loadDashboard();
    });
    await _future;
  }

  Future<void> _runOperation(
    Future<void> Function() operation,
    String successMessage,
  ) async {
    setState(() => _operationBusy = true);
    try {
      await operation();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage)),
      );
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _AppColors.rose,
          content: Text(error.toString()),
        ),
      );
    } finally {
      if (mounted) setState(() => _operationBusy = false);
    }
  }

  Future<void> _showAddProductDialog() async {
    final input = await showDialog<_ProductInput>(
      context: context,
      builder: (_) => const _AddProductDialog(),
    );
    if (input == null) return;

    await _runOperation(
      () => widget.dataSource.addProduct(
        name: input.name,
        category: input.category,
        price: input.price,
        stock: input.stock,
        reorderLevel: input.reorderLevel,
      ),
      'تمت إضافة المنتج إلى قاعدة البيانات',
    );
  }

  Future<void> _showQuickSaleDialog(List<ProductRecord> products) async {
    final input = await showDialog<_SaleInput>(
      context: context,
      builder: (_) => _QuickSaleDialog(products: products),
    );
    if (input == null) return;

    await _runOperation(
      () => widget.dataSource.registerSale(
        productId: input.productId,
        quantity: input.quantity,
        customerName: input.customerName,
        channel: input.channel,
      ),
      'تم تسجيل الفاتورة وتحديث المخزون',
    );
  }

  Future<void> _showRestockDialog(List<ProductRecord> products) async {
    final input = await showDialog<_RestockInput>(
      context: context,
      builder: (_) => _RestockDialog(products: products),
    );
    if (input == null) return;

    await _runOperation(
      () => widget.dataSource.restockProduct(
        productId: input.productId,
        quantity: input.quantity,
        note: input.note,
      ),
      'تم تحديث رصيد المخزون',
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DashboardSnapshot>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingView();
        }
        if (snapshot.hasError) {
          return _DatabaseErrorView(
            error: snapshot.error.toString(),
            onRetry: () {
              setState(() {
                _future = _initializeAndLoad();
              });
            },
          );
        }

        final data = snapshot.requireData;
        return _DashboardShell(
          data: data,
          operationBusy: _operationBusy,
          onRefresh: _refresh,
          onAddProduct: _showAddProductDialog,
          onQuickSale: () => _showQuickSaleDialog(data.products),
          onRestock: () => _showRestockDialog(data.products),
        );
      },
    );
  }
}

class _DashboardShell extends StatelessWidget {
  const _DashboardShell({
    required this.data,
    required this.operationBusy,
    required this.onRefresh,
    required this.onAddProduct,
    required this.onQuickSale,
    required this.onRestock,
  });

  final DashboardSnapshot data;
  final bool operationBusy;
  final VoidCallback onRefresh;
  final VoidCallback onAddProduct;
  final VoidCallback onQuickSale;
  final VoidCallback onRestock;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 1120;
        final main = Column(
          children: [
            _HeaderBar(
              generatedAt: data.generatedAt,
              operationBusy: operationBusy,
              onRefresh: onRefresh,
            ),
            Expanded(
              child: _DashboardContent(
                data: data,
                compact: compact,
                operationBusy: operationBusy,
                onAddProduct: onAddProduct,
                onQuickSale: onQuickSale,
                onRestock: onRestock,
              ),
            ),
          ],
        );

        return Scaffold(
          body: compact
              ? main
              : Row(
                  children: [
                    const _SideNav(),
                    Expanded(child: main),
                  ],
                ),
        );
      },
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({
    required this.data,
    required this.compact,
    required this.operationBusy,
    required this.onAddProduct,
    required this.onQuickSale,
    required this.onRestock,
  });

  final DashboardSnapshot data;
  final bool compact;
  final bool operationBusy;
  final VoidCallback onAddProduct;
  final VoidCallback onQuickSale;
  final VoidCallback onRestock;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 34),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TitleBlock(data: data),
          const SizedBox(height: 16),
          _ActionStrip(
            busy: operationBusy,
            onAddProduct: onAddProduct,
            onQuickSale: onQuickSale,
            onRestock: onRestock,
          ),
          const SizedBox(height: 18),
          _MetricGrid(metrics: data.metrics, compact: compact),
          const SizedBox(height: 18),
          if (compact) ...[
            _OrdersPanel(orders: data.orders),
            const SizedBox(height: 18),
            _LowStockPanel(products: data.lowStockProducts),
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: _OrdersPanel(orders: data.orders)),
                const SizedBox(width: 18),
                Expanded(
                  flex: 4,
                  child: _LowStockPanel(products: data.lowStockProducts),
                ),
              ],
            ),
          const SizedBox(height: 18),
          if (compact) ...[
            _ProductsPanel(products: data.products),
            const SizedBox(height: 18),
            _TopProductsPanel(products: data.topProducts),
            const SizedBox(height: 18),
            _ChannelsPanel(channels: data.channels),
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                    flex: 5, child: _ProductsPanel(products: data.products)),
                const SizedBox(width: 18),
                Expanded(
                  flex: 4,
                  child: _TopProductsPanel(products: data.topProducts),
                ),
                const SizedBox(width: 18),
                Expanded(
                    flex: 3, child: _ChannelsPanel(channels: data.channels)),
              ],
            ),
          const SizedBox(height: 18),
          _ActivityPanel(activities: data.activities),
        ],
      ),
    );
  }
}

class _HeaderBar extends StatelessWidget {
  const _HeaderBar({
    required this.generatedAt,
    required this.operationBusy,
    required this.onRefresh,
  });

  final DateTime generatedAt;
  final bool operationBusy;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;

        return Container(
          height: compact ? 72 : 84,
          padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 28),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: _AppColors.line)),
          ),
          child: Row(
            children: [
              const _StatusPill(),
              if (compact)
                const Spacer()
              else ...[
                const SizedBox(width: 16),
                const Expanded(child: _SearchBox()),
                const SizedBox(width: 16),
                Text(
                  'آخر تحديث ${_formatTime(generatedAt)}',
                  style: const TextStyle(color: _AppColors.muted),
                ),
              ],
              const SizedBox(width: 12),
              Tooltip(
                message: 'تحديث البيانات',
                child: IconButton.filledTonal(
                  onPressed: operationBusy ? null : onRefresh,
                  icon: operationBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.data});

  final DashboardSnapshot data;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'لوحة تشغيل متجر الرحمة',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
              ),
              const SizedBox(height: 6),
              const Text(
                'تطبيق Windows فعلي متصل بـ MySQL: فواتير، منتجات، مخزون، وقنوات بيع.',
                style: TextStyle(color: _AppColors.muted, height: 1.5),
              ),
            ],
          ),
        ),
        _DatabaseBadge(
          label: 'store_dashboard_db',
          value: '${data.products.length} منتج · ${data.orders.length} فاتورة',
        ),
      ],
    );
  }
}

class _ActionStrip extends StatelessWidget {
  const _ActionStrip({
    required this.busy,
    required this.onAddProduct,
    required this.onQuickSale,
    required this.onRestock,
  });

  final bool busy;
  final VoidCallback onAddProduct;
  final VoidCallback onQuickSale;
  final VoidCallback onRestock;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        FilledButton.icon(
          onPressed: busy ? null : onQuickSale,
          icon: const Icon(Icons.point_of_sale_rounded),
          label: const Text('بيع سريع'),
        ),
        OutlinedButton.icon(
          onPressed: busy ? null : onAddProduct,
          icon: const Icon(Icons.add_box_rounded),
          label: const Text('إضافة منتج'),
        ),
        OutlinedButton.icon(
          onPressed: busy ? null : onRestock,
          icon: const Icon(Icons.inventory_rounded),
          label: const Text('تغذية مخزون'),
        ),
        const _SoftBadge(
          icon: Icons.storage_rounded,
          text: 'MySQL localhost:3306',
          color: _AppColors.primary,
        ),
        const _SoftBadge(
          icon: Icons.verified_rounded,
          text: 'العمليات تحفظ فورًا',
          color: _AppColors.emerald,
        ),
      ],
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.metrics, required this.compact});

  final DashboardMetrics metrics;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final items = [
      _MetricItem(
        title: 'إيراد اليوم',
        value: formatMoney(metrics.todayRevenue),
        subtitle: 'من فواتير قاعدة البيانات',
        icon: Icons.payments_rounded,
        color: _AppColors.emerald,
        progress: (metrics.todayRevenue / 120000).clamp(.05, 1).toDouble(),
      ),
      _MetricItem(
        title: 'طلبات اليوم',
        value: metrics.todayOrders.toString(),
        subtitle: 'عمليات بيع مسجلة',
        icon: Icons.receipt_long_rounded,
        color: _AppColors.primary,
        progress: (metrics.todayOrders / 18).clamp(.05, 1).toDouble(),
      ),
      _MetricItem(
        title: 'متوسط السلة',
        value: formatMoney(metrics.averageBasket),
        subtitle: 'متوسط قيمة الفاتورة',
        icon: Icons.shopping_basket_rounded,
        color: _AppColors.violet,
        progress: (metrics.averageBasket / 12000).clamp(.05, 1).toDouble(),
      ),
      _MetricItem(
        title: 'مخزون منخفض',
        value: metrics.lowStockCount.toString(),
        subtitle: 'منتجات عند حد إعادة الطلب',
        icon: Icons.warning_amber_rounded,
        color: _AppColors.amber,
        progress: (metrics.lowStockCount / 12).clamp(.05, 1).toDouble(),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: compact ? 2 : 4,
        mainAxisExtent: 150,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemBuilder: (context, index) => _MetricCard(item: items[index]),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.item});

  final _MetricItem item;

  @override
  Widget build(BuildContext context) {
    return _Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(item.icon, color: item.color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _AppColors.muted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            item.value,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.subtitle,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: item.progress,
              minHeight: 6,
              color: item.color,
              backgroundColor: item.color.withValues(alpha: .1),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrdersPanel extends StatelessWidget {
  const _OrdersPanel({required this.orders});

  final List<OrderRecord> orders;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      icon: Icons.receipt_long_rounded,
      title: 'الطلبات النشطة',
      subtitle: 'آخر الفواتير من MySQL',
      child: orders.isEmpty
          ? const _EmptyState(text: 'لا توجد فواتير بعد')
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 44,
                dataRowMinHeight: 54,
                dataRowMaxHeight: 62,
                horizontalMargin: 14,
                columnSpacing: 26,
                columns: const [
                  DataColumn(label: Text('رقم')),
                  DataColumn(label: Text('العميل')),
                  DataColumn(label: Text('القناة')),
                  DataColumn(label: Text('الإجمالي')),
                  DataColumn(label: Text('الحالة')),
                  DataColumn(label: Text('الوقت')),
                ],
                rows: orders.map((order) {
                  return DataRow(
                    cells: [
                      DataCell(Text('#${order.id}')),
                      DataCell(
                        SizedBox(
                          width: 150,
                          child: Text(
                            order.customerName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      DataCell(_StatusChip(
                          order.channel, _channelColor(order.channel))),
                      DataCell(Text(formatMoney(order.total))),
                      DataCell(_StatusChip(
                          order.status, _statusColor(order.status))),
                      DataCell(Text(_formatTime(order.createdAt))),
                    ],
                  );
                }).toList(),
              ),
            ),
    );
  }
}

class _LowStockPanel extends StatelessWidget {
  const _LowStockPanel({required this.products});

  final List<ProductRecord> products;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      icon: Icons.inventory_2_rounded,
      title: 'تنبيهات المخزون',
      subtitle: 'منتجات تحتاج متابعة',
      child: products.isEmpty
          ? const _EmptyState(text: 'كل المنتجات فوق حد إعادة الطلب')
          : Column(
              children: [
                for (final product in products.take(6)) ...[
                  _LowStockTile(product: product),
                  if (product != products.take(6).last)
                    const SizedBox(height: 12),
                ],
              ],
            ),
    );
  }
}

class _ProductsPanel extends StatelessWidget {
  const _ProductsPanel({required this.products});

  final List<ProductRecord> products;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      icon: Icons.storefront_rounded,
      title: 'المنتجات',
      subtitle: 'أسعار ومخزون من قاعدة البيانات',
      child: Column(
        children: [
          for (final product in products.take(8)) ...[
            _ProductTile(product: product),
            if (product != products.take(8).last) const SizedBox(height: 13),
          ],
        ],
      ),
    );
  }
}

class _TopProductsPanel extends StatelessWidget {
  const _TopProductsPanel({required this.products});

  final List<TopProductRecord> products;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      icon: Icons.sell_rounded,
      title: 'أفضل المنتجات',
      subtitle: 'محسوبة من تفاصيل الفواتير',
      child: Column(
        children: [
          for (final product in products) ...[
            _TopProductTile(product: product),
            if (product != products.last) const SizedBox(height: 13),
          ],
        ],
      ),
    );
  }
}

class _ChannelsPanel extends StatelessWidget {
  const _ChannelsPanel({required this.channels});

  final List<ChannelRecord> channels;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      icon: Icons.hub_rounded,
      title: 'قنوات البيع',
      subtitle: 'توزيع الطلبات',
      child: channels.isEmpty
          ? const _EmptyState(text: 'لا توجد قنوات بعد')
          : Column(
              children: [
                for (final channel in channels) ...[
                  _ChannelTile(channel: channel),
                  if (channel != channels.last) const SizedBox(height: 14),
                ],
              ],
            ),
    );
  }
}

class _ActivityPanel extends StatelessWidget {
  const _ActivityPanel({required this.activities});

  final List<ActivityRecord> activities;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      icon: Icons.timeline_rounded,
      title: 'سجل العمليات',
      subtitle: 'مبيعات وحركة مخزون فعلية',
      child: activities.isEmpty
          ? const _EmptyState(text: 'لا توجد عمليات بعد')
          : Wrap(
              spacing: 14,
              runSpacing: 14,
              children: activities.map((item) {
                return SizedBox(
                  width: 360,
                  child: _ActivityTile(item: item),
                );
              }).toList(),
            ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product});

  final ProductRecord product;

  @override
  Widget build(BuildContext context) {
    final color = product.isLowStock ? _AppColors.amber : _AppColors.emerald;

    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.shopping_bag_rounded, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      product.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  Text(
                    formatMoney(product.price),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                '${product.category} · مخزون ${product.stock} · حد ${product.reorderLevel}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _AppColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: product.stockRatio,
                  minHeight: 6,
                  color: color,
                  backgroundColor: color.withValues(alpha: .1),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LowStockTile extends StatelessWidget {
  const _LowStockTile({required this.product});

  final ProductRecord product;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: _AppColors.amber.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _AppColors.amber.withValues(alpha: .18)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: _AppColors.amber),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  'المتوفر ${product.stock} والحد الأدنى ${product.reorderLevel}',
                  style: const TextStyle(color: _AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopProductTile extends StatelessWidget {
  const _TopProductTile({required this.product});

  final TopProductRecord product;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                product.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            Text(
              formatMoney(product.revenue),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          '${product.category} · ${product.units} وحدة',
          style: const TextStyle(color: _AppColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: product.performance,
            minHeight: 7,
            color: _AppColors.primary,
            backgroundColor: _AppColors.primary.withValues(alpha: .1),
          ),
        ),
      ],
    );
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({required this.channel});

  final ChannelRecord channel;

  @override
  Widget build(BuildContext context) {
    final color = _channelColor(channel.channel);

    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(_channelIcon(channel.channel), color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      channel.channel,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  Text(
                    '${(channel.share * 100).round()}%',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: channel.share.clamp(.04, 1),
                  minHeight: 7,
                  color: color,
                  backgroundColor: color.withValues(alpha: .1),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.item});

  final ActivityRecord item;

  @override
  Widget build(BuildContext context) {
    final color = switch (item.kind) {
      'sale' => _AppColors.primary,
      'restock' => _AppColors.emerald,
      'create' => _AppColors.violet,
      _ => _AppColors.amber,
    };

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: _AppColors.canvas,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _AppColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(_activityIcon(item.kind), color: color, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    Text(
                      _formatTime(item.createdAt),
                      style: const TextStyle(
                        color: _AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  item.detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _AppColors.muted, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _AppColors.primary.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: _AppColors.primary, size: 21),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _Surface extends StatelessWidget {
  const _Surface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _AppColors.line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .035),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SideNav extends StatelessWidget {
  const _SideNav();

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.dashboard_rounded, 'لوحة التحكم'),
      (Icons.point_of_sale_rounded, 'المبيعات'),
      (Icons.inventory_2_rounded, 'المخزون'),
      (Icons.people_alt_rounded, 'العملاء'),
      (Icons.analytics_rounded, 'التقارير'),
      (Icons.settings_rounded, 'الإعدادات'),
    ];

    return Container(
      width: 278,
      color: _AppColors.sidebar,
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _AppColors.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child:
                    const Icon(Icons.storefront_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'NOVA POS',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Windows + MySQL',
                      style: TextStyle(color: Color(0xFFAAB2C5), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const _SidebarStatus(),
          const SizedBox(height: 18),
          for (var i = 0; i < items.length; i++) ...[
            _NavTile(icon: items[i].$1, label: items[i].$2, selected: i == 0),
            const SizedBox(height: 6),
          ],
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .07),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: .08)),
            ),
            child: const Text(
              'كل عملية بيع أو توريد يتم حفظها في MySQL مباشرة.',
              style: TextStyle(color: Color(0xFFC7CEDD), height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.label,
    required this.selected,
  });

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color:
            selected ? Colors.white.withValues(alpha: .12) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: selected ? Colors.white : const Color(0xFFAAB2C5),
            size: 21,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFFC7CEDD),
                fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarStatus extends StatelessWidget {
  const _SidebarStatus();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: const Row(
        children: [
          Icon(Icons.sensors_rounded, color: _AppColors.emerald, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'قاعدة البيانات متصلة',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
            ),
          ),
          _SmallDot(color: _AppColors.emerald),
        ],
      ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox();

  @override
  Widget build(BuildContext context) {
    return TextField(
      decoration: InputDecoration(
        hintText: 'بحث سريع في المنتجات والفواتير',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: Tooltip(
          message: 'فلترة',
          child: IconButton(
            onPressed: () {},
            icon: const Icon(Icons.filter_list_rounded),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _AppColors.emerald.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _AppColors.emerald.withValues(alpha: .16)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.storage_rounded, color: _AppColors.emerald, size: 19),
          SizedBox(width: 8),
          Text(
            'MySQL متصل',
            style: TextStyle(
              color: _AppColors.emerald,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _DatabaseBadge extends StatelessWidget {
  const _DatabaseBadge({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.dns_rounded, color: _AppColors.primary, size: 20),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(color: _AppColors.muted, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SoftBadge extends StatelessWidget {
  const _SoftBadge({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: .16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .16)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _SmallDot extends StatelessWidget {
  const _SmallDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 110,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _AppColors.canvas,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _AppColors.line),
      ),
      child: Text(text, style: const TextStyle(color: _AppColors.muted)),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 18),
              Text(
                'جاري الاتصال بـ MySQL وتجهيز قاعدة البيانات...',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DatabaseErrorView extends StatelessWidget {
  const _DatabaseErrorView({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _AppColors.canvas,
      body: Center(
        child: Container(
          width: 620,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _AppColors.line),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline_rounded, color: _AppColors.rose),
              const SizedBox(height: 12),
              const Text(
                'تعذر الاتصال بقاعدة البيانات',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              const Text(
                'تأكد أن MySQL يعمل على 127.0.0.1:3306 وأن المستخدم root وكلمة المرور root.',
                style: TextStyle(color: _AppColors.muted, height: 1.5),
              ),
              const SizedBox(height: 12),
              SelectableText(
                error,
                style: const TextStyle(color: _AppColors.rose, fontSize: 12),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddProductDialog extends StatefulWidget {
  const _AddProductDialog();

  @override
  State<_AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState extends State<_AddProductDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _category = TextEditingController(text: 'عام');
  final _price = TextEditingController();
  final _stock = TextEditingController(text: '0');
  final _reorder = TextEditingController(text: '10');

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _price.dispose();
    _stock.dispose();
    _reorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _DialogFrame(
      title: 'إضافة منتج',
      icon: Icons.add_box_rounded,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TextField(controller: _name, label: 'اسم المنتج'),
            const SizedBox(height: 12),
            _TextField(controller: _category, label: 'التصنيف'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _TextField(
                    controller: _price,
                    label: 'السعر',
                    number: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TextField(
                    controller: _stock,
                    label: 'المخزون',
                    number: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TextField(
                    controller: _reorder,
                    label: 'حد إعادة الطلب',
                    number: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _DialogActions(
              onSubmit: () {
                if (!_formKey.currentState!.validate()) return;
                Navigator.of(context).pop(
                  _ProductInput(
                    name: _name.text,
                    category: _category.text,
                    price: double.parse(_price.text),
                    stock: int.parse(_stock.text),
                    reorderLevel: int.parse(_reorder.text),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickSaleDialog extends StatefulWidget {
  const _QuickSaleDialog({required this.products});

  final List<ProductRecord> products;

  @override
  State<_QuickSaleDialog> createState() => _QuickSaleDialogState();
}

class _QuickSaleDialogState extends State<_QuickSaleDialog> {
  final _formKey = GlobalKey<FormState>();
  final _customer = TextEditingController(text: 'عميل نقدي');
  final _quantity = TextEditingController(text: '1');
  int? _productId;
  String _channel = 'المتجر';

  @override
  void initState() {
    super.initState();
    _productId = widget.products.isEmpty ? null : widget.products.first.id;
  }

  @override
  void dispose() {
    _customer.dispose();
    _quantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _DialogFrame(
      title: 'بيع سريع',
      icon: Icons.point_of_sale_rounded,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int>(
              value: _productId,
              items: widget.products.map((product) {
                return DropdownMenuItem(
                  value: product.id,
                  child: Text('${product.name} · ${product.stock} متوفر'),
                );
              }).toList(),
              onChanged: (value) => setState(() => _productId = value),
              decoration: const InputDecoration(labelText: 'المنتج'),
              validator: (value) => value == null ? 'اختر المنتج' : null,
            ),
            const SizedBox(height: 12),
            _TextField(controller: _customer, label: 'اسم العميل'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _TextField(
                    controller: _quantity,
                    label: 'الكمية',
                    number: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _channel,
                    items: const [
                      DropdownMenuItem(value: 'المتجر', child: Text('المتجر')),
                      DropdownMenuItem(
                          value: 'أونلاين', child: Text('أونلاين')),
                      DropdownMenuItem(value: 'واتساب', child: Text('واتساب')),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _channel = value);
                    },
                    decoration: const InputDecoration(labelText: 'القناة'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _DialogActions(
              onSubmit: () {
                if (!_formKey.currentState!.validate()) return;
                Navigator.of(context).pop(
                  _SaleInput(
                    productId: _productId!,
                    quantity: int.parse(_quantity.text),
                    customerName: _customer.text,
                    channel: _channel,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _RestockDialog extends StatefulWidget {
  const _RestockDialog({required this.products});

  final List<ProductRecord> products;

  @override
  State<_RestockDialog> createState() => _RestockDialogState();
}

class _RestockDialogState extends State<_RestockDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantity = TextEditingController(text: '10');
  final _note = TextEditingController(text: 'توريد جديد');
  int? _productId;

  @override
  void initState() {
    super.initState();
    _productId = widget.products.isEmpty ? null : widget.products.first.id;
  }

  @override
  void dispose() {
    _quantity.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _DialogFrame(
      title: 'تغذية مخزون',
      icon: Icons.inventory_rounded,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int>(
              value: _productId,
              items: widget.products.map((product) {
                return DropdownMenuItem(
                  value: product.id,
                  child: Text('${product.name} · الحالي ${product.stock}'),
                );
              }).toList(),
              onChanged: (value) => setState(() => _productId = value),
              decoration: const InputDecoration(labelText: 'المنتج'),
              validator: (value) => value == null ? 'اختر المنتج' : null,
            ),
            const SizedBox(height: 12),
            _TextField(controller: _quantity, label: 'الكمية', number: true),
            const SizedBox(height: 12),
            _TextField(controller: _note, label: 'ملاحظة'),
            const SizedBox(height: 18),
            _DialogActions(
              onSubmit: () {
                if (!_formKey.currentState!.validate()) return;
                Navigator.of(context).pop(
                  _RestockInput(
                    productId: _productId!,
                    quantity: int.parse(_quantity.text),
                    note: _note.text,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogFrame extends StatelessWidget {
  const _DialogFrame({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(icon, color: _AppColors.primary),
          const SizedBox(width: 10),
          Text(title),
        ],
      ),
      content: SizedBox(width: 520, child: child),
    );
  }
}

class _DialogActions extends StatelessWidget {
  const _DialogActions({required this.onSubmit});

  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        const SizedBox(width: 10),
        FilledButton.icon(
          onPressed: onSubmit,
          icon: const Icon(Icons.check_rounded),
          label: const Text('حفظ'),
        ),
      ],
    );
  }
}

class _TextField extends StatelessWidget {
  const _TextField({
    required this.controller,
    required this.label,
    this.number = false,
  });

  final TextEditingController controller;
  final String label;
  final bool number;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(labelText: label),
      validator: (value) {
        final text = value?.trim() ?? '';
        if (text.isEmpty) return 'هذا الحقل مطلوب';
        if (number && double.tryParse(text) == null) return 'أدخل رقمًا صحيحًا';
        return null;
      },
    );
  }
}

class _ProductInput {
  const _ProductInput({
    required this.name,
    required this.category,
    required this.price,
    required this.stock,
    required this.reorderLevel,
  });

  final String name;
  final String category;
  final double price;
  final int stock;
  final int reorderLevel;
}

class _SaleInput {
  const _SaleInput({
    required this.productId,
    required this.quantity,
    required this.customerName,
    required this.channel,
  });

  final int productId;
  final int quantity;
  final String customerName;
  final String channel;
}

class _RestockInput {
  const _RestockInput({
    required this.productId,
    required this.quantity,
    required this.note,
  });

  final int productId;
  final int quantity;
  final String note;
}

class _MetricItem {
  const _MetricItem({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.progress,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
  final double progress;
}

class _AppColors {
  static const canvas = Color(0xFFF6F7FB);
  static const muted = Color(0xFF667085);
  static const line = Color(0xFFE4E7EC);
  static const sidebar = Color(0xFF111827);
  static const primary = Color(0xFF2563EB);
  static const emerald = Color(0xFF059669);
  static const amber = Color(0xFFD97706);
  static const rose = Color(0xFFE11D48);
  static const cyan = Color(0xFF0891B2);
  static const violet = Color(0xFF7C3AED);
}

Color _channelColor(String channel) {
  return switch (channel) {
    'المتجر' => _AppColors.primary,
    'أونلاين' => _AppColors.violet,
    'واتساب' => _AppColors.emerald,
    _ => _AppColors.cyan,
  };
}

IconData _channelIcon(String channel) {
  return switch (channel) {
    'المتجر' => Icons.store_mall_directory_rounded,
    'أونلاين' => Icons.language_rounded,
    'واتساب' => Icons.chat_bubble_rounded,
    _ => Icons.hub_rounded,
  };
}

Color _statusColor(String status) {
  return switch (status) {
    'جاهز' => _AppColors.emerald,
    'قيد التجهيز' => _AppColors.primary,
    'شحن' => _AppColors.cyan,
    _ => _AppColors.amber,
  };
}

IconData _activityIcon(String kind) {
  return switch (kind) {
    'sale' => Icons.receipt_long_rounded,
    'restock' => Icons.inventory_rounded,
    'create' => Icons.add_box_rounded,
    _ => Icons.sync_rounded,
  };
}

String _formatTime(DateTime date) {
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
