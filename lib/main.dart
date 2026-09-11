import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'data/initial_employees.dart';
import 'models/employee.dart';
import 'models/payroll_record.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/image_saver.dart';
import 'services/payroll_engine.dart';
import 'widgets/employee_portal_screen.dart';
import 'widgets/login_screen.dart';
import 'widgets/two_month_calendar_planner.dart';

void main() {
  runApp(const SignaturePayrollApp());
}

class SignaturePayrollApp extends StatelessWidget {
  const SignaturePayrollApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Signature Payroll Suite',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0284C7),
          primary: const Color(0xFF0284C7),
          surface: Colors.white,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        cardTheme: const CardThemeData(
          color: Colors.white,
          elevation: 1,
        ),
      ),
      home: const PayrollMainScreen(),
    );
  }
}

class PayrollMainScreen extends StatefulWidget {
  const PayrollMainScreen({super.key});

  @override
  State<PayrollMainScreen> createState() => _PayrollMainScreenState();
}

class _PayrollMainScreenState extends State<PayrollMainScreen> {
  int _currentTab = 0;

  final GlobalKey _payslipKey = GlobalKey();
  bool _isExportingImage = false;
  bool _isSyncingExcel = false;
  bool _isAttendanceCalendarView = true;
  bool _isApiOnline = false;
  bool _isRefreshing = false;

  late List<Employee> _employees;
  List<String> _periods = [DateFormat('yyyy-MM').format(DateTime.now())];
  String _selectedPeriod = DateFormat('yyyy-MM').format(DateTime.now());
  String _selectedGroupFilter = 'All Groups';

  Map<String, PayrollRecord> _payrollRecords = {};
  List<Map<String, dynamic>> _attendanceLogs = [];
  List<Map<String, dynamic>> _adjustments = [];

  String? _selectedPayslipEp;
  String _payslipGroupFilter = 'All Groups';

  AuthSession? _currentSession;
  bool _isCheckingAuth = true;

  @override
  void initState() {
    super.initState();
    _employees = List.from(initialEmployees);
    _initializeData();
  }

  Future<void> _initializeData() async {
    // 1. Check API Connection
    final connected = await ApiService.checkConnection();
    setState(() => _isApiOnline = connected);

    // 2. Fetch all 24 periods from Database
    final currentPeriodStr = DateFormat('yyyy-MM').format(DateTime.now());
    final fetchedPeriods = await ApiService.fetchPeriods();
    if (fetchedPeriods.isNotEmpty) {
      setState(() {
        _periods = fetchedPeriods;
        if (_periods.contains(currentPeriodStr)) {
          _selectedPeriod = currentPeriodStr;
        } else if (!_periods.contains(_selectedPeriod)) {
          _selectedPeriod = _periods.first;
        }
      });
    }

    // 3. Fetch Employees from Database
    final dbEmployees = await ApiService.fetchEmployees();
    if (dbEmployees != null && dbEmployees.isNotEmpty) {
      setState(() => _employees = dbEmployees);
    }

    if (_employees.isNotEmpty) {
      final active = _employees.where((e) => e.isActive).toList();
      _selectedPayslipEp = active.isNotEmpty ? active.first.epCode : _employees.first.epCode;
    }

    // 4. Load saved auth session
    final saved = AuthService.loadSavedSession(_employees);
    if (mounted) {
      setState(() {
        _currentSession = saved;
        _isCheckingAuth = false;
      });
    }

    await _fetchDataAndRecalculate();
  }

  Future<void> _fetchDataAndRecalculate({bool reloadEmployees = false}) async {
    if (reloadEmployees) {
      final dbEmployees = await ApiService.fetchEmployees();
      if (dbEmployees != null && dbEmployees.isNotEmpty && mounted) {
        setState(() => _employees = dbEmployees);
      }
    }

    // Fetch real attendance and adjustments for this period
    final att = await ApiService.fetchAttendance(period: _selectedPeriod);
    final adj = await ApiService.fetchAdjustments(period: _selectedPeriod);

    if (!mounted) return;
    setState(() {
      _attendanceLogs = att;
      _adjustments = adj;
    });

    final Map<String, PayrollRecord> newRecords = {};
    for (final emp in _employees) {
      final rec = PayrollEngine.calculateEmployeeRecord(
        employee: emp,
        period: _selectedPeriod,
      );
      if (rec != null) {
        // Aggregate real attendance logs strictly within this employee's pay cycle dates
        final empAtt = _attendanceLogs.where((a) {
          if (a['ep_code'] != emp.epCode) return false;
          final dStr = a['date']?.toString() ?? '';
          if (dStr.isEmpty) return false;
          try {
            final d = DateTime.parse(dStr);
            final dOnly = DateTime(d.year, d.month, d.day);
            final startOnly = DateTime(rec.cycleStartDate.year, rec.cycleStartDate.month, rec.cycleStartDate.day);
            final endOnly = DateTime(rec.cycleEndDate.year, rec.cycleEndDate.month, rec.cycleEndDate.day);
            return (dOnly.isAtSameMomentAs(startOnly) || dOnly.isAfter(startOnly)) &&
                   (dOnly.isAtSameMomentAs(endOnly) || dOnly.isBefore(endOnly));
          } catch (_) {
            return false;
          }
        }).toList();
        empAtt.sort((a, b) => (a['date']?.toString() ?? '').compareTo(b['date']?.toString() ?? ''));
        PayrollEngine.applyAttendance(rec, empAtt);

        // Aggregate real adjustments
        final empAdj = _adjustments.where((a) => a['ep_code'] == emp.epCode).toList();
        for (final a in empAdj) {
          final amt = (a['amount'] as num?)?.toDouble() ?? 0.0;
          final cat = a['category']?.toString() ?? '';
          final type = a['type']?.toString() ?? '';

          if (type == 'Income') {
            if (cat.contains('OT')) {
              rec.overtimePay += amt;
            } else if (cat.contains('Bonus')) {
              rec.bonusPay += amt;
            } else if (cat.contains('Housing') || cat.contains('ห้องพัก')) {
              rec.housingAllowance = amt;
              rec.housingAllowanceNote = 'ปรับปรุงยอดค่าห้องพักในงวด';
            } else {
              rec.otherExtra += amt;
            }
          } else {
            if (cat.contains('Advance')) {
              rec.advanceDeduction += amt;
            } else if (cat.contains('Work Permit') || cat.contains('Passport')) {
              rec.workPermitDeduction += amt;
            } else {
              rec.otherDeduction += amt;
            }
          }
        }

        // Keep local overrides if any (strictly within the same period to prevent cross-period bleeding)
        if (_payrollRecords.containsKey(emp.epCode)) {
          final old = _payrollRecords[emp.epCode]!;
          if (old.period == rec.period && empAdj.isEmpty) {
            rec.overtimePay = old.overtimePay;
            rec.bonusPay = old.bonusPay;
            rec.otherExtra = old.otherExtra;
            rec.advanceDeduction = old.advanceDeduction;
            rec.workPermitDeduction = old.workPermitDeduction;
            rec.otherDeduction = old.otherDeduction;
            rec.housingAllowance = old.housingAllowance;
          }
        }

        newRecords[emp.epCode] = rec;
      }
    }
    setState(() {
      _payrollRecords = newRecords;
      if (_selectedPayslipEp == null || !newRecords.containsKey(_selectedPayslipEp)) {
        if (newRecords.isNotEmpty) {
          _selectedPayslipEp = newRecords.keys.first;
        } else {
          _selectedPayslipEp = null;
        }
      }
    });
  }

  List<PayrollRecord> get _filteredRecords {
    return _payrollRecords.values.where((r) {
      if (_selectedGroupFilter == 'All Groups') return true;
      return r.payGroup == _selectedGroupFilter;
    }).toList();
  }

  Future<void> _savePayslipAsImage(PayrollRecord record) async {
    setState(() => _isExportingImage = true);
    try {
      await Future.delayed(const Duration(milliseconds: 100));
      final boundary = _payslipKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      final ui.Image image = await boundary.toImage(pixelRatio: 2.5);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        final Uint8List pngBytes = byteData.buffer.asUint8List();
        final fileName = 'payslip_${record.epCode}_${record.nickname}_${record.period}.png';
        ImageSaver.savePng(pngBytes, fileName);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Payslip image downloaded: $fileName'),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExportingImage = false);
    }
  }

