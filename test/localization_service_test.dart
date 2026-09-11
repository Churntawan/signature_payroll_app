import 'package:flutter_test/flutter_test.dart';
import 'package:signature_payroll_app/services/localization_service.dart';

void main() {
  group('Localization Service & Dictionary Tests', () {
    test('SubLanguage fromCode resolves properly', () {
      expect(SubLanguage.fromCode('th'), SubLanguage.thai);
      expect(SubLanguage.fromCode('my'), SubLanguage.burmese);
      expect(SubLanguage.fromCode('unknown'), SubLanguage.thai);
      expect(SubLanguage.fromCode(null), SubLanguage.thai);
    });

    test('AppText formats English primary with Thai secondary in parentheses', () {
      const text = AppText(en: 'Net Pay', th: 'ยอดรับสุทธิ', my: 'အသားတင်ရရှိငွေ');
      expect(text.get(SubLanguage.thai), 'Net Pay (ยอดรับสุทธิ)');
      expect(text.sub(SubLanguage.thai), 'ยอดรับสุทธิ');
      expect(text.primary, 'Net Pay');
    });

    test('AppText formats English primary with Burmese secondary in parentheses', () {
      const text = AppText(en: 'Net Pay', th: 'ยอดรับสุทธิ', my: 'အသားတင်ရရှိငွေ');
      expect(text.get(SubLanguage.burmese), 'Net Pay (အသားတင်ရရှိငွေ)');
      expect(text.sub(SubLanguage.burmese), 'အသားတင်ရရှိငွေ');
      expect(text.primary, 'Net Pay');
    });

    test('L10n contains essential payroll and payslip dictionary terms', () {
      // Payslip items
      expect(L10n.baseSalary.get(SubLanguage.thai), contains('เงินเดือน'));
      expect(L10n.baseSalary.get(SubLanguage.burmese), contains('လစာ'));

      expect(L10n.housingAllowance.get(SubLanguage.thai), contains('ค่าห้องพัก'));
      expect(L10n.housingAllowance.get(SubLanguage.burmese), contains('အိမ်ခန်းစရိတ်'));

      expect(L10n.overtimePay.get(SubLanguage.thai), contains('ค่าล่วงเวลา'));
      expect(L10n.overtimePay.get(SubLanguage.burmese), contains('အချိန်ပိုကြေး'));

      expect(L10n.advanceDeduction.get(SubLanguage.thai), contains('หักเงินเบิกล่วงหน้า'));
      expect(L10n.advanceDeduction.get(SubLanguage.burmese), contains('ကြိုထုတ်ငွေ'));

      expect(L10n.netSalary.get(SubLanguage.thai), contains('ยอดรับสุทธิ'));
      expect(L10n.netSalary.get(SubLanguage.burmese), contains('အသားတင်'));

      // Status badges
      expect(L10n.statusDayOff.get(SubLanguage.thai), contains('วันหยุด'));
      expect(L10n.statusDayOff.get(SubLanguage.burmese), contains('နားရက်'));

      expect(L10n.statusSick.get(SubLanguage.thai), contains('ลาป่วย'));
      expect(L10n.statusSick.get(SubLanguage.burmese), contains('ဖျားနာခွင့်'));
    });

    test('Day name resolver produces correct localized days', () {
      expect(L10n.getDayName(DateTime.monday, SubLanguage.thai), 'Monday (จันทร์)');
      expect(L10n.getDayName(DateTime.monday, SubLanguage.burmese), 'Monday (တနင်္လာ)');
      expect(L10n.getDayName(DateTime.sunday, SubLanguage.thai), 'Sunday (อาทิตย์)');
      expect(L10n.getDayName(DateTime.sunday, SubLanguage.burmese), 'Sunday (တနင်္ဂနွေ)');
    });

    test('L10n.setSubLanguage updates current value notifier', () {
      L10n.setSubLanguage(SubLanguage.burmese);
      expect(L10n.sub, SubLanguage.burmese);
      expect(L10n.currentSubLang.value, SubLanguage.burmese);

      L10n.setSubLanguage(SubLanguage.thai);
      expect(L10n.sub, SubLanguage.thai);
      expect(L10n.currentSubLang.value, SubLanguage.thai);
    });
  });
}
