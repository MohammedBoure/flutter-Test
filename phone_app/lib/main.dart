import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

const _backgroundTickEvent = 'backgroundTick';
const _silentCounterEvent = 'silentCounterTick';
const _stopServiceCommand = 'stopService';
const _startSilentCounterCommand = 'startSilentCounter';
const _stopSilentCounterCommand = 'stopSilentCounter';
const _resetSilentCounterCommand = 'resetSilentCounter';
const _backgroundNotificationId = 9401;
const _backgroundNotificationChannelId = 'permission_lab_background';
const _backgroundNotificationChannelName = 'Permission Lab Service';
const _backgroundNotificationChannelDescription =
    'إشعار دائم لخدمة Permission Lab التي تعمل في الخلفية.';
const _notificationIcon = 'ic_bg_service_small';
const _notificationAccent = Color(0xFF0F766E);

final _notifications = FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeServiceNotificationTheme();
  await initializeBackgroundService();
  runApp(const PhonePermissionsLabApp());
}

Future<void> initializeServiceNotificationTheme() async {
  const initializationSettings = InitializationSettings(
    android: AndroidInitializationSettings(_notificationIcon),
  );

  await _notifications.initialize(initializationSettings);

  const channel = AndroidNotificationChannel(
    _backgroundNotificationChannelId,
    _backgroundNotificationChannelName,
    description: _backgroundNotificationChannelDescription,
    importance: Importance.low,
    playSound: false,
    enableVibration: false,
    showBadge: false,
  );

  await _notifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);
}

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onBackgroundServiceStart,
      autoStart: false,
      autoStartOnBoot: true,
      isForegroundMode: true,
      notificationChannelId: _backgroundNotificationChannelId,
      initialNotificationTitle: 'Permission Lab | خدمة الخلفية',
      initialNotificationContent: 'جاهزة وتنتظر أول نبضة',
      foregroundServiceNotificationId: _backgroundNotificationId,
      foregroundServiceTypes: [AndroidForegroundType.dataSync],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onBackgroundServiceStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void onBackgroundServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  await initializeServiceNotificationTheme();

  if (service is AndroidServiceInstance) {
    await service.setAsForegroundService();
  }

  Timer? heartbeatTimer;
  Timer? silentCounterTimer;
  var tick = 0;
  var silentCounter = 0;
  var silentCounterRunning = false;
  DateTime? silentCounterStartedAt;
  final startedAt = DateTime.now();
  await _showStyledServiceNotification(
    tick: tick,
    now: startedAt,
    startedAt: startedAt,
  );

  service.on(_stopServiceCommand).listen((event) {
    heartbeatTimer?.cancel();
    silentCounterTimer?.cancel();
    _notifications.cancel(_backgroundNotificationId);
    service.stopSelf();
  });

  service.on(_startSilentCounterCommand).listen((event) {
    if (silentCounterRunning) return;

    silentCounterRunning = true;
    silentCounterStartedAt = DateTime.now();
    service.invoke(_silentCounterEvent, {
      'running': true,
      'counter': silentCounter,
      'startedAt': silentCounterStartedAt!.toIso8601String(),
      'timestamp': silentCounterStartedAt!.toIso8601String(),
    });

    silentCounterTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      silentCounter += 1;
      final now = DateTime.now();
      service.invoke(_silentCounterEvent, {
        'running': true,
        'counter': silentCounter,
        'startedAt': silentCounterStartedAt?.toIso8601String(),
        'timestamp': now.toIso8601String(),
      });
    });
  });

  service.on(_stopSilentCounterCommand).listen((event) {
    silentCounterTimer?.cancel();
    silentCounterTimer = null;
    silentCounterRunning = false;
    service.invoke(_silentCounterEvent, {
      'running': false,
      'counter': silentCounter,
      'startedAt': silentCounterStartedAt?.toIso8601String(),
      'timestamp': DateTime.now().toIso8601String(),
    });
  });

  service.on(_resetSilentCounterCommand).listen((event) {
    silentCounter = 0;
    service.invoke(_silentCounterEvent, {
      'running': silentCounterRunning,
      'counter': silentCounter,
      'startedAt': silentCounterStartedAt?.toIso8601String(),
      'timestamp': DateTime.now().toIso8601String(),
    });
  });

  heartbeatTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
    tick += 1;
    final now = DateTime.now();

    if (service is AndroidServiceInstance) {
      final isForeground = await service.isForegroundService();
      if (isForeground) {
        await _showStyledServiceNotification(
          tick: tick,
          now: now,
          startedAt: startedAt,
        );
      }
    }

    service.invoke(_backgroundTickEvent, {
      'tick': tick,
      'startedAt': startedAt.toIso8601String(),
      'timestamp': now.toIso8601String(),
    });
  });
}

