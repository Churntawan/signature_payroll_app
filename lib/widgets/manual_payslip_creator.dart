import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/employee.dart';
import '../models/payroll_record.dart';
import '../services/image_saver.dart';
import '../services/payroll_engine.dart';

class ManualPayslipCreator extends StatefulWidget {
  final String period;
  final List<Employee> employees;
  final PayrollRecord? initialRecord;
  final Function(PayrollRecord) onSaveToRecords;

  const ManualPayslipCreator({
    super.key,
    required this.period,
    required this.employees,
    this.initialRecord,
    required this.onSaveToRecords,
  });

  @override
  State<ManualPayslipCreator> createState() => _ManualPayslipCreatorState();
}

class _ManualPayslipCreatorState extends State<ManualPayslipCreator> {
  final GlobalKey _previewKey = GlobalKey();
  final currencyFormat = NumberFormat('#,##0.00', 'en_US');
  final dateFormat = DateFormat('dd/MM/yyyy');

  bool _isExporting = false;

  // Controllers
  late TextEditingController _epCtrl;
  late TextEditingController _nameCtrl;
  late TextEditingController _payGroupCtrl;
  late TextEditingController _wageTypeCtrl;
  late TextEditingController _periodCtrl;
  late TextEditingController _baseSalaryCtrl;

  late TextEditingController _workDaysCtrl;
  late TextEditingController _dayOffCtrl;
  late TextEditingController _sickCtrl;
  late TextEditingController _halfDaysCtrl;
  late TextEditingController _otDaysCtrl;

  late TextEditingController _housingCtrl;
  late TextEditingController _otCtrl;
  late TextEditingController _bonusCtrl;
  late TextEditingController _otherExtraCtrl;
  late TextEditingController _extraNoteCtrl;

  late TextEditingController _advanceCtrl;
  late TextEditingController _wpCtrl;
  late TextEditingController _otherDedCtrl;
  late TextEditingController _dedNoteCtrl;
  late TextEditingController _excessOffCtrl;

