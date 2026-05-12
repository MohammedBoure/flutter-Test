# Store Dashboard

تطبيق Flutter Desktop لإدارة متجر على Windows مع MySQL محلي.

## قاعدة البيانات

القيم الافتراضية:

```text
DB_HOST=127.0.0.1
DB_PORT=3306
DB_USER=root
DB_PASSWORD=root
DB_NAME=store_dashboard_db
```

التطبيق ينشئ قاعدة البيانات والجداول والبيانات الأولية تلقائيًا عند التشغيل.

## التشغيل

```powershell
flutter pub get
dart run tool/setup_database.dart
flutter run -d windows
```

يمكن تغيير الاتصال بدون تعديل الكود:

```powershell
flutter run -d windows --dart-define=DB_PASSWORD=your_password
```
