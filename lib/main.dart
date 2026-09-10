import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'data/initial_employees.dart';
import 'models/employee.dart';
import 'models/payroll_record.dart';
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
          seedColor: const Color(0xFF0284C7), // Ocean Cyan / Deep Navy
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

  // รายชื่อพนักงานในระบบ (เริ่มต้นจาก 31 คนใน Excel)
  late List<Employee> _employees;

  // งวดปัจจุบัน
  String _selectedPeriod = '2025-01';
  String _selectedGroupFilter = 'ทั้งหมด'; // 'ทั้งหมด', 'Date : 1', 'Date : 10', 'Date : 20'

  // บันทึกรายการเงินเดือนที่คำนวณและปรับแต่งแล้ว
  Map<String, PayrollRecord> _payrollRecords = {};

  // พนักงานที่กำลังเปิดดูสลิป
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
        // ถ้ารายการเดิมมีการใส่ OT/เบิกเงินไว้ ให้คงไว้
        if (_payrollRecords.containsKey(emp.epCode)) {
          final old = _payrollRecords[emp.epCode]!;
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
      if (_selectedGroupFilter == 'ทั้งหมด') return true;
      return r.payGroup == _selectedGroupFilter;
    }).toList();
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
                  'ระบบบริหารเงินเดือนและ Smart Prorate',
                  style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // เลือกงวด
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
                    .map((p) => DropdownMenuItem(value: p, child: Text('งวด $p')))
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
            label: 'คำนวณเงินเดือน',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'สลิปเงินเดือน',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_alt_outlined),
            selectedIcon: Icon(Icons.people_alt),
            label: 'ทะเบียนพนักงาน',
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
        // แถบเลือกรอบจ่าย
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('ทั้งหมด'),
                const SizedBox(width: 8),
                _buildFilterChip('Date : 1', subtitle: '2 ก่อนหน้า - 1 นี้'),
                const SizedBox(width: 8),
                _buildFilterChip('Date : 10', subtitle: '11 ก่อนหน้า - 10 นี้'),
                const SizedBox(width: 8),
                _buildFilterChip('Date : 20', subtitle: '21 ก่อนหน้า - 20 นี้'),
              ],
            ),
          ),
        ),

        // กล่องสรุปภาพรวมการเงิน (KPI Cards)
        Container(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _buildSummaryCard(
                    title: 'ยอดจ่ายสุทธิทั้งหมด',
                    value: '฿${currency.format(totalNet)}',
                    color: const Color(0xFF0284C7),
                    icon: Icons.payments,
                    subtitle: 'พนักงานในรอบนี้ ${records.length} คน',
                  ),
                  _buildSummaryCard(
                    title: 'ค่าจ้างฐาน + Prorate',
                    value: '฿${currency.format(totalBase)}',
                    color: const Color(0xFF334155),
                    icon: Icons.account_balance_wallet,
                    subtitle: prorateCount > 0 ? '⚠️ คิดเฉลี่ย Prorate $prorateCount คน' : 'ทำงานเต็มงวดทุกคน',
                  ),
                  _buildSummaryCard(
                    title: 'รายได้เสริม (+)',
                    value: '+฿${currency.format(totalExtra)}',
                    color: const Color(0xFF10B981),
                    icon: Icons.trending_up,
                    subtitle: 'OT, โบนัส, เบี้ยขยัน',
                  ),
                  _buildSummaryCard(
                    title: 'รายการหัก (-)',
                    value: '-฿${currency.format(totalDeduction)}',
                    color: const Color(0xFFEF4444),
                    icon: Icons.trending_down,
                    subtitle: 'เบิก, ค่า Work Permit',
                  ),
                ],
              );
            },
          ),
        ),

        // รายการพนักงานในรอบ
        Expanded(
          child: records.isEmpty
              ? const Center(child: Text('ไม่มีพนักงานในรอบจ่ายที่เลือก'))
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
                            // Avatar
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

                            // รายละเอียด
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

                                  // Badge กรณี Prorate
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
                                            'Prorate: ${rec.workedDays} วัน (วันละ ฿${(rec.dailyRate).toStringAsFixed(0)}) [${rec.prorateReason}]',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Color(0xFFC2410C),
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                  // สรุปตัวเลข
                                  Text(
                                    'ฐาน: ฿${currency.format(rec.basePay)}  |  เพิ่ม: +฿${currency.format(rec.totalExtra)}  |  หัก: -฿${currency.format(rec.totalDeduction)}',
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                  ),
                                ],
                              ),
                            ),

                            // ยอดสุทธิ และปุ่มแอ็กชัน
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
                                      tooltip: 'แก้ไขรายการเพิ่ม/หัก',
                                      icon: const Icon(Icons.edit_note, color: Color(0xFF0284C7)),
                                      onPressed: () => _showEditAdjustmentsDialog(rec),
                                      constraints: const BoxConstraints(),
                                      padding: const EdgeInsets.all(6),
                                    ),
                                    IconButton(
                                      tooltip: 'ดูสลิปเงินเดือน',
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
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
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
          constraints: const BoxConstraints(maxWidth: 650),
          child: Column(
            children: [
              // เมนูเลือกพนักงาน
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      const Text('เลือกพนักงาน: ', style: TextStyle(fontWeight: FontWeight.bold)),
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
                    child: Text('กรุณาเลือกพนักงานเพื่อแสดงสลิป'),
                  ),
                )
              else ...[
                // ตัวสลิปเงินเดือนแบบสวยงาม
                Card(
                  elevation: 3,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // หัวสลิป
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
                                  'ใบแจ้งยอดเงินเดือน / PAYSLIP',
                                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'งวด ${record.period}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 32),

                        // ข้อมูลพนักงานและรอบการจ่าย
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
                                    'ชื่อพนักงาน: ${record.nickname} (${record.epCode})',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'กลุ่ม: ${record.payGroup}',
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'รอบงาน: ${df.format(record.cycleStartDate)} - ${df.format(record.cycleEndDate)}',
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'วันจ่าย: ${df.format(record.payDate)}',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF0284C7)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // แจ้งเตือน Prorate ถ้ามี
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
                                    'งวดนี้คิดค่าแรงตามสัดส่วน (Prorate) จำนวน ${record.workedDays} วัน (วันละ ฿${currency.format(record.dailyRate)}) • สาเหตุ: ${record.prorateReason}',
                                    style: const TextStyle(fontSize: 12, color: Color(0xFFC2410C)),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // ตารางแจกแจงรายรับ และ รายการหัก
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ฝั่งรายรับ
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '➕ รายการได้ (Earnings)',
                                    style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                                  ),
                                  const SizedBox(height: 8),
                                  _buildPayslipLine(
                                    record.isProrate ? 'ค่าจ้างตามสัดส่วน' : 'เงินเดือนฐาน',
                                    '฿${currency.format(record.basePay)}',
                                  ),
                                  if (record.overtimePay > 0)
                                    _buildPayslipLine('ค่าล่วงเวลา (OT)', '+฿${currency.format(record.overtimePay)}'),
                                  if (record.bonusPay > 0)
                                    _buildPayslipLine('เบี้ยขยัน / โบนัส', '+฿${currency.format(record.bonusPay)}'),
                                  if (record.otherExtra > 0)
                                    _buildPayslipLine('รายได้พิเศษอื่นๆ', '+฿${currency.format(record.otherExtra)}'),
                                  const Divider(height: 16),
                                  _buildPayslipLine(
                                    'รวมเงินได้',
                                    '฿${currency.format(record.basePay + record.totalExtra)}',
                                    isBold: true,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 24),

                            // ฝั่งรายการหัก
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '➖ รายการหัก (Deductions)',
                                    style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFEF4444)),
                                  ),
                                  const SizedBox(height: 8),
                                  _buildPayslipLine(
                                    'เงินเบิกล่วงหน้า',
                                    record.advanceDeduction > 0 ? '-฿${currency.format(record.advanceDeduction)}' : '฿0.00',
                                  ),
                                  _buildPayslipLine(
                                    'ค่า Work Permit/Passport',
                                    record.workPermitDeduction > 0 ? '-฿${currency.format(record.workPermitDeduction)}' : '฿0.00',
                                  ),
                                  if (record.otherDeduction > 0)
                                    _buildPayslipLine('รายการหักอื่นๆ', '-฿${currency.format(record.otherDeduction)}'),
                                  const Divider(height: 16),
                                  _buildPayslipLine(
                                    'รวมรายการหัก',
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

                        // ยอดสุทธิ (Net Pay Highlight)
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
                                    'ยอดรับสุทธิ (NET PAY)',
                                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    'ไม่มีการหักประกันสังคม',
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
                const SizedBox(height: 20),

                // ปุ่มแอ็กชัน
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () {
                        final text = PayrollEngine.formatLinePayslip(record!);
                        Clipboard.setData(ClipboardData(text: text));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('✅ คัดลอกข้อความสลิปสำหรับส่ง LINE เรียบร้อยแล้ว!'),
                            backgroundColor: Color(0xFF10B981),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF06C755), // LINE Green
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('คัดลอกส่ง LINE (Copy for LINE)', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: () => _showEditAdjustmentsDialog(record!),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.tune),
                      label: const Text('ปรับยอดเงินได้/หัก'),
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
        // แถบสถิติพนักงาน
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text(
                'พนักงานทั้งหมด (${_employees.length} คน)',
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
                  'ทำงานอยู่: $activeCount',
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
                  'ลาออกแล้ว: $resignedCount',
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
                label: const Text('เพิ่มพนักงานใหม่'),
              ),
            ],
          ),
        ),

        // รายการพนักงาน
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
                        'รอบจ่าย: ${emp.payGroup}  |  เงินเดือนฐาน: ฿${currency.format(emp.baseSalary)}  |  พักข้างนอก: ${emp.stayOutside}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      if (emp.startDate != null)
                        Text(
                          '📅 วันเริ่มงาน: ${df.format(emp.startDate!)}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF0284C7)),
                        ),
                      if (emp.resignDate != null)
                        Text(
                          '🚪 วันลาออก: ${df.format(emp.resignDate!)}',
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
                            Text('กำหนดวันเริ่ม/วันลาออก (Prorate)'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'toggle_status',
                        child: Row(
                          children: [
                            Icon(emp.isActive ? Icons.person_off : Icons.person, size: 18),
                            SizedBox(width: 8),
                            Text(emp.isActive ? 'ปรับเป็นลาออก (Resigned)' : 'ปรับเป็นทำงานอยู่ (Active)'),
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
          title: Text('ปรับรายการเงินได้/หัก: ${record.nickname} (${record.epCode})'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 480,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('➕ รายรับเสริม (บาท)', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                  const SizedBox(height: 8),
                  TextField(
                    controller: otCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'ค่าล่วงเวลา (OT)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: bonusCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'เบี้ยขยัน / โบนัส', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: otherExtraCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'เงินเพิ่มอื่นๆ', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: extraNoteCtrl,
                    decoration: const InputDecoration(labelText: 'หมายเหตุเงินเพิ่ม', border: OutlineInputBorder()),
                  ),
                  const Divider(height: 24),

                  const Text('➖ รายการหัก (บาท)', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFEF4444))),
                  const SizedBox(height: 8),
                  TextField(
                    controller: advanceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'เงินเบิกล่วงหน้า', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: wpCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'ค่าเอกสาร Work Permit / Passport', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: otherDedCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'รายการหักอื่นๆ', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: dedNoteCtrl,
                    decoration: const InputDecoration(labelText: 'หมายเหตุรายการหัก', border: OutlineInputBorder()),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ยกเลิก'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
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
              child: const Text('บันทึก'),
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
              title: const Text('เพิ่มพนักงานใหม่'),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: epCtrl,
                      decoration: const InputDecoration(labelText: 'รหัสพนักงาน (EP Code)'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'ชื่อเล่น (Nickname)'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: salaryCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'เงินเดือนฐาน (บาท)'),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: payGroup,
                      decoration: const InputDecoration(labelText: 'รอบจ่ายเงินเดือน'),
                      items: const [
                        DropdownMenuItem(value: 'Date : 1', child: Text('รอบวันที่ 1 (2 ก่อนหน้า - 1 นี้)')),
                        DropdownMenuItem(value: 'Date : 10', child: Text('รอบวันที่ 10 (11 ก่อนหน้า - 10 นี้)')),
                        DropdownMenuItem(value: 'Date : 20', child: Text('รอบวันที่ 20 (21 ก่อนหน้า - 20 นี้)')),
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
                            ? 'กำหนดวันเริ่มงาน (เพื่อคิด Prorate อัตโนมัติ)'
                            : 'วันเริ่มงาน: ${DateFormat('dd/MM/yyyy').format(startDate!)}',
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
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
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
                  child: const Text('เพิ่มพนักงาน'),
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
              title: Text('กำหนดวันเข้างาน / ลาออก: ${emp.nickname}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: Text(start == null ? 'ยังไม่ได้ระบุวันเริ่มงาน' : 'วันเริ่มงาน: ${df.format(start!)}'),
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
                    title: Text(resign == null ? 'ยังไม่ได้ระบุวันลาออก' : 'วันลาออก: ${df.format(resign!)}'),
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
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
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
                  child: const Text('บันทึก'),
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
          content: Text('เปลี่ยนสถานะ ${emp.nickname} เป็น $newStatus เรียบร้อยแล้ว'),
        ),
      );
    }
  }
}