  DateTime _payDate = DateTime.now();
  DateTime _cycleStartDate = DateTime.now();
  DateTime _cycleEndDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _initFromRecord(widget.initialRecord);
  }

  void _initFromRecord(PayrollRecord? rec) {
    final now = DateTime.now();
    _payDate = rec?.payDate ?? now;
    _cycleStartDate = rec?.cycleStartDate ?? DateTime(now.year, now.month, 1);
    _cycleEndDate = rec?.cycleEndDate ?? DateTime(now.year, now.month + 1, 0);

    _epCtrl = TextEditingController(text: rec?.epCode ?? 'EP-CUSTOM');
    _nameCtrl = TextEditingController(text: rec?.nickname ?? 'พนักงาน');
    _payGroupCtrl = TextEditingController(text: rec?.payGroup ?? 'Date : 10');
    _wageTypeCtrl = TextEditingController(text: rec?.wageType ?? 'Monthly');
    _periodCtrl = TextEditingController(text: rec?.period ?? widget.period);
    _baseSalaryCtrl = TextEditingController(text: (rec?.baseSalary ?? 12000).toStringAsFixed(0));

    _workDaysCtrl = TextEditingController(text: (rec?.workDays ?? 26).toString());
    _dayOffCtrl = TextEditingController(text: (rec?.dayOff ?? 4).toString());
    _sickCtrl = TextEditingController(text: (rec?.sickLeave ?? 0).toString());
    _halfDaysCtrl = TextEditingController(text: (rec?.halfDays ?? 0).toString());
    _otDaysCtrl = TextEditingController(text: (rec?.otDays ?? 0).toString());

    _housingCtrl = TextEditingController(text: (rec?.housingAllowance ?? 0) > 0 ? rec!.housingAllowance.toStringAsFixed(0) : '0');
    _otCtrl = TextEditingController(text: (rec?.overtimePay ?? 0) > 0 ? rec!.overtimePay.toStringAsFixed(0) : '0');
    _bonusCtrl = TextEditingController(text: (rec?.bonusPay ?? 0) > 0 ? rec!.bonusPay.toStringAsFixed(0) : '0');
    _otherExtraCtrl = TextEditingController(text: (rec?.otherExtra ?? 0) > 0 ? rec!.otherExtra.toStringAsFixed(0) : '0');
    _extraNoteCtrl = TextEditingController(text: rec?.extraNote ?? '');

    _advanceCtrl = TextEditingController(text: (rec?.advanceDeduction ?? 0) > 0 ? rec!.advanceDeduction.toStringAsFixed(0) : '0');
    _wpCtrl = TextEditingController(text: (rec?.workPermitDeduction ?? 0) > 0 ? rec!.workPermitDeduction.toStringAsFixed(0) : '0');
    _otherDedCtrl = TextEditingController(text: (rec?.otherDeduction ?? 0) > 0 ? rec!.otherDeduction.toStringAsFixed(0) : '0');
    _dedNoteCtrl = TextEditingController(text: rec?.deductionNote ?? '');
    _excessOffCtrl = TextEditingController(text: (rec?.excessDayOffDeduction ?? 0) > 0 ? rec!.excessDayOffDeduction.toStringAsFixed(0) : '0');
  }

  void _loadFromEmployee(Employee emp) {
    setState(() {
      _epCtrl.text = emp.epCode;
      _nameCtrl.text = emp.nickname;
      _payGroupCtrl.text = emp.payGroup;
      _wageTypeCtrl.text = emp.wageType;
      _baseSalaryCtrl.text = emp.baseSalary.toStringAsFixed(0);
      _housingCtrl.text = emp.stayOutside == 'Yes' ? '1000' : '0';
    });
  }

  PayrollRecord _buildCurrentRecord() {
    final baseSal = double.tryParse(_baseSalaryCtrl.text) ?? 12000.0;
    final wDays = int.tryParse(_workDaysCtrl.text) ?? 26;
    final dOff = int.tryParse(_dayOffCtrl.text) ?? 4;
    final sLeave = int.tryParse(_sickCtrl.text) ?? 0;
    final halfDays = int.tryParse(_halfDaysCtrl.text) ?? 0;
    final otDays = int.tryParse(_otDaysCtrl.text) ?? 0;

    final housing = double.tryParse(_housingCtrl.text) ?? 0.0;
    final ot = double.tryParse(_otCtrl.text) ?? 0.0;
    final bonus = double.tryParse(_bonusCtrl.text) ?? 0.0;
    final otherExtra = double.tryParse(_otherExtraCtrl.text) ?? 0.0;

    final advance = double.tryParse(_advanceCtrl.text) ?? 0.0;
    final wp = double.tryParse(_wpCtrl.text) ?? 0.0;
    final otherDed = double.tryParse(_otherDedCtrl.text) ?? 0.0;
    final excessDed = double.tryParse(_excessOffCtrl.text) ?? 0.0;

    final wageType = _wageTypeCtrl.text;
    final dailyRate = (baseSal / 30.0).roundToDouble();
    final basePay = wageType == 'Daily' ? (dailyRate * wDays).roundToDouble() : baseSal;

    return PayrollRecord(
      epCode: _epCtrl.text.trim(),
      nickname: _nameCtrl.text.trim(),
      payGroup: _payGroupCtrl.text.trim(),
      period: _periodCtrl.text.trim(),
      cycleStartDate: _cycleStartDate,
      cycleEndDate: _cycleEndDate,
      payDate: _payDate,
      baseSalary: baseSal,
      dailyRate: dailyRate,
      isProrate: false,
      workedDays: wDays,
      wageType: wageType,
      basePay: basePay,
      housingAllowance: housing,
      housingAllowanceNote: housing > 0 ? 'ค่าห้องพักแมนนวล' : '',
      overtimePay: ot,
      bonusPay: bonus,
      otherExtra: otherExtra,
      extraNote: _extraNoteCtrl.text,
      advanceDeduction: advance,
      workPermitDeduction: wp,
      otherDeduction: otherDed,
      deductionNote: _dedNoteCtrl.text,
      workDays: wDays,
      dayOff: dOff,
      sickLeave: sLeave,
      halfDays: halfDays,
      otDays: otDays,
      excessDayOffDays: excessDed > 0 ? (excessDed / (dailyRate > 0 ? dailyRate : 1)) : 0,
      excessDayOffDeduction: excessDed,
      status: 'Approved',
    );
  }

  Future<void> _exportAsPng(PayrollRecord rec) async {
    setState(() => _isExporting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Future.delayed(const Duration(milliseconds: 100));
      final boundary = _previewKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        setState(() => _isExporting = false);
        return;
      }

      final ui.Image image = await boundary.toImage(pixelRatio: 2.5);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        final Uint8List pngBytes = byteData.buffer.asUint8List();
        final fileName = 'payslip_manual_${rec.epCode}_${rec.nickname}_${rec.period}.png';
        ImageSaver.savePng(pngBytes, fileName);

        messenger.showSnackBar(
          SnackBar(
            content: Text('✅ ดาวน์โหลดสลิปเงินเดือนเป็นรูปภาพเรียบร้อย: $fileName'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('⚠️ เกิดข้อผิดพลาดในการบันทึกรูป: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _copyForLine(PayrollRecord rec) {
    final text = PayrollEngine.formatLinePayslip(rec);
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ คัดลอกข้อความสลิปเงินเดือนสำหรับส่ง LINE เรียบร้อย!'),
        backgroundColor: Color(0xFF06C755),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    final currentRec = _buildCurrentRecord();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Action / Info Banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit_document, color: Colors.white, size: 24),
                        SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '✍️ ระบบออกสลิปเงินเดือนแบบแมนนวล (Manual PaySlip Creator)',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            Text(
                              'กำหนดตัวเลข รายรับ-รายจ่าย ได้อิสระ พร้อมดูตัวอย่างสลิปสดและบันทึกรูปภาพ/ส่ง LINE ทันที',
                              style: TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ),
                    // Quick Load from Employee Dropdown
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<Employee>(
                          hint: const Text('ดึงข้อมูลพนักงาน', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          items: widget.employees.map((e) {
                            return DropdownMenuItem(
                              value: e,
                              child: Text('${e.epCode} - ${e.nickname} (${e.payGroup})', style: const TextStyle(fontSize: 12)),
                            );
                          }).toList(),
                          onChanged: (emp) {
                            if (emp != null) _loadFromEmployee(emp);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              if (isDesktop)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left Form (Width: 500)
                    Expanded(
                      flex: 5,
                      child: _buildFormCard(),
                    ),
                    const SizedBox(width: 20),
                    // Right Live Preview Card (Width: 500)
                    Expanded(
                      flex: 6,
                      child: _buildPreviewColumn(currentRec),
                    ),
                  ],
                )
              else
                Column(
                  children: [
                    _buildFormCard(),
                    const SizedBox(height: 20),
                    _buildPreviewColumn(currentRec),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('📋 1. ข้อมูลพนักงานและงวดจ่าย', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0369A1))),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _epCtrl,
                    decoration: const InputDecoration(labelText: 'รหัสพนักงาน (EP Code)', isDense: true, border: OutlineInputBorder()),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: 'ชื่อเล่นพนักงาน', isDense: true, border: OutlineInputBorder()),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _payGroupCtrl,
                    decoration: const InputDecoration(labelText: 'รอบจ่าย (Pay Group)', isDense: true, border: OutlineInputBorder()),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _wageTypeCtrl.text,
                    decoration: const InputDecoration(labelText: 'ประเภทค่าจ้าง', isDense: true, border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'Monthly', child: Text('รายเดือน (Monthly)')),
                      DropdownMenuItem(value: 'Daily', child: Text('รายวัน (Daily)')),
                    ],
                    onChanged: (v) {
                      _wageTypeCtrl.text = v ?? 'Monthly';
                      setState(() {});
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _periodCtrl,
                    decoration: const InputDecoration(labelText: 'งวดเงินเดือน (Period)', isDense: true, border: OutlineInputBorder()),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _baseSalaryCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'ฐานเงินเดือน (บาท)', isDense: true, border: OutlineInputBorder()),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),

            const Divider(height: 28),
            const Text('📅 2. สถิติวันทำงาน & วันหยุดในงวด', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A))),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _workDaysCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'วันทำงานจริง', isDense: true, border: OutlineInputBorder()),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _dayOffCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'วันหยุด (Off)', isDense: true, border: OutlineInputBorder()),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _sickCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'ลาป่วย (Sick)', isDense: true, border: OutlineInputBorder()),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _otDaysCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'วัน OT', isDense: true, border: OutlineInputBorder()),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),

            const Divider(height: 28),
            const Text('➕ 3. รายรับและเงินเพิ่ม (Earnings)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF10B981))),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _housingCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'ค่าห้องพัก (Housing)', isDense: true, border: OutlineInputBorder()),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _otCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'ค่าล่วงเวลา (OT ฿)', isDense: true, border: OutlineInputBorder()),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _bonusCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'เบี้ยขยัน / โบนัส', isDense: true, border: OutlineInputBorder()),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _otherExtraCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'เงินเพิ่มอื่นๆ', isDense: true, border: OutlineInputBorder()),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _extraNoteCtrl,
              decoration: const InputDecoration(labelText: 'หมายเหตุรายรับพิเศษ', isDense: true, border: OutlineInputBorder()),
              onChanged: (_) => setState(() {}),
            ),

            const Divider(height: 28),
            const Text('➖ 4. รายการหัก (Deductions)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFFEF4444))),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _advanceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'หักเบิกล่วงหน้า (Advance)', isDense: true, border: OutlineInputBorder()),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _wpCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'หักค่าพาสปอร์ต / CI', isDense: true, border: OutlineInputBorder()),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _excessOffCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'หักหยุดเกิน (Excess Off)', isDense: true, border: OutlineInputBorder()),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _otherDedCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'หักอื่นๆ (Other)', isDense: true, border: OutlineInputBorder()),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _dedNoteCtrl,
              decoration: const InputDecoration(labelText: 'หมายเหตุรายการหัก', isDense: true, border: OutlineInputBorder()),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewColumn(PayrollRecord rec) {
    return Column(
      children: [
        // Action toolbar for this payslip
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: () => _copyForLine(rec),
              icon: const Icon(Icons.chat_bubble_outline, size: 16),
              label: const Text('คัดลอกส่ง LINE'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF06C755),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
            ElevatedButton.icon(
              onPressed: _isExporting ? null : () => _exportAsPng(rec),
              icon: _isExporting
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.image, size: 16),
              label: Text(_isExporting ? 'กำลังบันทึก...' : '📸 เซฟเป็นรูปภาพ (PNG)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
            FilledButton.icon(
              onPressed: () {
                widget.onSaveToRecords(rec);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('✅ บันทึกสลิปแมนนวลของ ${rec.nickname} เข้าสู่ระบบเงินเดือนเรียบร้อย'),
                    backgroundColor: const Color(0xFF10B981),
                  ),
                );
              },
              icon: const Icon(Icons.save_rounded, size: 16),
              label: const Text('💾 บันทึกเข้าระบบ'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Live Payslip Card Preview
        RepaintBoundary(
          key: _previewKey,
          child: Card(
            elevation: 3,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'SIGNATURE PAYROLL',
                                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 0.5),
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
                          'Period ${rec.period}',
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
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Employee: ${rec.nickname} (${rec.epCode})',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Pay Group: ${rec.payGroup} • Wage: ${rec.wageType == 'Daily' ? 'รายวัน' : 'รายเดือน'}',
                                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Cycle: ${dateFormat.format(rec.cycleStartDate)} - ${dateFormat.format(rec.cycleEndDate)}',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF475569)),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Pay Date: ${dateFormat.format(rec.payDate)}',
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF0284C7)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Attendance Stats
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFBBF7D0)),
                    ),
                    child: Row(
                      children: [
                        _buildAttendanceItem(Icons.work_history_outlined, 'Work Days', '${rec.workDays}d'),
                        _buildAttendanceItem(Icons.beach_access_outlined, 'Day-offs', '${rec.dayOff}d'),
                        _buildAttendanceItem(Icons.healing_outlined, 'Sick Leave', '${rec.sickLeave}d'),
                        _buildAttendanceItem(Icons.hourglass_bottom_outlined, 'Half-days', '${rec.halfDays}'),
                        _buildAttendanceItem(Icons.more_time_outlined, 'OT Days', '${rec.otDays}'),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Earnings & Deductions
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('➕ Earnings (รายรับ)', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF10B981), fontSize: 13)),
                            const SizedBox(height: 8),
                            _buildPayslipLine(
                              rec.wageType == 'Daily'
                                  ? 'Daily Wage (${rec.workDays}d @ ฿${currencyFormat.format(rec.dailyRate)})'
                                  : 'Base Salary',
                              '฿${currencyFormat.format(rec.basePay)}',
                            ),
                            if (rec.housingAllowance > 0)
                              _buildPayslipLine('Housing Allowance (ค่าห้องพัก)', '+฿${currencyFormat.format(rec.housingAllowance)}', color: const Color(0xFF059669)),
                            if (rec.overtimePay > 0)
                              _buildPayslipLine('Overtime Pay (OT)', '+฿${currencyFormat.format(rec.overtimePay)}'),
                            if (rec.bonusPay > 0)
                              _buildPayslipLine('Incentive / Bonus', '+฿${currencyFormat.format(rec.bonusPay)}'),
                            if (rec.otherExtra > 0)
                              _buildPayslipLine('Other Extra', '+฿${currencyFormat.format(rec.otherExtra)}'),
                            const Divider(height: 16),
                            _buildPayslipLine('Total Earnings', '฿${currencyFormat.format(rec.basePay + rec.totalExtra)}', isBold: true),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('➖ Deductions (รายการหัก)', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFEF4444), fontSize: 13)),
                            const SizedBox(height: 8),
                            if (rec.excessDayOffDeduction > 0)
                              _buildPayslipLine('Excess Day-offs', '-฿${currencyFormat.format(rec.excessDayOffDeduction)}', color: const Color(0xFFDC2626)),
                            _buildPayslipLine('Advance Payment', rec.advanceDeduction > 0 ? '-฿${currencyFormat.format(rec.advanceDeduction)}' : '฿0.00'),
                            _buildPayslipLine('Work Permit / Passport', rec.workPermitDeduction > 0 ? '-฿${currencyFormat.format(rec.workPermitDeduction)}' : '฿0.00'),
                            if (rec.otherDeduction > 0)
                              _buildPayslipLine('Other Deductions', '-฿${currencyFormat.format(rec.otherDeduction)}'),
                            const Divider(height: 16),
                            _buildPayslipLine('Total Deductions', '-฿${currencyFormat.format(rec.totalDeduction)}', isBold: true, color: const Color(0xFFEF4444)),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // NET PAYOUT Bar
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                          '฿${currencyFormat.format(rec.netPay)}',
                          style: const TextStyle(
                            color: Color(0xFF38BDF8),
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (rec.deductionNote.isNotEmpty || rec.extraNote.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Note: ${rec.deductionNote.isNotEmpty ? rec.deductionNote : rec.extraNote}',
                        style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAttendanceItem(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF059669)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF065F46))),
        Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF047857))),
      ],
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
                fontSize: 12,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                color: const Color(0xFF475569),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: color ?? (isBold ? const Color(0xFF0F172A) : const Color(0xFF334155)),
            ),
          ),
        ],
      ),
    );
  }
}
