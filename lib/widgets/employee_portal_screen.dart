import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/employee.dart';
import '../models/payroll_record.dart';
import '../services/api_service.dart';
import '../services/image_saver.dart';
import '../services/payroll_engine.dart';

class EmployeePortalScreen extends StatefulWidget {
  final Employee employee;
  final List<String> periods;
  final VoidCallback onLogout;

  const EmployeePortalScreen({
    super.key,
    required this.employee,
    required this.periods,
    required this.onLogout,
  });

  @override
  State<EmployeePortalScreen> createState() => _EmployeePortalScreenState();
}

class _EmployeePortalScreenState extends State<EmployeePortalScreen> {
  int _currentTab = 0; // 0 = Payslip, 1 = Attendance Schedule
  late String _selectedPeriod;
  bool _isLoading = false;
  bool _isExporting = false;
  final GlobalKey _payslipKey = GlobalKey();

  List<Map<String, dynamic>> _employeeAttendance = [];
  List<Map<String, dynamic>> _employeeAdjustments = [];
  PayrollRecord? _currentRecord;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final currentPeriodStr = DateFormat('yyyy-MM').format(now);
    if (widget.periods.contains(currentPeriodStr)) {
      _selectedPeriod = currentPeriodStr;
    } else if (widget.periods.isNotEmpty) {
      _selectedPeriod = widget.periods.first;
    } else {
      _selectedPeriod = '2026-09';
    }

