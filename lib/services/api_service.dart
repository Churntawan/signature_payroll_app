import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/employee.dart';

class ApiService {
  static const String baseUrl = 'http://127.0.0.1:8000/api';

  // 1. Check API connection status
  static Future<bool> checkConnection() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/health')).timeout(const Duration(seconds: 2));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // 2. Fetch all 24 periods from Database
  static Future<List<String>> fetchPeriods() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/periods')).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List<dynamic> list = data['periods'] ?? [];
        return list.map((e) => e.toString()).toList();
      }
    } catch (_) {}
    return [
      '2025-01', '2025-02', '2025-03', '2025-04', '2025-05', '2025-06',
      '2025-07', '2025-08', '2025-09', '2025-10', '2025-11', '2025-12',
      '2026-01', '2026-02', '2026-03', '2026-04', '2026-05', '2026-06',
      '2026-07', '2026-08', '2026-09', '2026-10', '2026-11', '2026-12'
    ];
  }

  // 3. Fetch employees from Database
  static Future<List<Employee>?> fetchEmployees() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/employees')).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List<dynamic> list = data['employees'] ?? [];
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

  // 4. Fetch Attendance logs
  static Future<List<Map<String, dynamic>>> fetchAttendance({String? period, String? epCode}) async {
    try {
      String url = '$baseUrl/attendance?';
      if (period != null) url += 'period=$period&';
      if (epCode != null) url += 'ep_code=$epCode&';

      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List<dynamic> list = data['attendance'] ?? [];
        return list.map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (_) {}
    return [];
  }

  // 5. Create new Attendance entry (Day-off, Sick, Half-day, OT)
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
        Uri.parse('$baseUrl/attendance'),
        headers: {'Content-Type': 'application/json'},
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
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // 6. Fetch Adjustments (Advances, Work Permit, Bonuses)
  static Future<List<Map<String, dynamic>>> fetchAdjustments({String? period, String? epCode}) async {
    try {
      String url = '$baseUrl/adjustments?';
      if (period != null) url += 'period=$period&';
      if (epCode != null) url += 'ep_code=$epCode&';

      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List<dynamic> list = data['adjustments'] ?? [];
        return list.map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (_) {}
    return [];
  }

  // 7. Create new Adjustment (Advance, Work Permit, Bonus)
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
        Uri.parse('$baseUrl/adjustments'),
        headers: {'Content-Type': 'application/json'},
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
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
