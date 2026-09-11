import 'package:flutter/foundation.dart';
import 'session_storage.dart';

enum SubLanguage {
  thai('th', 'ไทย', '🇹🇭'),
  burmese('my', 'မြန်မာ', '🇲🇲');

  final String code;
  final String label;
  final String flag;
  const SubLanguage(this.code, this.label, this.flag);

  static SubLanguage fromCode(String? code) {
    if (code == 'my') return SubLanguage.burmese;
    return SubLanguage.thai;
  }
}

class AppText {
  final String en;
  final String th;
  final String my;

  const AppText({required this.en, required this.th, required this.my});

  /// Returns "$en ($sub)" format e.g. "Base Salary (เงินเดือนพื้นฐาน)"
  String get(SubLanguage sub) {
    final subText = sub == SubLanguage.thai ? th : my;
    if (subText.isEmpty) return en;
    return '$en ($subText)';
  }

  /// Returns only the secondary language string e.g. "เงินเดือนพื้นฐาน" or "အခြေခံလစာ"
  String sub(SubLanguage sub) {
    return sub == SubLanguage.thai ? th : my;
  }

  /// Returns only English
  String get primary => en;
}

class L10n {
  static final ValueNotifier<SubLanguage> currentSubLang =
      ValueNotifier<SubLanguage>(loadSavedSubLanguage());

  static SubLanguage get sub => currentSubLang.value;

  static SubLanguage loadSavedSubLanguage() {
    final saved = SessionStorage.get('sp_sub_lang');
    return SubLanguage.fromCode(saved);
  }

  static void setSubLanguage(SubLanguage lang) {
    SessionStorage.set('sp_sub_lang', lang.code);
    currentSubLang.value = lang;
  }

  // ===========================================================================
  // AUTH & LOGIN
  // ===========================================================================
  static const appTitle = AppText(
    en: 'SIGNATURE PAYROLL',
    th: 'ระบบเงินเดือนซิกเนเจอร์',
    my: 'ဆစ်ဂနေးချာ လစာစီမံခန့်ခွဲမှု',
  );

  static const roleAdmin = AppText(
    en: 'Admin',
    th: 'ผู้ดูแลระบบ',
    my: 'စီမံခန့်ခွဲသူ',
  );

  static const roleStaff = AppText(
    en: 'Staff',
    th: 'พนักงาน',
    my: 'ဝန်ထမ်း',
  );

  static const password = AppText(
    en: 'Password',
    th: 'รหัสผ่าน',
    my: 'စကားဝှက်',
  );

  static const passwordHint = AppText(
    en: 'Enter admin password',
    th: 'กรอกรหัสผ่านผู้ดูแลระบบ',
    my: 'စီမံခန့်ခွဲသူ စကားဝှက်ထည့်ပါ',
  );

  static const employeeCode = AppText(
    en: 'Employee Code',
    th: 'รหัสพนักงาน',
    my: 'ဝန်ထမ်းကုဒ်',
  );

  static const employeeCodeHint = AppText(
    en: 'e.g. EP39 or EP01',
    th: 'เช่น EP39 หรือ EP01',
    my: 'ဥပမာ EP39 သို့မဟုတ် EP01',
  );

  static const pinCode = AppText(
    en: 'PIN Code',
    th: 'รหัส PIN',
    my: 'ပင်နံပါတ်',
  );

  static const pinCodeHint = AppText(
    en: '4-6 digit PIN (Default: 1234)',
    th: 'รหัส PIN 4-6 หลัก (ค่าเริ่มต้น: 1234)',
    my: '၄-၆ လုံး ပင်နံပါတ် (နဂို: 1234)',
  );

  static const rememberSession = AppText(
    en: 'Remember Login',
    th: 'จดจำการเข้าสู่ระบบ',
    my: 'အကောင့်မှတ်ထားမည်',
  );

  static const loginButton = AppText(
    en: 'Sign In',
    th: 'เข้าสู่ระบบ',
    my: 'အကောင့်ဝင်ရန်',
  );

  static const logoutButton = AppText(
    en: 'Logout',
    th: 'ออกจากระบบ',
    my: 'အကောင့်ထွက်ရန်',
  );

  static const logoutConfirmTitle = AppText(
    en: 'Confirm Logout',
    th: 'ยืนยันออกจากระบบ',
    my: 'အကောင့်ထွက်ရန် အတည်ပြုပါ',
  );

  static const logoutConfirmMessage = AppText(
    en: 'Do you want to sign out from the portal?',
    th: 'คุณต้องการออกจากระบบใช่หรือไม่?',
    my: 'အကောင့်မှ ထွက်ခွာလိုပါသလား?',
  );

