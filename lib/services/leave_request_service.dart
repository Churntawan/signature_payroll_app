import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/leave_request.dart';
import 'session_storage.dart';

class LeaveRequestResult {
  final bool success;
  final String? error; // 'date_too_soon', 'duplicate_date', or null
  final LeaveRequest? request;

  const LeaveRequestResult({required this.success, this.error, this.request});
}

class LeaveRequestService {
  static const String _storageKey = 'sp_leave_requests';
  static List<LeaveRequest> _cachedRequests = [];
  static bool _initialized = false;

  static final ValueNotifier<int> pendingCountNotifier = ValueNotifier<int>(0);

  static void initialize() {
    if (_initialized) return;
    _loadFromStorage();
    _initialized = true;
    _updatePendingCount();
  }

  static void _loadFromStorage() {
    try {
      final raw = SessionStorage.get(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final List<dynamic> list = jsonDecode(raw);
        _cachedRequests = list.map((e) => LeaveRequest.fromJson(Map<String, dynamic>.from(e))).toList();
      } else {
        _cachedRequests = [];
      }
    } catch (_) {
      _cachedRequests = [];
    }
  }

  static void _saveToStorage() {
    try {
      final jsonList = _cachedRequests.map((e) => e.toJson()).toList();
      SessionStorage.set(_storageKey, jsonEncode(jsonList));
    } catch (_) {}
    _updatePendingCount();
  }

  static void _updatePendingCount() {
    final count = _cachedRequests.where((r) => r.status == LeaveRequestStatus.pending).length;
    pendingCountNotifier.value = count;
  }

  /// Get all requests, optionally filtered by employee code
  static List<LeaveRequest> getRequests({String? epCode}) {
    initialize();
    if (epCode != null && epCode.isNotEmpty) {
      return _cachedRequests
          .where((r) => r.epCode.toUpperCase() == epCode.toUpperCase())
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return List.from(_cachedRequests)..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// Get pending requests
  static List<LeaveRequest> getPendingRequests() {
    initialize();
    return _cachedRequests
        .where((r) => r.status == LeaveRequestStatus.pending)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  /// Submit a new leave request with 1-day advance notice validation
  static LeaveRequestResult submitRequest({
    required String epCode,
    required String nickname,
    required DateTime date,
    required String category,
    String note = '',
  }) {
    initialize();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final requestedDay = DateTime(date.year, date.month, date.day);

    // Rule: Must request at least 1 day in advance (Tomorrow onwards)
    if (!requestedDay.isAfter(today)) {
      return const LeaveRequestResult(success: false, error: 'date_too_soon');
    }

    final dateStr = '${requestedDay.year.toString().padLeft(4, '0')}-${requestedDay.month.toString().padLeft(2, '0')}-${requestedDay.day.toString().padLeft(2, '0')}';

    // Rule: Check for duplicate active request for this employee on this date
    final existing = _cachedRequests.where((r) =>
        r.epCode.toUpperCase() == epCode.toUpperCase() &&
        r.dateStr == dateStr &&
        r.status != LeaveRequestStatus.rejected);

    if (existing.isNotEmpty) {
      return const LeaveRequestResult(success: false, error: 'duplicate_date');
    }

    final newReq = LeaveRequest(
      id: 'REQ-${DateTime.now().millisecondsSinceEpoch}',
      epCode: epCode,
      nickname: nickname,
      date: requestedDay,
      category: category,
      note: note.trim(),
      status: LeaveRequestStatus.pending,
      createdAt: DateTime.now(),
    );

    _cachedRequests.insert(0, newReq);
    _saveToStorage();

    return LeaveRequestResult(success: true, request: newReq);
  }

  /// Approve request and trigger attendance creation
  static Future<bool> approveRequest(
    LeaveRequest req, {
    required Future<bool> Function(String date, String epCode, String nickname, String category, String note) onAttendanceCreated,
  }) async {
    initialize();

    final idx = _cachedRequests.indexWhere((r) => r.id == req.id);
    if (idx == -1) return false;

    // Call attendance creator
    final success = await onAttendanceCreated(
      req.dateStr,
      req.epCode,
      req.nickname,
      req.category,
      req.note.isEmpty ? 'Approved leave request' : req.note,
    );

    if (success) {
      _cachedRequests[idx].status = LeaveRequestStatus.approved;
      _cachedRequests[idx].reviewedAt = DateTime.now();
      _saveToStorage();
      return true;
    }
    return false;
  }

  /// Reject/Ignore request
  static bool rejectRequest(LeaveRequest req, {String? reason}) {
    initialize();

    final idx = _cachedRequests.indexWhere((r) => r.id == req.id);
    if (idx == -1) return false;

    _cachedRequests[idx].status = LeaveRequestStatus.rejected;
    _cachedRequests[idx].reviewedAt = DateTime.now();
    _cachedRequests[idx].rejectionReason = reason;
    _saveToStorage();
    return true;
  }

  /// Cancel request by employee (only if still pending)
  static bool cancelRequest(String requestId) {
    initialize();

    final idx = _cachedRequests.indexWhere((r) => r.id == requestId);
    if (idx == -1) return false;

    if (_cachedRequests[idx].status == LeaveRequestStatus.pending) {
      _cachedRequests.removeAt(idx);
      _saveToStorage();
      return true;
    }
    return false;
  }

  /// Helper to find other employees who have scheduled Day-off or Sick leave on the requested date
  static List<String> getConflictingEmployees(
    DateTime date,
    List<Map<String, dynamic>> attendanceLogs, {
    String? excludeEpCode,
  }) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    final dStr = '$y-$m-$d';

    final conflicts = <String>{};
    for (final log in attendanceLogs) {
      if (log['date']?.toString() == dStr) {
        final ep = log['ep_code']?.toString() ?? '';
        final cat = log['category']?.toString() ?? '';
        if (excludeEpCode != null && ep.toUpperCase() == excludeEpCode.toUpperCase()) {
          continue;
        }
        if (cat == 'Day-off' || cat == 'Sick') {
          final nick = log['nickname']?.toString() ?? ep;
          conflicts.add(nick.isNotEmpty ? nick : ep);
        }
      }
    }
    return conflicts.toList();
  }
}
