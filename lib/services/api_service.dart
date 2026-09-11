import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import '../models/employee.dart';
import '../models/payroll_record.dart';

class ApiService {
  // Supabase Cloud REST API Endpoint
  static const String supabaseUrl = 'https://qsmigegcefcbohmufywh.supabase.co/rest/v1';
  static const String supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFzbWlnZWdjZWZjYm9obXVmeXdoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkwNDM4MDAsImV4cCI6MjEwNDYxOTgwMH0.jIEkmGeSVzht81fGEQnxOM-n9TGG7AFumkFEe5SVGTk';

  static Map<String, String> get _headers => {
    'apikey': supabaseKey,
    'Authorization': 'Bearer $supabaseKey',
    'Content-Type': 'application/json',
  };

  // 1. Check API connection status (Supabase Cloud)
  static Future<bool> checkConnection() async {
    try {
      final res = await http.get(
        Uri.parse('$supabaseUrl/employees?select=ep_code&limit=1'),
        headers: _headers,
      ).timeout(const Duration(seconds: 4));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // 2. Fetch all 24 periods
  static Future<List<String>> fetchPeriods() async {
    return [
      '2025-01', '2025-02', '2025-03', '2025-04', '2025-05', '2025-06',
      '2025-07', '2025-08', '2025-09', '2025-10', '2025-11', '2025-12',
      '2026-01', '2026-02', '2026-03', '2026-04', '2026-05', '2026-06',
      '2026-07', '2026-08', '2026-09', '2026-10', '2026-11', '2026-12'
    ];
  }

  // 3. Fetch employees from Supabase Cloud
  static Future<List<Employee>?> fetchEmployees() async {
    try {
      final res = await http.get(
        Uri.parse('$supabaseUrl/employees?select=*&order=ep_code.asc'),
        headers: _headers,
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final List<dynamic> list = jsonDecode(res.body);
        return list.map((item) {
          DateTime? sDate;
          DateTime? rDate;
          if (item['start_date'] != null && item['start_date'].toString().isNotEmpty) {
            sDate = DateTime.tryParse(item['start_date']);
          }
          if (item['resign_date'] != null && item['resign_date'].toString().isNotEmpty) {
            rDate = DateTime.tryParse(item['resign_date']);
          }
          return Employee(
            epCode: item['ep_code'] ?? '',
            nickname: item['nickname'] ?? '',
            status: item['status'] ?? 'Active',
            baseSalary: (item['base_salary'] as num?)?.toDouble() ?? 0.0,
            payGroup: item['pay_group'] ?? 'Date : 10',
            stayOutside: item['stay_outside'] ?? 'No',
            startDate: sDate,
            resignDate: rDate,
            note: item['note'] ?? '',
          );
        }).toList();
      }
    } catch (_) {}
    return null;
  }

  // 4. Fetch Attendance logs from Supabase Cloud
  static Future<List<Map<String, dynamic>>> fetchAttendance({String? period, String? epCode}) async {
    try {
      String query = '$supabaseUrl/attendance_log?select=*&order=date.desc';
      if (epCode != null && epCode.isNotEmpty) {
        query += '&ep_code=eq.$epCode';
      }
      if (period != null && period.length >= 7) {
        try {
          final parts = period.split('-');
          final y = int.parse(parts[0]);
          final m = int.parse(parts[1]);
          final prevY = m > 1 ? y : y - 1;
          final prevM = m > 1 ? m - 1 : 12;
          final lastDay = DateTime(y, m + 1, 0).day;
          final cycleStart = '${prevY.toString().padLeft(4, '0')}-${prevM.toString().padLeft(2, '0')}-01';
          final cycleEnd = '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-${lastDay.toString().padLeft(2, '0')}';
          query += '&date=gte.$cycleStart&date=lte.$cycleEnd';
        } catch (_) {}
      }

      final res = await http.get(Uri.parse(query), headers: _headers).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final List<dynamic> list = jsonDecode(res.body);
        return list.map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (_) {}
    return [];
  }

  // 5. Create new Attendance entry in Supabase Cloud
  static Future<bool> createAttendance({
    required String date,
    required String epCode,
    required String nickname,
    required String category,
    String shift = 'Normal',
    double units = 1.0,
    String note = '',
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$supabaseUrl/attendance_log'),
        headers: _headers,
        body: jsonEncode({
          'date': date,
          'ep_code': epCode,
          'nickname': nickname,
          'category': category,
          'shift': shift,
          'units': units,
          'note': note,
        }),
      );
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  // 6. Fetch Adjustments from Supabase Cloud
  static Future<List<Map<String, dynamic>>> fetchAdjustments({String? period, String? epCode}) async {
    try {
      String query = '$supabaseUrl/payroll_adjustments?select=*&order=due_date.desc';
      if (period != null && period.isNotEmpty) {
        query += '&period=eq.$period';
      }
      if (epCode != null && epCode.isNotEmpty) {
        query += '&ep_code=eq.$epCode';
      }

      final res = await http.get(Uri.parse(query), headers: _headers).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final List<dynamic> list = jsonDecode(res.body);
        return list.map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (_) {}
    return [];
  }

  // 7. Create new Adjustment in Supabase Cloud
  static Future<bool> createAdjustment({
    required String period,
    required String dueDate,
    required String epCode,
    required String nickname,
    required String type,
    required String category,
    String description = '',
    required double amount,
    String status = 'Pending',
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$supabaseUrl/payroll_adjustments'),
        headers: _headers,
        body: jsonEncode({
          'period': period,
          'due_date': dueDate,
          'ep_code': epCode,
          'nickname': nickname,
          'type': type,
          'category': category,
          'description': description,
          'amount': amount,
          'status': status,
        }),
      );
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  // 8. Sync and save calculated payroll summary to Supabase Cloud
  static Future<Map<String, dynamic>?> savePayrollSummary(List<PayrollRecord> records) async {
    try {
      final payload = records.map((r) => {
        'period': r.period,
        'ep_code': r.epCode,
        'nickname': r.nickname,
        'pay_type': r.isProrate ? 'Prorated' : 'Full Month',
        'base_salary': r.baseSalary,
        'work_days': r.workDays,
        'day_off': r.dayOff,
        'sick': r.sickLeave,
        'half_day': r.halfDays,
        'ot_days': r.otDays,
        'base_pay': r.basePay,
        'total_extra': r.totalExtra,
        'total_deduction': r.totalDeduction,
        'net_pay': r.netPay,
        'status': r.status,
        'note': r.isProrate ? r.prorateReason : '',
      }).toList();

      final upsertHeaders = Map<String, String>.from(_headers);
      upsertHeaders['Prefer'] = 'resolution=merge-duplicates';

      final res = await http.post(
        Uri.parse('$supabaseUrl/payroll_summary?on_conflict=period,ep_code'),
        headers: upsertHeaders,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200 || res.statusCode == 201) {
        return {
          'message': 'Payroll summary saved to Supabase Cloud successfully',
          'total': records.length,
          'updated': records.length,
          'created': 0,
        };
      }
    } catch (_) {}
    return null;
  }

  // 9. Update employee status in Supabase Cloud
  static Future<bool> updateEmployeeStatus({
    required String epCode,
    required String status,
    DateTime? resignDate,
  }) async {
    try {
      final Map<String, dynamic> body = {
        'status': status,
        'resign_date': resignDate != null ? DateFormat('yyyy-MM-dd').format(resignDate) : null,
      };
      final res = await http.patch(
        Uri.parse('$supabaseUrl/employees?ep_code=eq.$epCode'),
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 5));
      return res.statusCode == 200 || res.statusCode == 204;
    } catch (_) {
      return false;
    }
  }

  // 10. Update employee start & resign dates in Supabase Cloud
  static Future<bool> updateEmployeeDates({
    required String epCode,
    DateTime? startDate,
    DateTime? resignDate,
    String? status,
  }) async {
    try {
      final Map<String, dynamic> body = {
        'start_date': startDate != null ? DateFormat('yyyy-MM-dd').format(startDate) : null,
        'resign_date': resignDate != null ? DateFormat('yyyy-MM-dd').format(resignDate) : null,
      };
      if (status != null) {
        body['status'] = status;
      }
      final res = await http.patch(
        Uri.parse('$supabaseUrl/employees?ep_code=eq.$epCode'),
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 5));
      return res.statusCode == 200 || res.statusCode == 204;
    } catch (_) {
      return false;
    }
  }

  // 11. Create or fully upsert Employee in Supabase Cloud
  static Future<bool> saveEmployee(Employee emp) async {
    try {
      final Map<String, dynamic> body = {
        'ep_code': emp.epCode,
        'nickname': emp.nickname,
        'status': emp.status,
        'base_salary': emp.baseSalary,
        'pay_group': emp.payGroup,
        'stay_outside': emp.stayOutside,
        'start_date': emp.startDate != null ? DateFormat('yyyy-MM-dd').format(emp.startDate!) : null,
        'resign_date': emp.resignDate != null ? DateFormat('yyyy-MM-dd').format(emp.resignDate!) : null,
        'note': emp.note,
      };
      final upsertHeaders = Map<String, String>.from(_headers);
      upsertHeaders['Prefer'] = 'resolution=merge-duplicates';

      final res = await http.post(
        Uri.parse('$supabaseUrl/employees?on_conflict=ep_code'),
        headers: upsertHeaders,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 5));
      return res.statusCode == 200 || res.statusCode == 201 || res.statusCode == 204;
    } catch (_) {
      return false;
    }
  }

  // 12. Bulk create Attendance records in Supabase Cloud
  static Future<bool> batchCreateAttendance(List<Map<String, dynamic>> records) async {
    if (records.isEmpty) return true;
    try {
      final upsertHeaders = Map<String, String>.from(_headers);
      upsertHeaders['Prefer'] = 'resolution=merge-duplicates';

      final res = await http.post(
        Uri.parse('$supabaseUrl/attendance_log'),
        headers: upsertHeaders,
        body: jsonEncode(records),
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return true;
      } else {
        // ignore: avoid_print
        print('batchCreateAttendance failed with code: ${res.statusCode}, body: ${res.body}');
        return false;
      }
    } catch (e) {
      // ignore: avoid_print
      print('batchCreateAttendance exception: $e');
      return false;
    }
  }

  // 13. Clear existing Day-offs for a date range in Supabase Cloud
  static Future<bool> clearDayOffsForRange({
    required String startDate,
    required String endDate,
    String? epCode,
  }) async {
    try {
      String query = '$supabaseUrl/attendance_log?category=eq.Day-off&date=gte.$startDate&date=lte.$endDate';
      if (epCode != null && epCode.isNotEmpty) {
        query += '&ep_code=eq.$epCode';
      }
      final res = await http.delete(
        Uri.parse(query),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      return res.statusCode == 200 || res.statusCode == 204;
    } catch (_) {
      return false;
    }
  }

  // 14. Clear existing Day-offs strictly for a specific Period in Supabase Cloud
  static Future<bool> clearDayOffsForPeriod({
    required String period,
    String? epCode,
  }) async {
    try {
      final parts = period.split('-');
      final y = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      final prevY = m > 1 ? y : y - 1;
      final prevM = m > 1 ? m - 1 : 12;
      final cycleStart = '${prevY.toString().padLeft(4, '0')}-${prevM.toString().padLeft(2, '0')}-02';
      final lastDay = DateTime(y, m + 1, 0).day;
      final cycleEnd = '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-${lastDay.toString().padLeft(2, '0')}';
      return clearDayOffsForRange(startDate: cycleStart, endDate: cycleEnd, epCode: epCode);
    } catch (_) {
      return false;
    }
  }

  // 15. Delete a single Attendance entry from Supabase Cloud
  static Future<bool> deleteAttendance({
    dynamic id,
    String? date,
    String? epCode,
    String? category,
  }) async {
    try {
      String query;
      if (id != null && id.toString().isNotEmpty) {
        query = '$supabaseUrl/attendance_log?id=eq.$id';
      } else if (date != null && epCode != null) {
        query = '$supabaseUrl/attendance_log?date=eq.$date&ep_code=eq.$epCode';
        if (category != null) {
          query += '&category=eq.$category';
        }
      } else {
        return false;
      }
      final res = await http.delete(
        Uri.parse(query),
        headers: _headers,
      ).timeout(const Duration(seconds: 8));
      return res.statusCode == 200 || res.statusCode == 204;
    } catch (_) {
      return false;
    }
  }

  // 16. Delete a single Payroll Adjustment entry from Supabase Cloud
  static Future<bool> deleteAdjustment({
    dynamic id,
    String? epCode,
    String? dueDate,
    String? category,
  }) async {
    try {
      String query;
      if (id != null && id.toString().isNotEmpty) {
        query = '$supabaseUrl/payroll_adjustments?id=eq.$id';
      } else if (epCode != null && dueDate != null) {
        query = '$supabaseUrl/payroll_adjustments?ep_code=eq.$epCode&due_date=eq.$dueDate';
        if (category != null) {
          query += '&category=eq.$category';
        }
      } else {
        return false;
      }
      final res = await http.delete(
        Uri.parse(query),
        headers: _headers,
      ).timeout(const Duration(seconds: 8));
      return res.statusCode == 200 || res.statusCode == 204;
    } catch (_) {
      return false;
    }
  }
}