  static const cancel = AppText(
    en: 'Cancel',
    th: 'ยกเลิก',
    my: 'မလုပ်တော့ပါ',
  );

  static const errAdminPwdEmpty = AppText(
    en: 'Please enter admin password',
    th: 'กรุณากรอกรหัสผ่านผู้ดูแลระบบ',
    my: 'စီမံခန့်ခွဲသူ စကားဝှက်ထည့်ပါ',
  );

  static const errAdminPwdWrong = AppText(
    en: 'Incorrect password. Please try again.',
    th: 'รหัสผ่านไม่ถูกต้อง กรุณาลองใหม่อีกครั้ง',
    my: 'စကားဝှက်မှားယွင်းနေပါသည်။ ထပ်မံကြိုးစားပါ။',
  );

  static const errEpCodeEmpty = AppText(
    en: 'Please enter employee code',
    th: 'กรุณาระบุรหัสพนักงาน (เช่น EP39)',
    my: 'ဝန်ထမ်းကုဒ်ထည့်ပါ (ဥပမာ EP39)',
  );

  static const errPinEmpty = AppText(
    en: 'Please enter 4-6 digit PIN',
    th: 'กรุณาระบุรหัส PIN 4-6 หลัก',
    my: '၄-၆ လုံး ပင်နံပါတ်ထည့်ပါ',
  );

  static const errEmployeeNotFound = AppText(
    en: 'Invalid Employee Code or PIN',
    th: 'รหัสพนักงานหรือ PIN ไม่ถูกต้อง',
    my: 'ဝန်ထမ်းကုဒ် သို့မဟုတ် ပင်နံပါတ် မှားယွင်းနေပါသည်',
  );

  // ===========================================================================
  // TABS & NAVIGATION
  // ===========================================================================
  static const tabPayslip = AppText(
    en: 'Payslip',
    th: 'สลิปเงินเดือน',
    my: 'လစာစလစ်',
  );

  static const tabSchedule = AppText(
    en: 'Work Schedule',
    th: 'ตารางวันหยุด & เวลา',
    my: 'အလုပ်ချိန်နှင့် နားရက်ဇယား',
  );

  // ===========================================================================
  // PAYSLIP
  // ===========================================================================
  static const payslipTitle = AppText(
    en: 'PAYSLIP',
    th: 'ใบแจ้งเงินเดือน',
    my: 'လစာရှင်းတမ်း စလစ်',
  );

  static const periodLabel = AppText(
    en: 'Period',
    th: 'งวดประจำเดือน',
    my: 'လစာကာလ',
  );

  static const workCycle = AppText(
    en: 'Work Cycle',
    th: 'รอบการทำงาน',
    my: 'အလုပ်ဆင်းသည့် ကာလ',
  );

  static const payDate = AppText(
    en: 'Pay Date',
    th: 'วันที่จ่ายเงิน',
    my: 'လစာထုတ်ရက်',
  );

  static const paidOn = AppText(
    en: 'Paid on',
    th: 'ชำระแล้วเมื่อ',
    my: 'ပေးချေပြီးသည့်ရက်',
  );

  static const pendingPayDateTitle = AppText(
    en: 'Payslip Pending',
    th: 'สลิปเงินเดือนอยู่ระหว่างดำเนินการ',
    my: 'လစာစလစ် စိစစ်ဆဲဖြစ်ပါသည်',
  );

  static const pendingPayDateDesc = AppText(
    en: '🔒 Current payslip is under calculation.\nFull payslip details will be available on the scheduled pay date.',
    th: '🔒 ยอดเงินเดือนอยู่ระหว่างการคำนวณและปรับปรุงรอบงวด\nระบบจะเปิดให้ตรวจสอบสลิปเงินเดือนได้เมื่อถึงกำหนดวันจ่ายเงินเดือนครับ',
    my: '🔒 လစာအား စိစစ်တွက်ချက်နေဆဲဖြစ်ပါသည်။\nသတ်မှတ်လစာထုတ်ရက်ရောက်မှသာ စလစ်အပြည့်အစုံကို ကြည့်ရှုနိုင်ပါမည်။',
  );

  static const viewScheduleBtn = AppText(
    en: 'View Work & Leave Calendar',
    th: 'ดูตารางวันหยุด & วันทำงานที่บันทึกไว้',
    my: 'နားရက်နှင့် အလုပ်ဆင်းမှတ်တမ်း ကြည့်ရန်',
  );

