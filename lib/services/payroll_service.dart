import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class PayrollService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Collection Names
  static const String colSalaries = 'staff_salary';
  static const String colPayrolls = 'payroll';
  static const String colPayrollItems = 'payroll_items';
  static const String colOvertime = 'overtime_records'; // Assuming this exists or I'll create it
  static const String colLeaves = 'leave_requests';

  // --- Salary Definitions ---

  Future<void> upsertSalaryDefinition({
    required String staffId,
    required String institutionId,
    required double baseSalary,
    required String salaryType, // monthly / hourly
    double? extraHourRate, // for teachers
    double? overtimeHourRate, // for admin/support
  }) async {
    await _firestore.collection(colSalaries).doc(staffId).set({
      'staffId': staffId,
      'institutionId': institutionId,
      'baseSalary': baseSalary,
      'salaryType': salaryType,
      'extraHourRate': extraHourRate ?? 0.0,
      'overtimeHourRate': overtimeHourRate ?? 0.0,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>?> getSalaryDefinition(String staffId) async {
    final doc = await _firestore.collection(colSalaries).doc(staffId).get();
    return doc.exists ? doc.data() : null;
  }

  Future<List<Map<String, dynamic>>> getAllSalaries(String institutionId) async {
    final query = await _firestore
        .collection(colSalaries)
        .where('institutionId', isEqualTo: institutionId)
        .get();
    return query.docs.map((e) => e.data()).toList();
  }

  // --- Overtime & Extra Hours ---

  Future<double> getTotalOvertimeAmount(String staffId, int month, int year) async {
    // Mesai modülünden gelen: staff_id, date, total_amount or hours
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 0);
    final startStr = DateFormat('yyyy-MM-dd').format(start);
    final endStr = DateFormat('yyyy-MM-dd').format(end);

    try {
      final query = await _firestore
          .collection(colOvertime)
          .where('staffId', isEqualTo: staffId)
          .where('date', isGreaterThanOrEqualTo: startStr)
          .where('date', isLessThanOrEqualTo: endStr)
          .get();

      double total = 0.0;
      for (var doc in query.docs) {
        total += (doc.data()['totalAmount'] ?? 0.0).toDouble();
      }
      return total;
    } catch (e) {
      print("Overtime fetch error (maybe no records): $e");
      return 0.0;
    }
  }

  // --- Leave Deductions ---

  Future<double> getUnpaidLeaveDeduction(String staffId, int month, int year, double dailySalary) async {
    final startStr = DateFormat('yyyy-MM-01').format(DateTime(year, month, 1));
    final endStr = DateFormat('yyyy-MM-dd').format(DateTime(year, month + 1, 0));

    try {
      final query = await _firestore
          .collection(colLeaves)
          .where('staffId', isEqualTo: staffId)
          .where('status', isEqualTo: 'approved')
          .where('leaveType', isEqualTo: 'Ücretsiz İzin')
          .get();

      double totalDeduction = 0.0;
      for (var doc in query.docs) {
        final data = doc.data();
        final sDate = data['startDate'].toString();
        // Overlap logic simplified
        if (sDate.compareTo(startStr) >= 0 && sDate.compareTo(endStr) <= 0) {
          final days = (data['totalDays'] ?? 0).toDouble();
          totalDeduction += days * dailySalary;
        }
      }
      return totalDeduction;
    } catch (e) {
      return 0.0;
    }
  }

  // --- Payroll Generation ---

  Future<String> generatePayroll({
    required String staffId,
    required String institutionId,
    required int month,
    required int year,
    double extraLectures = 0.0,
    double customBonus = 0.0,
    double customDeduction = 0.0,
  }) async {
    final existing = await _firestore
        .collection(colPayrolls)
        .where('staffId', isEqualTo: staffId)
        .where('month', isEqualTo: month)
        .where('year', isEqualTo: year)
        .limit(1)
        .get();
    
    if (existing.docs.isNotEmpty) {
      throw Exception('Bu ay için zaten bir bordro oluşturulmuş.');
    }

    final salary = await getSalaryDefinition(staffId);
    if (salary == null) throw Exception('Maaş tanımı bulunamadı.');

    final double base = (salary['baseSalary'] ?? 0.0).toDouble();
    final double hourlyRate = (salary['extraHourRate'] ?? 0.0).toDouble();
    
    final double overtimeAmount = await getTotalOvertimeAmount(staffId, month, year);
    final double extraLectureAmount = extraLectures * hourlyRate;
    
    double totalEarnings = base + overtimeAmount + extraLectureAmount + customBonus;

    final double dailySalary = base / 30.0;
    final double leaveDeduction = await getUnpaidLeaveDeduction(staffId, month, year, dailySalary);
    
    double totalDeductions = leaveDeduction + customDeduction;

    double netSalary = totalEarnings - totalDeductions;
    if (netSalary < 0) netSalary = 0;

    final pDoc = await _firestore.collection(colPayrolls).add({
      'staffId': staffId,
      'institutionId': institutionId,
      'month': month,
      'year': year,
      'baseSalary': base,
      'totalEarnings': totalEarnings,
      'totalDeductions': totalDeductions,
      'netSalary': netSalary,
      'status': 'draft',
      'createdAt': FieldValue.serverTimestamp(),
    });

    final batch = _firestore.batch();
    
    batch.set(_firestore.collection(colPayrollItems).doc(), {
      'payrollId': pDoc.id,
      'type': 'earning',
      'title': 'Temel Maaş',
      'amount': base,
    });
    if (overtimeAmount > 0) {
      batch.set(_firestore.collection(colPayrollItems).doc(), {
        'payrollId': pDoc.id,
        'type': 'earning',
        'title': 'Fazla Mesai',
        'amount': overtimeAmount,
      });
    }
    if (extraLectureAmount > 0) {
      batch.set(_firestore.collection(colPayrollItems).doc(), {
        'payrollId': pDoc.id,
        'type': 'earning',
        'title': 'Ek Ders Ücreti ($extraLectures Saat)',
        'amount': extraLectureAmount,
      });
    }
    if (customBonus > 0) {
       batch.set(_firestore.collection(colPayrollItems).doc(), {
        'payrollId': pDoc.id,
        'type': 'earning',
        'title': 'Ek Kazanç / Prim',
        'amount': customBonus,
      });
    }

    if (leaveDeduction > 0) {
      batch.set(_firestore.collection(colPayrollItems).doc(), {
        'payrollId': pDoc.id,
        'type': 'deduction',
        'title': 'Ücretsiz İzin Kesintisi',
        'amount': leaveDeduction,
      });
    }
    if (customDeduction > 0) {
      batch.set(_firestore.collection(colPayrollItems).doc(), {
        'payrollId': pDoc.id,
        'type': 'deduction',
        'title': 'Diğer Kesintiler',
        'amount': customDeduction,
      });
    }

    await batch.commit();
    return pDoc.id;
  }

  // --- Getters ---

  Future<List<Map<String, dynamic>>> getPayrolls({
    required String institutionId,
    int? month,
    int? year,
    String? staffId,
  }) async {
    Query query = _firestore.collection(colPayrolls).where('institutionId', isEqualTo: institutionId);
    
    if (month != null) query = query.where('month', isEqualTo: month);
    if (year != null) query = query.where('year', isEqualTo: year);
    if (staffId != null) query = query.where('staffId', isEqualTo: staffId);

    final snapshot = await query.get();
    return snapshot.docs.map((doc) => {
      ...doc.data() as Map<String, dynamic>,
      'id': doc.id,
      'staffId': (doc.data() as Map<String, dynamic>)['staffId'],
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getPayrollItems(String payrollId) async {
    final query = await _firestore
        .collection(colPayrollItems)
        .where('payrollId', isEqualTo: payrollId)
        .get();
    return query.docs.map((e) => e.data()).toList();
  }

  Future<void> updatePayrollStatus(String payrollId, String status) async {
    await _firestore.collection(colPayrolls).doc(payrollId).update({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deletePayroll(String payrollId) async {
    // Delete items first
    final items = await _firestore.collection(colPayrollItems).where('payrollId', isEqualTo: payrollId).get();
    final batch = _firestore.batch();
    for (var doc in items.docs) { batch.delete(doc.reference); }
    batch.delete(_firestore.collection(colPayrolls).doc(payrollId));
    await batch.commit();
  }
}
