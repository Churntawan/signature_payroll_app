import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/employee.dart';
import '../models/salary_record.dart';
import '../services/salary_history_service.dart';
import '../services/api_service.dart';
import '../services/localization_service.dart';

class SalaryHistoryModal extends StatefulWidget {
  final Employee employee;
  final String currentPeriod;
  final List<String> availablePeriods;
  final VoidCallback onUpdated;

  const SalaryHistoryModal({
    super.key,
    required this.employee,
    required this.currentPeriod,
    required this.availablePeriods,
    required this.onUpdated,
  });

  @override
  State<SalaryHistoryModal> createState() => _SalaryHistoryModalState();
}

class _SalaryHistoryModalState extends State<SalaryHistoryModal> {
  final _currencyFormat = NumberFormat('#,##0.00', 'en_US');
  final _dateFormat = DateFormat('dd/MM/yyyy HH:mm');

  late TextEditingController _salaryCtrl;
  late TextEditingController _reasonCtrl;
  late String _selectedPeriod;

  bool _isSaving = false;

  final List<String> _quickReasons = [
    'ผ่านโปร (Probation)',
    'ปรับประจำปี (Annual)',
    'ปรับตำแหน่ง (Promotion)',
    'แก้ไขข้อมูลย้อนหลัง (Correction)',
  ];

  @override
  void initState() {
    super.initState();
    // Default to the current base salary
    _salaryCtrl = TextEditingController(
      text: widget.employee.baseSalary > 0
          ? widget.employee.baseSalary.toStringAsFixed(0)
          : '12000',
    );
    _reasonCtrl = TextEditingController();
    _selectedPeriod = widget.currentPeriod;
  }