Future<void> _showStyledServiceNotification({
  required int tick,
  required DateTime now,
  required DateTime startedAt,
}) async {
  final startedLabel = _formatTime(startedAt);
  final nowLabel = _formatTime(now);
  final content = tick == 0
      ? 'تم تشغيل الخدمة عند $startedLabel'
      : 'نبضة $tick | آخر تحديث $nowLabel';

  await _notifications.show(
    _backgroundNotificationId,
    'Permission Lab يعمل في الخلفية',
    content,
    NotificationDetails(
      android: AndroidNotificationDetails(
        _backgroundNotificationChannelId,
        _backgroundNotificationChannelName,
        channelDescription: _backgroundNotificationChannelDescription,
        icon: _notificationIcon,
        importance: Importance.low,
        priority: Priority.low,
        category: AndroidNotificationCategory.service,
        color: _notificationAccent,
        colorized: true,
        ongoing: true,
        autoCancel: false,
        onlyAlertOnce: true,
        showWhen: true,
        when: now.millisecondsSinceEpoch,
        usesChronometer: true,
        ticker: 'Permission Lab background service',
        subText: 'Foreground service',
        styleInformation: BigTextStyleInformation(
          '$content\nالخدمة مستمرة حتى عند إغلاق واجهة التطبيق.',
          contentTitle: 'Permission Lab يعمل في الخلفية',
          summaryText: 'خدمة مستمرة',
        ),
      ),
    ),
  );
}

class PhonePermissionsLabApp extends StatelessWidget {
  const PhonePermissionsLabApp({
    super.key,
    this.backgroundService = const FlutterBackgroundServiceController(),
  });

  final BackgroundServiceController backgroundService;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF0F766E);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Permission Lab',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        scaffoldBackgroundColor: const Color(0xFFF6F8FA),
        cardTheme: CardTheme(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
        ),
      ),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: PermissionLabPage(backgroundService: backgroundService),
      ),
    );
  }
}

class PermissionLabPage extends StatefulWidget {
  const PermissionLabPage({
    super.key,
    required this.backgroundService,
  });

  final BackgroundServiceController backgroundService;

  @override
  State<PermissionLabPage> createState() => _PermissionLabPageState();
}

abstract class BackgroundServiceController {
  const BackgroundServiceController();

  Stream<Map<String, dynamic>?> get updates;
  Stream<Map<String, dynamic>?> get silentCounterUpdates;
  Future<bool> isRunning();
  Future<bool> start();
  void stop();
  void startSilentCounter();
  void stopSilentCounter();
  void resetSilentCounter();
}

class FlutterBackgroundServiceController extends BackgroundServiceController {
  const FlutterBackgroundServiceController();

  FlutterBackgroundService get _service => FlutterBackgroundService();

  @override
  Stream<Map<String, dynamic>?> get updates => _service.on(
        _backgroundTickEvent,
      );

  @override
  Stream<Map<String, dynamic>?> get silentCounterUpdates => _service.on(
        _silentCounterEvent,
      );

  @override
  Future<bool> isRunning() => _service.isRunning();

  @override
  Future<bool> start() => _service.startService();

  @override
  void stop() => _service.invoke(_stopServiceCommand);

  @override
  void startSilentCounter() => _service.invoke(_startSilentCounterCommand);

  @override
  void stopSilentCounter() => _service.invoke(_stopSilentCounterCommand);

  @override
  void resetSilentCounter() => _service.invoke(_resetSilentCounterCommand);
}

class _PermissionLabPageState extends State<PermissionLabPage> {
  final Map<Permission, PermissionStatus> _statuses = {};
  final Map<Permission, ServiceStatus> _services = {};
  final Map<Permission, bool> _rationales = {};
  final Set<Permission> _busy = {};
  StreamSubscription<Map<String, dynamic>?>? _backgroundSubscription;
  StreamSubscription<Map<String, dynamic>?>? _silentCounterSubscription;
  Timer? _backgroundPoller;
  bool _refreshing = true;
  bool _serviceBusy = false;
  bool _silentCounterBusy = false;
  bool _backgroundServiceRunning = false;
  bool _silentCounterRunning = false;
  int _backgroundTick = 0;
  int _silentCounter = 0;
  DateTime? _backgroundStartedAt;
  DateTime? _lastBackgroundTickAt;
  DateTime? _silentCounterStartedAt;
  DateTime? _lastSilentCounterTickAt;