  static const saveSlipImageBtn = AppText(
    en: 'Save Slip Image',
    th: 'บันทึกรูปสลิป',
    my: 'လစာစလစ်ပုံ သိမ်းဆည်းရန်',
  );

  static const slipImageSaved = AppText(
    en: 'Payslip image saved successfully',
    th: 'บันทึกรูปภาพสลิปเงินเดือนเรียบร้อยแล้ว',
    my: 'လစာစလစ်ပုံ သိမ်းဆည်းပြီးပါပြီ',
  );

  // Profile fields
  static const fieldCode = AppText(
    en: 'Employee Code',
    th: 'รหัสพนักงาน',
    my: 'ဝန်ထမ်းကုဒ်',
  );

  static const fieldPayGroup = AppText(
    en: 'Pay Group',
    th: 'กลุ่มการจ่าย',
    my: 'လစာထုတ်အုပ်စု',
  );

  // Summary badges
  static const badgeWorkedDays = AppText(
    en: 'Worked Days',
    th: 'วันทำงานจริง',
    my: 'အလုပ်ဆင်းရက်',
  );

  static const badgeDayOff = AppText(
    en: 'Day-off',
    th: 'วันหยุด',
    my: 'နားရက်',
  );

  static const badgeSickLeave = AppText(
    en: 'Sick Leave',
    th: 'ลาป่วย',
    my: 'ဖျားနာခွင့်',
  );

  static const unitDays = AppText(
    en: 'Days',
    th: 'วัน',
    my: 'ရက်',
  );

  // Earnings section
  static const sectionEarnings = AppText(
    en: 'EARNINGS',
    th: 'รายได้',
    my: 'ရရှိသော ဝင်ငွေများ',
  );

  static const baseSalary = AppText(
    en: 'Base Salary / Daily Wage',
    th: 'เงินเดือน / ค่าจ้างฐาน',
    my: 'လစာ / အခြေခံနေ့တွက်ခ',
  );

  static const housingAllowance = AppText(
    en: 'Housing Allowance',
    th: 'ค่าห้องพัก',
    my: 'အိမ်ခန်းစရိတ်',
  );

  static const overtimePay = AppText(
    en: 'Overtime Pay (OT)',
    th: 'ค่าล่วงเวลา',
    my: 'အချိန်ပိုကြေး (OT)',
  );

  static const bonusPay = AppText(
    en: 'Bonus / Incentive',
    th: 'โบนัส / เบี้ยขยัน',
    my: 'အပိုဆုကြေး / ဘောနပ်စ်',
  );

  static const otherExtra = AppText(
    en: 'Other Income',
    th: 'รายรับอื่นๆ',
    my: 'အခြားဝင်ငွေ',
  );

  static const totalEarnings = AppText(
    en: 'Total Earnings',
    th: 'รวมรายรับทั้งสิ้น',
    my: 'စုစုပေါင်း ဝင်ငွေ',
  );

  // Deductions section
  static const sectionDeductions = AppText(
    en: 'DEDUCTIONS',
    th: 'รายการหัก',
    my: 'ဖြတ်တောက်ငွေများ',
  );

  static const advanceDeduction = AppText(
    en: 'Advance Loan',
    th: 'หักเงินเบิกล่วงหน้า',
    my: 'ကြိုထုတ်ငွေ ဖြတ်တောက်ခြင်း',
  );

  static const workPermitDeduction = AppText(
    en: 'Work Permit / Passport',
    th: 'หักค่าเอกสาร/พาสปอร์ต',
    my: 'ပတ်စပို့/လက်မှတ်ကြေး ဖြတ်တောက်ခြင်း',
  );

  static const excessDayOffDeduction = AppText(
    en: 'Excess Day-off',
    th: 'หักหยุดเกินโควตา',
    my: 'နားရက်ကျော် ဖြတ်တောက်ခြင်း',
  );

  static const otherDeduction = AppText(
    en: 'Other Deduction',
    th: 'หักรายการอื่นๆ',
    my: 'အခြားဖြတ်တောက်ငွေ',
  );

  static const noDeductions = AppText(
    en: 'No deductions in this period',
    th: 'ไม่มีรายการหักเงินในงวดนี้',
    my: 'ဤလတွင် ဖြတ်တောက်ငွေ မရှိပါ',
  );

  static const totalDeductions = AppText(
    en: 'Total Deductions',
    th: 'รวมรายการหักทั้งสิ้น',
    my: 'စုစုပေါင်း ဖြတ်တောက်ငွေ',
  );