  Future<void> _syncPayrollToExcel() async {
    setState(() => _isSyncingExcel = true);
    try {
      final records = _payrollRecords.values.toList();
      if (records.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No records to sync.'), backgroundColor: Colors.orange),
          );
        }
        return;
      }
      final res = await ApiService.savePayrollSummary(records);
      if (res != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Synced ${res['total']} records to Supabase Cloud Database!'),
              backgroundColor: const Color(0xFF10B981),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ Failed to sync with Cloud Database.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error syncing: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncingExcel = false);
    }
  }

  void _exportBankSummaryCsv() {
    final records = _filteredRecords;
    if (records.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No records to export.'), backgroundColor: Colors.orange),
      );
      return;
    }

    final buffer = StringBuffer();
    // CSV Header (UTF-8 BOM will be prepended by ImageSaver.saveCsv)
    buffer.writeln('Period,EP Code,Nickname,Pay Group,Pay Date,Base Salary,Prorated,Work Days,Day Off,Sick Leave,Half Days,OT Days,Base Pay,Overtime Pay,Bonus Pay,Other Extra,Advance Deduction,Work Permit Deduction,Other Deduction,Net Pay,Status');

    final df = DateFormat('yyyy-MM-dd');
    for (final r in records) {
      buffer.writeln(
        '${r.period},'
        '${r.epCode},'
        '"${r.nickname}",'
        '"${r.payGroup}",'
        '${df.format(r.payDate)},'
        '${r.baseSalary.toStringAsFixed(2)},'
        '${r.isProrate ? "Yes" : "No"},'
        '${r.workDays},'
        '${r.dayOff},'
        '${r.sickLeave},'
        '${r.halfDays},'
        '${r.otDays},'
        '${r.basePay.toStringAsFixed(2)},'
        '${r.overtimePay.toStringAsFixed(2)},'
        '${r.bonusPay.toStringAsFixed(2)},'
        '${r.otherExtra.toStringAsFixed(2)},'
        '${r.advanceDeduction.toStringAsFixed(2)},'
        '${r.workPermitDeduction.toStringAsFixed(2)},'
        '${r.otherDeduction.toStringAsFixed(2)},'
        '${r.netPay.toStringAsFixed(2)},'
        '${r.status}'
      );
    }

    final fileName = 'payroll_summary_${_selectedPeriod}_${_selectedGroupFilter.replaceAll(' ', '_')}.csv';
    ImageSaver.saveCsv(buffer.toString(), fileName);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ Exported Bank & Accounting CSV: $fileName'),
        backgroundColor: const Color(0xFF10B981),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingAuth) {
      return const Scaffold(
        backgroundColor: Color(0xFF0B1120),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF38BDF8)),
        ),
      );
    }

    if (_currentSession == null) {
      return LoginScreen(
        employees: _employees,
        onLoginSuccess: (session) {
          setState(() => _currentSession = session);
        },
      );
    }

    if (_currentSession!.isEmployee) {
      final emp = _currentSession!.employee ??
          _employees.firstWhere(
            (e) => e.epCode == _currentSession!.epCode,
            orElse: () => _employees.first,
          );
      return EmployeePortalScreen(
        employee: emp,
        periods: _periods,
        onLogout: () {
          AuthService.clearSession();
          setState(() => _currentSession = null);
        },
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 650;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        title: isMobile
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.diamond_outlined, size: 16, color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Payroll',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: _isApiOnline ? const Color(0xFF10B981) : Colors.amber,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.diamond_outlined, size: 20, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'SIGNATURE PAYROLL',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _isApiOnline ? const Color(0xFF10B981) : Colors.amber,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                _isApiOnline ? 'Supabase Cloud Connected ⚡' : 'Offline Local Mode',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: _isApiOnline ? const Color(0xFF4ADE80) : const Color(0xFFFCD34D),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
        actions: [
          // Current Date Badge
          Container(
            margin: EdgeInsets.symmetric(vertical: isMobile ? 10 : 8),
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 12, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.today_outlined, size: 14, color: Color(0xFF38BDF8)),
                const SizedBox(width: 5),
                if (!isMobile)
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'TODAY',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF94A3B8),
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        DateFormat('EEE, d MMM yyyy').format(DateTime.now()),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  )
                else
                  Text(
                    DateFormat('d MMM').format(DateTime.now()),
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),

          // Period Selector Dropdown
          Container(
            margin: EdgeInsets.symmetric(vertical: isMobile ? 10 : 8, horizontal: isMobile ? 6 : 12),
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _periods.contains(_selectedPeriod) ? _selectedPeriod : _periods.first,
                dropdownColor: const Color(0xFF1E293B),
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: isMobile ? 12 : 13,
                ),
                items: _periods
                    .map((p) => DropdownMenuItem(value: p, child: Text(isMobile ? p : 'Period $p')))
                    .toList(),
                onChanged: (val) {
                  if (val != null && val != _selectedPeriod) {
                    setState(() {
                      _selectedPeriod = val;
                      _payrollRecords.clear();
                    });
                    _fetchDataAndRecalculate();
                  }
                },
              ),
            ),
          ),
          // Instant Cloud Refresh Button
          IconButton(
            icon: _isRefreshing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(color: Color(0xFF38BDF8), strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, size: 20, color: Color(0xFF38BDF8)),
            tooltip: 'Refresh all data from Supabase Cloud',
            onPressed: _isRefreshing
                ? null
                : () async {
                    setState(() => _isRefreshing = true);
                    final messenger = ScaffoldMessenger.of(context);
                    await _fetchDataAndRecalculate(reloadEmployees: true);
                    if (mounted) {
                      setState(() => _isRefreshing = false);
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('⚡ Refreshed from Supabase Cloud Database!'),
                          backgroundColor: Color(0xFF10B981),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
          ),
          IconButton(
            icon: const Icon(Icons.logout, size: 20, color: Color(0xFFF87171)),
            tooltip: 'ออกจากระบบ (Admin Logout)',
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF1E293B),
                  title: const Text('ยืนยันออกจากระบบ', style: TextStyle(color: Colors.white)),
                  content: const Text('คุณต้องการออกจากระบบผู้ดูแลใช่หรือไม่?', style: TextStyle(color: Color(0xFFCBD5E1))),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                      onPressed: () {
                        Navigator.pop(ctx);
                        AuthService.clearSession();
                        setState(() => _currentSession = null);
                      },
                      child: const Text('ออกจากระบบ'),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: IndexedStack(
        index: _currentTab,
        children: [
          _buildPayrollHub(),
          _buildAttendanceTracker(),
          _buildAdjustmentsLedger(),
          _buildPayslipView(),
          _buildEmployeesDirectory(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTab,
        onDestinationSelected: (idx) {
          setState(() => _currentTab = idx);
          if (idx == 0 || idx == 4) {
            _fetchDataAndRecalculate(reloadEmployees: true);
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calculate_outlined),
            selectedIcon: Icon(Icons.calculate),
            label: 'Payroll',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Planner',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'Adjust',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Payslip',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_alt_outlined),
            selectedIcon: Icon(Icons.people_alt),
            label: 'Staff',
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // TAB 1: PAYROLL HUB
  // ===========================================================================
  Widget _buildPayrollHub() {
    final records = _filteredRecords;
    final currency = NumberFormat('#,##0.00', 'en_US');

    final totalNet = records.fold<double>(0, (sum, r) => sum + r.netPay);
    final totalBase = records.fold<double>(0, (sum, r) => sum + r.basePay);
    final totalExtra = records.fold<double>(0, (sum, r) => sum + r.totalExtra);
    final totalDeduction = records.fold<double>(0, (sum, r) => sum + r.totalDeduction);
    final prorateCount = records.where((r) => r.isProrate).length;
    final isMobile = MediaQuery.of(context).size.width < 650;

    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isMobile) ...[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('All Groups'),
                      const SizedBox(width: 8),
                      _buildFilterChip('Date : 1', subtitle: '2nd prev - 1st current'),
                      const SizedBox(width: 8),
                      _buildFilterChip('Date : 10', subtitle: '11th prev - 10th current'),
                      const SizedBox(width: 8),
                      _buildFilterChip('Date : 20', subtitle: '21st prev - 20th current'),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _exportBankSummaryCsv,
                        icon: const Icon(Icons.file_download_outlined, size: 16),
                        label: const Text('Export CSV', style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF0284C7),
                          side: const BorderSide(color: Color(0xFF0284C7)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isSyncingExcel ? null : _syncPayrollToExcel,
                        icon: _isSyncingExcel
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.cloud_upload_outlined, size: 16),
                        label: Text(
                          _isSyncingExcel ? 'Syncing...' : 'Sync to Cloud',
                          style: const TextStyle(fontSize: 12),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildFilterChip('All Groups'),
                            const SizedBox(width: 8),
                            _buildFilterChip('Date : 1', subtitle: '2nd prev - 1st current'),
                            const SizedBox(width: 8),
                            _buildFilterChip('Date : 10', subtitle: '11th prev - 10th current'),
                            const SizedBox(width: 8),
                            _buildFilterChip('Date : 20', subtitle: '21st prev - 20th current'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: _exportBankSummaryCsv,
                      icon: const Icon(Icons.file_download_outlined, size: 18),
                      label: const Text('Export Bank / CSV'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0284C7),
                        side: const BorderSide(color: Color(0xFF0284C7)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _isSyncingExcel ? null : _syncPayrollToExcel,
                      icon: _isSyncingExcel
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.sync, size: 18),
                      label: Text(_isSyncingExcel ? 'Syncing...' : 'Sync to Excel Summary'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ],
              // Prominent Auto-Schedule Day-off Banner in Tab 1
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4F46E5), Color(0xFF6366F1)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4F46E5).withValues(alpha: 0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '⚡ จัดตารางวันหยุดประจำงวด (Auto-Schedule)',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
                          ),
                          Text(
                            'เลือกวันหยุด จ.-อา. ของพนักงาน ระบบสร้างวันหยุดให้อัตโนมัติทั้งเดือน',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 11.5),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _showAutoScheduleDayOffsDialog,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF4F46E5),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        elevation: 1,
                      ),
                      child: const Text('จัดตารางทันที', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: isMobile
              ? Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildSummaryCard(
                            title: 'Total Net Payout',
                            value: '฿${currency.format(totalNet)}',
                            color: const Color(0xFF0284C7),
                            icon: Icons.payments,
                            subtitle: '${records.length} Employees',
                            isCompact: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildSummaryCard(
                            title: 'Base & Prorate Pay',
                            value: '฿${currency.format(totalBase)}',
                            color: const Color(0xFF334155),
                            icon: Icons.account_balance_wallet,
                            subtitle: prorateCount > 0 ? '$prorateCount Prorate' : 'All full month',
                            isCompact: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildSummaryCard(
                            title: 'Earnings (+)',
                            value: '+฿${currency.format(totalExtra)}',
                            color: const Color(0xFF10B981),
                            icon: Icons.trending_up,
                            subtitle: 'OT, Bonuses & Extra',
                            isCompact: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildSummaryCard(
                            title: 'Deductions (-)',
                            value: '-฿${currency.format(totalDeduction)}',
                            color: const Color(0xFFEF4444),
                            icon: Icons.trending_down,
                            subtitle: 'Advances, Fees',
                            isCompact: true,
                          ),
                        ),
                      ],
                    ),
                  ],
                )
              : Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _buildSummaryCard(
                      title: 'Total Net Payout',
                      value: '฿${currency.format(totalNet)}',
                      color: const Color(0xFF0284C7),
                      icon: Icons.payments,
                      subtitle: '${records.length} Employees in this cycle',
                    ),
                    _buildSummaryCard(
                      title: 'Base & Prorate Pay',
                      value: '฿${currency.format(totalBase)}',
                      color: const Color(0xFF334155),
                      icon: Icons.account_balance_wallet,
                      subtitle: prorateCount > 0 ? '⚠️ $prorateCount Smart Prorate applied' : 'All full month',
                    ),
                    _buildSummaryCard(
                      title: 'Earnings (+)',
                      value: '+฿${currency.format(totalExtra)}',
                      color: const Color(0xFF10B981),
                      icon: Icons.trending_up,
                      subtitle: 'OT, Bonuses & Allowances',
                    ),
                    _buildSummaryCard(
                      title: 'Deductions (-)',
                      value: '-฿${currency.format(totalDeduction)}',
                      color: const Color(0xFFEF4444),
                      icon: Icons.trending_down,
                      subtitle: 'Advances, Work Permit fees',
                    ),
                  ],
                ),
        ),
        Expanded(
          child: records.isEmpty
              ? const Center(child: Text('No employees found in this cycle.'))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: records.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, idx) {
                    final rec = records[idx];
                    return Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: rec.isProrate ? const Color(0xFFF97316) : const Color(0xFFE2E8F0),
                          width: rec.isProrate ? 1.5 : 1,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: rec.isProrate
                                  ? const Color(0xFFFFF7ED)
                                  : const Color(0xFFF0F9FF),
                              foregroundColor: rec.isProrate
                                  ? const Color(0xFFEA580C)
                                  : const Color(0xFF0284C7),
                              child: Text(
                                rec.nickname.isNotEmpty ? rec.nickname[0].toUpperCase() : '?',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          rec.nickname,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF1F5F9),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          rec.epCode,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF475569),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFE0F2FE),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          rec.payGroup,
                                          style: const TextStyle(fontSize: 11, color: Color(0xFF0369A1)),
                                        ),
                                      ),
                                      if (rec.wageType == 'Daily') ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFEF3C7),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            'รายวัน (Daily)',
                                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFB45309)),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  if (rec.isProrate)
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 4),
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFF7ED),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: const Color(0xFFFED7AA)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.info_outline, size: 13, color: Color(0xFFEA580C)),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              'Prorate: ${rec.workedDays} days (@ ฿${(rec.dailyRate).toStringAsFixed(0)}/day) [${rec.prorateReason}]',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFFC2410C),
                                                fontWeight: FontWeight.w500,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  Wrap(
                                    spacing: 5,
                                    runSpacing: 4,
                                    children: [
                                      _buildMiniBadge('💼 ${rec.workDays}d', const Color(0xFFF1F5F9), const Color(0xFF475569)),
                                      _buildMiniBadge('🏖️ ${rec.dayOff}d', const Color(0xFFECFDF5), const Color(0xFF059669)),
                                      if (rec.sickLeave > 0)
                                        _buildMiniBadge('🩺 ${rec.sickLeave}d', const Color(0xFFFEF2F2), const Color(0xFFDC2626)),
                                      if (rec.otDays > 0)
                                        _buildMiniBadge('⚡ ${rec.otDays}d OT', const Color(0xFFFAF5FF), const Color(0xFF7C3AED)),
                                      if (rec.housingAllowance > 0)
                                        _buildMiniBadge('🏠 ฿${currency.format(rec.housingAllowance)}', const Color(0xFFECFDF5), const Color(0xFF059669)),
                                      if (rec.excessDayOffDays > 0)
                                        _buildMiniBadge('⚠️ หยุดเกิน ${rec.excessDayOffDays}d (-฿${currency.format(rec.excessDayOffDeduction)})', const Color(0xFFFEF2F2), const Color(0xFFDC2626)),
                                      if ((rec.overtimePay + rec.bonusPay + rec.otherExtra) > 0)
                                        _buildMiniBadge('+฿${currency.format(rec.overtimePay + rec.bonusPay + rec.otherExtra)}', const Color(0xFFF0FDF4), const Color(0xFF16A34A)),
                                      if ((rec.advanceDeduction + rec.workPermitDeduction + rec.otherDeduction) > 0)
                                        _buildMiniBadge('-฿${currency.format(rec.advanceDeduction + rec.workPermitDeduction + rec.otherDeduction)}', const Color(0xFFFEF2F2), const Color(0xFFDC2626)),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    rec.wageType == 'Daily'
                                        ? 'Daily: ฿${currency.format(rec.dailyRate)}/day × ${rec.workDays}d = ฿${currency.format(rec.basePay)}'
                                        : 'Base: ฿${currency.format(rec.basePay)}',
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '฿${currency.format(rec.netPay)}',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: 'Adjust Pay & Attendance',
                                      icon: const Icon(Icons.edit_note, color: Color(0xFF0284C7)),
                                      onPressed: () => _showEditAdjustmentsDialog(rec),
                                      constraints: const BoxConstraints(),
                                      padding: const EdgeInsets.all(6),
                                    ),
                                    IconButton(
                                      tooltip: 'View Digital Payslip',
                                      icon: const Icon(Icons.receipt_long, color: Color(0xFF10B981)),
                                      onPressed: () {
                                        setState(() {
                                          _selectedPayslipEp = rec.epCode;
                                          _currentTab = 3;
                                        });
                                      },
                                      constraints: const BoxConstraints(),
                                      padding: const EdgeInsets.all(6),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ===========================================================================
  // TAB 2: ATTENDANCE & DAY-OFF LOGGER (NEW!)
  // ===========================================================================
  Widget _buildAttendanceTracker() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 768;

    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Attendance & Day-off Log (${_attendanceLogs.length} records)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: isMobile ? 14 : 16),
                        ),
                        Text(
                          'Period $_selectedPeriod • Logs sync directly with Cloud Database',
                          style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                  if (!isMobile) ...[
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment<bool>(
                          value: true,
                          label: Text('Calendar Planner'),
                          icon: Icon(Icons.calendar_month, size: 16),
                        ),
                        ButtonSegment<bool>(
                          value: false,
                          label: Text('List View'),
                          icon: Icon(Icons.list_alt, size: 16),
                        ),
                      ],
                      selected: {_isAttendanceCalendarView},
                      onSelectionChanged: (val) {
                        setState(() => _isAttendanceCalendarView = val.first);
                      },
                      style: SegmentedButton.styleFrom(
                        selectedBackgroundColor: const Color(0xFFE0F2FE),
                        selectedForegroundColor: const Color(0xFF0369A1),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _showAutoScheduleDayOffsDialog,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4F46E5),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      ),
                      icon: const Icon(Icons.auto_awesome, size: 18),
                      label: const Text('⚡ จัดตารางวันหยุด (Auto)'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () => _showLogAttendanceDialog(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      ),
                      icon: const Icon(Icons.add_task, size: 18),
                      label: const Text('+ บันทึกรายวัน'),
                    ),
                  ],
                ],
              ),
              if (isMobile) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment<bool>(
                            value: true,
                            label: Text('Planner', style: TextStyle(fontSize: 11)),
                            icon: Icon(Icons.calendar_month, size: 14),
                          ),
                          ButtonSegment<bool>(
                            value: false,
                            label: Text('List', style: TextStyle(fontSize: 11)),
                            icon: Icon(Icons.list_alt, size: 14),
                          ),
                        ],
                        selected: {_isAttendanceCalendarView},
                        onSelectionChanged: (val) {
                          setState(() => _isAttendanceCalendarView = val.first);
                        },
                        style: SegmentedButton.styleFrom(
                          selectedBackgroundColor: const Color(0xFFE0F2FE),
                          selectedForegroundColor: const Color(0xFF0369A1),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    ElevatedButton.icon(
                      onPressed: _showAutoScheduleDayOffsDialog,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4F46E5),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.auto_awesome, size: 15),
                      label: const Text('จัดตารางวันหยุด', style: TextStyle(fontSize: 11.5)),
                    ),
                    const SizedBox(width: 6),
                    ElevatedButton(
                      onPressed: () => _showLogAttendanceDialog(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Icon(Icons.add, size: 18),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: _isAttendanceCalendarView
              ? TwoMonthCalendarPlanner(
                  period: _selectedPeriod,
                  attendanceLogs: _attendanceLogs,
                  onAddAttendance: (date) => _showLogAttendanceDialog(initialDate: date),
                  onAutoScheduleMonth: (monthDate) => _showAutoScheduleForMonthDialog(monthDate),
                  onClearMonthDayOffs: _handleClearMonthDayOffs,
                  onDeleteAttendance: _handleDeleteAttendance,
                )
              : (_attendanceLogs.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.event_available, size: 48, color: Color(0xFF94A3B8)),
                          SizedBox(height: 12),
                          Text('No attendance records logged for this period yet.'),
                          Text('Click "+ Log Day-off / Leave / OT" to record.', style: TextStyle(color: Color(0xFF94A3B8))),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _attendanceLogs.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 6),
                      itemBuilder: (context, idx) {
                        final log = _attendanceLogs[idx];
                        final cat = log['category'] ?? 'Day-off';
                        Color badgeColor = const Color(0xFF3B82F6);
                        if (cat == 'Day-off') badgeColor = const Color(0xFF10B981);
                        if (cat == 'Sick') badgeColor = const Color(0xFFEF4444);
                        if (cat == 'Half-day') badgeColor = const Color(0xFFF59E0B);
                        if (cat.contains('OT')) badgeColor = const Color(0xFF8B5CF6);

                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: badgeColor.withValues(alpha: 0.12),
                              foregroundColor: badgeColor,
                              child: Icon(
                                cat == 'Day-off'
                                    ? Icons.beach_access
                                    : (cat == 'Sick' ? Icons.healing : Icons.schedule),
                                size: 18,
                              ),
                            ),
                            title: Row(
                              children: [
                                Text(
                                  log['nickname'] ?? '',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(width: 8),
                                Text('(${log['ep_code']})', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: badgeColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    cat,
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: badgeColor),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Text(
                              'Date: ${log['date']}  |  Units: ${log['units']}  |  Shift: ${log['shift']}${(log['note'] != null && log['note'].toString().isNotEmpty) ? '  • Note: ${log['note']}' : ''}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                              tooltip: 'ยกเลิก / ลบรายการนี้',
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (c) => AlertDialog(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    title: const Row(
                                      children: [
                                        Icon(Icons.warning_amber_rounded, color: Colors.red, size: 22),
                                        SizedBox(width: 8),
                                        Text('ยืนยันยกเลิกรายการ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                    content: Text('ต้องการยกเลิก ${log['category']} ของ ${log['nickname']} (${log['ep_code']}) ในวันที่ ${log['date']} หรือไม่?'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(c, false),
                                        child: const Text('ไม่ยกเลิก'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () => Navigator.pop(c, true),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red,
                                          foregroundColor: Colors.white,
                                        ),
                                        child: const Text('ยืนยันยกเลิก'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  _handleDeleteAttendance(log);
                                }
                              },
                            ),
                          ),
                        );
                      },
                    )),
        ),
      ],
    );
  }

  // ===========================================================================
  // TAB 3: EXPENSES & ADJUSTMENTS LEDGER (NEW!)
  // ===========================================================================
  Widget _buildAdjustmentsLedger() {
    final currency = NumberFormat('#,##0.00', 'en_US');
    final totalAdvances = _adjustments
        .where((a) => a['category']?.toString().contains('Advance') == true)
        .fold<double>(0, (sum, a) => sum + ((a['amount'] as num?)?.toDouble() ?? 0.0));
    final totalWorkPermit = _adjustments
        .where((a) => a['category']?.toString().contains('Work Permit') == true || a['category']?.toString().contains('Passport') == true)
        .fold<double>(0, (sum, a) => sum + ((a['amount'] as num?)?.toDouble() ?? 0.0));

    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Expenses & Advance Ledger (${_adjustments.length} records)',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text(
                    'Total Advances: ฿${currency.format(totalAdvances)}  |  Work Permit: ฿${currency.format(totalWorkPermit)}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                ],
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _showLogAdjustmentDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.add_card, size: 18),
                label: const Text('Record Advance / Expense'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _adjustments.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.credit_card_off, size: 48, color: Color(0xFF94A3B8)),
                      SizedBox(height: 12),
                      Text('No advance payments or adjustments recorded for this period.'),
                      Text('Click "+ Record Advance / Expense" to add.', style: TextStyle(color: Color(0xFF94A3B8))),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _adjustments.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 6),
                  itemBuilder: (context, idx) {
                    final adj = _adjustments[idx];
                    final isIncome = adj['type'] == 'Income';
                    final amt = (adj['amount'] as num?)?.toDouble() ?? 0.0;

                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isIncome ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                          foregroundColor: isIncome ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                          child: Icon(isIncome ? Icons.add : Icons.remove),
                        ),
                        title: Row(
                          children: [
                            Text(
                              adj['nickname'] ?? '',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 8),
                            Text('(${adj['ep_code']})', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                adj['category'] ?? '',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Text(
                          'Due Date: ${adj['due_date']}  |  ${adj['description'] ?? ''}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${isIncome ? '+' : '-'}฿${currency.format(amt)}',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: isIncome ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                              tooltip: 'ยกเลิกลบรายจ่ายรายการนี้',
                              onPressed: () => _handleDeleteAdjustment(adj),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ===========================================================================
  // TAB 4: DIGITAL PAYSLIP VIEWER
  // ===========================================================================
  Widget _buildPayslipView() {
    final currency = NumberFormat('#,##0.00', 'en_US');
    final df = DateFormat('dd/MM/yyyy');
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    // Available records for the selected period filtered by pay group
    final availableRecords = _payrollRecords.values.where((r) {
      if (_payslipGroupFilter == 'All Groups') return true;
      return r.payGroup == _payslipGroupFilter;
    }).toList();

    PayrollRecord? record;
    if (_selectedPayslipEp != null && _payrollRecords.containsKey(_selectedPayslipEp) && availableRecords.any((r) => r.epCode == _selectedPayslipEp)) {
      record = _payrollRecords[_selectedPayslipEp];
    } else if (availableRecords.isNotEmpty) {
      _selectedPayslipEp = availableRecords.first.epCode;
      record = availableRecords.first;
    } else {
      record = null;
    }

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: isMobile ? 12 : 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            children: [
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildPayslipGroupChip('All Groups'),
                            const SizedBox(width: 6),
                            _buildPayslipGroupChip('Date : 1'),
                            const SizedBox(width: 6),
                            _buildPayslipGroupChip('Date : 10'),
                            const SizedBox(width: 6),
                            _buildPayslipGroupChip('Date : 20'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.badge_outlined, size: 20, color: Theme.of(context).primaryColor),
                          const SizedBox(width: 8),
                          Text(isMobile ? 'Staff: ' : 'Select Employee: ', style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                isExpanded: true,
                                value: (_selectedPayslipEp != null && availableRecords.any((r) => r.epCode == _selectedPayslipEp)) ? _selectedPayslipEp : null,
                                hint: const Text('เลือกพนักงาน'),
                                items: availableRecords.map((r) {
                                  final emp = _employees.firstWhere(
                                    (e) => e.epCode == r.epCode,
                                    orElse: () => Employee(epCode: r.epCode, nickname: r.nickname, status: 'Active', baseSalary: r.baseSalary, payGroup: r.payGroup),
                                  );
                                  final isResigned = !emp.isActive || (emp.resignDate != null);
                                  return DropdownMenuItem(
                                    value: r.epCode,
                                    child: Text(
                                      '${r.epCode} - ${r.nickname} (${r.payGroup})${isResigned ? ' [พ้นสภาพ/ลาออก]' : ''}',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isResigned ? const Color(0xFFDC2626) : const Color(0xFF0F172A),
                                        fontWeight: isResigned ? FontWeight.w500 : FontWeight.normal,
                                      ),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) setState(() => _selectedPayslipEp = val);
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (record == null)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('Please select an active employee to view payslip.'),
                  ),
                )
              else ...[
                RepaintBoundary(
                  key: _payslipKey,
                  child: Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: EdgeInsets.all(isMobile ? 16 : 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Header: Company Logo/Name + Period Chip
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0F172A),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(Icons.diamond, color: Colors.white, size: 18),
                                    ),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'SIGNATURE PAYROLL',
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 0.5,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            'PAYSLIP / SALARY STATEMENT',
                                            style: TextStyle(fontSize: 11, color: Color(0xFF64748B), letterSpacing: 0.5),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Period ${record.period}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 24),

                          // Employee Info Box
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: isMobile
                                ? Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '${record.nickname} (${record.epCode})',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFE0F2FE),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              record.payGroup,
                                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0369A1)),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'Cycle: ${df.format(record.cycleStartDate)} - ${df.format(record.cycleEndDate)}',
                                            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                          ),
                                          Text(
                                            'Pay Date: ${df.format(record.payDate)}',
                                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                                          ),
                                        ],
                                      ),
                                    ],
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Employee: ${record.nickname} (${record.epCode})',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Pay Group: ${record.payGroup}',
                                            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                          ),
                                        ],
                                      ),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            'Cycle: ${df.format(record.cycleStartDate)} - ${df.format(record.cycleEndDate)}',
                                            style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Pay Date: ${df.format(record.payDate)}',
                                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF0284C7)),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                          ),
                          const SizedBox(height: 12),

                          // Attendance Stats Box
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0FDF4),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFBBF7D0)),
                            ),
                            child: Row(
                              children: [
                                Expanded(child: _buildAttendanceItem(Icons.work_history_outlined, 'Work Days', '${record.workDays}d')),
                                Expanded(child: _buildAttendanceItem(Icons.beach_access_outlined, 'Day-offs', '${record.dayOff}d')),
                                Expanded(child: _buildAttendanceItem(Icons.healing_outlined, 'Sick Leave', '${record.sickLeave}d')),
                                Expanded(child: _buildAttendanceItem(Icons.hourglass_bottom_outlined, 'Half-days', '${record.halfDays}')),
                                Expanded(child: _buildAttendanceItem(Icons.more_time_outlined, 'OT Days', '${record.otDays}')),
                              ],
                            ),
                          ),

                          // Detailed Leave and Day-off Dates Card
                          _buildLeaveDetailsCard(record),

                          const SizedBox(height: 12),
                          if (record.isProrate)
                            Container(
                              margin: const EdgeInsets.only(bottom: 14),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF7ED),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFFED7AA)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.info, color: Color(0xFFEA580C), size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Smart Prorate applied: ${record.workedDays} eligible days (@ ฿${currency.format(record.dailyRate)}/day) • Reason: ${record.prorateReason}',
                                      style: const TextStyle(fontSize: 11.5, color: Color(0xFFC2410C)),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // Earnings & Deductions Sections (Stacked on mobile, side-by-side on desktop)
                          if (isMobile) ...[
                            _buildEarningsSection(record, currency),
                            const SizedBox(height: 14),
                            const Divider(height: 1),
                            const SizedBox(height: 14),
                            _buildDeductionsSection(record, currency),
                          ] else ...[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: _buildEarningsSection(record, currency)),
                                const SizedBox(width: 24),
                                Expanded(child: _buildDeductionsSection(record, currency)),
                              ],
                            ),
                          ],

                          const SizedBox(height: 20),

                          // NET PAYOUT Bar
                          Container(
                            padding: EdgeInsets.all(isMobile ? 14 : 16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'NET PAYOUT',
                                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      'Social Security: Excluded',
                                      style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 12),
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                      '฿${currency.format(record.netPay)}',
                                      style: TextStyle(
                                        color: const Color(0xFF38BDF8),
                                        fontSize: isMobile ? 20 : 22,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _isExportingImage ? null : () => _savePayslipAsImage(record!),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0284C7),
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 20, vertical: isMobile ? 12 : 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: _isExportingImage
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.image, size: 18),
                      label: Text(_isExportingImage ? 'Saving...' : 'Save as Image (PNG)', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        final text = PayrollEngine.formatLinePayslip(record!);
                        Clipboard.setData(ClipboardData(text: text));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('✅ Formatted Payslip copied to clipboard! Ready to paste in LINE.'),
                            backgroundColor: Color(0xFF10B981),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF06C755),
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 20, vertical: isMobile ? 12 : 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.chat_bubble_outline, size: 18),
                      label: const Text('Copy for LINE', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _showEditAdjustmentsDialog(record!),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 18, vertical: isMobile ? 12 : 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.tune, size: 18),
                      label: const Text('Quick Adjustments'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeaveDetailsCard(PayrollRecord record) {
    String formatDates(List<Map<String, dynamic>> logs, {bool showNote = false}) {
      if (logs.isEmpty) return '';
      return logs.map((l) {
        final d = _formatShortDate(l['date']?.toString());
        final note = l['note']?.toString().trim();
        if (showNote && note != null && note.isNotEmpty) {
          return '$d ($note)';
        }
        return d;
      }).join(', ');
    }

    final hasAnyLogs = record.dayOffLogs.isNotEmpty ||
        record.sickLogs.isNotEmpty ||
        record.halfDayLogs.isNotEmpty ||
        record.otDayLogs.isNotEmpty ||
        record.workDayLogs.isNotEmpty ||
        record.otherLeaveLogs.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.calendar_month_outlined, size: 15, color: Color(0xFF475569)),
              SizedBox(width: 6),
              Text(
                'รายละเอียดวันหยุด & วันลาในงวดนี้',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (!hasAnyLogs)
            const Text(
              '• ไม่มีบันทึกวันหยุด/วันลาพิเศษในงวดนี้ (Full Attendance)',
              style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontStyle: FontStyle.italic),
            )
          else ...[
            if (record.workDayLogs.isNotEmpty)
              _buildLeaveDateRow(
                'วันทำงาน (Work):',
                formatDates(record.workDayLogs),
                const Color(0xFF0284C7),
              ),
            if (record.dayOffLogs.isNotEmpty)
              _buildLeaveDateRow(
                'วันหยุด (OFF):',
                formatDates(record.dayOffLogs),
                const Color(0xFF10B981),
              ),
            if (record.sickLogs.isNotEmpty)
              _buildLeaveDateRow(
                'ลาป่วย (Sick):',
                formatDates(record.sickLogs, showNote: true),
                const Color(0xFFEA580C),
              ),
            if (record.halfDayLogs.isNotEmpty)
              _buildLeaveDateRow(
                'ครึ่งวัน (Half):',
                formatDates(record.halfDayLogs, showNote: true),
                const Color(0xFFD97706),
              ),
            if (record.otDayLogs.isNotEmpty)
              _buildLeaveDateRow(
                'ทำงานวันหยุด (OT):',
                formatDates(record.otDayLogs),
                const Color(0xFF7C3AED),
              ),
            if (record.otherLeaveLogs.isNotEmpty)
              _buildLeaveDateRow(
                'ลาอื่นๆ (Leave):',
                formatDates(record.otherLeaveLogs, showNote: true),
                const Color(0xFF64748B),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildPayslipGroupChip(String group) {
    final isSelected = _payslipGroupFilter == group;
    return ChoiceChip(
      label: Text(
        group,
        style: TextStyle(
          fontSize: 11.5,
          color: isSelected ? Colors.white : const Color(0xFF334155),
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      selectedColor: const Color(0xFF0284C7),
      backgroundColor: const Color(0xFFF1F5F9),
      side: BorderSide.none,
      onSelected: (val) {
        if (val) {
          setState(() {
            _payslipGroupFilter = group;
            final recs = _payrollRecords.values.where((r) => group == 'All Groups' || r.payGroup == group).toList();
            if (recs.isNotEmpty && !recs.any((r) => r.epCode == _selectedPayslipEp)) {
              _selectedPayslipEp = recs.first.epCode;
            }
          });
        }
      },
    );
  }

  Widget _buildEarningsSection(PayrollRecord record, NumberFormat currency) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '➕ Earnings (รายรับ)',
          style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF10B981), fontSize: 13),
        ),
        const SizedBox(height: 8),
        _buildPayslipLine(
          record.wageType == 'Daily'
              ? 'Daily Wage (${record.workDays} days @ ฿${currency.format(record.dailyRate)})'
              : (record.isProrate ? 'Prorated Base Pay' : 'Base Salary'),
          '฿${currency.format(record.basePay)}',
        ),
        if (record.housingAllowance > 0)
          _buildPayslipLine(
            'Housing Allowance (ค่าห้องพัก)',
            '+฿${currency.format(record.housingAllowance)}',
            color: const Color(0xFF059669),
          ),
        if (record.overtimePay > 0)
          _buildPayslipLine('Overtime (OT)', '+฿${currency.format(record.overtimePay)}'),
        if (record.bonusPay > 0)
          _buildPayslipLine('Incentive / Bonus', '+฿${currency.format(record.bonusPay)}'),
        if (record.otherExtra > 0)
          _buildPayslipLine('Other Extra', '+฿${currency.format(record.otherExtra)}'),
        const Divider(height: 16),
        _buildPayslipLine(
          'Total Earnings',
          '฿${currency.format(record.basePay + record.totalExtra)}',
          isBold: true,
        ),
      ],
    );
  }

  Widget _buildDeductionsSection(PayrollRecord record, NumberFormat currency) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '➖ Deductions (รายการหัก)',
          style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFEF4444), fontSize: 13),
        ),
        const SizedBox(height: 8),
        if (record.excessDayOffDeduction > 0)
          _buildPayslipLine(
            'Excess Day-offs (${record.excessDayOffDays}d @ ฿${currency.format(record.dailyRate)})',
            '-฿${currency.format(record.excessDayOffDeduction)}',
            color: const Color(0xFFDC2626),
          ),
        _buildPayslipLine(
          'Advance Payment',
          record.advanceDeduction > 0 ? '-฿${currency.format(record.advanceDeduction)}' : '฿0.00',
        ),
        _buildPayslipLine(
          'Work Permit / Passport',
          record.workPermitDeduction > 0 ? '-฿${currency.format(record.workPermitDeduction)}' : '฿0.00',
        ),
        if (record.otherDeduction > 0)
          _buildPayslipLine('Other Deductions', '-฿${currency.format(record.otherDeduction)}'),
        const Divider(height: 16),
        _buildPayslipLine(
          'Total Deductions',
          '-฿${currency.format(record.totalDeduction)}',
          isBold: true,
          color: const Color(0xFFEF4444),
        ),
      ],
    );
  }

  // ===========================================================================
  // TAB 5: EMPLOYEES DIRECTORY
  // ===========================================================================
  Widget _buildEmployeesDirectory() {
    final currency = NumberFormat('#,##0.00', 'en_US');
    final activeCount = _employees.where((e) => e.isActive).length;
    final resignedCount = _employees.where((e) => !e.isActive).length;

    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text(
                'Employees (${_employees.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Active: $activeCount',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF15803D), fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Resigned: $resignedCount',
                  style: const TextStyle(fontSize: 12, color: Color(0xFFB91C1C), fontWeight: FontWeight.bold),
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _showAddEmployeeDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.person_add, size: 18),
                label: const Text('Add Employee'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: _employees.length,
            separatorBuilder: (context, index) => const SizedBox(height: 6),
            itemBuilder: (context, idx) {
              final emp = _employees[idx];
              final df = DateFormat('dd/MM/yyyy');

              return Card(
                color: emp.isActive ? Colors.white : const Color(0xFFF8FAFC),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: emp.isActive ? const Color(0xFFE0F2FE) : const Color(0xFFF1F5F9),
                    foregroundColor: emp.isActive ? const Color(0xFF0369A1) : const Color(0xFF94A3B8),
                    child: Text(emp.nickname.isNotEmpty ? emp.nickname[0] : '?'),
                  ),
                  title: Row(
                    children: [
                      Text(
                        emp.nickname,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: emp.isActive ? Colors.black87 : const Color(0xFF94A3B8),
                          decoration: emp.isActive ? null : TextDecoration.lineThrough,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('(${emp.epCode})', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: emp.isActive ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          emp.isActive ? 'Active' : 'Resigned',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: emp.isActive ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
                          ),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 2),
                      Text(
                        'Group: ${emp.payGroup}  |  Type: ${emp.wageType == 'Daily' ? 'รายวัน (Daily)' : 'รายเดือน (Monthly)'}  |  Salary: ฿${currency.format(emp.baseSalary)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        'Stay Outside: ${emp.stayOutside}${emp.stayOutside.toLowerCase() == 'yes' ? ' (ค่าห้อง: ฿${currency.format(emp.housingAllowance)}/ด.)' : ''}',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF0369A1)),
                      ),
                      if (emp.startDate != null)
                        Text(
                          '📅 Start Date: ${df.format(emp.startDate!)}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF0284C7)),
                        ),
                      if (emp.resignDate != null)
                        Text(
                          '🚪 Resign Date: ${df.format(emp.resignDate!)}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFFDC2626)),
                        ),
                      Row(
                        children: [
                          Icon(Icons.key, size: 12, color: emp.hasCustomPin ? const Color(0xFF10B981) : const Color(0xFF64748B)),
                          const SizedBox(width: 4),
                          Text(
                            'PIN: ${emp.pin}${emp.hasCustomPin ? '' : ' (ค่าเริ่มต้น)'}',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: emp.hasCustomPin ? const Color(0xFF10B981) : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                      if (emp.note.isNotEmpty)
                        Text('📝 ${emp.note}', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                    ],
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (val) {
                      if (val == 'toggle_status') {
                        _toggleEmployeeStatus(emp);
                      } else if (val == 'set_dates') {
                        _showSetDatesDialog(emp);
                      } else if (val == 'edit_welfare') {
                        _showEditEmployeeWelfareDialog(emp);
                      } else if (val == 'set_pin') {
                        _showSetPinDialog(emp);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'set_pin',
                        child: const Row(
                          children: [
                            Icon(Icons.pin_outlined, size: 18, color: Color(0xFF10B981)),
                            SizedBox(width: 8),
                            Text('ตั้งรหัส PIN พนักงาน (Portal)'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'edit_welfare',
                        child: const Row(
                          children: [
                            Icon(Icons.tune, size: 18, color: Color(0xFF0284C7)),
                            SizedBox(width: 8),
                            Text('ประเภทการจ้าง & สวัสดิการค่าห้องพัก'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'set_dates',
                        child: const Row(
                          children: [
                            Icon(Icons.date_range, size: 18),
                            SizedBox(width: 8),
                            Text('Set Start/Resign Dates (Prorate)'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'toggle_status',
                        child: Row(
                          children: [
                            Icon(emp.isActive ? Icons.person_off : Icons.person, size: 18),
                            SizedBox(width: 8),
                            Text(emp.isActive ? 'Mark as Resigned' : 'Mark as Active'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // ATTENDANCE MANAGEMENT & ACTIONS
  // ===========================================================================

  Future<void> _handleDeleteAttendance(Map<String, dynamic> log) async {
    final id = log['id'];
    final date = log['date']?.toString() ?? '';
    final epCode = log['ep_code']?.toString() ?? '';
    final nickname = log['nickname']?.toString() ?? '';
    final category = log['category']?.toString() ?? 'Day-off';

    // 1. Optimistic UI update: Remove locally immediately
    setState(() {
      _attendanceLogs.removeWhere((a) {
        if (id != null && a['id'] != null) return a['id'] == id;
        return a['ep_code'] == epCode && a['date'] == date && a['category'] == category;
      });
    });

    // 2. Call Supabase API to delete
    final ok = await ApiService.deleteAttendance(
      id: id,
      date: date,
      epCode: epCode,
      category: category,
    );

    // 3. Recalculate payroll & re-fetch
    await _fetchDataAndRecalculate();

    if (mounted) {
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🗑️ ยกเลิกรายการ $category ของ $nickname ($date) สำเร็จแล้ว'),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ ไม่สามารถลบข้อมูลจาก Cloud ได้ กรุณาลองใหม่อีกครั้ง'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleClearMonthDayOffs(DateTime targetMonth) async {
    final monthName = DateFormat('MMMM yyyy').format(targetMonth);
    final monthPrefix = '${targetMonth.year}-${targetMonth.month.toString().padLeft(2, '0')}';
    final daysInMonth = DateTime(targetMonth.year, targetMonth.month + 1, 0).day;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
            SizedBox(width: 8),
            Text('ยืนยันล้างวันหยุดทั้งเดือน', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text('คุณต้องการยกเลิกและล้างวันหยุดทั้งหมดของพนักงานทุกคนในเดือน $monthName หรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('ไม่ลบ'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('ยืนยันล้างทั้งเดือน'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _attendanceLogs.removeWhere((a) =>
          a['category'] == 'Day-off' &&
          (a['date']?.toString() ?? '').startsWith(monthPrefix)
        );
      });

      final startStr = '$monthPrefix-01';
      final endStr = '$monthPrefix-$daysInMonth';
      final ok = await ApiService.clearDayOffsForRange(startDate: startStr, endDate: endStr);

      await _fetchDataAndRecalculate();

      if (mounted) {
        if (ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🗑️ ล้างวันหยุดทั้งหมดของเดือน $monthName เรียบร้อยแล้ว'),
              backgroundColor: const Color(0xFF10B981),
              duration: const Duration(seconds: 3),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ ไม่สามารถลบข้อมูลจาก Cloud ได้ กรุณาลองใหม่อีกครั้ง'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _handleDeleteAdjustment(Map<String, dynamic> adj) async {
    final id = adj['id'];
    final epCode = adj['ep_code']?.toString() ?? '';
    final nickname = adj['nickname']?.toString() ?? '';
    final category = adj['category']?.toString() ?? 'Adjustment';
    final dueDate = adj['due_date']?.toString() ?? '';
    final amount = (adj['amount'] as num?)?.toDouble() ?? 0.0;
    final currency = NumberFormat('#,##0.00', 'en_US');

    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
            SizedBox(width: 8),
            Text('ยืนยันยกเลิกลบรายจ่าย', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text('คุณต้องการยกเลิกและลบรายการ $category ของ $nickname ($epCode)\nจำนวน ฿${currency.format(amount)} ใช่หรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('ไม่ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('ยืนยันยกเลิก'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // 1. Optimistic removal locally
      setState(() {
        _adjustments.removeWhere((a) {
          if (id != null && a['id'] != null) return a['id'] == id;
          return a['ep_code'] == epCode && a['due_date'] == dueDate && a['category'] == category;
        });
      });

      // 2. Call Cloud API
      final ok = await ApiService.deleteAdjustment(
        id: id,
        epCode: epCode,
        dueDate: dueDate,
        category: category,
      );

      // 3. Clear local cache for this employee and recalculate
      _payrollRecords.remove(epCode);
      await _fetchDataAndRecalculate();

      if (mounted) {
        if (ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🗑️ ยกเลิกรายการ $category ฿${currency.format(amount)} ของ $nickname สำเร็จแล้ว'),
              backgroundColor: const Color(0xFF10B981),
              duration: const Duration(seconds: 3),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ ไม่สามารถลบข้อมูลจาก Cloud ได้ กรุณาลองใหม่อีกครั้ง'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  // ===========================================================================
  // DIALOGS: AUTO-SCHEDULE DAY-OFFS (MONTH-BY-MONTH & PERIOD), ADD ATTENDANCE
  // ===========================================================================

  void _showAutoScheduleForMonthDialog(DateTime targetMonth) {
    final activeEmps = _employees.where((e) => e.isActive).toList();
    if (activeEmps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่มีพนักงานที่กำลังทำงาน (Active) ในระบบ')),
      );
      return;
    }

    final monthName = DateFormat('MMMM yyyy').format(targetMonth);
    final monthPrefix = '${targetMonth.year}-${targetMonth.month.toString().padLeft(2, '0')}';
    final daysInMonth = DateTime(targetMonth.year, targetMonth.month + 1, 0).day;
    final shortDf = DateFormat('dd/MM');

    // Weekday definitions: 1 = Monday to 7 = Sunday
    const weekdayDefs = [
      {'day': 1, 'short': 'จ.', 'name': 'วันจันทร์'},
      {'day': 2, 'short': 'อ.', 'name': 'วันอังคาร'},
      {'day': 3, 'short': 'พ.', 'name': 'วันพุธ'},
      {'day': 4, 'short': 'พฤ.', 'name': 'วันพฤหัสฯ'},
      {'day': 5, 'short': 'ศ.', 'name': 'วันศุกร์'},
      {'day': 6, 'short': 'ส.', 'name': 'วันเสาร์'},
      {'day': 7, 'short': 'อา.', 'name': 'วันอาทิตย์'},
    ];

    // Read existing day-offs for each employee that fall within this target calendar month
    final Map<String, Set<int>> chosenDays = {};
    for (final emp in activeEmps) {
      final existingMonthDayOffs = _attendanceLogs
          .where((a) => a['ep_code'] == emp.epCode && a['category'] == 'Day-off' && (a['date']?.toString() ?? '').startsWith(monthPrefix))
          .toList();
      final Set<int> weekdays = {};
      for (final a in existingMonthDayOffs) {
        final dStr = a['date']?.toString() ?? '';
        if (dStr.isNotEmpty) {
          try {
            final d = DateTime.parse(dStr);
            weekdays.add(d.weekday);
          } catch (_) {}
        }
      }

      // If no day-offs found for this month yet, fallback to employee's preferred day-offs or past patterns
      if (weekdays.isEmpty) {
        if (emp.preferredDayOffs.isNotEmpty) {
          weekdays.addAll(emp.preferredDayOffs);
        } else {
          final pastLogs = _attendanceLogs
              .where((a) => a['ep_code'] == emp.epCode && a['category'] == 'Day-off')
              .toList();
          for (final a in pastLogs.take(4)) {
            final dStr = a['date']?.toString() ?? '';
            if (dStr.isNotEmpty) {
              try {
                final d = DateTime.parse(dStr);
                weekdays.add(d.weekday);
              } catch (_) {}
            }
          }
        }
      }

      chosenDays[emp.epCode] = weekdays;
    }

    bool clearExistingDayOffs = true;
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            int totalGeneratedDays = 0;
            for (final emp in activeEmps) {
              final empDays = chosenDays[emp.epCode] ?? {};
              for (int day = 1; day <= daysInMonth; day++) {
                final d = DateTime(targetMonth.year, targetMonth.month, day);
                if (emp.startDate != null) {
                  final startOnly = DateTime(emp.startDate!.year, emp.startDate!.month, emp.startDate!.day);
                  if (d.isBefore(startOnly)) continue;
                }
                if (emp.resignDate != null) {
                  final resignOnly = DateTime(emp.resignDate!.year, emp.resignDate!.month, emp.resignDate!.day);
                  if (d.isAfter(resignOnly)) continue;
                }
                if (empDays.contains(d.weekday)) {
                  totalGeneratedDays++;
                }
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.auto_awesome, color: Color(0xFF4F46E5), size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'จัดตารางวันหยุดเดือน $monthName',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                        ),
                        Text(
                          'วางแผนวันหยุดเฉพาะเดือน $monthName (วันที่ 1 - $daysInMonth)',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.normal),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 640,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.calendar_month, size: 16, color: Color(0xFF0369A1)),
                                const SizedBox(width: 6),
                                Text(
                                  'กำหนดวันหยุดของเดือน $monthName โดยเฉพาะ:',
                                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF0369A1)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'เลือกวันที่พนักงานหยุดในแต่ละสัปดาห์ ระบบจะสร้างวันหยุดสำหรับเดือน $monthName ให้อัตโนมัติ โดยไม่ส่งผลกระทบต่อเดือนอื่น',
                              style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569)),
                            ),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: isSubmitting
                                  ? null
                                  : () => setDlgState(() => clearExistingDayOffs = !clearExistingDayOffs),
                              child: Row(
                                children: [
                                  SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: Checkbox(
                                      value: clearExistingDayOffs,
                                      onChanged: isSubmitting
                                          ? null
                                          : (v) => setDlgState(() => clearExistingDayOffs = v ?? true),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'ล้างวันหยุดเดิมเฉพาะในเดือน $monthName ก่อนสร้างใหม่',
                                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: isSubmitting
                                      ? null
                                      : () {
                                          setDlgState(() {
                                            for (final emp in activeEmps) {
                                              final days = chosenDays[emp.epCode] ?? {};
                                              days.add(7); // Sunday
                                              chosenDays[emp.epCode] = days;
                                            }
                                          });
                                        },
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  icon: const Icon(Icons.wb_sunny_outlined, size: 14, color: Color(0xFFD97706)),
                                  label: const Text('+ ทุกคนหยุดวันอาทิตย์', style: TextStyle(fontSize: 11)),
                                ),
                                OutlinedButton.icon(
                                  onPressed: isSubmitting
                                      ? null
                                      : () {
                                          setDlgState(() {
                                            for (final emp in activeEmps) {
                                              final days = chosenDays[emp.epCode] ?? {};
                                              days.add(1); // Monday
                                              chosenDays[emp.epCode] = days;
                                            }
                                          });
                                        },
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  icon: const Icon(Icons.calendar_today, size: 14, color: Color(0xFF4F46E5)),
                                  label: const Text('+ ทุกคนหยุดวันจันทร์', style: TextStyle(fontSize: 11)),
                                ),
                                OutlinedButton.icon(
                                  onPressed: isSubmitting
                                      ? null
                                      : () {
                                          setDlgState(() {
                                            for (final emp in activeEmps) {
                                              chosenDays[emp.epCode] = {};
                                            }
                                          });
                                        },
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  icon: const Icon(Icons.clear_all, size: 14),
                                  label: const Text('ล้างวันหยุดทั้งหมด', style: TextStyle(fontSize: 11)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'พนักงานที่กำลังทำงาน (Active Staff):',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF334155)),
                      ),
                      const SizedBox(height: 6),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: activeEmps.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, idx) {
                          final emp = activeEmps[idx];
                          final empDays = chosenDays[emp.epCode] ?? {};

                          // Calculate all dates in this month
                          final List<DateTime> generatedDates = [];
                          for (int day = 1; day <= daysInMonth; day++) {
                            final d = DateTime(targetMonth.year, targetMonth.month, day);
                            if (emp.startDate != null) {
                              final startOnly = DateTime(emp.startDate!.year, emp.startDate!.month, emp.startDate!.day);
                              if (d.isBefore(startOnly)) continue;
                            }
                            if (emp.resignDate != null) {
                              final resignOnly = DateTime(emp.resignDate!.year, emp.resignDate!.month, emp.resignDate!.day);
                              if (d.isAfter(resignOnly)) continue;
                            }
                            if (empDays.contains(d.weekday)) {
                              generatedDates.add(d);
                            }
                          }

                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 14,
                                      backgroundColor: const Color(0xFFE0F2FE),
                                      foregroundColor: const Color(0xFF0369A1),
                                      child: Text(
                                        emp.nickname.isNotEmpty ? emp.nickname[0] : '?',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${emp.nickname} (${emp.epCode})',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                          ),
                                          Text(
                                            'กลุ่ม ${emp.payGroup} • เดือน $monthName',
                                            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: generatedDates.isNotEmpty ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'หยุด ${generatedDates.length} วัน',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: generatedDates.isNotEmpty ? const Color(0xFF15803D) : const Color(0xFF64748B),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                // Weekday toggles
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: weekdayDefs.map((def) {
                                      final dayNum = def['day'] as int;
                                      final shortName = def['short'] as String;
                                      final isSelected = empDays.contains(dayNum);

                                      return Padding(
                                        padding: const EdgeInsets.only(right: 6),
                                        child: InkWell(
                                          onTap: isSubmitting
                                              ? null
                                              : () {
                                                  setDlgState(() {
                                                    if (isSelected) {
                                                      empDays.remove(dayNum);
                                                    } else {
                                                      empDays.add(dayNum);
                                                    }
                                                    chosenDays[emp.epCode] = empDays;
                                                  });
                                                },
                                          borderRadius: BorderRadius.circular(8),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFFF1F5F9),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(
                                                color: isSelected ? const Color(0xFF4338CA) : const Color(0xFFE2E8F0),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (isSelected)
                                                  const Padding(
                                                    padding: EdgeInsets.only(right: 4),
                                                    child: Icon(Icons.check, size: 12, color: Colors.white),
                                                  ),
                                                Text(
                                                  shortName,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                                    color: isSelected ? Colors.white : const Color(0xFF334155),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                if (generatedDates.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '📅 วันหยุดเดือนนี้: ${generatedDates.map((d) => shortDf.format(d)).join(', ')} (${generatedDates.length} วัน)',
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF334155), fontWeight: FontWeight.w500),
                                    ),
                                  )
                                else
                                  const Text(
                                    'แตะเลือกวันด้านบน เช่น [จ.] เพื่อกำหนดวันหยุดในเดือนนี้',
                                    style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontStyle: FontStyle.italic),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actionsPadding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              actions: [
                OutlinedButton.icon(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (c) => AlertDialog(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              title: const Row(
                                children: [
                                  Icon(Icons.warning_amber_rounded, color: Colors.red, size: 22),
                                  SizedBox(width: 8),
                                  Text('ยืนยันล้างวันหยุดทั้งเดือน', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              content: Text('ต้องการยกเลิกและลบวันหยุดทั้งหมดของพนักงานทุกคนในเดือน $monthName หรือไม่?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(c, false),
                                  child: const Text('ไม่ลบ'),
                                ),
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(c, true),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text('ยืนยันล้างทั้งเดือน'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            setDlgState(() => isSubmitting = true);
                            final messenger = ScaffoldMessenger.of(context);
                            final navigator = Navigator.of(ctx);

                            try {
                              final startStr = '$monthPrefix-01';
                              final endStr = '$monthPrefix-$daysInMonth';
                              await ApiService.clearDayOffsForRange(
                                startDate: startStr,
                                endDate: endStr,
                              );

                              if (mounted) {
                                setState(() {
                                  _attendanceLogs.removeWhere((a) =>
                                    a['category'] == 'Day-off' &&
                                    (a['date']?.toString() ?? '').startsWith(monthPrefix)
                                  );
                                });
                              }

                              await _fetchDataAndRecalculate();
                              navigator.pop();
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text('🗑️ ล้างวันหยุดทั้งหมดของเดือน $monthName เรียบร้อยแล้ว'),
                                  backgroundColor: const Color(0xFF10B981),
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                            } catch (e) {
                              setDlgState(() => isSubmitting = false);
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text('⚠️ เกิดข้อผิดพลาด: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Color(0xFFFCA5A5)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18, color: Colors.red),
                  label: const Text('ล้างวันหยุดทั้งเดือนนี้'),
                ),
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                  child: const Text('ยกเลิก (Cancel)'),
                ),
                ElevatedButton.icon(
                  onPressed: (isSubmitting || totalGeneratedDays == 0)
                      ? null
                      : () async {
                          setDlgState(() => isSubmitting = true);
                          final messenger = ScaffoldMessenger.of(context);
                          final navigator = Navigator.of(ctx);

                          try {
                            final List<Map<String, dynamic>> allBatchRecords = [];

                            for (final emp in activeEmps) {
                              final empDays = chosenDays[emp.epCode] ?? {};

                              for (int day = 1; day <= daysInMonth; day++) {
                                final d = DateTime(targetMonth.year, targetMonth.month, day);
                                if (emp.startDate != null) {
                                  final startOnly = DateTime(emp.startDate!.year, emp.startDate!.month, emp.startDate!.day);
                                  if (d.isBefore(startOnly)) continue;
                                }
                                if (emp.resignDate != null) {
                                  final resignOnly = DateTime(emp.resignDate!.year, emp.resignDate!.month, emp.resignDate!.day);
                                  if (d.isAfter(resignOnly)) continue;
                                }

                                if (empDays.contains(d.weekday)) {
                                  allBatchRecords.add({
                                    'date': DateFormat('yyyy-MM-dd').format(d),
                                    'ep_code': emp.epCode,
                                    'nickname': emp.nickname,
                                    'category': 'Day-off',
                                    'shift': 'Normal',
                                    'units': 1.0,
                                    'note': 'วันหยุดประจำเดือน $monthName',
                                  });
                                }
                              }
                            }

                            // 1. Clear old day-offs for this month range in Supabase in ONE atomic call
                            if (clearExistingDayOffs) {
                              final startStr = '$monthPrefix-01';
                              final endStr = '$monthPrefix-$daysInMonth';
                              await ApiService.clearDayOffsForRange(
                                startDate: startStr,
                                endDate: endStr,
                              );
                            }

                            // 2. Batch insert to Supabase
                            if (allBatchRecords.isNotEmpty) {
                              final ok = await ApiService.batchCreateAttendance(allBatchRecords);
                              if (!ok) {
                                throw Exception('ไม่สามารถบันทึกข้อมูลไปยังระบบได้ กรุณาลองใหม่อีกครั้ง');
                              }
                            }

                            // 3. IMMEDIATE OPTIMISTIC LOCAL STATE UPDATE:
                            // Update local attendanceLogs so the calendar updates instantly without waiting for network lag!
                            if (mounted) {
                              setState(() {
                                if (clearExistingDayOffs) {
                                  _attendanceLogs.removeWhere((a) =>
                                    a['category'] == 'Day-off' &&
                                    (a['date']?.toString() ?? '').startsWith(monthPrefix)
                                  );
                                }
                                _attendanceLogs.addAll(allBatchRecords);
                                // Ensure the selected period matches or displays targetMonth
                                if (_selectedPeriod != monthPrefix && _periods.contains(monthPrefix)) {
                                  _selectedPeriod = monthPrefix;
                                }
                              });
                            }

                            // 4. Background re-sync & recalculate
                            await _fetchDataAndRecalculate();

                            navigator.pop();
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('✅ จัดตารางวันหยุดเดือน $monthName สำเร็จแล้ว (${allBatchRecords.length} วัน) วันหยุดอัปเดตบนปฏิทินทันที'),
                                backgroundColor: const Color(0xFF10B981),
                                duration: const Duration(seconds: 3),
                              ),
                            );
                          } catch (e) {
                            setDlgState(() => isSubmitting = false);
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('⚠️ เกิดข้อผิดพลาด: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  icon: isSubmitting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.flash_on, size: 18),
                  label: Text(
                    isSubmitting
                        ? 'กำลังสร้าง...'
                        : (totalGeneratedDays == 0
                            ? 'เลือกวันหยุดก่อนบันทึก (0 วัน)'
                            : '⚡ บันทึกวันหยุดเดือน $monthName ($totalGeneratedDays วัน)'),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAutoScheduleDayOffsDialog() {
    final activeEmps = _employees.where((e) => e.isActive).toList();
    if (activeEmps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่มีพนักงานที่กำลังทำงาน (Active) ในระบบ')),
      );
      return;
    }

    final df = DateFormat('dd/MM/yyyy');
    final shortDf = DateFormat('dd/MM');

    // Weekday definitions: 1 = Monday to 7 = Sunday
    const weekdayDefs = [
      {'day': 1, 'short': 'จ.', 'name': 'วันจันทร์'},
      {'day': 2, 'short': 'อ.', 'name': 'วันอังคาร'},
      {'day': 3, 'short': 'พ.', 'name': 'วันพุธ'},
      {'day': 4, 'short': 'พฤ.', 'name': 'วันพฤหัสฯ'},
      {'day': 5, 'short': 'ศ.', 'name': 'วันศุกร์'},
      {'day': 6, 'short': 'ส.', 'name': 'วันเสาร์'},
      {'day': 7, 'short': 'อา.', 'name': 'วันอาทิตย์'},
    ];

    // Initialize chosen weekdays for EACH employee strictly from THIS PERIOD's existing attendance logs
    final Map<String, Set<int>> chosenDays = {};
    for (final emp in activeEmps) {
      final existingDayOffs = _attendanceLogs
          .where((a) => a['ep_code'] == emp.epCode && a['category'] == 'Day-off')
          .toList();
      final Set<int> weekdays = {};
      for (final a in existingDayOffs) {
        final dStr = a['date']?.toString() ?? '';
        if (dStr.isNotEmpty) {
          try {
            final d = DateTime.parse(dStr);
            weekdays.add(d.weekday);
          } catch (_) {}
        }
      }
      chosenDays[emp.epCode] = weekdays;
    }

    bool clearExistingDayOffs = true;
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            // Count total day-offs that will be created for this period
            int totalGeneratedDays = 0;
            for (final emp in activeEmps) {
              final cycle = PayrollEngine.getCycleRange(_selectedPeriod, emp.payGroup);
              final empDays = chosenDays[emp.epCode] ?? {};
              for (var d = cycle.startDate; !d.isAfter(cycle.endDate); d = d.add(const Duration(days: 1))) {
                final dOnly = DateTime(d.year, d.month, d.day);
                if (emp.startDate != null) {
                  final startOnly = DateTime(emp.startDate!.year, emp.startDate!.month, emp.startDate!.day);
                  if (dOnly.isBefore(startOnly)) continue;
                }
                if (emp.resignDate != null) {
                  final resignOnly = DateTime(emp.resignDate!.year, emp.resignDate!.month, emp.resignDate!.day);
                  if (dOnly.isAfter(resignOnly)) continue;
                }
                if (empDays.contains(d.weekday)) {
                  totalGeneratedDays++;
                }
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.auto_awesome, color: Color(0xFF4F46E5), size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'จัดตารางวันหยุดเฉพาะงวด $_selectedPeriod',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                        ),
                        const Text(
                          'วางแผนเฉพาะงวดนี้ • ปลอดภัย ไม่กระทบแพลนงวดอื่น 100%',
                          style: TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.normal),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 640,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Notice & Explanation Card
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.verified_user_outlined, size: 16, color: Color(0xFF0369A1)),
                                SizedBox(width: 6),
                                Text(
                                  'ระบบแยกวันหยุดเฉพาะงวด (Per-Period Isolation):',
                                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF0369A1)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'การเลือกวันหยุดนี้จะมีผลเฉพาะงวด $_selectedPeriod เท่านั้น ระบบจะไม่ไปยุ่งหรือแตะต้องข้อมูลของงวดอื่นที่ผ่านมาเด็ดขาด',
                              style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569)),
                            ),
                            const SizedBox(height: 8),
                            // Clear existing checkbox
                            InkWell(
                              onTap: isSubmitting
                                  ? null
                                  : () => setDlgState(() => clearExistingDayOffs = !clearExistingDayOffs),
                              child: Row(
                                children: [
                                  SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: Checkbox(
                                      value: clearExistingDayOffs,
                                      onChanged: isSubmitting
                                          ? null
                                          : (v) => setDlgState(() => clearExistingDayOffs = v ?? true),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'ล้างวันหยุดเดิมเฉพาะของงวด $_selectedPeriod นี้ก่อนสร้างใหม่',
                                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'พนักงานที่กำลังทำงาน (Active Staff):',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF334155)),
                      ),
                      const SizedBox(height: 6),
                      // Employees list
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: activeEmps.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, idx) {
                          final emp = activeEmps[idx];
                          final cycle = PayrollEngine.getCycleRange(_selectedPeriod, emp.payGroup);
                          final empDays = chosenDays[emp.epCode] ?? {};

                          // Calculate the exact dates that will be generated for this employee in this cycle
                          final List<DateTime> generatedDates = [];
                          for (var d = cycle.startDate; !d.isAfter(cycle.endDate); d = d.add(const Duration(days: 1))) {
                            final dOnly = DateTime(d.year, d.month, d.day);
                            if (emp.startDate != null) {
                              final startOnly = DateTime(emp.startDate!.year, emp.startDate!.month, emp.startDate!.day);
                              if (dOnly.isBefore(startOnly)) continue;
                            }
                            if (emp.resignDate != null) {
                              final resignOnly = DateTime(emp.resignDate!.year, emp.resignDate!.month, emp.resignDate!.day);
                              if (dOnly.isAfter(resignOnly)) continue;
                            }
                            if (empDays.contains(d.weekday)) {
                              generatedDates.add(d);
                            }
                          }

                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 14,
                                      backgroundColor: const Color(0xFFE0F2FE),
                                      foregroundColor: const Color(0xFF0369A1),
                                      child: Text(
                                        emp.nickname.isNotEmpty ? emp.nickname[0] : '?',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${emp.nickname} (${emp.epCode})',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                          ),
                                          Text(
                                            '${emp.payGroup} • รอบ ${df.format(cycle.startDate)} - ${df.format(cycle.endDate)}',
                                            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: generatedDates.isNotEmpty ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'หยุด ${generatedDates.length} วัน',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: generatedDates.isNotEmpty ? const Color(0xFF15803D) : const Color(0xFF64748B),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                // 7 Weekday Toggles
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: weekdayDefs.map((def) {
                                      final dayNum = def['day'] as int;
                                      final shortName = def['short'] as String;
                                      final isSelected = empDays.contains(dayNum);

                                      return Padding(
                                        padding: const EdgeInsets.only(right: 6),
                                        child: InkWell(
                                          onTap: isSubmitting
                                              ? null
                                              : () {
                                                  setDlgState(() {
                                                    if (isSelected) {
                                                      empDays.remove(dayNum);
                                                    } else {
                                                      empDays.add(dayNum);
                                                    }
                                                    chosenDays[emp.epCode] = empDays;
                                                  });
                                                },
                                          borderRadius: BorderRadius.circular(8),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFFF1F5F9),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(
                                                color: isSelected ? const Color(0xFF4338CA) : const Color(0xFFE2E8F0),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (isSelected)
                                                  const Padding(
                                                    padding: EdgeInsets.only(right: 4),
                                                    child: Icon(Icons.check, size: 12, color: Colors.white),
                                                  ),
                                                Text(
                                                  shortName,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                                    color: isSelected ? Colors.white : const Color(0xFF334155),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                // Preview Dates List
                                if (generatedDates.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '📅 วันหยุดในงวดนี้: ${generatedDates.map((d) => shortDf.format(d)).join(', ')} (${generatedDates.length} วัน)',
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF334155), fontWeight: FontWeight.w500),
                                    ),
                                  )
                                else
                                  const Text(
                                    'แตะเลือกวันด้านบน เช่น [จ.] เพื่อกำหนดวันหยุดในงวดนี้',
                                    style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontStyle: FontStyle.italic),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actionsPadding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              actions: [
                OutlinedButton.icon(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (c) => AlertDialog(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              title: const Row(
                                children: [
                                  Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
                                  SizedBox(width: 8),
                                  Text('ยืนยันล้างวันหยุดทั้งงวด', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              content: Text('คุณต้องการยกเลิกและล้างวันหยุดทั้งหมดของพนักงานทุกคนในงวด $_selectedPeriod หรือไม่?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(c, false),
                                  child: const Text('ไม่ลบ'),
                                ),
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(c, true),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text('ยืนยันล้างทั้งงวด'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            setDlgState(() => isSubmitting = true);
                            final messenger = ScaffoldMessenger.of(context);
                            final navigator = Navigator.of(ctx);

                            try {
                              for (final emp in activeEmps) {
                                final cycle = PayrollEngine.getCycleRange(_selectedPeriod, emp.payGroup);
                                final startStr = DateFormat('yyyy-MM-dd').format(cycle.startDate);
                                final endStr = DateFormat('yyyy-MM-dd').format(cycle.endDate);
                                await ApiService.clearDayOffsForRange(
                                  startDate: startStr,
                                  endDate: endStr,
                                  epCode: emp.epCode,
                                );
                              }

                              if (mounted) {
                                setState(() {
                                  for (final emp in activeEmps) {
                                    final cycle = PayrollEngine.getCycleRange(_selectedPeriod, emp.payGroup);
                                    _attendanceLogs.removeWhere((a) {
                                      if (a['ep_code'] != emp.epCode || a['category'] != 'Day-off') return false;
                                      final dStr = a['date']?.toString() ?? '';
                                      if (dStr.isEmpty) return false;
                                      try {
                                        final d = DateTime.parse(dStr);
                                        return !d.isBefore(cycle.startDate) && !d.isAfter(cycle.endDate);
                                      } catch (_) {
                                        return false;
                                      }
                                    });
                                  }
                                });
                              }

                              await _fetchDataAndRecalculate();
                              navigator.pop();
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text('🗑️ ล้างวันหยุดทั้งหมดในงวด $_selectedPeriod เรียบร้อยแล้ว'),
                                  backgroundColor: const Color(0xFF10B981),
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                            } catch (e) {
                              setDlgState(() => isSubmitting = false);
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text('⚠️ เกิดข้อผิดพลาด: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Color(0xFFFCA5A5)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18, color: Colors.red),
                  label: const Text('ล้างวันหยุดทั้งงวดนี้'),
                ),
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                  child: const Text('ยกเลิก (Cancel)'),
                ),
                ElevatedButton.icon(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          setDlgState(() => isSubmitting = true);
                          final messenger = ScaffoldMessenger.of(context);
                          final navigator = Navigator.of(ctx);

                          try {
                            // 1. Prepare batch records strictly for _selectedPeriod
                            final List<Map<String, dynamic>> allBatchRecords = [];

                            for (final emp in activeEmps) {
                              final cycle = PayrollEngine.getCycleRange(_selectedPeriod, emp.payGroup);
                              final empDays = chosenDays[emp.epCode] ?? {};

                              // Clear old day-offs STRICTLY for this cycle's date range
                              if (clearExistingDayOffs) {
                                final startStr = DateFormat('yyyy-MM-dd').format(cycle.startDate);
                                final endStr = DateFormat('yyyy-MM-dd').format(cycle.endDate);
                                await ApiService.clearDayOffsForRange(
                                  startDate: startStr,
                                  endDate: endStr,
                                  epCode: emp.epCode,
                                );
                              }

                              // Generate records
                              for (var d = cycle.startDate; !d.isAfter(cycle.endDate); d = d.add(const Duration(days: 1))) {
                                final dOnly = DateTime(d.year, d.month, d.day);
                                if (emp.startDate != null) {
                                  final startOnly = DateTime(emp.startDate!.year, emp.startDate!.month, emp.startDate!.day);
                                  if (dOnly.isBefore(startOnly)) continue;
                                }
                                if (emp.resignDate != null) {
                                  final resignOnly = DateTime(emp.resignDate!.year, emp.resignDate!.month, emp.resignDate!.day);
                                  if (dOnly.isAfter(resignOnly)) continue;
                                }

                                if (empDays.contains(d.weekday)) {
                                  allBatchRecords.add({
                                    'date': DateFormat('yyyy-MM-dd').format(d),
                                    'ep_code': emp.epCode,
                                    'nickname': emp.nickname,
                                    'category': 'Day-off',
                                    'shift': 'Normal',
                                    'units': 1.0,
                                    'note': 'วันหยุดประจำงวด $_selectedPeriod',
                                  });
                                }
                              }
                            }

                            // 2. Batch insert to Supabase attendance_log
                            if (allBatchRecords.isNotEmpty) {
                              final ok = await ApiService.batchCreateAttendance(allBatchRecords);
                              if (!ok) {
                                throw Exception('ไม่สามารถบันทึกข้อมูลไปยังระบบได้ กรุณาลองใหม่อีกครั้ง');
                              }
                            }

                            // 3. Reload data for this period (no need to reload employees)
                            await _fetchDataAndRecalculate(reloadEmployees: false);

                            navigator.pop();
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('✅ บันทึกวันหยุดเฉพาะงวด $_selectedPeriod สำเร็จ! (สร้าง ${allBatchRecords.length} วัน) ไม่กระทบงวดอื่น'),
                                backgroundColor: const Color(0xFF10B981),
                                duration: const Duration(seconds: 3),
                              ),
                            );
                          } catch (e) {
                            setDlgState(() => isSubmitting = false);
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('⚠️ เกิดข้อผิดพลาด: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  icon: isSubmitting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.flash_on, size: 18),
                  label: Text(isSubmitting ? 'กำลังสร้าง...' : '⚡ บันทึกวันหยุดงวด $_selectedPeriod ($totalGeneratedDays วัน)'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showLogAttendanceDialog({DateTime? initialDate}) {
    DateTime selectedDate = initialDate ?? DateTime.now();
    String epCode = _employees.first.epCode;
    String category = 'Day-off';
    final noteCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            final emp = _employees.firstWhere((e) => e.epCode == epCode, orElse: () => _employees.first);
            return AlertDialog(
              title: const Text('Log Day-off / Leave / OT'),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Date: ${DateFormat('yyyy-MM-dd').format(selectedDate)}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.calendar_today),
                        onPressed: () async {
                          final p = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime(2024),
                            lastDate: DateTime(2030),
                          );
                          if (p != null) setDlgState(() => selectedDate = p);
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: epCode,
                      decoration: const InputDecoration(labelText: 'Employee'),
                      items: _employees.map((e) {
                        return DropdownMenuItem(value: e.epCode, child: Text('${e.epCode} - ${e.nickname}'));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setDlgState(() => epCode = val);
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: category,
                      decoration: const InputDecoration(labelText: 'Category'),
                      items: const [
                        DropdownMenuItem(value: 'Day-off', child: Text('Day-off (วันหยุดประจำ)')),
                        DropdownMenuItem(value: 'Sick', child: Text('Sick Leave (ลาป่วย)')),
                        DropdownMenuItem(value: 'Half-day', child: Text('Half-day (ทำงานครึ่งวัน)')),
                        DropdownMenuItem(value: 'OT Days', child: Text('OT Days (ทำงานล่วงเวลา)')),
                        DropdownMenuItem(value: 'Work Days', child: Text('Work Days (วันทำงาน)')),
                      ],
                      onChanged: (val) {
                        if (val != null) setDlgState(() => category = val);
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: noteCtrl,
                      decoration: const InputDecoration(labelText: 'Note (Optional)'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () async {
                    final dateStr = DateFormat('yyyy-MM-dd').format(selectedDate);
                    final messenger = ScaffoldMessenger.of(context);
                    final navigator = Navigator.of(ctx);

                    final success = await ApiService.createAttendance(
                      date: dateStr,
                      epCode: epCode,
                      nickname: emp.nickname,
                      category: category,
                      note: noteCtrl.text,
                    );
                    navigator.pop();
                    if (mounted) {
                      _fetchDataAndRecalculate();
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(success ? '✅ Attendance logged to Database!' : '⚠️ Logged locally'),
                          backgroundColor: success ? const Color(0xFF10B981) : Colors.orange,
                        ),
                      );
                    }
                  },
                  child: const Text('Save to Database'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showLogAdjustmentDialog() {
    String epCode = _employees.first.epCode;
    String type = 'Deduction';
    String category = 'Advance Payment';
    final amtCtrl = TextEditingController(text: '1000');
    final descCtrl = TextEditingController();
    DateTime dueDate = DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            final emp = _employees.firstWhere((e) => e.epCode == epCode, orElse: () => _employees.first);
            return AlertDialog(
              title: const Text('Record Advance / Expense / Bonus'),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: epCode,
                      decoration: const InputDecoration(labelText: 'Employee'),
                      items: _employees.map((e) {
                        return DropdownMenuItem(value: e.epCode, child: Text('${e.epCode} - ${e.nickname}'));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setDlgState(() => epCode = val);
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: type,
                      decoration: const InputDecoration(labelText: 'Type'),
                      items: const [
                        DropdownMenuItem(value: 'Deduction', child: Text('Deduction (รายการหักเงิน)')),
                        DropdownMenuItem(value: 'Income', child: Text('Income (รายรับเสริม/โบนัส)')),
                      ],
                      onChanged: (val) {
                        if (val != null) setDlgState(() => type = val);
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: category,
                      decoration: const InputDecoration(labelText: 'Category'),
                      items: type == 'Deduction'
                          ? const [
                              DropdownMenuItem(value: 'Advance Payment', child: Text('Advance Payment (เงินเบิกล่วงหน้า)')),
                              DropdownMenuItem(value: 'Work Permit', child: Text('Work Permit Fee (ค่าเอกสารแรงงาน)')),
                              DropdownMenuItem(value: 'Passport / CI', child: Text('Passport / CI (ค่าพาสปอร์ต)')),
                              DropdownMenuItem(value: 'Other Deduction', child: Text('Other Deduction (หักอื่นๆ)')),
                            ]
                          : const [
                              DropdownMenuItem(value: 'Bonus', child: Text('Bonus / Incentive (เบี้ยขยัน/โบนัส)')),
                              DropdownMenuItem(value: 'OT Allowance', child: Text('OT Allowance (ค่ากะพิเศษ)')),
                              DropdownMenuItem(value: 'Other Income', child: Text('Other Income (รายรับอื่นๆ)')),
                            ],
                      onChanged: (val) {
                        if (val != null) setDlgState(() => category = val);
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: amtCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Amount (THB)'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: descCtrl,
                      decoration: const InputDecoration(labelText: 'Description / Note'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () async {
                    final amount = double.tryParse(amtCtrl.text) ?? 0;
                    final dueStr = DateFormat('yyyy-MM-dd').format(dueDate);
                    final messenger = ScaffoldMessenger.of(context);
                    final navigator = Navigator.of(ctx);

                    final success = await ApiService.createAdjustment(
                      period: _selectedPeriod,
                      dueDate: dueStr,
                      epCode: epCode,
                      nickname: emp.nickname,
                      type: type,
                      category: category,
                      description: descCtrl.text,
                      amount: amount,
                    );
                    navigator.pop();
                    if (mounted) {
                      _fetchDataAndRecalculate();
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(success ? '✅ Expense recorded to Database!' : '⚠️ Recorded locally'),
                          backgroundColor: success ? const Color(0xFF10B981) : Colors.orange,
                        ),
                      );
                    }
                  },
                  child: const Text('Save to Database'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildAttendanceItem(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF16A34A)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF475569))),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF166534))),
          ),
        ],
      ),
    );
  }

  Widget _buildPayslipLine(String label, String value, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                color: const Color(0xFF475569),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: color ?? const Color(0xFF1E293B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaveDateRow(String title, String dates, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: color),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              dates,
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF334155), fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  String _formatShortDate(String? dStr) {
    if (dStr == null || dStr.isEmpty) return '';
    try {
      final d = DateTime.parse(dStr);
      return DateFormat('dd/MM').format(d);
    } catch (_) {
      return dStr;
    }
  }

  Widget _buildMiniBadge(String text, Color bg, Color textCol) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textCol),
      ),
    );
  }

  Widget _buildFilterChip(String label, {String? subtitle}) {
    final isSelected = _selectedGroupFilter == label;
    return FilterChip(
      selected: isSelected,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      label: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
          if (subtitle != null)
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 10,
                color: isSelected ? Colors.white70 : const Color(0xFF64748B),
              ),
            ),
        ],
      ),
      selectedColor: const Color(0xFF0284C7),
      labelStyle: TextStyle(color: isSelected ? Colors.white : const Color(0xFF334155)),
      onSelected: (_) {
        setState(() => _selectedGroupFilter = label);
      },
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required Color color,
    required IconData icon,
    required String subtitle,
    bool isCompact = false,
  }) {
    return Container(
      width: isCompact ? null : 220,
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 10 : 12, vertical: isCompact ? 10 : 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: isCompact ? 11 : 12,
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(icon, size: isCompact ? 15 : 16, color: color),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: isCompact ? 16 : 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(fontSize: isCompact ? 10 : 11, color: const Color(0xFF94A3B8)),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  void _showEditAdjustmentsDialog(PayrollRecord record) {
    final workDaysCtrl = TextEditingController(text: record.workDays.toString());
    final dayOffCtrl = TextEditingController(text: record.dayOff.toString());
    final sickCtrl = TextEditingController(text: record.sickLeave.toString());
    final halfCtrl = TextEditingController(text: record.halfDays.toString());
    final otDaysCtrl = TextEditingController(text: record.otDays.toString());

    final otCtrl = TextEditingController(text: record.overtimePay > 0 ? record.overtimePay.toString() : '');
    final bonusCtrl = TextEditingController(text: record.bonusPay > 0 ? record.bonusPay.toString() : '');
    final housingCtrl = TextEditingController(text: record.housingAllowance > 0 ? record.housingAllowance.toString() : '');
    final otherExtraCtrl = TextEditingController(text: record.otherExtra > 0 ? record.otherExtra.toString() : '');
    final extraNoteCtrl = TextEditingController(text: record.extraNote);

    final advanceCtrl = TextEditingController(text: record.advanceDeduction > 0 ? record.advanceDeduction.toString() : '');
    final wpCtrl = TextEditingController(text: record.workPermitDeduction > 0 ? record.workPermitDeduction.toString() : '');
    final otherDedCtrl = TextEditingController(text: record.otherDeduction > 0 ? record.otherDeduction.toString() : '');
    final dedNoteCtrl = TextEditingController(text: record.deductionNote);

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Adjust Pay & Attendance: ${record.nickname} (${record.epCode})'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 520,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🏖️ Attendance & Day-offs', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0369A1))),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: workDaysCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Work Days', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: dayOffCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Day-offs', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: sickCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Sick Leave', border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: halfCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Half-days', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: otDaysCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'OT Days', border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  const Text('➕ Earnings / Allowances (THB)', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                  const SizedBox(height: 8),
                  TextField(
                    controller: housingCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Housing Allowance (ค่าห้องพัก ฿)',
                      helperText: record.housingAllowanceNote.isNotEmpty ? record.housingAllowanceNote : null,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: otCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Overtime Pay (OT)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: bonusCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Attendance Bonus / Incentive', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: otherExtraCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Other Extra Earnings', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: extraNoteCtrl,
                    decoration: const InputDecoration(labelText: 'Earnings Note', border: OutlineInputBorder()),
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('➖ Deductions (THB)', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFEF4444))),
                      TextButton.icon(
                        onPressed: () {
                          advanceCtrl.text = '0';
                          wpCtrl.text = '0';
                          otherDedCtrl.text = '0';
                          dedNoteCtrl.clear();
                        },
                        icon: const Icon(Icons.clear_all, size: 16, color: Colors.red),
                        label: const Text('ล้างรายจ่ายทั้งหมด (0 ฿)', style: TextStyle(fontSize: 12, color: Colors.red)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: advanceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Advance Payment Deduction', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: wpCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Work Permit / Passport Fee', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: otherDedCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Other Deductions', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: dedNoteCtrl,
                    decoration: const InputDecoration(labelText: 'Deduction Note', border: OutlineInputBorder()),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                setState(() {
                  record.workDays = int.tryParse(workDaysCtrl.text) ?? record.workDays;
                  record.dayOff = int.tryParse(dayOffCtrl.text) ?? record.dayOff;
                  record.sickLeave = int.tryParse(sickCtrl.text) ?? record.sickLeave;
                  record.halfDays = int.tryParse(halfCtrl.text) ?? record.halfDays;
                  record.otDays = int.tryParse(otDaysCtrl.text) ?? record.otDays;

                  if (record.wageType == 'Daily') {
                    record.basePay = (record.dailyRate * record.workDays).roundToDouble();
                    record.excessDayOffDays = 0;
                    record.excessDayOffDeduction = 0.0;
                  } else {
                    if (record.dayOff > 4) {
                      record.excessDayOffDays = record.dayOff - 4;
                      record.excessDayOffDeduction = (record.excessDayOffDays * record.dailyRate).roundToDouble();
                    } else {
                      record.excessDayOffDays = 0;
                      record.excessDayOffDeduction = 0.0;
                    }
                  }

                  record.housingAllowance = double.tryParse(housingCtrl.text) ?? 0;
                  if (record.housingAllowance > 0 && record.housingAllowanceNote.isEmpty) {
                    record.housingAllowanceNote = 'ปรับปรุงยอดค่าห้องพักในงวด';
                  }

                  record.overtimePay = double.tryParse(otCtrl.text) ?? 0;
                  record.bonusPay = double.tryParse(bonusCtrl.text) ?? 0;
                  record.otherExtra = double.tryParse(otherExtraCtrl.text) ?? 0;
                  record.extraNote = extraNoteCtrl.text;

                  record.advanceDeduction = double.tryParse(advanceCtrl.text) ?? 0;
                  record.workPermitDeduction = double.tryParse(wpCtrl.text) ?? 0;
                  record.otherDeduction = double.tryParse(otherDedCtrl.text) ?? 0;
                  record.deductionNote = dedNoteCtrl.text;
                });
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(ctx);

                // Auto-sync this employee's payroll record to Supabase Cloud
                final res = await ApiService.savePayrollSummary([record]);
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        res != null
                            ? '✅ Adjustments for ${record.nickname} saved to Cloud Database!'
                            : '⚠️ Adjustments saved locally.',
                      ),
                      backgroundColor: res != null ? const Color(0xFF10B981) : Colors.orange,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
              child: const Text('Save Changes'),
            ),
          ],
        );
      },
    );
  }

  void _showAddEmployeeDialog() {
    final epCtrl = TextEditingController(text: 'EP${_employees.length + 1}');
    final nameCtrl = TextEditingController();
    final salaryCtrl = TextEditingController(text: '12000');
    final housingCtrl = TextEditingController(text: '1000');
    String payGroup = 'Date : 10';
    String wageType = 'Monthly';
    String stayOutside = 'No';
    DateTime? startDate;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add New Employee'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: epCtrl,
                        decoration: const InputDecoration(labelText: 'Employee Code (EP Code)'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(labelText: 'Nickname'),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: wageType,
                        decoration: const InputDecoration(labelText: 'Wage Type (ประเภทการจ้าง)'),
                        items: const [
                          DropdownMenuItem(value: 'Monthly', child: Text('รายเดือน (Monthly Salary)')),
                          DropdownMenuItem(value: 'Daily', child: Text('รายวัน (Daily Wage)')),
                        ],
                        onChanged: (val) {
                          if (val != null) setDialogState(() => wageType = val);
                        },
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: salaryCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: wageType == 'Daily' ? 'Daily Wage Rate (฿/วัน)' : 'Base Salary (฿/เดือน)',
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: payGroup,
                        decoration: const InputDecoration(labelText: 'Pay Group Cycle'),
                        items: const [
                          DropdownMenuItem(value: 'Date : 1', child: Text('Date : 1 (2nd prev - 1st current)')),
                          DropdownMenuItem(value: 'Date : 10', child: Text('Date : 10 (11th prev - 10th current)')),
                          DropdownMenuItem(value: 'Date : 20', child: Text('Date : 20 (21st prev - 20th current)')),
                        ],
                        onChanged: (val) {
                          if (val != null) setDialogState(() => payGroup = val);
                        },
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: stayOutside,
                        decoration: const InputDecoration(labelText: 'สวัสดิการค่าห้องพัก (Stay Outside)'),
                        items: const [
                          DropdownMenuItem(value: 'No', child: Text('No (ไม่ได้รับสิทธิ์)')),
                          DropdownMenuItem(value: 'Yes', child: Text('Yes (ได้รับสวัสดิการค่าห้องพัก)')),
                        ],
                        onChanged: (val) {
                          if (val != null) setDialogState(() => stayOutside = val);
                        },
                      ),
                      if (stayOutside == 'Yes') ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: housingCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'จำนวนเงินสวัสดิการค่าห้องพัก (฿/เดือน)'),
                        ),
                      ],
                      const SizedBox(height: 12),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          startDate == null
                              ? 'Set Start Date (For Smart Prorate & Housing Eligibility)'
                              : 'Start Date: ${DateFormat('dd/MM/yyyy').format(startDate!)}',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.calendar_month),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (picked != null) setDialogState(() => startDate = picked);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () async {
                    if (nameCtrl.text.trim().isNotEmpty) {
                      final rawEmp = Employee(
                        epCode: epCtrl.text.trim(),
                        nickname: nameCtrl.text.trim(),
                        status: 'Active',
                        baseSalary: double.tryParse(salaryCtrl.text) ?? 12000,
                        payGroup: payGroup,
                        stayOutside: stayOutside,
                        startDate: startDate,
                      );
                      final newEmp = rawEmp.copyWithWelfareSettings(
                        wageType: wageType,
                        stayOutside: stayOutside,
                        housingAllowance: stayOutside == 'Yes' ? (double.tryParse(housingCtrl.text) ?? 1000.0) : 0.0,
                      );

                      setState(() {
                        _employees.add(newEmp);
                      });

                      final messenger = ScaffoldMessenger.of(context);
                      final navigator = Navigator.of(ctx);
                      navigator.pop();

                      final success = await ApiService.saveEmployee(newEmp);
                      await _fetchDataAndRecalculate(reloadEmployees: true);

                      if (mounted) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              success
                                  ? '✅ ${newEmp.nickname} saved to Cloud Database!'
                                  : '⚠️ Added locally, cloud sync pending.',
                            ),
                            backgroundColor: success ? const Color(0xFF10B981) : Colors.orange,
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('Save Employee'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showSetDatesDialog(Employee emp) {
    DateTime? start = emp.startDate;
    DateTime? resign = emp.resignDate;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final df = DateFormat('dd/MM/yyyy');
            return AlertDialog(
              title: Text('Start & Resign Dates: ${emp.nickname}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: Text(start == null ? 'No Start Date set' : 'Start Date: ${df.format(start!)}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.calendar_today),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: start ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (picked != null) setDialogState(() => start = picked);
                          },
                        ),
                        if (start != null)
                          IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => setDialogState(() => start = null),
                          ),
                      ],
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    title: Text(resign == null ? 'No Resign Date set' : 'Resign Date: ${df.format(resign!)}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.exit_to_app, color: Colors.red),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: resign ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (picked != null) setDialogState(() => resign = picked);
                          },
                        ),
                        if (resign != null)
                          IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => setDialogState(() => resign = null),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () async {
                    final index = _employees.indexWhere((e) => e.epCode == emp.epCode);
                    if (index != -1) {
                      final newStatus = resign != null ? 'Resigned' : emp.status;
                      setState(() {
                        _employees[index] = emp.copyWith(
                          startDate: start,
                          resignDate: resign,
                          status: newStatus,
                        );
                      });

                      final messenger = ScaffoldMessenger.of(context);
                      final navigator = Navigator.of(ctx);
                      navigator.pop();

                      final success = await ApiService.updateEmployeeDates(
                        epCode: emp.epCode,
                        startDate: start,
                        resignDate: resign,
                        status: newStatus,
                      );
                      await _fetchDataAndRecalculate(reloadEmployees: true);

                      if (mounted) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              success
                                  ? '✅ Dates & status for ${emp.nickname} saved to Cloud Database!'
                                  : '⚠️ Saved locally, cloud sync pending.',
                            ),
                            backgroundColor: success ? const Color(0xFF10B981) : Colors.orange,
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('Save Dates'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEditEmployeeWelfareDialog(Employee emp) {
    String wageType = emp.wageType;
    String stayOutside = emp.stayOutside;
    final dailyRateCtrl = TextEditingController(
      text: emp.dailyWageRate.toStringAsFixed(0),
    );
    final housingCtrl = TextEditingController(
      text: emp.housingAllowance > 0 ? emp.housingAllowance.toStringAsFixed(0) : '1000',
    );

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('สวัสดิการ & การจ้าง: ${emp.nickname} (${emp.epCode})'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: wageType,
                        decoration: const InputDecoration(
                          labelText: 'ประเภทการจ่ายค่าจ้าง (Wage Type)',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'Monthly', child: Text('รายเดือน (Monthly Salary)')),
                          DropdownMenuItem(value: 'Daily', child: Text('รายวัน (Daily Wage)')),
                        ],
                        onChanged: (val) {
                          if (val != null) setDialogState(() => wageType = val);
                        },
                      ),
                      if (wageType == 'Daily') ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: dailyRateCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'อัตราค่าจ้างรายวัน (฿/วัน)',
                            helperText: 'ค่าเริ่มต้นคำนวณจาก (ฐานเงินเดือน ÷ 30 วัน) หรือปรับเปลี่ยนตามต้องการ',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Text(
                          wageType == 'Daily'
                              ? 'ℹ️ พนักงานรายวัน: ฐานเงินเดือนจะคิดจาก (อัตราค่าจ้างรายวัน × วันทำงานจริงในแต่ละงวด)'
                              : 'ℹ️ พนักงานรายเดือน: ฐานเงินเดือนคิดตามปกติ โควตาวันหยุด 4 ครั้ง/งวด (หยุดเกินจะหักตามอัตราวัน)',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                        ),
                      ),
                      const Divider(height: 24),
                      DropdownButtonFormField<String>(
                        initialValue: stayOutside,
                        decoration: const InputDecoration(
                          labelText: 'สิทธิ์สวัสดิการค่าห้องพัก (Stay Outside)',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'No', child: Text('No (ไม่ได้รับสิทธิ์)')),
                          DropdownMenuItem(value: 'Yes', child: Text('Yes (ได้รับสวัสดิการค่าห้องพัก)')),
                        ],
                        onChanged: (val) {
                          if (val != null) setDialogState(() => stayOutside = val);
                        },
                      ),
                      if (stayOutside.toLowerCase() == 'yes') ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: housingCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'ยอดสวัสดิการค่าห้องพัก (฿/เดือน)',
                            helperText: 'กำหนดเองได้ตามความเหมาะสม (ค่าเริ่มต้น 1,000 บาท)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFA7F3D0)),
                          ),
                          child: const Text(
                            '📌 กฎการจ่าย: เริ่มได้รับในเดือนถัดไปหลังจากทำงานครบ 1 เดือน และหากลาออกระหว่างงวดจะไม่ได้รับสิทธิ์ในงวดนั้น',
                            style: TextStyle(fontSize: 12, color: Color(0xFF047857)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () async {
                    final allowance = stayOutside.toLowerCase() == 'yes'
                        ? (double.tryParse(housingCtrl.text) ?? 1000.0)
                        : 0.0;
                    final customDailyRate = wageType == 'Daily'
                        ? double.tryParse(dailyRateCtrl.text)
                        : null;
                    final updatedEmp = emp.copyWithWelfareSettings(
                      wageType: wageType,
                      dailyRate: customDailyRate,
                      stayOutside: stayOutside,
                      housingAllowance: allowance,
                    );

                    final index = _employees.indexWhere((e) => e.epCode == emp.epCode);
                    if (index != -1) {
                      setState(() {
                        _employees[index] = updatedEmp;
                      });
                    }

                    final messenger = ScaffoldMessenger.of(context);
                    Navigator.pop(ctx);

                    final success = await ApiService.saveEmployee(updatedEmp);
                    await _fetchDataAndRecalculate(reloadEmployees: true);

                    if (mounted) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            success
                                ? '✅ บันทึกประเภทการจ้างและสวัสดิการของ ${emp.nickname} เรียบร้อยแล้ว!'
                                : '⚠️ บันทึกข้อมูลเฉพาะเครื่องนี้ (Local)',
                          ),
                          backgroundColor: success ? const Color(0xFF10B981) : Colors.orange,
                        ),
                      );
                    }
                  },
                  child: const Text('บันทึกการตั้งค่า'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _toggleEmployeeStatus(Employee emp) async {
    final index = _employees.indexWhere((e) => e.epCode == emp.epCode);
    if (index != -1) {
      final newStatus = emp.isActive ? 'Resigned' : 'Active';
      final resignDate = newStatus == 'Resigned' ? (emp.resignDate ?? DateTime.now()) : null;

      setState(() {
        _employees[index] = emp.copyWith(
          status: newStatus,
          resignDate: resignDate,
        );
      });

      final messenger = ScaffoldMessenger.of(context);
      final success = await ApiService.updateEmployeeStatus(
        epCode: emp.epCode,
        status: newStatus,
        resignDate: resignDate,
      );

      await _fetchDataAndRecalculate(reloadEmployees: true);

      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? '✅ ${emp.nickname} status updated to $newStatus (Saved to Cloud Database)'
                  : '⚠️ Updated locally, cloud sync pending.',
            ),
            backgroundColor: success ? const Color(0xFF10B981) : Colors.orange,
          ),
        );
      }
    }
  }

  void _showSetPinDialog(Employee emp) {
    final pinCtrl = TextEditingController(text: emp.pin);
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('ตั้งรหัส PIN: ${emp.nickname} (${emp.epCode})'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'กำหนดรหัส PIN 4-6 หลัก สำหรับพนักงานเข้าใช้งาน Employee Portal ดูสลิปเงินเดือนและตารางวันหยุดของตนเอง',
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: pinCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: 'รหัส PIN (ตัวเลข 4-6 หลัก)',
                  hintText: 'เช่น 1234 หรือเลขท้าย 4 ตัว',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.pin),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final newPin = pinCtrl.text.trim();
                if (newPin.length < 4) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('กรุณากำหนดรหัส PIN อย่างน้อย 4 หลัก'), backgroundColor: Colors.orange),
                  );
                  return;
                }

                final updatedEmp = emp.copyWithPin(newPin);
                final index = _employees.indexWhere((e) => e.epCode == emp.epCode);
                if (index != -1) {
                  setState(() => _employees[index] = updatedEmp);
                }

                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(ctx);

                final success = await ApiService.saveEmployee(updatedEmp);
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        success
                            ? '✅ ตั้งรหัส PIN ของ ${emp.nickname} เป็น $newPin เรียบร้อยแล้ว (บันทึกลง Cloud Database)!'
                            : '⚠️ บันทึก PIN เฉพาะเครื่องนี้ (Local)',
                      ),
                      backgroundColor: success ? const Color(0xFF10B981) : Colors.orange,
                    ),
                  );
                }
              },
              child: const Text('บันทึก PIN'),
            ),
          ],
        );
      },
    );
  }
}

