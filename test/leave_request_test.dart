import 'package:flutter_test/flutter_test.dart';
import 'package:signature_payroll_app/models/leave_request.dart';
import 'package:signature_payroll_app/services/leave_request_service.dart';
import 'package:signature_payroll_app/services/localization_service.dart';

void main() {
  setUp(() {
    LeaveRequestService.initialize();
    // Clear requests for test
    final reqs = LeaveRequestService.getRequests();
    for (final r in reqs) {
      LeaveRequestService.cancelRequest(r.id);
    }
  });

  group('Leave Request & Approval Tests', () {
    test('Advance notice validation: rejects today and past dates', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));

      // Attempt today
      final resToday = LeaveRequestService.submitRequest(
        epCode: 'EP39',
        nickname: 'Cherry',
        date: today,
        category: 'Day-off',
        note: 'Emergency',
      );
      expect(resToday.success, isFalse);
      expect(resToday.error, 'date_too_soon');

      // Attempt yesterday
      final resYesterday = LeaveRequestService.submitRequest(
        epCode: 'EP39',
        nickname: 'Cherry',
        date: yesterday,
        category: 'Sick',
        note: 'Fever',
      );
      expect(resYesterday.success, isFalse);
      expect(resYesterday.error, 'date_too_soon');
    });

    test('Advance notice validation: accepts tomorrow and future dates with notes', () {
      final now = DateTime.now();
      final tomorrow = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
      final nextWeek = DateTime(now.year, now.month, now.day).add(const Duration(days: 7));

      // Tomorrow with Day-off and note
      final resTomorrow = LeaveRequestService.submitRequest(
        epCode: 'EP39',
        nickname: 'Cherry',
        date: tomorrow,
        category: 'Day-off',
        note: 'Personal family matter',
      );
      expect(resTomorrow.success, isTrue);
      expect(resTomorrow.request, isNotNull);
      expect(resTomorrow.request!.category, 'Day-off');
      expect(resTomorrow.request!.note, 'Personal family matter');
      expect(resTomorrow.request!.status, LeaveRequestStatus.pending);

      // Next week with Sick Leave and note
      final resSick = LeaveRequestService.submitRequest(
        epCode: 'EP01',
        nickname: 'Chujai',
        date: nextWeek,
        category: 'Sick',
        note: 'Doctor appointment checkup',
      );
      expect(resSick.success, isTrue);
      expect(resSick.request!.category, 'Sick');
      expect(resSick.request!.note, 'Doctor appointment checkup');
      expect(LeaveRequestService.pendingCountNotifier.value, 2);
    });

    test('Duplicate date validation: prevents duplicate active requests for same employee', () {
      final now = DateTime.now();
      final futureDate = DateTime(now.year, now.month, now.day).add(const Duration(days: 3));

      final first = LeaveRequestService.submitRequest(
        epCode: 'EP23',
        nickname: 'Aem',
        date: futureDate,
        category: 'Day-off',
        note: 'Rest day',
      );
      expect(first.success, isTrue);

      final second = LeaveRequestService.submitRequest(
        epCode: 'EP23',
        nickname: 'Aem',
        date: futureDate,
        category: 'Sick',
        note: 'Different reason same date',
      );
      expect(second.success, isFalse);
      expect(second.error, 'duplicate_date');
    });

    test('Approve request: marks approved and triggers attendance creator', () async {
      final now = DateTime.now();
      final futureDate = DateTime(now.year, now.month, now.day).add(const Duration(days: 4));

      final submitted = LeaveRequestService.submitRequest(
        epCode: 'EP10',
        nickname: 'Zin',
        date: futureDate,
        category: 'Day-off',
        note: 'Trip to Bangkok',
      );
      expect(submitted.success, isTrue);

      bool attendanceCreated = false;
      String? createdCategory;

      final approveSuccess = await LeaveRequestService.approveRequest(
        submitted.request!,
        onAttendanceCreated: (date, epCode, nickname, category, note) async {
          attendanceCreated = true;
          createdCategory = category;
          return true;
        },
      );

      expect(approveSuccess, isTrue);
      expect(attendanceCreated, isTrue);
      expect(createdCategory, 'Day-off');
      expect(submitted.request!.status, LeaveRequestStatus.approved);
      expect(submitted.request!.reviewedAt, isNotNull);
    });

    test('Reject request: marks rejected with reason', () {
      final now = DateTime.now();
      final futureDate = DateTime(now.year, now.month, now.day).add(const Duration(days: 5));

      final submitted = LeaveRequestService.submitRequest(
        epCode: 'EP05',
        nickname: 'Benz',
        date: futureDate,
        category: 'Day-off',
        note: 'Day-off request',
      );
      expect(submitted.success, isTrue);

      final rejected = LeaveRequestService.rejectRequest(submitted.request!, reason: 'Understaffed');
      expect(rejected, isTrue);
      expect(submitted.request!.status, LeaveRequestStatus.rejected);
      expect(submitted.request!.rejectionReason, 'Understaffed');
    });

    test('Cancel request: employee can cancel pending request', () {
      final now = DateTime.now();
      final futureDate = DateTime(now.year, now.month, now.day).add(const Duration(days: 6));

      final submitted = LeaveRequestService.submitRequest(
        epCode: 'EP15',
        nickname: 'Fern',
        date: futureDate,
        category: 'Day-off',
      );
      expect(submitted.success, isTrue);
      expect(LeaveRequestService.getRequests(epCode: 'EP15').length, 1);

      final cancelled = LeaveRequestService.cancelRequest(submitted.request!.id);
      expect(cancelled, isTrue);
      expect(LeaveRequestService.getRequests(epCode: 'EP15').isEmpty, isTrue);
    });

    test('Conflict detection helper correctly finds other off employees', () {
      final targetDate = DateTime(2026, 9, 20);
      final logs = [
        {'date': '2026-09-20', 'ep_code': 'EP10', 'nickname': 'Zin', 'category': 'Day-off'},
        {'date': '2026-09-20', 'ep_code': 'EP39', 'nickname': 'Cherry', 'category': 'Sick'},
        {'date': '2026-09-20', 'ep_code': 'EP01', 'nickname': 'Chujai', 'category': 'Work Days'},
        {'date': '2026-09-21', 'ep_code': 'EP05', 'nickname': 'Benz', 'category': 'Day-off'},
      ];

      final conflicts = LeaveRequestService.getConflictingEmployees(targetDate, logs, excludeEpCode: 'EP15');
      expect(conflicts.length, 2);
      expect(conflicts, contains('Zin'));
      expect(conflicts, contains('Cherry'));
      expect(conflicts, isNot(contains('Chujai')));
      expect(conflicts, isNot(contains('Benz')));
    });

    test('Localization contains all leave request terms in TH and MY', () {
      expect(L10n.tabLeaveRequest.get(SubLanguage.thai), contains('ขอวันหยุด'));
      expect(L10n.tabLeaveRequest.get(SubLanguage.burmese), contains('ခွင့်တောင်းဆိုခြင်း'));

      expect(L10n.advanceNoticeRule.get(SubLanguage.thai), contains('1 วัน'));
      expect(L10n.advanceNoticeRule.get(SubLanguage.burmese), contains('၁ ရက်'));

      expect(L10n.btnApprove.get(SubLanguage.thai), contains('อนุมัติ'));
      expect(L10n.btnApprove.get(SubLanguage.burmese), contains('အတည်ပြုသည်'));

      expect(L10n.btnIgnore.get(SubLanguage.thai), contains('ปฏิเสธ'));
      expect(L10n.btnIgnore.get(SubLanguage.burmese), contains('ငြင်းပယ်သည်'));
    });
  });
}
