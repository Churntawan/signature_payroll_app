import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/payroll_record.dart';
import '../models/employee.dart';
import '../services/manual_payroll_service.dart';

class ManualPayrollSheet extends StatefulWidget {
  final String period;
  final List<Employee> employees;
  final Map<String, PayrollRecord> records;
  final String selectedGroupFilter;
  final Function(Map<String, PayrollRecord>) onRecordsUpdated;
  final VoidCallback onExportCsv;
  final VoidCallback onPreloadAutoCalculated;
  final Function(String epCode) onViewPayslip;

  const ManualPayrollSheet({
    super.key,
    required this.period,
    required this.employees,
    required this.records,
    required this.selectedGroupFilter,
    required this.onRecordsUpdated,
    required this.onExportCsv,
    required this.onPreloadAutoCalculated,
    required this.onViewPayslip,
  });

  @override
  State<ManualPayrollSheet> createState() => _ManualPayrollSheetState();
}

class _ManualPayrollSheetState extends State<ManualPayrollSheet> {
  final Map<String, Map<String, TextEditingController>> _controllers = {};
  final ScrollController _verticalScrollCtrl = ScrollController();
  final ScrollController _horizontalScrollCtrl = ScrollController();
  String _searchQuery = '';
  bool _isSaving = false;
  bool _hasSavedData = false;
  final currencyFormat = NumberFormat('#,##0.00', 'en_US');
  final intFormat = NumberFormat('#,##0', 'en_US');

  @override
  void initState() {
    super.initState();
    _checkSavedState();
    _initControllers();
  }