    _fetchEmployeeData();
  }

  Future<void> _fetchEmployeeData() async {
    setState(() => _isLoading = true);

    try {
      // Fetch attendance and adjustments specifically for this employee and period
      final att = await ApiService.fetchAttendance(
        period: _selectedPeriod,
        epCode: widget.employee.epCode,
      );
      final adj = await ApiService.fetchAdjustments(
        period: _selectedPeriod,
        epCode: widget.employee.epCode,
      );

      final rec = PayrollEngine.calculateEmployeeRecord(
        employee: widget.employee,
        period: _selectedPeriod,
      );

      if (rec != null) {
        // Filter attendance strictly within this cycle
        final cycleAtt = att.where((a) {
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

        PayrollEngine.applyAttendance(rec, cycleAtt);

        // Apply adjustments
        for (final a in adj) {
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

        setState(() {
          _currentRecord = rec;
          _employeeAttendance = cycleAtt;
          _employeeAdjustments = adj;
        });
      } else {
        setState(() {
          _currentRecord = null;
          _employeeAttendance = [];
          _employeeAdjustments = [];
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Check if the pay date for the selected record has arrived today or in the past
  bool _isPayDateArrived(PayrollRecord rec) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final payDay = DateTime(rec.payDate.year, rec.payDate.month, rec.payDate.day);
    return today.isAtSameMomentAs(payDay) || today.isAfter(payDay);
  }

  Future<void> _downloadPayslipImage() async {
    if (_currentRecord == null) return;
    setState(() => _isExporting = true);
    try {
      await Future.delayed(const Duration(milliseconds: 100));
      final boundary = _payslipKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      final ui.Image image = await boundary.toImage(pixelRatio: 2.5);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        final Uint8List pngBytes = byteData.buffer.asUint8List();
        final fileName = 'payslip_${_currentRecord!.epCode}_${_currentRecord!.nickname}_${_currentRecord!.period}.png';
        ImageSaver.savePng(pngBytes, fileName);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ บันทึกรูปภาพสลิปเงินเดือนเรียบร้อยแล้ว ($fileName)'),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการบันทึกรูป: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
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
              child: const Icon(Icons.person, size: 18, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${widget.employee.nickname} (${widget.employee.epCode})',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'พนักงาน • ${widget.employee.payGroup}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // Period Selector
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: widget.periods.contains(_selectedPeriod) ? _selectedPeriod : widget.periods.first,
                dropdownColor: const Color(0xFF0F172A),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                items: widget.periods.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                onChanged: (val) {
                  if (val != null && val != _selectedPeriod) {
                    setState(() => _selectedPeriod = val);
                    _fetchEmployeeData();
                  }
                },
              ),
            ),
          ),

          // Logout Button
          IconButton(
            icon: const Icon(Icons.logout, size: 20, color: Color(0xFFEF4444)),
            tooltip: 'ออกจากระบบ (Logout)',
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF1E293B),
                  title: const Text('ยืนยันออกจากระบบ', style: TextStyle(color: Colors.white)),
                  content: const Text('คุณต้องการออกจากระบบใช่หรือไม่?', style: TextStyle(color: Color(0xFFCBD5E1))),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                      onPressed: () {
                        Navigator.pop(ctx);
                        widget.onLogout();
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8)))
          : IndexedStack(
              index: _currentTab,
              children: [
                _buildPayslipTab(isMobile),
                _buildScheduleTab(isMobile),
              ],
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTab,
        backgroundColor: const Color(0xFF1E293B),
        indicatorColor: const Color(0xFF0284C7).withOpacity(0.3),
        onDestinationSelected: (idx) => setState(() => _currentTab = idx),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined, color: Color(0xFF94A3B8)),
            selectedIcon: Icon(Icons.receipt_long, color: Color(0xFF38BDF8)),
            label: 'สลิปเงินเดือน',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined, color: Color(0xFF94A3B8)),
            selectedIcon: Icon(Icons.calendar_month, color: Color(0xFF38BDF8)),
            label: 'ตารางวันหยุด & เวลา',
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // TAB 1: PAYSLIP (With Pay Date Protection)
  // ===========================================================================
  Widget _buildPayslipTab(bool isMobile) {
    final currency = NumberFormat('#,##0.00', 'en_US');
    final df = DateFormat('dd/MM/yyyy');

    if (_currentRecord == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.person_off_outlined, size: 56, color: Color(0xFF64748B)),
              const SizedBox(height: 16),
              Text(
                'ไม่มีข้อมูลการทำงานในงวด $_selectedPeriod',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'คุณอาจยังไม่เริ่มงานหรือพ้นสภาพการทำงานก่อนเริ่มรอบงวดนี้',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final rec = _currentRecord!;
    final payDateArrived = _isPayDateArrived(rec);

    // If pay date has NOT arrived yet, protect payslip from early exposure
    if (!payDateArrived) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              color: const Color(0xFF1E293B),
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFF334155)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.hourglass_top_rounded, size: 48, color: Color(0xFFF59E0B)),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'สลิปเงินเดือนงวด ${rec.period}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'รอบการทำงาน: ${df.format(rec.cycleStartDate)} - ${df.format(rec.cycleEndDate)}',
                      style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.event_available, size: 18, color: Color(0xFF38BDF8)),
                              const SizedBox(width: 8),
                              const Text('กำหนดจ่ายรอบเงินเดือน:', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13)),
                              const SizedBox(width: 6),
                              Text(
                                df.format(rec.payDate),
                                style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            '🔒 ยอดเงินเดือนอยู่ระหว่างการคำนวณและปรับปรุงรอบงวด\nระบบจะเปิดให้ตรวจสอบสลิปเงินเดือนได้เมื่อถึงกำหนดวันจ่ายเงินเดือนครับ',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5, height: 1.5),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _currentTab = 1),
                      icon: const Icon(Icons.calendar_month, size: 16),
                      label: const Text('ดูตารางวันหยุด & วันทำงานที่บันทึกไว้'),
                      style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF38BDF8)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Pay date HAS arrived: Display full payslip with download button
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 24, vertical: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: Column(
            children: [
              // Download Action Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF10B981)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle, size: 14, color: Color(0xFF10B981)),
                        const SizedBox(width: 6),
                        Text(
                          'ชำระแล้วเมื่อ ${df.format(rec.payDate)}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isExporting ? null : _downloadPayslipImage,
                    icon: _isExporting
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.download, size: 16),
                    label: const Text('บันทึกรูปสลิป', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // The Printable / Downloadable Payslip Container
              RepaintBoundary(
                key: _payslipKey,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.diamond_outlined, size: 24, color: Colors.white),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('SIGNATURE RESORT & SPA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A))),
                                Text('PAYSLIP / ใบแจ้งเงินเดือน (${rec.period})', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24, thickness: 1.2),

                      // Employee Profile
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          children: [
                            _buildInfoRow('รหัสพนักงาน (Code):', '${rec.epCode} - ${rec.nickname}'),
                            const SizedBox(height: 4),
                            _buildInfoRow('กลุ่มการจ่าย (Pay Group):', rec.payGroup),
                            const SizedBox(height: 4),
                            _buildInfoRow('รอบการทำงาน (Cycle):', '${df.format(rec.cycleStartDate)} - ${df.format(rec.cycleEndDate)}'),
                            const SizedBox(height: 4),
                            _buildInfoRow('วันที่จ่าย (Pay Date):', df.format(rec.payDate)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Attendance Badges
                      Row(
                        children: [
                          Expanded(child: _buildBadgeCard('วันทำงาน', '${rec.workDays} วัน', const Color(0xFFE0F2FE), const Color(0xFF0369A1))),
                          const SizedBox(width: 8),
                          Expanded(child: _buildBadgeCard('วันหยุด', '${rec.dayOff} วัน', const Color(0xFFF1F5F9), const Color(0xFF475569))),
                          const SizedBox(width: 8),
                          Expanded(child: _buildBadgeCard('ลาป่วย', '${rec.sickLeave} วัน', const Color(0xFFFEF3C7), const Color(0xFFB45309))),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Earnings Section
                      const Text('รายได้ (EARNINGS)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF16A34A))),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: const Color(0xFFF0FDF4), borderRadius: BorderRadius.circular(8)),
                        child: Column(
                          children: [
                            _buildAmountRow('เงินเดือน / ค่าจ้างฐาน', rec.basePay, currency),
                            if (rec.housingAllowance > 0) ...[
                              const SizedBox(height: 4),
                              _buildAmountRow('ค่าห้องพัก (Housing)', rec.housingAllowance, currency),
                            ],
                            if (rec.overtimePay > 0) ...[
                              const SizedBox(height: 4),
                              _buildAmountRow('ค่าล่วงเวลา (OT)', rec.overtimePay, currency),
                            ],
                            if (rec.bonusPay > 0) ...[
                              const SizedBox(height: 4),
                              _buildAmountRow('โบนัส / เบี้ยขยัน', rec.bonusPay, currency),
                            ],
                            if (rec.otherExtra > 0) ...[
                              const SizedBox(height: 4),
                              _buildAmountRow('รายรับอื่นๆ', rec.otherExtra, currency),
                            ],
                            const Divider(height: 12),
                            _buildAmountRow('รวมรายรับทั้งสิ้น', rec.basePay + rec.totalExtra, currency, isBold: true),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Deductions Section
                      const Text('รายการหัก (DEDUCTIONS)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFDC2626))),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(8)),
                        child: Column(
                          children: [
                            if (rec.advanceDeduction > 0) ...[
                              _buildAmountRow('หักเงินเบิกล่วงหน้า (Advance)', rec.advanceDeduction, currency, isDeduct: true),
                              const SizedBox(height: 4),
                            ],
                            if (rec.workPermitDeduction > 0) ...[
                              _buildAmountRow('หักค่าเอกสาร/พาสปอร์ต', rec.workPermitDeduction, currency, isDeduct: true),
                              const SizedBox(height: 4),
                            ],
                            if (rec.excessDayOffDeduction > 0) ...[
                              _buildAmountRow('หักหยุดเกินโควตา (${rec.excessDayOffDays} วัน)', rec.excessDayOffDeduction, currency, isDeduct: true),
                              const SizedBox(height: 4),
                            ],
                            if (rec.otherDeduction > 0) ...[
                              _buildAmountRow('หักรายการอื่นๆ', rec.otherDeduction, currency, isDeduct: true),
                              const SizedBox(height: 4),
                            ],
                            if (rec.totalDeduction == 0)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 4),
                                child: Text('ไม่มีรายการหักเงินในงวดนี้', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                              ),
                            const Divider(height: 12),
                            _buildAmountRow('รวมรายการหักทั้งสิ้น', rec.totalDeduction, currency, isDeduct: true, isBold: true),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Net Pay Highlight
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF0F172A), Color(0xFF1E293B)]),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('ยอดรับสุทธิ', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                                Text('NET SALARY (THB)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                              ],
                            ),
                            Text(
                              '฿${currency.format(rec.netPay)}',
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // TAB 2: ATTENDANCE & PLANNER (Strictly Read-Only)
  // ===========================================================================
  Widget _buildScheduleTab(bool isMobile) {
    final df = DateFormat('dd/MM/yyyy');
    final dayNames = ['จันทร์', 'อังคาร', 'พุธ', 'พฤหัสบดี', 'ศุกร์', 'เสาร์', 'อาทิตย์'];

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 24, vertical: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Card
              Card(
                color: const Color(0xFF1E293B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.event_note, color: Color(0xFF38BDF8), size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'บันทึกวันหยุดและเวลาทำงาน (${widget.employee.nickname})',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'งวดเดือน: $_selectedPeriod  •  ดูได้อย่างเดียว (Read-Only)',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Summary Stats
              if (_currentRecord != null)
                Row(
                  children: [
                    Expanded(
                      child: _buildScheduleStatCard('วันทำงานทั้งหมด', '${_currentRecord!.workDays}', 'วัน', const Color(0xFF0284C7)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildScheduleStatCard('วันหยุดที่จัดไว้', '${_currentRecord!.dayOff}', 'วัน', const Color(0xFF64748B)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildScheduleStatCard('ลาป่วย', '${_currentRecord!.sickLeave}', 'วัน', const Color(0xFFD97706)),
                    ),
                  ],
                ),
              const SizedBox(height: 16),

              // Attendance Log Items (Read-only list)
              Card(
                color: const Color(0xFF1E293B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ประวัติวันหยุดและวันลาในงวดนี้',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 10),
                      if (_employeeAttendance.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.event_busy, size: 36, color: Color(0xFF64748B)),
                                SizedBox(height: 8),
                                Text('ยังไม่มีรายการวันหยุดที่ถูกบันทึกในงวดนี้', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                              ],
                            ),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _employeeAttendance.length,
                          separatorBuilder: (_, __) => const Divider(color: Color(0xFF334155), height: 1),
                          itemBuilder: (context, idx) {
                            final log = _employeeAttendance[idx];
                            final dStr = log['date']?.toString() ?? '';
                            final cat = log['category']?.toString() ?? '';
                            final shift = log['shift']?.toString() ?? 'Normal';
                            final note = log['note']?.toString() ?? '';

                            DateTime? dt;
                            String formattedDate = dStr;
                            String thaiDayName = '';
                            try {
                              dt = DateTime.parse(dStr);
                              formattedDate = df.format(dt);
                              thaiDayName = dayNames[dt.weekday - 1];
                            } catch (_) {}

                            Color badgeColor = const Color(0xFF64748B);
                            if (cat == 'Day-off') badgeColor = const Color(0xFF38BDF8);
                            if (cat == 'Sick') badgeColor = const Color(0xFFF59E0B);
                            if (cat == 'Work Days') badgeColor = const Color(0xFF10B981);

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '$formattedDate ($thaiDayName)',
                                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                        ),
                                        if (note.isNotEmpty)
                                          Text(note, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5)),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: badgeColor.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: badgeColor.withOpacity(0.5)),
                                    ),
                                    child: Text(
                                      cat,
                                      style: TextStyle(color: badgeColor, fontSize: 11.5, fontWeight: FontWeight.bold),
                                    ),
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
        Text(value, style: const TextStyle(color: Color(0xFF0F172A), fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildAmountRow(String label, double amt, NumberFormat nf, {bool isDeduct = false, bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: const Color(0xFF1E293B),
            fontSize: 12.5,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          '${isDeduct ? '-' : '+'}฿${nf.format(amt)}',
          style: TextStyle(
            color: isDeduct ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
            fontSize: 12.5,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildBadgeCard(String label, String value, Color bg, Color text) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 10.5, color: text, fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: text)),
        ],
      ),
    );
  }

  Widget _buildScheduleStatCard(String label, String value, String unit, Color color) {
    return Card(
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
                const SizedBox(width: 4),
                Text(unit, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
