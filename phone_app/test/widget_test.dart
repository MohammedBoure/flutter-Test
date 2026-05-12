import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:phone_permissions_lab/main.dart';

void main() {
  setUp(() {
    PermissionHandlerPlatform.instance = _FakePermissionHandlerPlatform();
  });

  testWidgets('shows the phone permissions lab', (tester) async {
    await tester.pumpWidget(
      const PhonePermissionsLabApp(
        backgroundService: _FakeBackgroundServiceController(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('مختبر صلاحيات الهاتف'), findsOneWidget);
    expect(find.text('خدمة الخلفية المستمرة'), findsOneWidget);
    expect(find.text('عداد صامت في الخلفية'), findsOneWidget);
    expect(find.text('تشغيل العداد'), findsOneWidget);
    expect(find.text('طلب الأساسية'), findsOneWidget);
  });
}

class _FakeBackgroundServiceController extends BackgroundServiceController {
  const _FakeBackgroundServiceController();

  @override
  Stream<Map<String, dynamic>?> get updates => const Stream.empty();

  @override
  Stream<Map<String, dynamic>?> get silentCounterUpdates =>
      const Stream.empty();

  @override
  Future<bool> isRunning() async => false;

  @override
  Future<bool> start() async => true;

  @override
  void stop() {}

  @override
  void startSilentCounter() {}

  @override
  void stopSilentCounter() {}

  @override
  void resetSilentCounter() {}
}

class _FakePermissionHandlerPlatform extends PermissionHandlerPlatform {
  final Map<Permission, PermissionStatus> _statuses = {};

  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async {
    return _statuses[permission] ?? PermissionStatus.denied;
  }

  @override
  Future<ServiceStatus> checkServiceStatus(Permission permission) async {
    return ServiceStatus.enabled;
  }

  @override
  Future<bool> shouldShowRequestPermissionRationale(
    Permission permission,
  ) async {
    return false;
  }

  @override
  Future<Map<Permission, PermissionStatus>> requestPermissions(
    List<Permission> permissions,
  ) async {
    return {
      for (final permission in permissions)
        permission: _statuses[permission] = PermissionStatus.granted,
    };
  }

  @override
  Future<bool> openAppSettings() async {
    return true;
  }
}
