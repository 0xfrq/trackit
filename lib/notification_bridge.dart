import 'package:flutter/services.dart';

import 'models/ledger.dart';

class NotificationBridge {
  static const _channel = MethodChannel('trackit/android');

  Future<bool> isAccessEnabled() async =>
      await _channel.invokeMethod<bool>('isAccessEnabled') ?? false;

  Future<void> openSettings() =>
      _channel.invokeMethod<void>('openNotificationSettings');

  Future<List<PendingCandidate>> drainCandidates() async {
    final rows =
        await _channel.invokeListMethod<Map<Object?, Object?>>('drainCandidates') ?? [];
    return rows
        .map((row) => PendingCandidate.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<void> acknowledge(String externalId) =>
      _channel.invokeMethod<void>('acknowledgeCandidate', externalId);
}
