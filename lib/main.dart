import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'data/initial_employees.dart';
import 'models/employee.dart';
import 'models/payroll_record.dart';
import 'services/api_service.dart';
import 'services/image_saver.dart';
import 'services/payroll_engine.dart';
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

  late List<Employee> _employees;
  List<String> _periods = [DateFormat('yyyy-MM').format(DateTime.now())];
  String _selectedPeriod = DateFormat('yyyy-MM').format(DateTime.now());
  String _selectedGroupFilter = 'All Groups';

  Map<String, PayrollRecord> _payrollRecords = {};
  List<Map<String, dynamic>> _attendanceLogs = [];
  List<Map<String, dynamic>> _adjustments = [];

  String? _selectedPayslipEp;

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
      _selectedPayslipEp = _employees.first.epCode;
    }

    await _fetchDataAndRecalculate();
  }

  Future<void> _fetchDataAndRecalculate() async {
    // Fetch real attendance and adjustments for this period
    final att = await ApiService.fetchAttendance(period: _selectedPeriod);
    final adj = await ApiService.fetchAdjustments(period: _selectedPeriod);

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

        if (empAtt.isNotEmpty) {
          rec.dayOff = empAtt.where((a) => a['category'] == 'Day-off').fold<double>(0.0, (sum, a) => sum + ((a['units'] as num?)?.toDouble() ?? 1.0)).round();
          rec.sickLeave = empAtt.where((a) => a['category'] == 'Sick').fold<double>(0.0, (sum, a) => sum + ((a['units'] as num?)?.toDouble() ?? 1.0)).round();
          rec.halfDays = empAtt.where((a) => a['category'] == 'Half-day').length;
          rec.otDays = empAtt.where((a) => a['category'] == 'OT Days').fold<double>(0.0, (sum, a) => sum + ((a['units'] as num?)?.toDouble() ?? 1.0)).round();
          if (!rec.isProrate) {
            rec.workDays = (30 - rec.dayOff - rec.sickLeave).clamp(0, 30);
          }
        }

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

        // Keep local overrides if any
        if (_payrollRecords.containsKey(emp.epCode)) {
          final old = _payrollRecords[emp.epCode]!;
          if (empAdj.isEmpty) {
            rec.overtimePay = old.overtimePay;
            rec.bonusPay = old.bonusPay;
            rec.otherExtra = old.otherExtra;
            rec.advanceDeduction = old.advanceDeduction;
            rec.workPermitDeduction = old.workPermitDeduction;
            rec.otherDeduction = old.otherDeduction;
          }
        }

        newRecords[emp.epCode] = rec;
      }
    }
    setState(() {
      _payrollRecords = newRecords;
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
              content: Text('✅ Synced ${res['total']} records to Excel sheet "Payroll_Summary" (Updated: ${res['updated']}, New: ${res['created']})'),
              backgroundColor: const Color(0xFF10B981),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ Failed to sync with Excel server. Ensure server.py is running.'),
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
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Row(
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
                          _isApiOnline ? 'REST API Connected' : 'Local Standalone Mode',
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
          // Current Date Badge (on the left of period selector)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.today_outlined, size: 16, color: Color(0xFF38BDF8)),
                const SizedBox(width: 8),
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
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Period Selector Dropdown (all 24 periods)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _periods.contains(_selectedPeriod) ? _selectedPeriod : _periods.first,
                dropdownColor: const Color(0xFF1E293B),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                items: _periods
                    .map((p) => DropdownMenuItem(value: p, child: Text('Period $p')))
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedPeriod = val);
                    _fetchDataAndRecalculate();
                  }
                },
              ),
            ),
          ),
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
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calculate_outlined),
            selectedIcon: Icon(Icons.calculate),
            label: 'Payroll Hub',
          ),
          NavigationDestination(
            icon: Icon(Icons.beach_access_outlined),
            selectedIcon: Icon(Icons.beach_access),
            label: 'Day-offs / Leave',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'Advances & Expenses',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Digital Payslip',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_alt_outlined),
            selectedIcon: Icon(Icons.people_alt),
            label: 'Employees',
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

    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
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
        ),
        Container(
          padding: const EdgeInsets.all(16),
          child: Wrap(
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
                                      Text(
                                        rec.nickname,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
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
                                          Text(
                                            'Prorate: ${rec.workedDays} days (@ ฿${(rec.dailyRate).toStringAsFixed(0)}/day) [${rec.prorateReason}]',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Color(0xFFC2410C),
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  Text(
                                    'Base: ฿${currency.format(rec.basePay)} | +Extra: ฿${currency.format(rec.totalExtra)} | -Ded: ฿${currency.format(rec.totalDeduction)} | Work: ${rec.workDays}d | Off: ${rec.dayOff}d${rec.sickLeave > 0 ? " | Sick: ${rec.sickLeave}d" : ""}${rec.otDays > 0 ? " | OT: ${rec.otDays}d" : ""}',
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
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
    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Attendance & Day-off Log (${_attendanceLogs.length} records)',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text(
                    'Period $_selectedPeriod • Logs sync directly with Excel Attendance_Log',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                ],
              ),
              const Spacer(),
              // View Mode Toggle (2-Month Planner vs List View)
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(
                    value: true,
                    label: Text('2-Month Planner'),
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
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () => _showLogAttendanceDialog(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                icon: const Icon(Icons.add_task, size: 18),
                label: const Text('Log Day-off / Leave / OT'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isAttendanceCalendarView
              ? TwoMonthCalendarPlanner(
                  period: _selectedPeriod,
                  attendanceLogs: _attendanceLogs,
                  onAddAttendance: (date) => _showLogAttendanceDialog(initialDate: date),
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
                        trailing: Text(
                          '${isIncome ? '+' : '-'}฿${currency.format(amt)}',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: isIncome ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                          ),
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

    PayrollRecord? record;
    if (_selectedPayslipEp != null && _payrollRecords.containsKey(_selectedPayslipEp)) {
      record = _payrollRecords[_selectedPayslipEp];
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      const Text('Select Employee: ', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: _selectedPayslipEp,
                            items: _payrollRecords.values.map((r) {
                              return DropdownMenuItem(
                                value: r.epCode,
                                child: Text('${r.epCode} - ${r.nickname} (${r.payGroup})'),
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
                ),
              ),
              const SizedBox(height: 16),
              if (record == null)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('Please select an employee to view payslip.'),
                  ),
                )
              else ...[
                RepaintBoundary(
                  key: _payslipKey,
                  child: Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
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
                                      const Text(
                                        'SIGNATURE PAYROLL',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'PAYSLIP / SALARY STATEMENT',
                                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B), letterSpacing: 0.5),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Period ${record.period}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 28),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
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
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0FDF4),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFBBF7D0)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildAttendanceItem(Icons.work_history_outlined, 'Work Days', '${record.workDays} days'),
                                _buildAttendanceItem(Icons.beach_access_outlined, 'Day-offs', '${record.dayOff} days'),
                                _buildAttendanceItem(Icons.healing_outlined, 'Sick Leave', '${record.sickLeave} days'),
                                _buildAttendanceItem(Icons.hourglass_bottom_outlined, 'Half-days', '${record.halfDays}'),
                                _buildAttendanceItem(Icons.more_time_outlined, 'OT Days', '${record.otDays}'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          if (record.isProrate)
                            Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(12),
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
                                      style: const TextStyle(fontSize: 12, color: Color(0xFFC2410C)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      '➕ Earnings',
                                      style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                                    ),
                                    const SizedBox(height: 8),
                                    _buildPayslipLine(
                                      record.isProrate ? 'Prorated Base Pay' : 'Base Salary',
                                      '฿${currency.format(record.basePay)}',
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
                                ),
                              ),
                              const SizedBox(width: 24),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      '➖ Deductions',
                                      style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFEF4444)),
                                    ),
                                    const SizedBox(height: 8),
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
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Container(
                            padding: const EdgeInsets.all(16),
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
                                Text(
                                  '฿${currency.format(record.netPay)}',
                                  style: const TextStyle(
                                    color: Color(0xFF38BDF8),
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
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
                const SizedBox(height: 20),
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
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: _isExportingImage
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.image),
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
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('Copy for LINE', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _showEditAdjustmentsDialog(record!),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.tune),
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
                        'Group: ${emp.payGroup}  |  Base Salary: ฿${currency.format(emp.baseSalary)}  |  Stay Outside: ${emp.stayOutside}',
                        style: const TextStyle(fontSize: 12),
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
                      }
                    },
                    itemBuilder: (context) => [
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
  // DIALOGS: ADD ATTENDANCE, ADD ADJUSTMENT, ADD EMPLOYEE
  // ===========================================================================

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
    return Column(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF16A34A)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF475569))),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF166534))),
      ],
    );
  }

  Widget _buildPayslipLine(String label, String value, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: const Color(0xFF475569),
            ),
          ),
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
  }) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
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
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(icon, size: 16, color: color),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
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
                  const Text('➖ Deductions (THB)', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFEF4444))),
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
              onPressed: () {
                setState(() {
                  record.workDays = int.tryParse(workDaysCtrl.text) ?? record.workDays;
                  record.dayOff = int.tryParse(dayOffCtrl.text) ?? record.dayOff;
                  record.sickLeave = int.tryParse(sickCtrl.text) ?? record.sickLeave;
                  record.halfDays = int.tryParse(halfCtrl.text) ?? record.halfDays;
                  record.otDays = int.tryParse(otDaysCtrl.text) ?? record.otDays;

                  record.overtimePay = double.tryParse(otCtrl.text) ?? 0;
                  record.bonusPay = double.tryParse(bonusCtrl.text) ?? 0;
                  record.otherExtra = double.tryParse(otherExtraCtrl.text) ?? 0;
                  record.extraNote = extraNoteCtrl.text;

                  record.advanceDeduction = double.tryParse(advanceCtrl.text) ?? 0;
                  record.workPermitDeduction = double.tryParse(wpCtrl.text) ?? 0;
                  record.otherDeduction = double.tryParse(otherDedCtrl.text) ?? 0;
                  record.deductionNote = dedNoteCtrl.text;
                });
                Navigator.pop(ctx);
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
    String payGroup = 'Date : 10';
    DateTime? startDate;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add New Employee'),
              content: SizedBox(
                width: 400,
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
                    TextField(
                      controller: salaryCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Base Salary (THB)'),
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
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        startDate == null
                            ? 'Set Start Date (For auto Smart Prorate)'
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
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () {
                    if (nameCtrl.text.isNotEmpty) {
                      final newEmp = Employee(
                        epCode: epCtrl.text,
                        nickname: nameCtrl.text,
                        status: 'Active',
                        baseSalary: double.tryParse(salaryCtrl.text) ?? 12000,
                        payGroup: payGroup,
                        startDate: startDate,
                      );
                      setState(() {
                        _employees.add(newEmp);
                      });
                      _fetchDataAndRecalculate();
                      Navigator.pop(ctx);
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
                  onPressed: () {
                    final index = _employees.indexWhere((e) => e.epCode == emp.epCode);
                    if (index != -1) {
                      setState(() {
                        _employees[index] = emp.copyWith(
                          startDate: start,
                          resignDate: resign,
                          status: resign != null ? 'Resigned' : emp.status,
                        );
                      });
                      _fetchDataAndRecalculate();
                    }
                    Navigator.pop(ctx);
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

  void _toggleEmployeeStatus(Employee emp) {
    final index = _employees.indexWhere((e) => e.epCode == emp.epCode);
    if (index != -1) {
      final newStatus = emp.isActive ? 'Resigned' : 'Active';
      setState(() {
        _employees[index] = emp.copyWith(
          status: newStatus,
          resignDate: newStatus == 'Resigned' ? (emp.resignDate ?? DateTime.now()) : null,
        );
      });
      _fetchDataAndRecalculate();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${emp.nickname} status updated to $newStatus'),
        ),
      );
    }
  }
}