  @override
  void initState() {
    super.initState();
    _listenToBackgroundService();
    unawaited(_refreshAll());
    unawaited(_refreshBackgroundServiceState());
    _backgroundPoller = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_refreshBackgroundServiceState()),
    );
  }

  @override
  void dispose() {
    _backgroundSubscription?.cancel();
    _silentCounterSubscription?.cancel();
    _backgroundPoller?.cancel();
    super.dispose();
  }

  void _listenToBackgroundService() {
    _backgroundSubscription = widget.backgroundService.updates.listen((event) {
      if (event == null || !mounted) return;

      setState(() {
        _backgroundTick = _asInt(event['tick']);
        _backgroundStartedAt = _asDate(event['startedAt']);
        _lastBackgroundTickAt = _asDate(event['timestamp']);
        _backgroundServiceRunning = true;
      });
    });

    _silentCounterSubscription =
        widget.backgroundService.silentCounterUpdates.listen((event) {
      if (event == null || !mounted) return;

      setState(() {
        _silentCounterRunning = event['running'] == true;
        _silentCounter = _asInt(event['counter']);
        _silentCounterStartedAt = _asDate(event['startedAt']);
        _lastSilentCounterTickAt = _asDate(event['timestamp']);
      });
    });
  }

  Future<void> _refreshBackgroundServiceState() async {
    final running = await widget.backgroundService.isRunning();
    if (!mounted) return;
    setState(() => _backgroundServiceRunning = running);
  }

  Future<void> _startBackgroundService() async {
    setState(() => _serviceBusy = true);
    try {
      await Permission.notification.request();
      final started = await widget.backgroundService.start();
      await _refreshBackgroundServiceState();
      if (!mounted) return;
      _showMessage(
        started ? 'تم تشغيل خدمة الخلفية' : 'الخدمة تعمل بالفعل أو لم تبدأ',
      );
    } finally {
      if (mounted) {
        setState(() => _serviceBusy = false);
      }
    }
  }

  Future<void> _stopBackgroundService() async {
    setState(() => _serviceBusy = true);
    try {
      widget.backgroundService.stop();
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await _refreshBackgroundServiceState();
      if (!mounted) return;
      setState(() {
        _silentCounterRunning = false;
      });
      _showMessage('تم إرسال أمر إيقاف خدمة الخلفية');
    } finally {
      if (mounted) {
        setState(() => _serviceBusy = false);
      }
    }
  }

  Future<void> _startSilentCounter() async {
    setState(() => _silentCounterBusy = true);
    try {
      if (!_backgroundServiceRunning) {
        await Permission.notification.request();
        await widget.backgroundService.start();
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await _refreshBackgroundServiceState();
      }

      widget.backgroundService.startSilentCounter();
      if (!mounted) return;
      setState(() => _silentCounterRunning = true);
      _showMessage('بدأ العداد الصامت داخل خدمة الخلفية');
    } finally {
      if (mounted) {
        setState(() => _silentCounterBusy = false);
      }
    }
  }

  Future<void> _stopSilentCounter() async {
    setState(() => _silentCounterBusy = true);
    try {
      widget.backgroundService.stopSilentCounter();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      setState(() => _silentCounterRunning = false);
      _showMessage('توقف العداد الصامت');
    } finally {
      if (mounted) {
        setState(() => _silentCounterBusy = false);
      }
    }
  }

  void _resetSilentCounter() {
    widget.backgroundService.resetSilentCounter();
    setState(() => _silentCounter = 0);
    _showMessage('تم تصفير العداد الصامت');
  }

  Future<void> _requestBatteryExemption() async {
    final status = await Permission.ignoreBatteryOptimizations.request();
    if (!mounted) return;
    _statuses[Permission.ignoreBatteryOptimizations] = status;
    setState(() {});
    _showMessage(
      status.isGranted
          ? 'تم السماح بتجاهل تحسين البطارية'
          : 'لم يتم السماح بتجاهل تحسين البطارية',
    );
  }

  Future<void> _refreshAll() async {
    setState(() => _refreshing = true);
    for (final spec in permissionSpecs) {
      await _refreshSpec(spec, notify: false);
    }
    if (mounted) {
      setState(() => _refreshing = false);
    }
  }

  Future<void> _refreshSpec(
    PermissionSpec spec, {
    bool notify = true,
  }) async {
    final statuses = <Permission, PermissionStatus>{};
    final services = <Permission, ServiceStatus>{};
    final rationales = <Permission, bool>{};

    for (final permission in spec.permissions) {
      statuses[permission] = await permission.status;
      rationales[permission] = await permission.shouldShowRequestRationale;
      if (permission is PermissionWithService) {
        services[permission] = await permission.serviceStatus;
      }
    }

    if (!mounted) return;
    setState(() {
      _statuses.addAll(statuses);
      _services.addAll(services);
      _rationales.addAll(rationales);
    });

    if (notify) {
      _showMessage('تم تحديث حالة ${spec.title}');
    }
  }

  Future<void> _requestSpec(PermissionSpec spec) async {
    setState(() => _busy.addAll(spec.permissions));
    try {
      final result = await spec.permissions.request();
      final services = <Permission, ServiceStatus>{};
      final rationales = <Permission, bool>{};

      for (final permission in spec.permissions) {
        rationales[permission] = await permission.shouldShowRequestRationale;
        if (permission is PermissionWithService) {
          services[permission] = await permission.serviceStatus;
        }
      }

      if (!mounted) return;
      setState(() {
        _statuses.addAll(result);
        _services.addAll(services);
        _rationales.addAll(rationales);
      });
      _showMessage('${spec.title}: ${_summaryLabel(spec)}');
    } finally {
      if (mounted) {
        setState(() => _busy.removeAll(spec.permissions));
      }
    }
  }

  Future<void> _requestEssentials() async {
    final essentials = permissionSpecs
        .where((spec) => spec.category == PermissionCategory.essential)
        .expand((spec) => spec.permissions)
        .toList();

    setState(() => _busy.addAll(essentials));
    try {
      final result = await essentials.request();
      if (!mounted) return;
      setState(() => _statuses.addAll(result));
      await _refreshAll();
      _showMessage('تم طلب الصلاحيات الأساسية');
    } finally {
      if (mounted) {
        setState(() => _busy.removeAll(essentials));
      }
    }
  }

  Future<void> _openSettings() async {
    final opened = await openAppSettings();
    if (!mounted) return;
    _showMessage(opened ? 'تم فتح إعدادات التطبيق' : 'تعذر فتح الإعدادات');
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _summaryLabel(PermissionSpec spec) {
    final statuses = spec.permissions.map((permission) {
      return _statuses[permission] ?? PermissionStatus.denied;
    }).toList();

    if (statuses.every((status) => status.isGranted)) {
      return 'مسموح';
    }
    if (statuses.any((status) => status.isLimited)) {
      return 'محدود';
    }
    if (statuses.any((status) => status.isPermanentlyDenied)) {
      return 'مرفوض دائمًا';
    }
    if (statuses.any((status) => status.isRestricted)) {
      return 'مقيّد';
    }
    return 'غير ممنوح';
  }

  Color _summaryColor(PermissionSpec spec) {
    final label = _summaryLabel(spec);
    return switch (label) {
      'مسموح' => const Color(0xFF047857),
      'محدود' => const Color(0xFF0E7490),
      'مرفوض دائمًا' => const Color(0xFFB91C1C),
      'مقيّد' => const Color(0xFF7C2D12),
      _ => const Color(0xFF6B7280),
    };
  }

  @override
  Widget build(BuildContext context) {
    final grantedCount = permissionSpecs.where((spec) {
      return spec.permissions.every((permission) {
        return _statuses[permission]?.isGranted ?? false;
      });
    }).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('مختبر صلاحيات الهاتف'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _refreshing ? null : _refreshAll,
            icon: _refreshing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'إعدادات التطبيق',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              sliver: SliverToBoxAdapter(
                child: _SummaryPanel(
                  grantedCount: grantedCount,
                  totalCount: permissionSpecs.length,
                  refreshing: _refreshing,
                  onRequestEssentials: _requestEssentials,
                  onOpenSettings: _openSettings,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              sliver: SliverToBoxAdapter(
                child: _BackgroundServicePanel(
                  running: _backgroundServiceRunning,
                  busy: _serviceBusy,
                  tick: _backgroundTick,
                  startedAt: _backgroundStartedAt,
                  lastTickAt: _lastBackgroundTickAt,
                  onStart: _startBackgroundService,
                  onStop: _stopBackgroundService,
                  onRefresh: _refreshBackgroundServiceState,
                  onBatteryExemption: _requestBatteryExemption,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              sliver: SliverToBoxAdapter(
                child: _SilentCounterPanel(
                  running: _silentCounterRunning,
                  busy: _silentCounterBusy,
                  counter: _silentCounter,
                  serviceRunning: _backgroundServiceRunning,
                  startedAt: _silentCounterStartedAt,
                  lastTickAt: _lastSilentCounterTickAt,
                  onStart: _startSilentCounter,
                  onStop: _stopSilentCounter,
                  onReset: _resetSilentCounter,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList.separated(
                itemCount: permissionSpecs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final spec = permissionSpecs[index];
                  return PermissionCard(
                    spec: spec,
                    summaryLabel: _summaryLabel(spec),
                    summaryColor: _summaryColor(spec),
                    statuses: _statuses,
                    services: _services,
                    rationales: _rationales,
                    busy: spec.permissions.any(_busy.contains),
                    onRequest: () => _requestSpec(spec),
                    onRefresh: () => _refreshSpec(spec),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({
    required this.grantedCount,
    required this.totalCount,
    required this.refreshing,
    required this.onRequestEssentials,
    required this.onOpenSettings,
  });

  final int grantedCount;
  final int totalCount;
  final bool refreshing;
  final VoidCallback onRequestEssentials;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final progress = totalCount == 0 ? 0.0 : grantedCount / totalCount;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F766E).withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.admin_panel_settings_rounded,
                    color: Color(0xFF0F766E),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$grantedCount من $totalCount صلاحية مفعلة',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'الطلبات تتم من Flutter، والتصريحات موجودة في AndroidManifest.',
                        style: TextStyle(color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                color: const Color(0xFF0F766E),
                backgroundColor: const Color(0xFFE5E7EB),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: refreshing ? null : onRequestEssentials,
                  icon: const Icon(Icons.verified_user_rounded),
                  label: const Text('طلب الأساسية'),
                ),
                OutlinedButton.icon(
                  onPressed: onOpenSettings,
                  icon: const Icon(Icons.tune_rounded),
                  label: const Text('إعدادات التطبيق'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BackgroundServicePanel extends StatelessWidget {
  const _BackgroundServicePanel({
    required this.running,
    required this.busy,
    required this.tick,
    required this.startedAt,
    required this.lastTickAt,
    required this.onStart,
    required this.onStop,
    required this.onRefresh,
    required this.onBatteryExemption,
  });

  final bool running;
  final bool busy;
  final int tick;
  final DateTime? startedAt;
  final DateTime? lastTickAt;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onRefresh;
  final VoidCallback onBatteryExemption;

  @override
  Widget build(BuildContext context) {
    final statusColor =
        running ? const Color(0xFF047857) : const Color(0xFF64748B);
    final lastTickLabel = lastTickAt == null
        ? 'لا توجد نبضة بعد'
        : 'آخر نبضة ${_formatTime(lastTickAt!)}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.sync_lock_rounded,
                    color: statusColor,
                  ),
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
                              'خدمة الخلفية المستمرة',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                          ),
                          _StatusPill(
                            text: running ? 'تعمل' : 'متوقفة',
                            color: statusColor,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$lastTickLabel | عدد النبضات $tick',
                        style: const TextStyle(color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetricPill(
                  icon: Icons.timelapse_rounded,
                  label: 'بدأت',
                  value:
                      startedAt == null ? 'غير متاح' : _formatTime(startedAt!),
                ),
                _MetricPill(
                  icon: Icons.notifications_active_rounded,
                  label: 'الوضع',
                  value: 'Foreground',
                ),
                const _MetricPill(
                  icon: Icons.restart_alt_rounded,
                  label: 'Boot',
                  value: 'مفعل',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: busy || running ? null : onStart,
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow_rounded),
                  label: const Text('تشغيل الخدمة'),
                ),
                OutlinedButton.icon(
                  onPressed: busy || !running ? null : onStop,
                  icon: const Icon(Icons.stop_rounded),
                  label: const Text('إيقاف'),
                ),
                IconButton.outlined(
                  tooltip: 'تحديث حالة الخدمة',
                  onPressed: busy ? null : onRefresh,
                  icon: const Icon(Icons.refresh_rounded),
                ),
                OutlinedButton.icon(
                  onPressed: onBatteryExemption,
                  icon: const Icon(Icons.battery_saver_rounded),
                  label: const Text('استثناء البطارية'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF475569)),
          const SizedBox(width: 6),
          Text(
            '$label: $value',
            style: const TextStyle(
              color: Color(0xFF475569),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SilentCounterPanel extends StatelessWidget {
  const _SilentCounterPanel({
    required this.running,
    required this.busy,
    required this.counter,
    required this.serviceRunning,
    required this.startedAt,
    required this.lastTickAt,
    required this.onStart,
    required this.onStop,
    required this.onReset,
  });

  final bool running;
  final bool busy;
  final int counter;
  final bool serviceRunning;
  final DateTime? startedAt;
  final DateTime? lastTickAt;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final statusColor =
        running ? const Color(0xFF2563EB) : const Color(0xFF64748B);
    final lastTickLabel = lastTickAt == null
        ? 'لم يبدأ العد بعد'
        : 'آخر رقم عند ${_formatTime(lastTickAt!)}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.exposure_plus_1_rounded,
                    color: statusColor,
                  ),
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
                              'عداد صامت في الخلفية',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                          ),
                          _StatusPill(
                            text: running ? 'يعد الآن' : 'متوقف',
                            color: statusColor,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$lastTickLabel | لا يظهر له إشعار مستقل',
                        style: const TextStyle(color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'القيمة الحالية',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    counter.toString(),
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          color: const Color(0xFF0F172A),
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetricPill(
                  icon: Icons.visibility_off_rounded,
                  label: 'الإشعار',
                  value: 'لا يوجد',
                ),
                _MetricPill(
                  icon: Icons.sync_lock_rounded,
                  label: 'الحامل',
                  value: serviceRunning ? 'الخدمة الأساسية' : 'سيبدأ تلقائيًا',
                ),
                _MetricPill(
                  icon: Icons.timelapse_rounded,
                  label: 'بدأ',
                  value:
                      startedAt == null ? 'غير متاح' : _formatTime(startedAt!),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: busy || running ? null : onStart,
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow_rounded),
                  label: const Text('تشغيل العداد'),
                ),
                OutlinedButton.icon(
                  onPressed: busy || !running ? null : onStop,
                  icon: const Icon(Icons.pause_rounded),
                  label: const Text('إيقاف العد'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : onReset,
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('تصفير'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class PermissionCard extends StatelessWidget {
  const PermissionCard({
    super.key,
    required this.spec,
    required this.summaryLabel,
    required this.summaryColor,
    required this.statuses,
    required this.services,
    required this.rationales,
    required this.busy,
    required this.onRequest,
    required this.onRefresh,
  });

  final PermissionSpec spec;
  final String summaryLabel;
  final Color summaryColor;
  final Map<Permission, PermissionStatus> statuses;
  final Map<Permission, ServiceStatus> services;
  final Map<Permission, bool> rationales;
  final bool busy;
  final VoidCallback onRequest;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: spec.color.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(spec.icon, color: spec.color),
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
                              spec.title,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                          ),
                          _StatusPill(
                            text: summaryLabel,
                            color: summaryColor,
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        spec.description,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final permission in spec.permissions)
                  _PermissionDetailChip(
                    label: _permissionName(permission),
                    status: statuses[permission],
                    service: services[permission],
                    showRationale: rationales[permission] ?? false,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              spec.manifestNames.join('  •  '),
              style: const TextStyle(
                color: Color(0xFF475569),
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: busy ? null : onRequest,
                    icon: busy
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.lock_open_rounded),
                    label: const Text('طلب الصلاحية'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: 'تحديث البطاقة',
                  onPressed: busy ? null : onRefresh,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionDetailChip extends StatelessWidget {
  const _PermissionDetailChip({
    required this.label,
    required this.status,
    required this.service,
    required this.showRationale,
  });

  final String label;
  final PermissionStatus? status;
  final ServiceStatus? service;
  final bool showRationale;

  @override
  Widget build(BuildContext context) {
    final statusText = _statusText(status);
    final color = _statusColor(status);
    final serviceText = service == null ? null : _serviceText(service!);
    final rationaleText = showRationale ? 'مبرر مطلوب' : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: .2)),
      ),
      child: Text(
        [
          label,
          statusText,
          if (serviceText != null) serviceText,
          if (rationaleText != null) rationaleText,
        ].join(' | '),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.text,
    required this.color,
  });

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .2)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

enum PermissionCategory { essential, media, advanced }

class PermissionSpec {
  const PermissionSpec({
    required this.title,
    required this.description,
    required this.permissions,
    required this.manifestNames,
    required this.icon,
    required this.color,
    required this.category,
  });

  final String title;
  final String description;
  final List<Permission> permissions;
  final List<String> manifestNames;
  final IconData icon;
  final Color color;
  final PermissionCategory category;
}

const permissionSpecs = <PermissionSpec>[
  PermissionSpec(
    title: 'الكاميرا',
    description: 'طلب CAMERA وتشغيل مسار السماح الذي تحتاجه تطبيقات التصوير.',
    permissions: [Permission.camera],
    manifestNames: ['android.permission.CAMERA'],
    icon: Icons.photo_camera_rounded,
    color: Color(0xFF2563EB),
    category: PermissionCategory.essential,
  ),
  PermissionSpec(
    title: 'الميكروفون',
    description: 'طلب RECORD_AUDIO لتجارب التسجيل والمكالمات الصوتية.',
    permissions: [Permission.microphone],
    manifestNames: ['android.permission.RECORD_AUDIO'],
    icon: Icons.mic_rounded,
    color: Color(0xFFC026D3),
    category: PermissionCategory.essential,
  ),
  PermissionSpec(
    title: 'الموقع أثناء الاستخدام',
    description: 'طلب الموقع الأمامي وفحص حالة خدمة الموقع على الجهاز.',
    permissions: [Permission.locationWhenInUse],
    manifestNames: [
      'android.permission.ACCESS_FINE_LOCATION',
      'android.permission.ACCESS_COARSE_LOCATION',
    ],
    icon: Icons.location_on_rounded,
    color: Color(0xFF059669),
    category: PermissionCategory.essential,
  ),
  PermissionSpec(
    title: 'الموقع في الخلفية',
    description: 'صلاحية إضافية بعد قبول الموقع الأمامي على Android 10+.',
    permissions: [Permission.locationAlways],
    manifestNames: ['android.permission.ACCESS_BACKGROUND_LOCATION'],
    icon: Icons.my_location_rounded,
    color: Color(0xFF0F766E),
    category: PermissionCategory.advanced,
  ),
  PermissionSpec(
    title: 'جهات الاتصال',
    description: 'قراءة وتعديل جهات الاتصال من مجموعة Contacts.',
    permissions: [Permission.contacts],
    manifestNames: [
      'android.permission.READ_CONTACTS',
      'android.permission.WRITE_CONTACTS',
      'android.permission.GET_ACCOUNTS',
    ],
    icon: Icons.contacts_rounded,
    color: Color(0xFF0891B2),
    category: PermissionCategory.essential,
  ),
  PermissionSpec(
    title: 'حالة الهاتف',
    description: 'طلب صلاحيات الهاتف وفحص توفر خدمة الاتصال في الجهاز.',
    permissions: [Permission.phone],
    manifestNames: [
      'android.permission.READ_PHONE_STATE',
      'android.permission.READ_PHONE_NUMBERS',
      'android.permission.CALL_PHONE',
    ],
    icon: Icons.phone_android_rounded,
    color: Color(0xFF4F46E5),
    category: PermissionCategory.advanced,
  ),
  PermissionSpec(
    title: 'الرسائل SMS',
    description: 'مجموعة Android الحساسة للقراءة والإرسال والاستقبال.',
    permissions: [Permission.sms],
    manifestNames: [
      'android.permission.READ_SMS',
      'android.permission.SEND_SMS',
      'android.permission.RECEIVE_SMS',
    ],
    icon: Icons.sms_rounded,
    color: Color(0xFFEA580C),
    category: PermissionCategory.advanced,
  ),
  PermissionSpec(
    title: 'الإشعارات',
    description: 'طلب POST_NOTIFICATIONS على Android 13 وما بعده.',
    permissions: [Permission.notification],
    manifestNames: ['android.permission.POST_NOTIFICATIONS'],
    icon: Icons.notifications_active_rounded,
    color: Color(0xFFCA8A04),
    category: PermissionCategory.essential,
  ),
  PermissionSpec(
    title: 'تحسين البطارية',
    description: 'استثناء التطبيق من قيود البطارية التي قد توقف الخدمة.',
    permissions: [Permission.ignoreBatteryOptimizations],
    manifestNames: ['android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS'],
    icon: Icons.battery_charging_full_rounded,
    color: Color(0xFF65A30D),
    category: PermissionCategory.advanced,
  ),
  PermissionSpec(
    title: 'الصور',
    description: 'قراءة الصور الحديثة عبر READ_MEDIA_IMAGES.',
    permissions: [Permission.photos],
    manifestNames: [
      'android.permission.READ_MEDIA_IMAGES',
      'android.permission.READ_MEDIA_VISUAL_USER_SELECTED',
    ],
    icon: Icons.image_rounded,
    color: Color(0xFFDB2777),
    category: PermissionCategory.media,
  ),
  PermissionSpec(
    title: 'الفيديو',
    description: 'قراءة ملفات الفيديو عبر READ_MEDIA_VIDEO.',
    permissions: [Permission.videos],
    manifestNames: ['android.permission.READ_MEDIA_VIDEO'],
    icon: Icons.videocam_rounded,
    color: Color(0xFF7C3AED),
    category: PermissionCategory.media,
  ),
  PermissionSpec(
    title: 'الصوتيات',
    description: 'قراءة ملفات الصوت عبر READ_MEDIA_AUDIO.',
    permissions: [Permission.audio],
    manifestNames: ['android.permission.READ_MEDIA_AUDIO'],
    icon: Icons.library_music_rounded,
    color: Color(0xFF0284C7),
    category: PermissionCategory.media,
  ),
  PermissionSpec(
    title: 'التخزين القديم',
    description: 'READ_EXTERNAL_STORAGE للأجهزة قبل Android 13.',
    permissions: [Permission.storage],
    manifestNames: [
      'android.permission.READ_EXTERNAL_STORAGE',
      'android.permission.WRITE_EXTERNAL_STORAGE',
    ],
    icon: Icons.folder_rounded,
    color: Color(0xFF64748B),
    category: PermissionCategory.media,
  ),
  PermissionSpec(
    title: 'الأجهزة القريبة',
    description: 'Bluetooth وNearby Wi-Fi للأجهزة الحديثة.',
    permissions: [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.nearbyWifiDevices,
    ],
    manifestNames: [
      'android.permission.BLUETOOTH_SCAN',
      'android.permission.BLUETOOTH_CONNECT',
      'android.permission.BLUETOOTH_ADVERTISE',
      'android.permission.NEARBY_WIFI_DEVICES',
    ],
    icon: Icons.bluetooth_searching_rounded,
    color: Color(0xFF1D4ED8),
    category: PermissionCategory.advanced,
  ),
  PermissionSpec(
    title: 'الحركة والحساسات',
    description: 'Activity Recognition وBody Sensors للتجارب الصحية والحركية.',
    permissions: [Permission.activityRecognition, Permission.sensors],
    manifestNames: [
      'android.permission.ACTIVITY_RECOGNITION',
      'android.permission.BODY_SENSORS',
    ],
    icon: Icons.directions_run_rounded,
    color: Color(0xFF16A34A),
    category: PermissionCategory.advanced,
  ),
  PermissionSpec(
    title: 'إدارة كل الملفات',
    description: 'صلاحية خاصة تفتح إعدادات Android بدل مربع حوار عادي.',
    permissions: [Permission.manageExternalStorage],
    manifestNames: ['android.permission.MANAGE_EXTERNAL_STORAGE'],
    icon: Icons.snippet_folder_rounded,
    color: Color(0xFF92400E),
    category: PermissionCategory.advanced,
  ),
  PermissionSpec(
    title: 'نافذة فوق التطبيقات',
    description: 'SYSTEM_ALERT_WINDOW لصلاحيات الرسم فوق التطبيقات.',
    permissions: [Permission.systemAlertWindow],
    manifestNames: ['android.permission.SYSTEM_ALERT_WINDOW'],
    icon: Icons.picture_in_picture_alt_rounded,
    color: Color(0xFFB91C1C),
    category: PermissionCategory.advanced,
  ),
  PermissionSpec(
    title: 'المنبهات الدقيقة',
    description: 'SCHEDULE_EXACT_ALARM للتنبيهات المجدولة بدقة.',
    permissions: [Permission.scheduleExactAlarm],
    manifestNames: ['android.permission.SCHEDULE_EXACT_ALARM'],
    icon: Icons.alarm_rounded,
    color: Color(0xFF9333EA),
    category: PermissionCategory.advanced,
  ),
  PermissionSpec(
    title: 'سياسة الإشعارات',
    description: 'فتح تحكم عدم الإزعاج عبر ACCESS_NOTIFICATION_POLICY.',
    permissions: [Permission.accessNotificationPolicy],
    manifestNames: ['android.permission.ACCESS_NOTIFICATION_POLICY'],
    icon: Icons.do_not_disturb_on_rounded,
    color: Color(0xFF334155),
    category: PermissionCategory.advanced,
  ),
];

String _permissionName(Permission permission) {
  return permission.toString().replaceFirst('Permission.', '');
}

String _statusText(PermissionStatus? status) {
  return switch (status) {
    PermissionStatus.granted => 'مسموح',
    PermissionStatus.denied => 'غير ممنوح',
    PermissionStatus.restricted => 'مقيّد',
    PermissionStatus.limited => 'محدود',
    PermissionStatus.permanentlyDenied => 'مرفوض دائمًا',
    PermissionStatus.provisional => 'مؤقت',
    null => 'غير مفحوص',
  };
}

Color _statusColor(PermissionStatus? status) {
  return switch (status) {
    PermissionStatus.granted => const Color(0xFF047857),
    PermissionStatus.limited => const Color(0xFF0E7490),
    PermissionStatus.permanentlyDenied => const Color(0xFFB91C1C),
    PermissionStatus.restricted => const Color(0xFF7C2D12),
    PermissionStatus.provisional => const Color(0xFF7C3AED),
    PermissionStatus.denied || null => const Color(0xFF64748B),
  };
}

String _serviceText(ServiceStatus service) {
  return switch (service) {
    ServiceStatus.enabled => 'الخدمة تعمل',
    ServiceStatus.disabled => 'الخدمة مغلقة',
    ServiceStatus.notApplicable => 'غير متاح',
  };
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

DateTime? _asDate(Object? value) {
  if (value is DateTime) return value;
  return DateTime.tryParse(value?.toString() ?? '');
}

String _formatTime(DateTime date) {
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  final second = date.second.toString().padLeft(2, '0');
  return '$hour:$minute:$second';
}