  // Net Pay
  static const netSalary = AppText(
    en: 'NET SALARY',
    th: 'ยอดรับสุทธิ',
    my: 'အသားတင် ရရှိငွေ',
  );

  // ===========================================================================
  // ATTENDANCE & SCHEDULE TAB
  // ===========================================================================
  static const scheduleHeaderTitle = AppText(
    en: 'Work & Leave Schedule',
    th: 'บันทึกวันหยุดและเวลาทำงาน',
    my: 'အလုပ်ချိန်နှင့် နားရက်မှတ်တမ်း',
  );

  static const readOnlyNotice = AppText(
    en: 'Read-Only',
    th: 'ดูได้อย่างเดียว',
    my: 'ကြည့်ရှုရန်သာ',
  );

  static const scheduleHistoryTitle = AppText(
    en: 'Day-off & Leave Log in this Period',
    th: 'ประวัติวันหยุดและวันลาในงวดนี้',
    my: 'ဤလအတွက် နားရက်နှင့် ခွင့်မှတ်တမ်း',
  );

  static const noAttendanceInPeriod = AppText(
    en: 'No leave or day-off records for this cycle',
    th: 'ยังไม่มีรายการวันหยุดที่ถูกบันทึกในงวดนี้',
    my: 'ဤလအတွက် နားရက်မှတ်တမ်း မရှိသေးပါ',
  );

  static const statusDayOff = AppText(
    en: 'Day-off',
    th: 'วันหยุด',
    my: 'နားရက်',
  );

  static const statusSick = AppText(
    en: 'Sick Leave',
    th: 'ลาป่วย',
    my: 'ဖျားနာခွင့်',
  );

  static const statusWork = AppText(
    en: 'Work',
    th: 'มาทำงาน',
    my: 'အလုပ်ဆင်း',
  );

  // Day names for schedule
  static const dayMon = AppText(en: 'Monday', th: 'จันทร์', my: 'တနင်္လာ');
  static const dayTue = AppText(en: 'Tuesday', th: 'อังคาร', my: 'အင်္ဂါ');
  static const dayWed = AppText(en: 'Wednesday', th: 'พุธ', my: 'ဗုဒ္ဓဟူး');
  static const dayThu = AppText(en: 'Thursday', th: 'พฤหัสบดี', my: 'ကြာသပတေး');
  static const dayFri = AppText(en: 'Friday', th: 'ศุกร์', my: 'သောကြာ');
  static const daySat = AppText(en: 'Saturday', th: 'เสาร์', my: 'စနေ');
  static const daySun = AppText(en: 'Sunday', th: 'อาทิตย์', my: 'တနင်္ဂနွေ');

  static String getDayName(int weekday, SubLanguage sub) {
    switch (weekday) {
      case DateTime.monday: return dayMon.get(sub);
      case DateTime.tuesday: return dayTue.get(sub);
      case DateTime.wednesday: return dayWed.get(sub);
      case DateTime.thursday: return dayThu.get(sub);
      case DateTime.friday: return dayFri.get(sub);
      case DateTime.saturday: return daySat.get(sub);
      case DateTime.sunday: return daySun.get(sub);
      default: return '';
    }
  }

  // ===========================================================================
  // LEAVE REQUESTS & APPROVAL NOTIFICATIONS
  // ===========================================================================
  static const tabLeaveRequest = AppText(
    en: 'Request Leave',
    th: 'ขอวันหยุด',
    my: 'ခွင့်တောင်းဆိုခြင်း',
  );

  static const leaveRequestTitle = AppText(
    en: 'Submit Leave Request',
    th: 'แบบฟอร์มขอวันหยุด & ลาป่วย',
    my: 'ခွင့်တောင်းဆိုလွှာ',
  );

  static const leaveType = AppText(
    en: 'Leave Type',
    th: 'ประเภทการลา',
    my: 'ခွင့်အမျိုးအစား',
  );

  static const typeDayOff = AppText(
    en: 'Day-off',
    th: 'วันหยุดปกติ',
    my: 'နားရက်',
  );

  static const typeSick = AppText(
    en: 'Sick Leave',
    th: 'ลาป่วย',
    my: 'ဖျားနာခွင့်',
  );

  static const selectDate = AppText(
    en: 'Requested Date',
    th: 'วันที่ต้องการขอลา',
    my: 'ခွင့်ယူမည့်ရက်',
  );

  static const advanceNoticeRule = AppText(
    en: 'Must request at least 1 day in advance (Tomorrow onwards)',
    th: 'ต้องขอล่วงหน้าอย่างน้อย 1 วัน (เริ่มตั้งแต่วันพรุ่งนี้เป็นต้นไป)',
    my: 'အနည်းဆုံး ၁ ရက် ကြိုတင်တောင်းဆိုရမည် (မနက်ဖြန်မှစ၍)',
  );

