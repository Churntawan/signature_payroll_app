import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'data/initial_employees.dart';
import 'models/employee.dart';
import 'models/payroll_record.dart';
import 'services/image_saver.dart';
import 'services/payroll_engine.dart';

void main() {
  runApp(const SignaturePayrollApp());
}

class SignaturePayrollApp extends StatelessWidget {
  const SignaturePayrollApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Signature Payroll',
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

  // Key for capturing the payslip as an image
  final GlobalKey _payslipKey = GlobalKey();
  bool _isExportingImage = false;

  // List of employees (starts with 31 from Excel)
  late List<Employee> _employees;

  // Current period and filter
  String _selectedPeriod = '2025-01';
  String _selectedGroupFilter = 'All Groups'; // 'All Groups', 'Date : 1', 'Date : 10', 'Date : 20'

  // Payroll records map (key: epCode)
  Map<String, PayrollRecord> _payrollRecords = {};

  // Selected employee for payslip view
  String? _selectedPayslipEp;

  @override
  void initState() {
    super.initState();
    _employees = List.from(initialEmployees);
    _recalculatePayroll();
    if (_employees.isNotEmpty) {
      _selectedPayslipEp = _employees.first.epCode;
    }
  }

  void _recalculatePayroll() {
    final Map<String, PayrollRecord> newRecords = {};
    for (final emp in _employees) {
      final rec = PayrollEngine.calculateEmployeeRecord(
        employee: emp,
        period: _selectedPeriod,
      );
      if (rec != null) {
        if (_payrollRecords.containsKey(emp.epCode)) {
          final old = _payrollRecords[emp.epCode]!;
          rec.workDays = old.workDays;
          rec.dayOff = old.dayOff;
          rec.sickLeave = old.sickLeave;
          rec.halfDays = old.halfDays;
          rec.otDays = old.otDays;
          rec.overtimePay = old.overtimePay;
          rec.bonusPay = old.bonusPay;
          rec.otherExtra = old.otherExtra;
          rec.extraNote = old.extraNote;
          rec.advanceDeduction = old.advanceDeduction;
          rec.workPermitDeduction = old.workPermitDeduction;
          rec.otherDeduction = old.otherDeduction;
          rec.deductionNote = old.deductionNote;
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

  // Save payslip as PNG image
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
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SIGNATURE PAYROLL',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
                Text(
                  'Smart Prorate & Payroll Management Suite',
                  style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                ),
              ],
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedPeriod,
                dropdownColor: const Color(0xFF1E293B),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                items: ['2025-01', '2025-02', '2025-03', '2025-04', '2025-05', '2025-06']
                    .map((p) => DropdownMenuItem(value: p, child: Text('Period $p')))
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedPeriod = val;
                      _recalculatePayroll();
                    });
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
          _buildPayslipView(),
          _buildEmployeesDirectory(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTab,
        onDestinationSelected: (idx) {
          setState(() {
            _currentTab = idx;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calculate_outlined),
            selectedIcon: Icon(Icons.calculate),
            label: 'Payroll Hub',
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
        // Pay Cycle Filter Bar
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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

        // KPI Summary Cards
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

        // Employee Payroll Records List
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
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
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
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF0369A1),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),

                                  // Smart Prorate indicator badge
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
                                    'Base: ฿${currency.format(rec.basePay)}  |  Extra: +฿${currency.format(rec.totalExtra)}  |  Ded: -฿${currency.format(rec.totalDeduction)}  |  Work: ${rec.workDays}d  Off: ${rec.dayOff}d',
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
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F172A),
                                  ),
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
                                          _currentTab = 1;
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
        setState(() {
          _selectedGroupFilter = label;
        });
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
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
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

  // ===========================================================================
  // TAB 2: DIGITAL PAYSLIP VIEWER
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
              // Employee Selector Card
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
                              if (val != null) {
                                setState(() {
                                  _selectedPayslipEp = val;
                                });
                              }
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
                // The Payslip Widget wrapped with RepaintBoundary for PNG Export
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
                          // Header
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

                          // Employee Info Box
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

                          // NEW: Attendance & Time-off / Day-offs Section
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0FDF4), // Gentle green
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

                          // Smart Prorate Banner
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

                          // Earnings vs Deductions Columns
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Earnings
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

                              // Deductions
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

                          // Net Pay Banner
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

                // Action Buttons: Save as Image, Copy for LINE, Adjustments
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    // Save as Image (PNG)
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

                    // Copy for LINE
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

                    // Adjust Pay & Attendance
                    OutlinedButton.icon(
                      onPressed: () => _showEditAdjustmentsDialog(record!),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.tune),
                      label: const Text('Adjust Pay & Attendance'),
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

  // ===========================================================================
  // TAB 3: EMPLOYEES DIRECTORY
  // ===========================================================================
  Widget _buildEmployeesDirectory() {
    final currency = NumberFormat('#,##0.00', 'en_US');
    final activeCount = _employees.where((e) => e.isActive).length;
    final resignedCount = _employees.where((e) => !e.isActive).length;

    return Column(
      children: [
        // Employee Directory Header
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

        // Employees List
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
                      Text(
                        '(${emp.epCode})',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
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
                        Text(
                          '📝 ${emp.note}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                        ),
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
  // DIALOGS & ACTIONS
  // ===========================================================================

  void _showEditAdjustmentsDialog(PayrollRecord record) {
    // Attendance Controllers
    final workDaysCtrl = TextEditingController(text: record.workDays.toString());
    final dayOffCtrl = TextEditingController(text: record.dayOff.toString());
    final sickCtrl = TextEditingController(text: record.sickLeave.toString());
    final halfCtrl = TextEditingController(text: record.halfDays.toString());
    final otDaysCtrl = TextEditingController(text: record.otDays.toString());

    // Financial Controllers
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
                  // Attendance Section
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

                  // Earnings Section
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

                  // Deductions Section
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
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
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
                          if (picked != null) {
                            setDialogState(() => startDate = picked);
                          }
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
                        _recalculatePayroll();
                      });
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
                            if (picked != null) {
                              setDialogState(() => start = picked);
                            }
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
                            if (picked != null) {
                              setDialogState(() => resign = picked);
                            }
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
                        _recalculatePayroll();
                      });
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
        _recalculatePayroll();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${emp.nickname} status updated to $newStatus'),
        ),
      );
    }
  }
}
