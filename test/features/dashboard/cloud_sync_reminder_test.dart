import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/services/supabase_service.dart';
import 'package:stockealo/features/dashboard/presentation/widgets/cloud_sync_reminder.dart';

void main() {
  final firstSeen = DateTime(2026, 11, 1);

  test('no aparece en los primeros días de uso', () {
    expect(CloudSyncReminder.shouldShow(now: DateTime(2026, 11, 2), firstSeen: firstSeen), isFalse);
    expect(CloudSyncReminder.shouldShow(now: DateTime(2026, 11, 4), firstSeen: firstSeen), isTrue);
  });

  test('si lo cierran, no vuelve hasta pasadas unas semanas', () {
    final dismissed = DateTime(2026, 11, 5);
    expect(
      CloudSyncReminder.shouldShow(now: DateTime(2026, 11, 20), firstSeen: firstSeen, dismissedAt: dismissed),
      isFalse,
    );
    expect(
      CloudSyncReminder.shouldShow(now: DateTime(2026, 11, 26), firstSeen: firstSeen, dismissedAt: dismissed),
      isTrue,
    );
  });

  test('fuera de la web la nube sigue siendo opcional', () {
    // Las pruebas corren fuera del navegador: el modo local se conserva
    expect(SupabaseService.cloudSyncForced, isFalse);
  });
}