  static const noteLabel = AppText(
    en: 'Reason / Note',
    th: 'หมายเหตุ / เหตุผล',
    my: 'အကြောင်းပြချက် / မှတ်ချက်',
  );

  static const noteHint = AppText(
    en: 'Enter note or reason (Optional)',
    th: 'ระบุเหตุผลหรือรายละเอียดเพิ่มเติม (ถ้ามี)',
    my: 'အကြောင်းပြချက် ထည့်သွင်းပါ (မထည့်လည်းရပါသည်)',
  );

  static const submitRequestBtn = AppText(
    en: 'Submit Request',
    th: 'ส่งคำขอวันหยุด',
    my: 'တောင်းဆိုလွှာ တင်ရန်',
  );

  static const requestSubmittedSuccess = AppText(
    en: 'Leave request submitted! Waiting for Admin review.',
    th: 'ส่งคำขอเรียบร้อยแล้ว! กำลังรอผู้ดูแลตรวจสอบ',
    my: 'ခွင့်တောင်းဆိုလွှာ တင်ပြီးပါပြီ။ စီမံခန့်ခွဲသူ စိစစ်မှုကို စောင့်ဆိုင်းနေပါသည်။',
  );

  static const myRequestsTitle = AppText(
    en: 'My Leave Requests History',
    th: 'ประวัติคำขอวันหยุดของฉัน',
    my: 'ကျွန်ုပ်၏ ခွင့်တောင်းဆိုမှု မှတ်တမ်း',
  );

  static const noRequestsYet = AppText(
    en: 'No leave requests submitted yet',
    th: 'ยังไม่มีประวัติการขอวันหยุด',
    my: 'ခွင့်တောင်းဆိုမှု မှတ်တမ်း မရှိသေးပါ',
  );

  static const statusPending = AppText(
    en: 'Pending',
    th: 'รออนุมัติ',
    my: 'စိစစ်ဆဲ',
  );

  static const statusApproved = AppText(
    en: 'Approved',
    th: 'อนุมัติแล้ว',
    my: 'ခွင့်ပြုပြီး',
  );

  static const statusRejected = AppText(
    en: 'Ignored',
    th: 'ไม่อนุมัติ',
    my: 'ငြင်းပယ်သည်',
  );

  static const btnCancel = AppText(
    en: 'Cancel',
    th: 'ยกเลิก',
    my: 'ပယ်ဖျက်ရန်',
  );

  static const btnApprove = AppText(
    en: 'Approve',
    th: 'อนุมัติ',
    my: 'အတည်ပြုသည်',
  );

  static const btnIgnore = AppText(
    en: 'Ignore',
    th: 'ปฏิเสธ',
    my: 'ငြင်းပယ်သည်',
  );

  static const adminBellTitle = AppText(
    en: 'Pending Leave Requests',
    th: 'คำขอวันหยุดรอการอนุมัติ',
    my: 'စိစစ်ရန် ခွင့်တောင်းဆိုမှုများ',
  );

  static const noPendingNotif = AppText(
    en: 'No pending leave requests at this time',
    th: 'ไม่มีคำขอวันหยุดที่รออนุมัติในขณะนี้',
    my: 'လောလောဆယ် စိစစ်ရန် ခွင့်တောင်းဆိုမှု မရှိပါ',
  );

  static const conflictNotice = AppText(
    en: 'other staff off on this day',
    th: 'คนหยุดในวันเดียวกันนี้แล้ว',
    my: 'ဦး ဤရက်တွင် နားရက်ရှိပြီးဖြစ်သည်',
  );

  static const errDateTooSoon = AppText(
    en: 'Cannot request for today or past dates. Please request at least 1 day in advance.',
    th: 'ไม่สามารถขอสำหรับวันนี้หรืออดีตได้ กรุณาขอล่วงหน้าอย่างน้อย 1 วัน',
    my: 'ယနေ့ သို့မဟုတ် ယခင်ရက်အတွက် တောင်းဆို၍မရပါ။ အနည်းဆုံး ၁ ရက် ကြိုတင်တောင်းဆိုပါ။',
  );

  static const errDuplicateDate = AppText(
    en: 'You already have an active request for this date',
    th: 'คุณมีคำขอสำหรับวันที่นี้อยู่แล้ว',
    my: 'ဤရက်အတွက် တောင်းဆိုထားပြီးဖြစ်ပါသည်',
  );
}
