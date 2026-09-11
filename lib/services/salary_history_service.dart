import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/salary_record.dart';
import 'session_storage.dart';
import 'api_service.dart';

class SalaryHistoryService {
  static const String _storageKey = 'sp_salary_history';
  static List<SalaryRecord> _cachedRecords = [];
  static bool _initialized = false;

  /// Notifier to trigger UI updates when salary records change
  static final ValueNotifier<int> changeNotifier = ValueNotifier<int>(0);

  /// Initialize service and load cached records
  static void initialize() {
    if (_initialized) return;
    _loadFromStorage();
    _initialized = true;
  }

  static void _loadFromStorage() {
    try {
      final raw = SessionStorage.get(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final List<dynamic> list = jsonDecode(raw);
        _cachedRecords = list
            .map((e) => SalaryRecord.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      } else {
        _cachedRecords = [];
      }
    } catch (_) {
      _cachedRecords = [];
    }
  }

  static void _saveToStorage() {
    try {
      final jsonList = _cachedRecords.map((e) => e.toJson()).toList();
      SessionStorage.set(_storageKey, jsonEncode(jsonList));
    } catch (_) {}
    changeNotifier.value++;
  }

  /// Sync from Supabase Cloud (gracefully falls back if table doesn't exist)
  static Future<void> syncFromCloud() async {
    initialize();
    try {
      final cloudRecords = await ApiService.fetchSalaryHistory();
      if (cloudRecords != null && cloudRecords.isNotEmpty) {
        // Merge cloud records with local cache
        final Map<String, SalaryRecord> map = {
          for (final r in _cachedRecords) r.id: r,
        };
        for (final cr in cloudRecords) {
          map[cr.id] = cr;
        }
        _cachedRecords = map.values.toList();
        _saveToStorage();
      }
    } catch (_) {}
  }

  /// Check if an employee has any salary adjustment history
  static bool hasHistory(String epCode) {
    initialize();
    return _cachedRecords.any((r) => r.epCode.toUpperCase() == epCode.toUpperCase());
  }

  /// Get all records for a specific employee, sorted from newest to oldest period
  static List<SalaryRecord> getRecordsForEmployee(String epCode) {
    initialize();
    final list = _cachedRecords
        .where((r) => r.epCode.toUpperCase() == epCode.toUpperCase())
        .toList();
    list.sort((a, b) => b.effectivePeriod.compareTo(a.effectivePeriod));
    return list;
  }

  /// Get the effective base salary for an employee in a given period ('YYYY-MM')
  ///
  /// Logic:
  /// 1. If employee has no adjustment history, return [defaultSalary].
  /// 2. Sort all adjustment records for employee chronologically ascending.
  /// 3. Find all adjustments effective on or before [period] (effectivePeriod <= period).
  ///    - If found: return the salary of the latest applicable adjustment.
  /// 4. If all adjustments are in the future (> period):
  ///    - Return the [previousSalary] of the earliest adjustment, or [defaultSalary].
  static double getSalaryForPeriod({
    required String epCode,
    required String period,
    required double defaultSalary,
  }) {
    initialize();
    final empRecords = _cachedRecords
        .where((r) => r.epCode.toUpperCase() == epCode.toUpperCase())
        .toList();

    if (empRecords.isEmpty) {
      return defaultSalary;
    }

    // Sort ascending by period (e.g. '2025-06', '2026-01', '2026-10')
    empRecords.sort((a, b) => a.effectivePeriod.compareTo(b.effectivePeriod));

    // Find the latest adjustment that is effective on or before the requested period
    final applicableRecords = empRecords
        .where((r) => r.effectivePeriod.compareTo(period) <= 0)
        .toList();

    if (applicableRecords.isNotEmpty) {
      return applicableRecords.last.baseSalary;
    }

    // If the requested period is older than all adjustments,
    // the salary was the previousSalary of the earliest adjustment
    final earliest = empRecords.first;
    return earliest.previousSalary ?? defaultSalary;
  }

  /// Add or update a salary record
  static Future<bool> addSalaryRecord(SalaryRecord record) async {
    initialize();

    // Check if a record already exists for the same employee and exact effective period
    final index = _cachedRecords.indexWhere(
      (r) => r.epCode.toUpperCase() == record.epCode.toUpperCase() &&
             r.effectivePeriod == record.effectivePeriod,
    );

    if (index != -1) {
      _cachedRecords[index] = record;
    } else {
      _cachedRecords.add(record);
    }

    _saveToStorage();

    // Async sync to Supabase Cloud
    ApiService.saveSalaryRecord(record).ignore();
    return true;
  }

  /// Delete a salary adjustment record (e.g. when correcting past data)
  static Future<bool> deleteSalaryRecord(String id) async {
    initialize();
    final countBefore = _cachedRecords.length;
    _cachedRecords.removeWhere((r) => r.id == id);

    if (_cachedRecords.length != countBefore) {
      _saveToStorage();
      ApiService.deleteSalaryRecord(id).ignore();
      return true;
    }
    return false;
  }

  /// Reset/clear cache for testing
  @visibleForTesting
  static void resetForTesting([List<SalaryRecord>? initialRecords]) {
    _cachedRecords = initialRecords != null ? List.from(initialRecords) : [];
    _initialized = true;
    changeNotifier.value++;
  }
}
