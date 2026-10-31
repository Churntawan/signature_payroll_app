import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/payroll_record.dart';
import 'session_storage.dart';
import 'api_service.dart';

class ManualPayrollService {
  static const String _storagePrefix = 'sp_manual_payroll_';

  /// Check if saved manual records exist for a given period
  static bool hasManualRecords(String period) {
    try {
      final key = '$_storagePrefix$period';
      final raw = SessionStorage.get(key);
      return raw != null && raw.trim().isNotEmpty && raw != '[]';
    } catch (_) {
      return false;
    }
  }

  /// Load saved manual records from Local Storage for a given period
  static List<Map<String, dynamic>>? loadManualRecords(String period) {
    try {
      final key = '$_storagePrefix$period';
      final raw = SessionStorage.get(key);
      if (raw != null && raw.trim().isNotEmpty) {
        final List<dynamic> list = jsonDecode(raw);
        return list.map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (_) {}
    return null;
  }

  /// Save manual records both locally and sync to Supabase Cloud
  static Future<Map<String, dynamic>> saveManualRecords({
    required String period,
    required List<PayrollRecord> records,
  }) async {
    // 1. Serialize full breakdown to Local Storage
    final key = '$_storagePrefix$period';
    final serializableList = records.map((r) => {
      'period': r.period,
      'ep_code': r.epCode,
      'nickname': r.nickname,
      'pay_group': r.payGroup,
      'wage_type': r.wageType,
      'base_salary': r.baseSalary,
      'daily_rate': r.dailyRate,
      'work_days': r.workDays,
      'day_off': r.dayOff,
      'sick_leave': r.sickLeave,
      'half_days': r.halfDays,
      'ot_days': r.otDays,
      'base_pay': r.basePay,
      'housing_allowance': r.housingAllowance,
      'housing_allowance_note': r.housingAllowanceNote,
      'overtime_pay': r.overtimePay,
      'bonus_pay': r.bonusPay,
      'other_extra': r.otherExtra,
      'extra_note': r.extraNote,
      'advance_deduction': r.advanceDeduction,
      'work_permit_deduction': r.workPermitDeduction,
      'other_deduction': r.otherDeduction,
      'deduction_note': r.deductionNote,
      'excess_day_off_days': r.excessDayOffDays,
      'excess_day_off_deduction': r.excessDayOffDeduction,
      'net_pay': r.netPay,
      'status': r.status,
      'is_prorate': r.isProrate,
      'prorate_reason': r.prorateReason,
    }).toList();

    try {
      SessionStorage.set(key, jsonEncode(serializableList));
    } catch (e) {
      debugPrint('Error saving to SessionStorage: $e');
    }

    // 2. Sync snapshot to Supabase Cloud
    Map<String, dynamic>? cloudRes;
    try {
      cloudRes = await ApiService.savePayrollSummary(records);
    } catch (e) {
      debugPrint('Error syncing to Supabase: $e');
    }

    return {
      'savedLocal': true,
      'savedCloud': cloudRes != null,
      'total': records.length,
    };
  }

  /// Clear manual records for a given period
  static void clearManualRecords(String period) {
    try {
      SessionStorage.remove('$_storagePrefix$period');
    } catch (_) {}
  }
}