  @override
  void dispose() {
    _salaryCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  List<SalaryRecord> _getRecords() {
    return SalaryHistoryService.getRecordsForEmployee(widget.employee.epCode);
  }

  Future<void> _saveAdjustment() async {
    final text = _salaryCtrl.text.replaceAll(',', '').trim();
    final newSalary = double.tryParse(text);

    if (newSalary == null || newSalary <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ กรุณากรอกจำนวนเงินเดือนที่ถูกต้อง (> 0 บาท)'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    // Calculate previous salary before this adjustment
    final previousSalary = SalaryHistoryService.getSalaryForPeriod(
      epCode: widget.employee.epCode,
      period: _selectedPeriod,
      defaultSalary: widget.employee.baseSalary,
    );

    final record = SalaryRecord(
      id: 'sal_${widget.employee.epCode}_${_selectedPeriod}_${DateTime.now().millisecondsSinceEpoch}',
      epCode: widget.employee.epCode,
      effectivePeriod: _selectedPeriod,
      baseSalary: newSalary,
      previousSalary: previousSalary != newSalary ? previousSalary : null,
      reason: _reasonCtrl.text.trim(),
      createdAt: DateTime.now(),
      createdByName: 'Admin',
    );

    await SalaryHistoryService.addSalaryRecord(record);

    // If this adjustment affects current/future period, also sync employee's main base salary
    final latestSalary = SalaryHistoryService.getSalaryForPeriod(
      epCode: widget.employee.epCode,
      period: widget.currentPeriod,
      defaultSalary: newSalary,
    );

    if (latestSalary != widget.employee.baseSalary) {
      final updatedEmp = widget.employee.copyWith(baseSalary: latestSalary);
      await ApiService.saveEmployee(updatedEmp);
    }

    widget.onUpdated();

    if (mounted) {
      setState(() {
        _isSaving = false;
        _reasonCtrl.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ บันทึกการปรับฐานเงินเดือนงวด $_selectedPeriod เรียบร้อยแล้ว!'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    }
  }

  Future<void> _deleteAdjustment(SalaryRecord rec) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('ยืนยันการลบข้อมูล', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: Text(
          'คุณต้องการลบประวัติการปรับเงินเดือนงวด ${rec.effectivePeriod} (฿${_currencyFormat.format(rec.baseSalary)}) ใช่หรือไม่?',
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ลบรายการ', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await SalaryHistoryService.deleteSalaryRecord(rec.id);

      // Recalculate latest active salary and sync employee record
      final latestSalary = SalaryHistoryService.getSalaryForPeriod(
        epCode: widget.employee.epCode,
        period: widget.currentPeriod,
        defaultSalary: widget.employee.baseSalary,
      );

      final updatedEmp = widget.employee.copyWith(baseSalary: latestSalary);
      await ApiService.saveEmployee(updatedEmp);

      widget.onUpdated();

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🗑️ ลบประวัติเงินเดือนงวด ${rec.effectivePeriod} เรียบร้อยแล้ว'),
            backgroundColor: const Color(0xFF64748B),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final records = _getRecords();
    final effectiveForCurrentPeriod = SalaryHistoryService.getSalaryForPeriod(
      epCode: widget.employee.epCode,
      period: widget.currentPeriod,
      defaultSalary: widget.employee.baseSalary,
    );

    return Dialog(
      backgroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF334155)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.trending_up, color: Color(0xFF10B981), size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '${widget.employee.nickname} (${widget.employee.epCode})',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0284C7).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFF0284C7).withOpacity(0.4)),
                              ),
                              child: Text(
                                widget.employee.wageType == 'Daily' ? 'รายวัน (Daily)' : 'รายเดือน (Monthly)',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF38BDF8)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'ฐานเงินเดือนปัจจุบันงวด ${widget.currentPeriod}: ฿${_currencyFormat.format(effectiveForCurrentPeriod)}',
                          style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFF94A3B8)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: Color(0xFF334155), height: 28),

              // Form: Add New Salary Adjustment
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.add_circle_outline, size: 16, color: Color(0xFF38BDF8)),
                        SizedBox(width: 6),
                        Text(
                          'บันทึกการปรับฐานเงินเดือนใหม่ (New Adjustment)',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        // New Salary Input
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _salaryCtrl,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                            decoration: InputDecoration(
                              labelText: 'ฐานเงินเดือนใหม่ (฿) *',
                              labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                              prefixIcon: const Icon(Icons.payments_outlined, color: Color(0xFF10B981), size: 20),
                              filled: true,
                              fillColor: const Color(0xFF0F172A),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: Color(0xFF334155)),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Effective Period Dropdown
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<String>(
                            value: _selectedPeriod,
                            dropdownColor: const Color(0xFF1E293B),
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            decoration: InputDecoration(
                              labelText: 'งวดที่มีผลบังคับใช้ *',
                              labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                              prefixIcon: const Icon(Icons.event_available, color: Color(0xFF38BDF8), size: 20),
                              filled: true,
                              fillColor: const Color(0xFF0F172A),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: Color(0xFF334155)),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                            items: widget.availablePeriods.map((p) {
                              final isCurrent = p == widget.currentPeriod;
                              return DropdownMenuItem(
                                value: p,
                                child: Text('$p${isCurrent ? ' (งวดปัจจุบัน)' : ''}'),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) setState(() => _selectedPeriod = val);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Reason Input
                    TextField(
                      controller: _reasonCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'เหตุผลการปรับ (ระบุหรือไม่ระบุก็ได้)',
                        labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                        prefixIcon: const Icon(Icons.edit_note, color: Color(0xFF94A3B8), size: 20),
                        hintText: 'เช่น ผ่านโปรทดลองงาน 3 เดือน, ปรับประจำปี',
                        hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFF334155)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Quick reason chips
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _quickReasons.map((qr) {
                        return InkWell(
                          onTap: () {
                            setState(() {
                              _reasonCtrl.text = qr;
                            });
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF334155)),
                            ),
                            child: Text(
                              qr,
                              style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _isSaving ? null : _saveAdjustment,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.save, size: 18),
                        label: Text(_isSaving ? 'กำลังบันทึก...' : '💾 บันทึกการปรับเงินเดือน'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // History List Title
              Row(
                children: [
                  const Icon(Icons.history, size: 18, color: Color(0xFF94A3B8)),
                  const SizedBox(width: 8),
                  Text(
                    'ประวัติการปรับฐานเงินเดือนย้อนหลัง (${records.length} รายการ)',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Records Timeline List
              Expanded(
                child: records.isEmpty
                    ? Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B).withOpacity(0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF334155).withOpacity(0.5)),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.receipt_long_outlined, size: 44, color: const Color(0xFF64748B).withOpacity(0.6)),
                              const SizedBox(height: 10),
                              const Text(
                                'ยังไม่มีประวัติการปรับเงินเดือนสำหรับพนักงานคนนี้',
                                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'ระบบจะคำนวณโดยใช้ฐานเงินเดือนเริ่มต้น หากมีการปรับฐานเงินเดือนสามารถบันทึกได้จากฟอร์มด้านบน',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Color(0xFF64748B), fontSize: 11.5),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: records.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final rec = records[index];
                          final diff = rec.salaryDiff;
                          final isIncrease = diff != null && diff > 0;
                          final isDecrease = diff != null && diff < 0;

                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFF334155)),
                            ),
                            child: Row(
                              children: [
                                // Period Badge
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0284C7).withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFF0284C7).withOpacity(0.4)),
                                  ),
                                  child: Column(
                                    children: [
                                      const Text(
                                        'มีผลตั้งแต่',
                                        style: TextStyle(fontSize: 9, color: Color(0xFF7DD3FC)),
                                      ),
                                      Text(
                                        rec.effectivePeriod,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 14),
                                // Details
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            '฿${_currencyFormat.format(rec.baseSalary)}',
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                          if (rec.previousSalary != null) ...[
                                            const SizedBox(width: 6),
                                            Text(
                                              '(เดิม: ฿${_currencyFormat.format(rec.previousSalary!)})',
                                              style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                                            ),
                                          ],
                                          if (diff != null && diff != 0) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: (isIncrease ? const Color(0xFF10B981) : const Color(0xFFEF4444)).withOpacity(0.15),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                '${isIncrease ? '+' : ''}฿${_currencyFormat.format(diff)}',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: isIncrease ? const Color(0xFF34D399) : const Color(0xFFF87171),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      if (rec.reason.isNotEmpty) ...[
                                        const SizedBox(height: 3),
                                        Text(
                                          '📝 ${rec.reason}',
                                          style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                                        ),
                                      ],
                                      const SizedBox(height: 2),
                                      Text(
                                        'บันทึกเมื่อ: ${_dateFormat.format(rec.createdAt)} โดย ${rec.createdByName}',
                                        style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                                      ),
                                    ],
                                  ),
                                ),
                                // Delete button for fixing errors
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 20),
                                  tooltip: 'ลบประวัติรายการนี้ (แก้ไขข้อมูลย้อนหลัง)',
                                  onPressed: () => _deleteAdjustment(rec),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
