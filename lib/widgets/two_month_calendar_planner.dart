import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class TwoMonthCalendarPlanner extends StatelessWidget {
  final String period; // e.g. '2026-09'
  final List<Map<String, dynamic>> attendanceLogs;
  final Function(DateTime date) onAddAttendance;
  final Function(DateTime monthDate)? onAutoScheduleMonth;
  final Function(DateTime monthDate)? onClearMonthDayOffs;
  final Function(Map<String, dynamic> log)? onDeleteAttendance;

  const TwoMonthCalendarPlanner({
    super.key,
    required this.period,
    required this.attendanceLogs,
    required this.onAddAttendance,
    this.onAutoScheduleMonth,
    this.onClearMonthDayOffs,
    this.onDeleteAttendance,
  });

  @override
  Widget build(BuildContext context) {
    // Parse year & month from period (e.g. '2026-09')
    final parts = period.split('-');
    final year = int.tryParse(parts[0]) ?? DateTime.now().year;
    final month = int.tryParse(parts[1]) ?? DateTime.now().month;

    final currentMonthDate = DateTime(year, month, 1);
    final prevMonthDate = DateTime(year, month - 1, 1);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 980;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Info Banner & Legend
              _buildLegendBar(context, prevMonthDate, currentMonthDate),
              const SizedBox(height: 16),

              // 2. Dual Month Grids (Side-by-side on wide screen, stacked on narrow)
              if (isWide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildMonthCard(context, prevMonthDate, isPrevMonth: true)),
                    const SizedBox(width: 16),
                    Expanded(child: _buildMonthCard(context, currentMonthDate, isPrevMonth: false)),
                  ],
                )
              else
                Column(
                  children: [
                    _buildMonthCard(context, prevMonthDate, isPrevMonth: true),
                    const SizedBox(height: 16),
                    _buildMonthCard(context, currentMonthDate, isPrevMonth: false),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  // ===========================================================================
  // LEGEND & INFO BAR
  // ===========================================================================
  Widget _buildLegendBar(BuildContext context, DateTime prevMonth, DateTime currMonth) {
    final f = DateFormat('MMMM yyyy');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
            children: [
              const Icon(Icons.date_range, color: Color(0xFF0284C7), size: 20),
              const SizedBox(width: 8),
              Text(
                'Cross-Month Payroll Planner: ${f.format(prevMonth)}  ⟷  ${f.format(currMonth)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const Spacer(),
              const Text(
                '💡 Click any date to view leaves or record time-off',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildLegendItem(const Color(0xFF10B981), 'Day-off (วันหยุด)'),
              _buildLegendItem(const Color(0xFF0284C7), 'Work Days (วันทำงาน)'),
              _buildLegendItem(const Color(0xFFEF4444), 'Sick Leave (ลาป่วย)'),
              _buildLegendItem(const Color(0xFFF59E0B), 'Half-day (ครึ่งวัน)'),
              _buildLegendItem(const Color(0xFF8B5CF6), 'OT Days (ทำงานวันหยุด @ ฿180/วัน)'),
              Container(
                height: 14,
                width: 1,
                color: const Color(0xFFCBD5E1),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFFCD34D)),
                    ),
                    child: const Text('✂️ Cut-off', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF92400E))),
                  ),
                  const SizedBox(width: 6),
                  const Text('Cut-offs (1st, 10th, 20th)', style: TextStyle(fontSize: 12, color: Color(0xFF475569))),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
      ],
    );
  }

  // ===========================================================================
  // SINGLE MONTH CALENDAR CARD
  // ===========================================================================
  Widget _buildMonthCard(BuildContext context, DateTime monthDate, {required bool isPrevMonth}) {
    final monthName = DateFormat('MMMM yyyy').format(monthDate);
    final daysInMonth = DateTime(monthDate.year, monthDate.month + 1, 0).day;
    // Weekday: 1 = Monday, ..., 7 = Sunday
    final firstWeekday = DateTime(monthDate.year, monthDate.month, 1).weekday;
    final leadingBlanks = firstWeekday - 1; // Mon-based offset

    // Filter logs for this month
    final monthPrefix = '${monthDate.year}-${monthDate.month.toString().padLeft(2, '0')}';
    final monthLogs = attendanceLogs.where((l) => (l['date']?.toString() ?? '').startsWith(monthPrefix)).toList();
    final dayOffCount = monthLogs.where((l) => l['category'] == 'Day-off').length;
    final sickCount = monthLogs.where((l) => l['category'] == 'Sick').length;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isPrevMonth ? const Color(0xFFE2E8F0) : const Color(0xFFBAE6FD),
          width: isPrevMonth ? 1 : 1.5,
        ),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Month Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isPrevMonth ? const Color(0xFFF1F5F9) : const Color(0xFFE0F2FE),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    Icons.calendar_month,
                    size: 18,
                    color: isPrevMonth ? const Color(0xFF64748B) : const Color(0xFF0284C7),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              monthName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: isPrevMonth ? const Color(0xFFF1F5F9) : const Color(0xFFE0F2FE),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isPrevMonth ? 'Previous' : 'Current',
                              style: TextStyle(
                                fontSize: 9.5,
                                color: isPrevMonth ? const Color(0xFF64748B) : const Color(0xFF0284C7),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '🏖️ หยุด $dayOffCount วัน  •  🤒 ลา $sickCount วัน',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                if (onAutoScheduleMonth != null) ...[
                  const SizedBox(width: 6),
                  ElevatedButton.icon(
                    onPressed: () => onAutoScheduleMonth!(monthDate),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      visualDensity: VisualDensity.compact,
                      elevation: 1,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.auto_awesome, size: 14),
                    label: Text(
                      '⚡ จัดวันหยุด ${DateFormat('MMM').format(monthDate)}',
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
                if (onClearMonthDayOffs != null) ...[
                  const SizedBox(width: 6),
                  OutlinedButton.icon(
                    onPressed: () => onClearMonthDayOffs!(monthDate),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Color(0xFFFCA5A5)),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.delete_sweep_outlined, size: 14, color: Colors.red),
                    label: Text(
                      'ล้างวันหยุด ${DateFormat('MMM').format(monthDate)}',
                      style: const TextStyle(fontSize: 11.5, color: Colors.red, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),

            // Weekday Headers
            Row(
              children: const [
                _WeekdayHeader('Mon'),
                _WeekdayHeader('Tue'),
                _WeekdayHeader('Wed'),
                _WeekdayHeader('Thu'),
                _WeekdayHeader('Fri'),
                _WeekdayHeader('Sat', isWeekend: true),
                _WeekdayHeader('Sun', isWeekend: true),
              ],
            ),
            const SizedBox(height: 6),

            // Days Grid
            _buildDaysGrid(context, monthDate, leadingBlanks, daysInMonth),
          ],
        ),
      ),
    );
  }

  Widget _buildDaysGrid(BuildContext context, DateTime monthDate, int leadingBlanks, int daysInMonth) {
    final totalCells = leadingBlanks + daysInMonth;
    final totalRows = (totalCells / 7).ceil();

    final today = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(today);

    return Column(
      children: List.generate(totalRows, (rowIdx) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(7, (colIdx) {
              final cellIdx = rowIdx * 7 + colIdx;
              final dayNum = cellIdx - leadingBlanks + 1;

              if (dayNum < 1 || dayNum > daysInMonth) {
                // Empty cell
                return const Expanded(child: SizedBox(height: 75));
              }

              final cellDate = DateTime(monthDate.year, monthDate.month, dayNum);
              final cellDateStr = DateFormat('yyyy-MM-dd').format(cellDate);
              final isToday = cellDateStr == todayStr;
              final isWeekend = colIdx >= 5;

              // Check for cut-offs
              String? cutOffTag;
              if (dayNum == 1) cutOffTag = '✂️ Cut 1';
              if (dayNum == 10) cutOffTag = '✂️ Cut 10';
              if (dayNum == 20) cutOffTag = '✂️ Cut 20';

              // Find leaves on this day
              final dayLogs = attendanceLogs.where((l) => l['date'] == cellDateStr).toList();

              return Expanded(
                child: InkWell(
                  onTap: () => _showDayDetailDialog(context, cellDate, dayLogs, cutOffTag),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    height: 75,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isToday
                          ? const Color(0xFFEFF6FF)
                          : (isWeekend ? const Color(0xFFF8FAFC) : Colors.white),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isToday
                            ? const Color(0xFF3B82F6)
                            : (cutOffTag != null ? const Color(0xFFFCD34D) : const Color(0xFFE2E8F0)),
                        width: isToday || cutOffTag != null ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Day Number & Cut-off badge
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '$dayNum',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isToday ? FontWeight.bold : FontWeight.w600,
                                color: isToday
                                    ? const Color(0xFF1D4ED8)
                                    : (isWeekend ? const Color(0xFF94A3B8) : const Color(0xFF1E293B)),
                              ),
                            ),
                            if (cutOffTag != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  cutOffTag,
                                  style: const TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF92400E),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),

                        // Leaves Chips
                        Expanded(
                          child: dayLogs.isEmpty
                              ? const SizedBox.shrink()
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    ...dayLogs.take(2).map((log) => _buildMiniLeaveChip(log)),
                                    if (dayLogs.length > 2)
                                      Text(
                                        '+${dayLogs.length - 2} more',
                                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                                      ),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      }),
    );
  }

  Widget _buildMiniLeaveChip(Map<String, dynamic> log) {
    final cat = log['category']?.toString() ?? 'Day-off';
    final name = log['nickname']?.toString() ?? '';

    Color bg = const Color(0xFFDCFCE7);
    Color fg = const Color(0xFF166534);

    if (cat == 'Sick') {
      bg = const Color(0xFFFEE2E2);
      fg = const Color(0xFF991B1B);
    } else if (cat == 'Half-day') {
      bg = const Color(0xFFFEF3C7);
      fg = const Color(0xFF92400E);
    } else if (cat.contains('OT')) {
      bg = const Color(0xFFEDE9FE);
      fg = const Color(0xFF5B21B6);
    } else if (cat == 'Work Days') {
      bg = const Color(0xFFE0F2FE);
      fg = const Color(0xFF0369A1);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        '$name ($cat)',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }

  // ===========================================================================
  // DAY DETAIL MODAL DIALOG
  // ===========================================================================
  void _showDayDetailDialog(
    BuildContext context,
    DateTime date,
    List<Map<String, dynamic>> dayLogs,
    String? cutOffTag,
  ) {
    final df = DateFormat('EEEE, d MMMM yyyy');

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.event, color: Color(0xFF0284C7), size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      df.format(date),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    if (cutOffTag != null)
                      Text(
                        'Important: $cutOffTag of Payroll Cycle',
                        style: const TextStyle(fontSize: 12, color: Color(0xFFD97706), fontWeight: FontWeight.w600),
                      ),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Employees on Leave (${dayLogs.length}):',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 8),
                if (dayLogs.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'No leaves or attendance recorded for this date.',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: dayLogs.length,
                      separatorBuilder: (c, i) => const Divider(height: 8),
                      itemBuilder: (c, i) {
                        final log = dayLogs[i];
                        final cat = log['category'] ?? 'Day-off';
                        final note = log['note']?.toString() ?? '';

                        Color dotColor = const Color(0xFF10B981);
                        if (cat == 'Work Days') dotColor = const Color(0xFF0284C7);
                        if (cat == 'Sick') dotColor = const Color(0xFFEF4444);
                        if (cat == 'Half-day') dotColor = const Color(0xFFF59E0B);
                        if (cat.contains('OT')) dotColor = const Color(0xFF8B5CF6);

                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor: dotColor.withValues(alpha: 0.15),
                            child: Icon(Icons.person, size: 14, color: dotColor),
                          ),
                          title: Text(
                            '${log['nickname']} (${log['ep_code']})',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          subtitle: Text(
                            note.isNotEmpty ? '$cat • Note: $note' : cat,
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: dotColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  cat,
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: dotColor),
                                ),
                              ),
                              if (onDeleteAttendance != null) ...[
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                  tooltip: 'ยกเลิกวันหยุด / ลบรายการนี้',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () async {
                                    final nickname = log['nickname'] ?? '';
                                    final epCode = log['ep_code'] ?? '';
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (c) => AlertDialog(
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        title: const Row(
                                          children: [
                                            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 22),
                                            SizedBox(width: 8),
                                            Text('ยืนยันยกเลิกวันหยุด', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                        content: Text('ต้องการยกเลิกวันหยุดของ $nickname ($epCode) ในวันที่ ${DateFormat('dd/MM/yyyy').format(date)} หรือไม่?'),
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
                                      Navigator.pop(ctx);
                                      onDeleteAttendance!(log);
                                    }
                                  },
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                onAddAttendance(date);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Log for This Date'),
            ),
          ],
        );
      },
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  final String label;
  final bool isWeekend;

  const _WeekdayHeader(this.label, {this.isWeekend = false});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isWeekend ? const Color(0xFFEF4444) : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }
}