  @override
  void didUpdateWidget(covariant ManualPayrollSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.period != widget.period ||
        oldWidget.records.length != widget.records.length) {
      _checkSavedState();
      _initControllers();
    }
  }

  void _checkSavedState() {
    _hasSavedData = ManualPayrollService.hasManualRecords(widget.period);
  }

  void _initControllers() {
    // Dispose old controllers not in new records
    _controllers.removeWhere((ep, ctrls) {
      if (!widget.records.containsKey(ep)) {
        for (final c in ctrls.values) {
          c.dispose();
        }
        return true;
      }
      return false;
    });

    for (final entry in widget.records.entries) {
      final ep = entry.key;
      final rec = entry.value;

      if (!_controllers.containsKey(ep)) {
        _controllers[ep] = {
          'baseSalary': TextEditingController(text: rec.baseSalary.toStringAsFixed(0)),
          'workDays': TextEditingController(text: rec.workDays.toString()),
          'dayOff': TextEditingController(text: rec.dayOff.toString()),
          'sickLeave': TextEditingController(text: rec.sickLeave.toString()),
          'housing': TextEditingController(text: rec.housingAllowance > 0 ? rec.housingAllowance.toStringAsFixed(0) : '0'),
          'ot': TextEditingController(text: rec.overtimePay > 0 ? rec.overtimePay.toStringAsFixed(0) : '0'),
          'bonus': TextEditingController(text: rec.bonusPay > 0 ? rec.bonusPay.toStringAsFixed(0) : '0'),
          'advance': TextEditingController(text: rec.advanceDeduction > 0 ? rec.advanceDeduction.toStringAsFixed(0) : '0'),
          'wp': TextEditingController(text: rec.workPermitDeduction > 0 ? rec.workPermitDeduction.toStringAsFixed(0) : '0'),
          'otherDed': TextEditingController(text: rec.otherDeduction > 0 ? rec.otherDeduction.toStringAsFixed(0) : '0'),
          'note': TextEditingController(text: rec.deductionNote.isNotEmpty ? rec.deductionNote : rec.extraNote),
        };
      } else {
        // Sync values if not focused
        final ctrls = _controllers[ep]!;
        _updateControllerIfDifferent(ctrls['baseSalary']!, rec.baseSalary.toStringAsFixed(0));
        _updateControllerIfDifferent(ctrls['workDays']!, rec.workDays.toString());
        _updateControllerIfDifferent(ctrls['dayOff']!, rec.dayOff.toString());
        _updateControllerIfDifferent(ctrls['sickLeave']!, rec.sickLeave.toString());
        _updateControllerIfDifferent(ctrls['housing']!, rec.housingAllowance > 0 ? rec.housingAllowance.toStringAsFixed(0) : '0');
        _updateControllerIfDifferent(ctrls['ot']!, rec.overtimePay > 0 ? rec.overtimePay.toStringAsFixed(0) : '0');
        _updateControllerIfDifferent(ctrls['bonus']!, rec.bonusPay > 0 ? rec.bonusPay.toStringAsFixed(0) : '0');
        _updateControllerIfDifferent(ctrls['advance']!, rec.advanceDeduction > 0 ? rec.advanceDeduction.toStringAsFixed(0) : '0');
        _updateControllerIfDifferent(ctrls['wp']!, rec.workPermitDeduction > 0 ? rec.workPermitDeduction.toStringAsFixed(0) : '0');
        _updateControllerIfDifferent(ctrls['otherDed']!, rec.otherDeduction > 0 ? rec.otherDeduction.toStringAsFixed(0) : '0');
        _updateControllerIfDifferent(ctrls['note']!, rec.deductionNote.isNotEmpty ? rec.deductionNote : rec.extraNote);
      }
    }
  }

  void _updateControllerIfDifferent(TextEditingController ctrl, String newVal) {
    if (ctrl.text != newVal && (double.tryParse(ctrl.text) ?? -1) != (double.tryParse(newVal) ?? -2)) {
      ctrl.text = newVal;
    }
  }

  @override
  void dispose() {
    _verticalScrollCtrl.dispose();
    _horizontalScrollCtrl.dispose();
    for (final ctrls in _controllers.values) {
      for (final c in ctrls.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  void _recalculateRecord(PayrollRecord rec, Map<String, TextEditingController> ctrls) {
    final baseSal = double.tryParse(ctrls['baseSalary']?.text ?? '') ?? rec.baseSalary;
    final wDays = int.tryParse(ctrls['workDays']?.text ?? '') ?? rec.workDays;
    final dOff = int.tryParse(ctrls['dayOff']?.text ?? '') ?? rec.dayOff;
    final sLeave = int.tryParse(ctrls['sickLeave']?.text ?? '') ?? rec.sickLeave;
    final housing = double.tryParse(ctrls['housing']?.text ?? '') ?? 0.0;
    final ot = double.tryParse(ctrls['ot']?.text ?? '') ?? 0.0;
    final bonus = double.tryParse(ctrls['bonus']?.text ?? '') ?? 0.0;
    final advance = double.tryParse(ctrls['advance']?.text ?? '') ?? 0.0;
    final wp = double.tryParse(ctrls['wp']?.text ?? '') ?? 0.0;
    final otherDed = double.tryParse(ctrls['otherDed']?.text ?? '') ?? 0.0;
    final note = ctrls['note']?.text ?? '';

    rec.workDays = wDays;
    rec.dayOff = dOff;
    rec.sickLeave = sLeave;

    final dailyRate = (baseSal / 30.0).roundToDouble();

    if (rec.wageType == 'Daily') {
      rec.basePay = (dailyRate * wDays).roundToDouble();
      rec.excessDayOffDays = 0.0;
      rec.excessDayOffDeduction = 0.0;
    } else {
      rec.basePay = baseSal;
      final totalOffDays = (dOff * 1.0) + (sLeave * 1.0) + (rec.halfDays * 0.5);
      if (totalOffDays > 4.0) {
        rec.excessDayOffDays = totalOffDays - 4.0;
        rec.excessDayOffDeduction = (rec.excessDayOffDays * dailyRate).roundToDouble();
      } else {
        rec.excessDayOffDays = 0.0;
        rec.excessDayOffDeduction = 0.0;
      }
    }

    rec.housingAllowance = housing;
    if (housing > 0 && rec.housingAllowanceNote.isEmpty) {
      rec.housingAllowanceNote = 'คีย์แมนนวล';
    }
    rec.overtimePay = ot;
    rec.bonusPay = bonus;
    rec.advanceDeduction = advance;
    rec.workPermitDeduction = wp;
    rec.otherDeduction = otherDed;
    rec.deductionNote = note;

    setState(() {});
    widget.onRecordsUpdated(widget.records);
  }

  Future<void> _saveAll() async {
    setState(() => _isSaving = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final recordsList = widget.records.values.toList();
      final res = await ManualPayrollService.saveManualRecords(
        period: widget.period,
        records: recordsList,
      );

      setState(() {
        _isSaving = false;
        _hasSavedData = true;
      });

      final bool savedCloud = res['savedCloud'] == true;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            savedCloud
                ? '✅ บันทึกเงินเดือนงวด ${widget.period} สำเร็จ (${res['total']} รายการ - Sync to Cloud ⚡)'
                : '💾 บันทึกเงินเดือนงวด ${widget.period} ลงเครื่องสำเร็จ (${res['total']} รายการ)',
          ),
          backgroundColor: savedCloud ? const Color(0xFF10B981) : const Color(0xFF0284C7),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      setState(() => _isSaving = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text('⚠️ เกิดข้อผิดพลาดในการบันทึก: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showAddTemporaryStaffDialog() {
    final epCtrl = TextEditingController(text: 'EP-TMP${widget.records.length + 1}');
    final nameCtrl = TextEditingController();
    final salaryCtrl = TextEditingController(text: '12000');
    String wageType = 'Monthly';
    String payGroup = 'Date : 10';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.person_add_alt_1, color: Color(0xFF0284C7)),
                  SizedBox(width: 8),
                  Text('เพิ่มแถวพนักงานชั่วคราว / รายวัน'),
                ],
              ),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: epCtrl,
                      decoration: const InputDecoration(labelText: 'รหัสพนักงาน (EP Code)', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'ชื่อเล่น (Nickname)', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: wageType,
                            decoration: const InputDecoration(labelText: 'ประเภทค่าจ้าง', border: OutlineInputBorder()),
                            items: const [
                              DropdownMenuItem(value: 'Monthly', child: Text('รายเดือน (Monthly)')),
                              DropdownMenuItem(value: 'Daily', child: Text('รายวัน (Daily)')),
                            ],
                            onChanged: (v) => setDlgState(() => wageType = v ?? 'Monthly'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: payGroup,
                            decoration: const InputDecoration(labelText: 'รอบจ่าย (Pay Group)', border: OutlineInputBorder()),
                            items: const [
                              DropdownMenuItem(value: 'Date : 1', child: Text('Date : 1')),
                              DropdownMenuItem(value: 'Date : 10', child: Text('Date : 10')),
                              DropdownMenuItem(value: 'Date : 20', child: Text('Date : 20')),
                            ],
                            onChanged: (v) => setDlgState(() => payGroup = v ?? 'Date : 10'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: salaryCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'ฐานเงินเดือน / อัตราฐาน (บาท)', border: OutlineInputBorder()),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7), foregroundColor: Colors.white),
                  onPressed: () {
                    final ep = epCtrl.text.trim();
                    final name = nameCtrl.text.trim();
                    final sal = double.tryParse(salaryCtrl.text.trim()) ?? 12000.0;
                    if (ep.isEmpty || name.isEmpty) return;

                    final now = DateTime.now();
                    final newRec = PayrollRecord(
                      epCode: ep,
                      nickname: name,
                      payGroup: payGroup,
                      period: widget.period,
                      cycleStartDate: DateTime(now.year, now.month, 1),
                      cycleEndDate: DateTime(now.year, now.month + 1, 0),
                      payDate: now,
                      baseSalary: sal,
                      dailyRate: (sal / 30.0).roundToDouble(),
                      isProrate: false,
                      workedDays: 26,
                      wageType: wageType,
                      basePay: wageType == 'Daily' ? ((sal / 30.0).roundToDouble() * 26) : sal,
                      workDays: 26,
                      dayOff: 4,
                    );

                    widget.records[ep] = newRec;
                    Navigator.pop(ctx);
                    _initControllers();
                    setState(() {});
                    widget.onRecordsUpdated(widget.records);
                  },
                  child: const Text('เพิ่มลงในตาราง'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  List<PayrollRecord> get _filteredRecords {
    return widget.records.values.where((r) {
      if (widget.selectedGroupFilter != 'All Groups' && r.payGroup != widget.selectedGroupFilter) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchEp = r.epCode.toLowerCase().contains(q);
        final matchName = r.nickname.toLowerCase().contains(q);
        if (!matchEp && !matchName) return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredRecords;
    final totalBase = filtered.fold<double>(0, (s, r) => s + r.basePay);
    final totalExtras = filtered.fold<double>(0, (s, r) => s + r.totalExtra);
    final totalDeductions = filtered.fold<double>(0, (s, r) => s + r.totalDeduction);
    final totalNet = filtered.fold<double>(0, (s, r) => s + r.netPay);

    return Column(
      children: [
        // 1. Toolbar / Action Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              // Search input
              SizedBox(
                width: 240,
                height: 38,
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'ค้นหาชื่อ หรือ รหัส EP...',
                    hintStyle: const TextStyle(fontSize: 12),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () => setState(() => _searchQuery = ''),
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v.trim()),
                ),
              ),

              // Action Buttons
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: widget.onPreloadAutoCalculated,
                    icon: const Icon(Icons.auto_fix_high, size: 16, color: Color(0xFF4F46E5)),
                    label: const Text('ดึงค่าคำนวณอัตโนมัติ', style: TextStyle(fontSize: 12, color: Color(0xFF4F46E5))),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF4F46E5)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _showAddTemporaryStaffDialog,
                    icon: const Icon(Icons.person_add_alt, size: 16),
                    label: const Text('เพิ่มแถวพนักงาน', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0284C7),
                      side: const BorderSide(color: Color(0xFF0284C7)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: widget.onExportCsv,
                    icon: const Icon(Icons.file_download_outlined, size: 16),
                    label: const Text('Export CSV', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF059669),
                      side: const BorderSide(color: Color(0xFF059669)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _isSaving ? null : _saveAll,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.save_rounded, size: 16),
                    label: Text(
                      _isSaving ? 'กำลังบันทึก...' : '💾 บันทึกทั้งหมด',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // 2. Info Banner (Status indicator)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          color: const Color(0xFFF1F5F9),
          child: Row(
            children: [
              const Icon(Icons.table_chart, size: 15, color: Color(0xFF475569)),
              const SizedBox(width: 8),
              Text(
                'ตารางคีย์เงินเดือนแมนนวล งวด ${widget.period} • กำลังแสดง ${filtered.length} คน',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
              ),
              const Spacer(),
              if (_hasSavedData)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, size: 12, color: Color(0xFF059669)),
                      SizedBox(width: 4),
                      Text('มีข้อมูลบันทึกในเครื่องแล้ว', style: TextStyle(fontSize: 11, color: Color(0xFF059669), fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
            ],
          ),
        ),

        // 3. Spreadsheet Data Table
        Expanded(
          child: filtered.isEmpty
              ? const Center(
                  child: Text(
                    'ไม่พบรายชื่อพนักงานในตัวกรองนี้',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                )
              : Scrollbar(
                  controller: _verticalScrollCtrl,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _verticalScrollCtrl,
                    primary: false,
                    scrollDirection: Axis.vertical,
                    child: Scrollbar(
                      controller: _horizontalScrollCtrl,
                      thumbVisibility: true,
                      notificationPredicate: (notif) => notif.depth == 1 || notif.metrics.axis == Axis.horizontal,
                      child: SingleChildScrollView(
                        controller: _horizontalScrollCtrl,
                        primary: false,
                        scrollDirection: Axis.horizontal,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: _buildSpreadsheetTable(filtered),
                        ),
                      ),
                    ),
                  ),
                ),
        ),

        // 4. Sticky Summary Totals Footer
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            child: Wrap(
              spacing: 24,
              runSpacing: 6,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.people, color: Colors.white70, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      'รวมทั้งหมด: ${filtered.length} คน',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ],
                ),
                Text(
                  'ฐานเงินเดือน: ฿${currencyFormat.format(totalBase)}',
                  style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13),
                ),
                Text(
                  'รายได้เพิ่ม: +฿${currencyFormat.format(totalExtras)}',
                  style: const TextStyle(color: Color(0xFF6EE7B7), fontSize: 13, fontWeight: FontWeight.w500),
                ),
                Text(
                  'รายการหัก: -฿${currencyFormat.format(totalDeductions)}',
                  style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 13, fontWeight: FontWeight.w500),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'ยอดจ่ายสุทธิ: ฿${currencyFormat.format(totalNet)}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSpreadsheetTable(List<PayrollRecord> records) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFCBD5E1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Table(
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        columnWidths: const {
          0: FixedColumnWidth(85),  // EP Code
          1: FixedColumnWidth(110), // Nickname
          2: FixedColumnWidth(95),  // Pay Group
          3: FixedColumnWidth(85),  // Type
          4: FixedColumnWidth(110), // Base Salary
          5: FixedColumnWidth(80),  // Work Days
          6: FixedColumnWidth(75),  // Day Off
          7: FixedColumnWidth(75),  // Sick Leave
          8: FixedColumnWidth(95),  // Housing
          9: FixedColumnWidth(95),  // OT
          10: FixedColumnWidth(95), // Bonus
          11: FixedColumnWidth(100),// Advance
          12: FixedColumnWidth(100),// WP/CI
          13: FixedColumnWidth(95), // Other Ded
          14: FixedColumnWidth(100),// Excess Off
          15: FixedColumnWidth(125),// Net Pay
          16: FixedColumnWidth(140),// Note
          17: FixedColumnWidth(65), // Payslip
        },
        children: [
          // Header Row
          TableRow(
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
            ),
            children: [
              _buildHeaderCell('รหัส (EP)'),
              _buildHeaderCell('ชื่อเล่น'),
              _buildHeaderCell('รอบจ่าย'),
              _buildHeaderCell('ประเภท'),
              _buildHeaderCell('ฐานเงินเดือน'),
              _buildHeaderCell('วันทำงาน'),
              _buildHeaderCell('วันหยุด'),
              _buildHeaderCell('ลาป่วย'),
              _buildHeaderCell('ค่าห้องพัก'),
              _buildHeaderCell('OT (บาท)'),
              _buildHeaderCell('เบี้ยขยัน/พิเศษ'),
              _buildHeaderCell('หักเบิก'),
              _buildHeaderCell('หักพาสปอร์ต'),
              _buildHeaderCell('หักอื่นๆ'),
              _buildHeaderCell('หักหยุดเกิน'),
              _buildHeaderCell('สุทธิ (Net ฿)', isHighlighted: true),
              _buildHeaderCell('หมายเหตุ'),
              _buildHeaderCell('สลิป'),
            ],
          ),

          // Data Rows
          for (int i = 0; i < records.length; i++)
            _buildDataRow(records[i], i % 2 == 0),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String text, {bool isHighlighted = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      alignment: Alignment.center,
      color: isHighlighted ? const Color(0xFF047857) : Colors.transparent,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: isHighlighted ? Colors.white : const Color(0xFFF8FAFC),
        ),
      ),
    );
  }

  TableRow _buildDataRow(PayrollRecord rec, bool isEven) {
    final ctrls = _controllers[rec.epCode] ?? {};

    return TableRow(
      decoration: BoxDecoration(
        color: isEven ? Colors.white : const Color(0xFFF8FAFC),
        border: const Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      children: [
        // 0. EP Code
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              rec.epCode,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF334155)),
            ),
          ),
        ),

        // 1. Nickname
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Text(
            rec.nickname,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF0F172A)),
            overflow: TextOverflow.ellipsis,
          ),
        ),

        // 2. Pay Group
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Center(
            child: Text(
              rec.payGroup,
              style: const TextStyle(fontSize: 11, color: Color(0xFF0369A1)),
            ),
          ),
        ),

        // 3. Wage Type
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: rec.wageType == 'Daily' ? const Color(0xFFFEF3C7) : const Color(0xFFE0F2FE),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              rec.wageType == 'Daily' ? 'รายวัน' : 'รายเดือน',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
                color: rec.wageType == 'Daily' ? const Color(0xFFB45309) : const Color(0xFF0369A1),
              ),
            ),
          ),
        ),

        // 4. Base Salary
        _buildNumericCell(ctrls['baseSalary'], (val) => _recalculateRecord(rec, ctrls)),

        // 5. Work Days
        _buildNumericCell(ctrls['workDays'], (val) => _recalculateRecord(rec, ctrls), isInt: true),

        // 6. Day Off
        _buildNumericCell(ctrls['dayOff'], (val) => _recalculateRecord(rec, ctrls), isInt: true),

        // 7. Sick Leave
        _buildNumericCell(ctrls['sickLeave'], (val) => _recalculateRecord(rec, ctrls), isInt: true),

        // 8. Housing
        _buildNumericCell(ctrls['housing'], (val) => _recalculateRecord(rec, ctrls), textColor: const Color(0xFF059669)),

        // 9. OT
        _buildNumericCell(ctrls['ot'], (val) => _recalculateRecord(rec, ctrls), textColor: const Color(0xFF7C3AED)),

        // 10. Bonus
        _buildNumericCell(ctrls['bonus'], (val) => _recalculateRecord(rec, ctrls), textColor: const Color(0xFF16A34A)),

        // 11. Advance Deduction
        _buildNumericCell(ctrls['advance'], (val) => _recalculateRecord(rec, ctrls), textColor: const Color(0xFFDC2626)),

        // 12. Work Permit Deduction
        _buildNumericCell(ctrls['wp'], (val) => _recalculateRecord(rec, ctrls), textColor: const Color(0xFFDC2626)),

        // 13. Other Deduction
        _buildNumericCell(ctrls['otherDed'], (val) => _recalculateRecord(rec, ctrls), textColor: const Color(0xFFDC2626)),

        // 14. Excess Day-Off Deduction (Auto computed)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          alignment: Alignment.center,
          child: Text(
            rec.excessDayOffDeduction > 0 ? '-฿${currencyFormat.format(rec.excessDayOffDeduction)}' : '-',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: rec.excessDayOffDeduction > 0 ? const Color(0xFFDC2626) : Colors.grey.shade400,
            ),
          ),
        ),

        // 15. Net Pay (Highlighted)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFA7F3D0)),
            ),
            child: Text(
              '฿${currencyFormat.format(rec.netPay)}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12.5,
                color: Color(0xFF047857),
              ),
            ),
          ),
        ),

        // 16. Note
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: TextField(
            controller: ctrls['note'],
            style: const TextStyle(fontSize: 11.5),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: Colors.grey.shade300)),
              hintText: 'หมายเหตุ...',
              hintStyle: const TextStyle(fontSize: 10.5, color: Colors.grey),
            ),
            onChanged: (val) {
              rec.deductionNote = val;
              widget.onRecordsUpdated(widget.records);
            },
          ),
        ),

        // 17. Payslip Button
        Center(
          child: IconButton(
            tooltip: 'ดูสลิปเงินเดือน',
            icon: const Icon(Icons.receipt_long, size: 18, color: Color(0xFF10B981)),
            onPressed: () => widget.onViewPayslip(rec.epCode),
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
          ),
        ),
      ],
    );
  }

  Widget _buildNumericCell(
    TextEditingController? ctrl,
    Function(String) onChanged, {
    Color? textColor,
    bool isInt = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
      child: TextField(
        controller: ctrl,
        keyboardType: isInt ? TextInputType.number : const TextInputType.numberWithOptions(decimal: true),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textColor ?? const Color(0xFF1E293B),
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: Color(0xFF0284C7), width: 1.5),
          ),
          filled: true,
          fillColor: Colors.white,
        ),
        onChanged: onChanged,
      ),
    );
  }
}
