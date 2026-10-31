import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/employee.dart';
import '../models/payroll_record.dart';
import '../services/image_saver.dart';

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
  int _activeFormTab = 0; // 0: Values & Numbers, 1: Edit Texts & Labels

  // Number / Data Controllers
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

  // Custom Texts & Labels Controllers (Edit all texts on slip)
  late TextEditingController _companyTitleCtrl;
  late TextEditingController _companySubtitleCtrl;
  late TextEditingController _cycleDatesCtrl;
  late TextEditingController _payDateCtrl;
  late TextEditingController _leaveHeaderCtrl;
  late TextEditingController _leaveDetailsCtrl;
  late TextEditingController _netPayoutSubtitleCtrl;
  late TextEditingController _footerNoteCtrl;

  late TextEditingController _baseSalaryLabelCtrl;
  late TextEditingController _housingLabelCtrl;
  late TextEditingController _otLabelCtrl;
  late TextEditingController _bonusLabelCtrl;
  late TextEditingController _otherExtraLabelCtrl;

  late TextEditingController _advanceLabelCtrl;
  late TextEditingController _wpLabelCtrl;
  late TextEditingController _excessOffLabelCtrl;
  late TextEditingController _otherDedLabelCtrl;

  DateTime _payDate = DateTime.now();
  DateTime _cycleStartDate = DateTime.now();
  DateTime _cycleEndDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _initFromRecord(widget.initialRecord);
  }

  @override
  void dispose() {
    _epCtrl.dispose();
    _nameCtrl.dispose();
    _payGroupCtrl.dispose();
    _wageTypeCtrl.dispose();
    _periodCtrl.dispose();
    _baseSalaryCtrl.dispose();

    _workDaysCtrl.dispose();
    _dayOffCtrl.dispose();
    _sickCtrl.dispose();
    _halfDaysCtrl.dispose();
    _otDaysCtrl.dispose();

    _housingCtrl.dispose();
    _otCtrl.dispose();
    _bonusCtrl.dispose();
    _otherExtraCtrl.dispose();
    _extraNoteCtrl.dispose();

    _advanceCtrl.dispose();
    _wpCtrl.dispose();
    _otherDedCtrl.dispose();
    _dedNoteCtrl.dispose();
    _excessOffCtrl.dispose();

    _companyTitleCtrl.dispose();
    _companySubtitleCtrl.dispose();
    _cycleDatesCtrl.dispose();
    _payDateCtrl.dispose();
    _leaveHeaderCtrl.dispose();
    _leaveDetailsCtrl.dispose();
    _netPayoutSubtitleCtrl.dispose();
    _footerNoteCtrl.dispose();

    _baseSalaryLabelCtrl.dispose();
    _housingLabelCtrl.dispose();
    _otLabelCtrl.dispose();
    _bonusLabelCtrl.dispose();
    _otherExtraLabelCtrl.dispose();

    _advanceLabelCtrl.dispose();
    _wpLabelCtrl.dispose();
    _excessOffLabelCtrl.dispose();
    _otherDedLabelCtrl.dispose();
    super.dispose();
  }

  String _formatShortDate(String? dStr) {
    if (dStr == null || dStr.isEmpty) return '';
    try {
      final parts = dStr.split('-');
      if (parts.length == 3) {
        return '${parts[2]}/${parts[1]}';
      }
    } catch (_) {}
    return dStr;
  }

  void _initFromRecord(PayrollRecord? rec) {
    final now = DateTime.now();
    _payDate = rec?.payDate ?? now;
    _cycleStartDate = rec?.cycleStartDate ?? DateTime(now.year, now.month, 1);
    _cycleEndDate = rec?.cycleEndDate ?? DateTime(now.year, now.month + 1, 0);

    _epCtrl = TextEditingController(text: rec?.epCode ?? 'EP02');
    _nameCtrl = TextEditingController(text: rec?.nickname ?? 'Aem');
    _payGroupCtrl = TextEditingController(text: rec?.payGroup ?? 'Date : 10');
    _wageTypeCtrl = TextEditingController(text: rec?.wageType ?? 'Monthly');
    _periodCtrl = TextEditingController(text: rec?.period ?? widget.period);
    _baseSalaryCtrl = TextEditingController(text: (rec?.baseSalary ?? 13000).toStringAsFixed(0));

    _workDaysCtrl = TextEditingController(text: (rec?.workDays ?? 25).toString());
    _dayOffCtrl = TextEditingController(text: (rec?.dayOff ?? 5).toString());
    _sickCtrl = TextEditingController(text: (rec?.sickLeave ?? 0).toString());
    _halfDaysCtrl = TextEditingController(text: (rec?.halfDays ?? 0).toString());
    _otDaysCtrl = TextEditingController(text: (rec?.otDays ?? 0).toString());

    _housingCtrl = TextEditingController(text: (rec?.housingAllowance ?? 0) > 0 ? rec!.housingAllowance.toStringAsFixed(0) : '1000');
    _otCtrl = TextEditingController(text: (rec?.overtimePay ?? 0) > 0 ? rec!.overtimePay.toStringAsFixed(0) : '0');
    _bonusCtrl = TextEditingController(text: (rec?.bonusPay ?? 0) > 0 ? rec!.bonusPay.toStringAsFixed(0) : '0');
    _otherExtraCtrl = TextEditingController(text: (rec?.otherExtra ?? 0) > 0 ? rec!.otherExtra.toStringAsFixed(0) : '0');
    _extraNoteCtrl = TextEditingController(text: rec?.extraNote ?? '');

    _advanceCtrl = TextEditingController(text: (rec?.advanceDeduction ?? 0) > 0 ? rec!.advanceDeduction.toStringAsFixed(0) : '2000');
    _wpCtrl = TextEditingController(text: (rec?.workPermitDeduction ?? 0) > 0 ? rec!.workPermitDeduction.toStringAsFixed(0) : '0');
    _otherDedCtrl = TextEditingController(text: (rec?.otherDeduction ?? 0) > 0 ? rec!.otherDeduction.toStringAsFixed(0) : '0');
    _dedNoteCtrl = TextEditingController(text: rec?.deductionNote ?? '');
    _excessOffCtrl = TextEditingController(text: (rec?.excessDayOffDeduction ?? 0) > 0 ? rec!.excessDayOffDeduction.toStringAsFixed(0) : '0');

    // Texts & Labels
    _companyTitleCtrl = TextEditingController(text: 'SIGNATURE PAYROLL');
    _companySubtitleCtrl = TextEditingController(text: 'PAYSLIP / SALARY STATEMENT');
    _cycleDatesCtrl = TextEditingController(text: 'Cycle: ${dateFormat.format(_cycleStartDate)} - ${dateFormat.format(_cycleEndDate)}');
    _payDateCtrl = TextEditingController(text: 'Pay Date: ${dateFormat.format(_payDate)}');
    _leaveHeaderCtrl = TextEditingController(text: 'รายละเอียดวันหยุด & วันลาในงวดนี้');

    // Format initial leave details text
    String leaveText = '';
    if (rec != null) {
      if (rec.dayOffLogs.isNotEmpty) {
        final dList = rec.dayOffLogs.map((l) => _formatShortDate(l['date']?.toString())).join(', ');
        leaveText += 'วันหยุด (OFF): $dList';
      }
      if (rec.sickLogs.isNotEmpty) {
        final sList = rec.sickLogs.map((l) => _formatShortDate(l['date']?.toString())).join(', ');
        if (leaveText.isNotEmpty) leaveText += '\n';
        leaveText += 'ลาป่วย (Sick): $sList';
      }
      if (rec.otDayLogs.isNotEmpty) {
        final otList = rec.otDayLogs.map((l) => _formatShortDate(l['date']?.toString())).join(', ');
        if (leaveText.isNotEmpty) leaveText += '\n';
        leaveText += 'ทำงานวันหยุด (OT): $otList';
      }
    }
    if (leaveText.isEmpty) {
      leaveText = 'วันหยุด (OFF): 16/09, 23/09, 30/09, 07/10, 10/10';
    }
    _leaveDetailsCtrl = TextEditingController(text: leaveText);

    _netPayoutSubtitleCtrl = TextEditingController(text: 'Social Security: Excluded');
    _footerNoteCtrl = TextEditingController(text: rec?.deductionNote.isNotEmpty == true ? rec!.deductionNote : (rec?.extraNote ?? ''));

    final isDaily = rec?.wageType == 'Daily';
    final dailyRate = ((rec?.baseSalary ?? 13000) / 30.0).roundToDouble();
    _baseSalaryLabelCtrl = TextEditingController(
      text: isDaily ? 'Daily Wage (${rec?.workDays ?? 25} days @ ฿${currencyFormat.format(dailyRate)})' : 'Base Salary',
    );
    _housingLabelCtrl = TextEditingController(text: 'Housing Allowance (ค่าห้องพัก)');
    _otLabelCtrl = TextEditingController(text: 'Overtime Pay (OT)');
    _bonusLabelCtrl = TextEditingController(text: 'Incentive / Bonus');
    _otherExtraLabelCtrl = TextEditingController(text: 'Other Extra');

    _advanceLabelCtrl = TextEditingController(text: 'Advance Payment');
    _wpLabelCtrl = TextEditingController(text: 'Work Permit / Passport');
    _excessOffLabelCtrl = TextEditingController(text: 'Excess Day-offs');
    _otherDedLabelCtrl = TextEditingController(text: 'Other Deductions');
  }

  void _loadFromEmployee(Employee emp) {
    setState(() {
      _epCtrl.text = emp.epCode;
      _nameCtrl.text = emp.nickname;
      _payGroupCtrl.text = emp.payGroup;
      _wageTypeCtrl.text = emp.wageType;
      _baseSalaryCtrl.text = emp.baseSalary.toStringAsFixed(0);
      _housingCtrl.text = emp.stayOutside == 'Yes' ? '1000' : '0';

      if (emp.wageType == 'Daily') {
        final dRate = (emp.baseSalary / 30.0).roundToDouble();
        _baseSalaryLabelCtrl.text = 'Daily Wage (${_workDaysCtrl.text} days @ ฿${currencyFormat.format(dRate)})';
      } else {
        _baseSalaryLabelCtrl.text = 'Base Salary';
      }
    });
  }

  void _resetTextsToDefault() {
    setState(() {
      _companyTitleCtrl.text = 'SIGNATURE PAYROLL';
      _companySubtitleCtrl.text = 'PAYSLIP / SALARY STATEMENT';
      _cycleDatesCtrl.text = 'Cycle: ${dateFormat.format(_cycleStartDate)} - ${dateFormat.format(_cycleEndDate)}';
      _payDateCtrl.text = 'Pay Date: ${dateFormat.format(_payDate)}';
      _leaveHeaderCtrl.text = 'รายละเอียดวันหยุด & วันลาในงวดนี้';
      _netPayoutSubtitleCtrl.text = 'Social Security: Excluded';

      final isDaily = _wageTypeCtrl.text == 'Daily';
      final baseSal = double.tryParse(_baseSalaryCtrl.text) ?? 13000.0;
      final dRate = (baseSal / 30.0).roundToDouble();
      final wDays = int.tryParse(_workDaysCtrl.text) ?? 25;

      _baseSalaryLabelCtrl.text = isDaily ? 'Daily Wage ($wDays days @ ฿${currencyFormat.format(dRate)})' : 'Base Salary';
      _housingLabelCtrl.text = 'Housing Allowance (ค่าห้องพัก)';
      _otLabelCtrl.text = 'Overtime Pay (OT)';
      _bonusLabelCtrl.text = 'Incentive / Bonus';
      _otherExtraLabelCtrl.text = 'Other Extra';

      _advanceLabelCtrl.text = 'Advance Payment';
      _wpLabelCtrl.text = 'Work Permit / Passport';
      _excessOffLabelCtrl.text = 'Excess Day-offs';
      _otherDedLabelCtrl.text = 'Other Deductions';
    });
  }

  double _calculateBasePay() {
    final baseSal = double.tryParse(_baseSalaryCtrl.text) ?? 0.0;
    final wDays = int.tryParse(_workDaysCtrl.text) ?? 25;
    if (_wageTypeCtrl.text == 'Daily') {
      final dailyRate = (baseSal / 30.0).roundToDouble();
      return (dailyRate * wDays).roundToDouble();
    }
    return baseSal;
  }

  double _calculateTotalEarnings() {
    final basePay = _calculateBasePay();
    final housing = double.tryParse(_housingCtrl.text) ?? 0.0;
    final ot = double.tryParse(_otCtrl.text) ?? 0.0;
    final bonus = double.tryParse(_bonusCtrl.text) ?? 0.0;
    final otherExtra = double.tryParse(_otherExtraCtrl.text) ?? 0.0;
    return basePay + housing + ot + bonus + otherExtra;
  }

  double _calculateTotalDeductions() {
    final advance = double.tryParse(_advanceCtrl.text) ?? 0.0;
    final wp = double.tryParse(_wpCtrl.text) ?? 0.0;
    final excess = double.tryParse(_excessOffCtrl.text) ?? 0.0;
    final otherDed = double.tryParse(_otherDedCtrl.text) ?? 0.0;
    return advance + wp + excess + otherDed;
  }

  double _calculateNetPay() {
    return _calculateTotalEarnings() - _calculateTotalDeductions();
  }

  PayrollRecord _buildCurrentRecord() {
    final baseSal = double.tryParse(_baseSalaryCtrl.text) ?? 13000.0;
    final wDays = int.tryParse(_workDaysCtrl.text) ?? 25;
    final dOff = int.tryParse(_dayOffCtrl.text) ?? 5;
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
    final basePay = _calculateBasePay();

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
      basePay: basePay,
      isProrate: false,
      workedDays: wDays,
      wageType: wageType,
      workDays: wDays,
      dayOff: dOff,
      sickLeave: sLeave,
      halfDays: halfDays,
      otDays: otDays,
      housingAllowance: housing,
      overtimePay: ot,
      bonusPay: bonus,
      otherExtra: otherExtra,
      extraNote: _extraNoteCtrl.text.trim(),
      advanceDeduction: advance,
      workPermitDeduction: wp,
      otherDeduction: otherDed,
      deductionNote: _dedNoteCtrl.text.trim(),
      excessDayOffDeduction: excessDed,
      attendanceDetails: const [],
    );
  }

  Future<void> _exportAsPng(PayrollRecord rec) async {
    setState(() => _isExporting = true);
    try {
      await Future.delayed(const Duration(milliseconds: 150));
      final boundary = _previewKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('Boundary not found');

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('ByteData is null');

      final pngBytes = byteData.buffer.asUint8List();
      final fileName = 'payslip_${rec.epCode}_${rec.nickname}_${rec.period}.png';
      ImageSaver.savePng(pngBytes, fileName);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📸 บันทึกสลิปรูปภาพ $fileName เรียบร้อยแล้ว'),
            backgroundColor: const Color(0xFF0284C7),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาดในการบันทึกรูปภาพ: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _copyForLine(PayrollRecord rec) {
    final currency = NumberFormat('#,##0.00', 'en_US');
    final netPay = _calculateNetPay();
    final basePay = _calculateBasePay();

    final buffer = StringBuffer();
    buffer.writeln('💎 ${_companyTitleCtrl.text} (${_periodCtrl.text})');
    buffer.writeln('👤 ${_nameCtrl.text} (${_epCtrl.text})');
    buffer.writeln('📅 ${_cycleDatesCtrl.text}');
    buffer.writeln('💰 ${_payDateCtrl.text}');
    buffer.writeln('--------------------------------');
    buffer.writeln('📊 สถิติเวลาทำงาน:');
    buffer.writeln('• ทำงาน: ${_workDaysCtrl.text} วัน | วันหยุด: ${_dayOffCtrl.text} วัน | ลาป่วย: ${_sickCtrl.text} วัน');
    if (_leaveDetailsCtrl.text.isNotEmpty && !_leaveDetailsCtrl.text.contains('ไม่มีบันทึก')) {
      buffer.writeln(_leaveDetailsCtrl.text);
    }
    buffer.writeln('--------------------------------');
    buffer.writeln('➕ รายรับ:');
    buffer.writeln('• ${_baseSalaryLabelCtrl.text}: ฿${currency.format(basePay)}');
    final housing = double.tryParse(_housingCtrl.text) ?? 0.0;
    if (housing > 0) buffer.writeln('• ${_housingLabelCtrl.text}: +฿${currency.format(housing)}');
    final ot = double.tryParse(_otCtrl.text) ?? 0.0;
    if (ot > 0) buffer.writeln('• ${_otLabelCtrl.text}: +฿${currency.format(ot)}');
    final bonus = double.tryParse(_bonusCtrl.text) ?? 0.0;
    if (bonus > 0) buffer.writeln('• ${_bonusLabelCtrl.text}: +฿${currency.format(bonus)}');
    final extra = double.tryParse(_otherExtraCtrl.text) ?? 0.0;
    if (extra > 0) buffer.writeln('• ${_otherExtraLabelCtrl.text}: +฿${currency.format(extra)}');

    buffer.writeln('--------------------------------');
    buffer.writeln('➖ รายการหัก:');
    final advance = double.tryParse(_advanceCtrl.text) ?? 0.0;
    if (advance > 0) buffer.writeln('• ${_advanceLabelCtrl.text}: -฿${currency.format(advance)}');
    final wp = double.tryParse(_wpCtrl.text) ?? 0.0;
    if (wp > 0) buffer.writeln('• ${_wpLabelCtrl.text}: -฿${currency.format(wp)}');
    final excess = double.tryParse(_excessOffCtrl.text) ?? 0.0;
    if (excess > 0) buffer.writeln('• ${_excessOffLabelCtrl.text}: -฿${currency.format(excess)}');
    final otherDed = double.tryParse(_otherDedCtrl.text) ?? 0.0;
    if (otherDed > 0) buffer.writeln('• ${_otherDedLabelCtrl.text}: -฿${currency.format(otherDed)}');

    buffer.writeln('================================');
    buffer.writeln('💵 NET PAYOUT: ฿${currency.format(netPay)}');
    if (_netPayoutSubtitleCtrl.text.isNotEmpty) {
      buffer.writeln('(${_netPayoutSubtitleCtrl.text})');
    }
    if (_footerNoteCtrl.text.isNotEmpty) {
      buffer.writeln('📝 หมายเหตุ: ${_footerNoteCtrl.text}');
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ คัดลอกสลิปเงินเดือนเรียบร้อย พร้อมวางส่งในแชท LINE'),
        backgroundColor: Color(0xFF06C755),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 960;
    final currentRec = _buildCurrentRecord();

    return isMobile
        ? SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _buildActionToolbar(currentRec),
                const SizedBox(height: 12),
                _buildLivePayslipCard(currentRec, isMobile: true),
                const SizedBox(height: 16),
                _buildEditorPanel(isMobile: true),
              ],
            ),
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: Form Editor (Scrollable)
              Expanded(
                flex: 5,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: _buildEditorPanel(isMobile: false),
                ),
              ),
              // Right: Action Toolbar + Live Payslip Preview Card
              Expanded(
                flex: 6,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildActionToolbar(currentRec),
                      const SizedBox(height: 12),
                      _buildLivePayslipCard(currentRec, isMobile: false),
                    ],
                  ),
                ),
              ),
            ],
          );
  }

  Widget _buildActionToolbar(PayrollRecord rec) {
    return Wrap(
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    );
  }

  Widget _buildEditorPanel({required bool isMobile}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.edit_document, size: 18, color: Color(0xFF059669)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '✍️ ระบบออกสลิปเงินเดือนแบบแมนนวล (Manual PaySlip Creator)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF065F46)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            // Autofill Employee dropdown
            if (widget.employees.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: '⚡ ดึงข้อมูลพนักงาน (Autofill)',
                  prefixIcon: Icon(Icons.person_search, color: Color(0xFF0284C7)),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                hint: const Text('เลือกพนักงานเพื่อกรอกข้อมูลอัตโนมัติ'),
                items: widget.employees.map((emp) {
                  return DropdownMenuItem(
                    value: emp.epCode,
                    child: Text('${emp.epCode} - ${emp.nickname} (${emp.payGroup})', overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (ep) {
                  if (ep != null) {
                    final emp = widget.employees.firstWhere((e) => e.epCode == ep);
                    _loadFromEmployee(emp);
                  }
                },
              ),
              const SizedBox(height: 14),
            ],

            // Mode Selector: Numbers vs Edit Text & Labels
            SegmentedButton<int>(
              segments: const [
                ButtonSegment<int>(
                  value: 0,
                  icon: Icon(Icons.calculate_outlined, size: 16),
                  label: Text('💰 1. ตัวเลข & ยอดเงิน'),
                ),
                ButtonSegment<int>(
                  value: 1,
                  icon: Icon(Icons.edit_note, size: 16),
                  label: Text('✏️ 2. ปรับแต่งข้อความบนสลิป'),
                ),
              ],
              selected: {_activeFormTab},
              onSelectionChanged: (val) => setState(() => _activeFormTab = val.first),
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: const Color(0xFFE0F2FE),
                selectedForegroundColor: const Color(0xFF0369A1),
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(height: 16),

            // Tab 0: Numbers & Amounts
            if (_activeFormTab == 0) ...[
              _buildNumbersTab(),
            ] else ...[
              // Tab 1: Edit All Texts & Labels on Slip
              _buildTextsTab(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNumbersTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('📋 ข้อมูลพนักงานและงวดจ่าย', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0369A1))),
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
                value: _wageTypeCtrl.text,
                decoration: const InputDecoration(labelText: 'ประเภทค่าจ้าง', isDense: true, border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'Monthly', child: Text('รายเดือน (Monthly)')),
                  DropdownMenuItem(value: 'Daily', child: Text('รายวัน (Daily)')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _wageTypeCtrl.text = val;
                      if (val == 'Daily') {
                        final baseSal = double.tryParse(_baseSalaryCtrl.text) ?? 13000.0;
                        final dRate = (baseSal / 30.0).roundToDouble();
                        _baseSalaryLabelCtrl.text = 'Daily Wage (${_workDaysCtrl.text} days @ ฿${currencyFormat.format(dRate)})';
                      } else {
                        _baseSalaryLabelCtrl.text = 'Base Salary';
                      }
                    });
                  }
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
        const Text('⏱️ สถิติวันทำงาน & วันหยุดในงวด', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0D9488))),
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
        const Text('➕ รายรับและเงินเพิ่ม (Earnings)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF10B981))),
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

        const Divider(height: 28),
        const Text('➖ รายการหัก (Deductions)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFFEF4444))),
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
      ],
    );
  }

  Widget _buildTextsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Text(
                '✏️ ปรับแก้ข้อความและป้ายกำกับบนสลิป',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF4F46E5)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _resetTextsToDefault,
              icon: const Icon(Icons.restart_alt, size: 16),
              label: const Text('รีเซ็ตข้อความ'),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Header Section Texts
        const Text('1. ส่วนหัวสลิป (Header)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF334155))),
        const SizedBox(height: 6),
        TextField(
          controller: _companyTitleCtrl,
          decoration: const InputDecoration(labelText: 'ชื่อหัวสลิป (Company Name)', isDense: true, border: OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _companySubtitleCtrl,
          decoration: const InputDecoration(labelText: 'คำบรรยายหัวสลิป (Subtitle)', isDense: true, border: OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),

        const Divider(height: 24),
        // Info Box Texts
        const Text('2. ข้อมูลรอบเวลาและวันจ่าย (Cycle & Pay Date)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF334155))),
        const SizedBox(height: 6),
        TextField(
          controller: _cycleDatesCtrl,
          decoration: const InputDecoration(labelText: 'ข้อความช่วงรอบ (Cycle Text)', isDense: true, border: OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _payDateCtrl,
          decoration: const InputDecoration(labelText: 'ข้อความวันจ่าย (Pay Date Text)', isDense: true, border: OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),

        const Divider(height: 24),
        // Leave & Attendance Details Card
        const Text('3. รายละเอียดวันหยุด & วันลา (Leave Details Card)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF334155))),
        const SizedBox(height: 6),
        TextField(
          controller: _leaveHeaderCtrl,
          decoration: const InputDecoration(labelText: 'หัวข้อการลา/วันหยุด', isDense: true, border: OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _leaveDetailsCtrl,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'รายละเอียดวันหยุด/วันลา (เช่น วันหยุด (OFF): 16/09, 23/09...)',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),

        const Divider(height: 24),
        // Earnings Item Labels
        const Text('4. ป้ายชื่อรายการฝั่งรายรับ (Earnings Labels)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF10B981))),
        const SizedBox(height: 6),
        TextField(
          controller: _baseSalaryLabelCtrl,
          decoration: const InputDecoration(labelText: 'ชื่อรายการเงินเดือนหลัก', isDense: true, border: OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _housingLabelCtrl,
          decoration: const InputDecoration(labelText: 'ชื่อรายการค่าห้องพัก', isDense: true, border: OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _otLabelCtrl,
          decoration: const InputDecoration(labelText: 'ชื่อรายการล่วงเวลา (OT)', isDense: true, border: OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _bonusLabelCtrl,
          decoration: const InputDecoration(labelText: 'ชื่อรายการโบนัส / เบี้ยขยัน', isDense: true, border: OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _otherExtraLabelCtrl,
          decoration: const InputDecoration(labelText: 'ชื่อรายการเงินเพิ่มพิเศษอื่นๆ', isDense: true, border: OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),

        const Divider(height: 24),
        // Deductions Item Labels
        const Text('5. ป้ายชื่อรายการฝั่งรายการหัก (Deductions Labels)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFFEF4444))),
        const SizedBox(height: 6),
        TextField(
          controller: _advanceLabelCtrl,
          decoration: const InputDecoration(labelText: 'ชื่อรายการเบิกล่วงหน้า', isDense: true, border: OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _wpLabelCtrl,
          decoration: const InputDecoration(labelText: 'ชื่อรายการค่าพาสปอร์ต / CI', isDense: true, border: OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _excessOffLabelCtrl,
          decoration: const InputDecoration(labelText: 'ชื่อรายการวันหยุดเกิน', isDense: true, border: OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _otherDedLabelCtrl,
          decoration: const InputDecoration(labelText: 'ชื่อรายการหักอื่นๆ', isDense: true, border: OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),

        const Divider(height: 24),
        // Net Payout & Footer Notes
        const Text('6. ข้อความแถบจ่ายสุทธิ & ท้ายสลิป (Net Payout & Notes)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF334155))),
        const SizedBox(height: 6),
        TextField(
          controller: _netPayoutSubtitleCtrl,
          decoration: const InputDecoration(
            labelText: 'ข้อความใต้ NET PAYOUT (เช่น Social Security: Excluded หรือ โอนเข้าบัญชี...)',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _footerNoteCtrl,
          decoration: const InputDecoration(labelText: 'หมายเหตุเพิ่มเติมท้ายสลิป (Footer Note)', isDense: true, border: OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  Widget _buildLivePayslipCard(PayrollRecord rec, {required bool isMobile}) {
    final basePay = _calculateBasePay();
    final totalEarnings = _calculateTotalEarnings();
    final totalDeductions = _calculateTotalDeductions();
    final netPay = totalEarnings - totalDeductions;

    final housing = double.tryParse(_housingCtrl.text) ?? 0.0;
    final ot = double.tryParse(_otCtrl.text) ?? 0.0;
    final bonus = double.tryParse(_bonusCtrl.text) ?? 0.0;
    final otherExtra = double.tryParse(_otherExtraCtrl.text) ?? 0.0;

    final advance = double.tryParse(_advanceCtrl.text) ?? 0.0;
    final wp = double.tryParse(_wpCtrl.text) ?? 0.0;
    final excess = double.tryParse(_excessOffCtrl.text) ?? 0.0;
    final otherDed = double.tryParse(_otherDedCtrl.text) ?? 0.0;

    return RepaintBoundary(
      key: _previewKey,
      child: Card(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 16 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header: Company Logo/Name + Period Chip (Identical to Standard)
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
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _companyTitleCtrl.text,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                _companySubtitleCtrl.text,
                                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), letterSpacing: 0.5),
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
                      'Period ${_periodCtrl.text}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ],
              ),

              const Divider(height: 24),

              // Employee Info Box (Identical to Standard layout)
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
                                  'Employee: ${_nameCtrl.text} (${_epCtrl.text})',
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
                                  _payGroupCtrl.text,
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
                                _cycleDatesCtrl.text,
                                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                              ),
                              Text(
                                _payDateCtrl.text,
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                              ),
                            ],
                          ),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Employee: ${_nameCtrl.text} (${_epCtrl.text})',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Pay Group: ${_payGroupCtrl.text}',
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
                                _cycleDatesCtrl.text,
                                style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _payDateCtrl.text,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF0284C7)),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),

              const SizedBox(height: 12),

              // Attendance Stats Box (5 equal-width columns with Expanded)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: Row(
                  children: [
                    Expanded(child: _buildAttendanceItem(Icons.work_history_outlined, 'Work Days', '${rec.workDays}d')),
                    Expanded(child: _buildAttendanceItem(Icons.beach_access_outlined, 'Day-offs', '${rec.dayOff}d')),
                    Expanded(child: _buildAttendanceItem(Icons.healing_outlined, 'Sick Leave', '${rec.sickLeave}d')),
                    Expanded(child: _buildAttendanceItem(Icons.hourglass_bottom_outlined, 'Half-days', '${rec.halfDays}')),
                    Expanded(child: _buildAttendanceItem(Icons.more_time_outlined, 'OT Days', '${rec.otDays}')),
                  ],
                ),
              ),

              // Detailed Leave and Day-off Dates Card (Identical to Standard Payslip)
              if (_leaveDetailsCtrl.text.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 10),
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
                          const Icon(Icons.calendar_month_outlined, size: 15, color: Color(0xFF475569)),
                          const SizedBox(width: 6),
                          Text(
                            _leaveHeaderCtrl.text,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _leaveDetailsCtrl.text,
                        style: const TextStyle(fontSize: 11.5, color: Color(0xFF334155), height: 1.4),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 16),

              // Earnings & Deductions Sections
              if (isMobile) ...[
                _buildEarningsSection(basePay, totalEarnings, housing, ot, bonus, otherExtra),
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 14),
                _buildDeductionsSection(totalDeductions, advance, wp, excess, otherDed),
              ] else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildEarningsSection(basePay, totalEarnings, housing, ot, bonus, otherExtra)),
                    const SizedBox(width: 24),
                    Expanded(child: _buildDeductionsSection(totalDeductions, advance, wp, excess, otherDed)),
                  ],
                ),
              ],

              const SizedBox(height: 20),

              // NET PAYOUT Bar (Identical to Standard)
              Container(
                padding: EdgeInsets.all(isMobile ? 14 : 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'NET PAYOUT',
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _netPayoutSubtitleCtrl.text,
                          style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          '฿${currencyFormat.format(netPay)}',
                          style: const TextStyle(
                            color: Color(0xFF38BDF8),
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Extra Note Box (if present)
              if (_footerNoteCtrl.text.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Note: ${_footerNoteCtrl.text}',
                    style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEarningsSection(
    double basePay,
    double totalEarnings,
    double housing,
    double ot,
    double bonus,
    double otherExtra,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '➕ Earnings (รายรับ)',
          style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF10B981), fontSize: 13),
        ),
        const SizedBox(height: 8),
        _buildPayslipLine(_baseSalaryLabelCtrl.text, '฿${currencyFormat.format(basePay)}'),
        if (housing > 0)
          _buildPayslipLine(
            _housingLabelCtrl.text,
            '+฿${currencyFormat.format(housing)}',
            color: const Color(0xFF059669),
          ),
        if (ot > 0)
          _buildPayslipLine(
            _otLabelCtrl.text,
            '+฿${currencyFormat.format(ot)}',
          ),
        if (bonus > 0)
          _buildPayslipLine(
            _bonusLabelCtrl.text,
            '+฿${currencyFormat.format(bonus)}',
          ),
        if (otherExtra > 0)
          _buildPayslipLine(
            _otherExtraLabelCtrl.text,
            '+฿${currencyFormat.format(otherExtra)}',
          ),
        const Divider(height: 16),
        _buildPayslipLine('Total Earnings', '฿${currencyFormat.format(totalEarnings)}', isBold: true),
      ],
    );
  }

  Widget _buildDeductionsSection(
    double totalDeductions,
    double advance,
    double wp,
    double excess,
    double otherDed,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '➖ Deductions (รายการหัก)',
          style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFEF4444), fontSize: 13),
        ),
        const SizedBox(height: 8),
        if (excess > 0)
          _buildPayslipLine(
            _excessOffLabelCtrl.text,
            '-฿${currencyFormat.format(excess)}',
            color: const Color(0xFFDC2626),
          ),
        _buildPayslipLine(
          _advanceLabelCtrl.text,
          advance > 0 ? '-฿${currencyFormat.format(advance)}' : '฿0.00',
        ),
        _buildPayslipLine(
          _wpLabelCtrl.text,
          wp > 0 ? '-฿${currencyFormat.format(wp)}' : '฿0.00',
        ),
        if (otherDed > 0)
          _buildPayslipLine(
            _otherDedLabelCtrl.text,
            '-฿${currencyFormat.format(otherDed)}',
          ),
        const Divider(height: 16),
        _buildPayslipLine(
          'Total Deductions',
          '-฿${currencyFormat.format(totalDeductions)}',
          isBold: true,
          color: const Color(0xFFEF4444),
        ),
      ],
    );
  }

  Widget _buildAttendanceItem(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF059669)),
        const SizedBox(height: 3),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF065F46))),
        const SizedBox(height: 1),
        Text(label, style: const TextStyle(fontSize: 10.5, color: Color(0xFF047857)), overflow: TextOverflow.ellipsis),
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
          const SizedBox(width: 8),
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
