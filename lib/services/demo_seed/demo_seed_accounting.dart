import 'package:cloud_firestore/cloud_firestore.dart';

import '../crypto_service.dart';
import 'demo_seed_context.dart';

/// Muhasebe / Finans demo verisi:
///  * cashes            – kasa & banka hesapları
///  * payment_plans     – öğrenci ödeme planları (taksitler, indirimler, peşinat)
///  * transactions      – tahsilatlar, giderler, gelirler, maaş ödemeleri
///  * staff_salary      – öğretmen maaş tanımları (şifreli alanlar)
///  * payroll           – aylık bordrolar (şifreli alanlar)
///  * payroll_items     – bordro kalemleri (şifreli tutarlar)
///
/// Kasa bakiyeleri, yazılan işlemlerin toplamı (açılış bakiyesi dahil) ile
/// tutarlıdır.
const List<String> demoAccountingTopCollections = [
  'cashes',
  'payment_plans',
  'transactions',
  'staff_salary',
  'payroll',
  'payroll_items',
];

const List<String> demoAccountingSchoolSubcollections = [];

Future<int> cleanDemoAccountingExtras(
  FirebaseFirestore db,
  String inst,
  String prefix,
  String schoolDocId,
) async {
  return 0;
}

String _d2(int n) => n.toString().padLeft(2, '0');
String _fmt(DateTime d) => '${_d2(d.day)}.${_d2(d.month)}.${d.year}';
double _round(double v, double step) => (v / step).round() * step;

class _Kasa {
  final String id;
  final String name;
  final String type;
  double movement = 0;
  _Kasa(this.id, this.name, this.type);
}

Future<void> seedDemoAccounting(DemoSeedContext ctx) async {
  final rng = ctx.rng;
  final today = DateTime(ctx.today.year, ctx.today.month, ctx.today.day);
  final students = ctx.allStudents;

  // Eğitim yılının başlangıç yılı (Eylül).
  final y = ctx.termStart.month >= 6
      ? ctx.termStart.year
      : ctx.termStart.year - 1;
  final yearStart = DateTime(y, 9, 1);

  // ───────────────────────── KASALAR ─────────────────────────
  final kMain = _Kasa(ctx.id('cash_main'), 'Ana Kasa (Nakit)', 'cash');
  final kPos = _Kasa(ctx.id('cash_pos'), 'Banka / POS Hesabı', 'bank');
  final kZiraat = _Kasa(
    ctx.id('cash_ziraat'),
    'Ziraat Bankası Vadesiz Hesap',
    'bank',
  );
  final kSmall = _Kasa(ctx.id('cash_small'), 'Küçük Harcama Kasası', 'cash');
  final kasalar = [kMain, kPos, kZiraat, kSmall];

  int txCounter = 0;
  int receiptCounter = 1000;

  Future<String> addTx({
    required String type,
    required String category,
    required String description,
    required double amount,
    required _Kasa kasa,
    required DateTime date,
    String? paymentMethod,
    String? receiptNo,
    Map<String, dynamic>? extra,
  }) async {
    txCounter++;
    final id = ctx.id('tx_$txCounter');
    await ctx.set(ctx.col('transactions').doc(id), {
      'institutionId': ctx.inst,
      'type': type,
      'category': category,
      'description': description,
      'amount': amount,
      'kasaId': kasa.id,
      'kasaName': kasa.name,
      if (paymentMethod != null) 'paymentMethod': paymentMethod,
      if (receiptNo != null) 'receiptNo': receiptNo,
      'date': Timestamp.fromDate(date),
      'userId': 'demo_accounting',
      ...?extra,
    });
    kasa.movement += type == 'income' ? amount : -amount;
    ctx.count('Muhasebe işlemi');
    return id;
  }

  DateTime atTime(DateTime d) =>
      DateTime(d.year, d.month, d.day, ctx.between(9, 16), ctx.between(0, 59));

  DateTime clampToday(DateTime d) => d.isAfter(today) ? today : d;

  // ───────────────────────── ÖDEME PLANLARI ─────────────────────────
  int txBudget = 1200; // öğrenci tahsilat işlemi üst sınırı
  final discountDefs = <Map<String, dynamic>>[
    {
      'id': 'kardes',
      'name': 'Kardeş İndirimi',
      'pct': 10.0,
      'reason': 'Kardeş kaydı',
    },
    {
      'id': 'erken',
      'name': 'Erken Kayıt İndirimi',
      'pct': 8.0,
      'reason': 'Erken kayıt kampanyası',
    },
    {
      'id': 'burs',
      'name': 'Başarı Bursu',
      'pct': 25.0,
      'reason': 'Giriş sınavı başarı bursu',
    },
    {
      'id': 'personel',
      'name': 'Personel Çocuğu İndirimi',
      'pct': 50.0,
      'reason': 'Kurum personeli çocuğu',
    },
  ];

  const methods = ['Nakit', 'Kredi Kartı', 'Havale/EFT'];
  _Kasa kasaFor(String m) =>
      m == 'Nakit' ? kMain : (m == 'Kredi Kartı' ? kPos : kZiraat);

  for (final s in students) {
    final level = s.level;
    double base = level <= 0
        ? 70000
        : (level <= 4 ? 85000 : (level <= 8 ? 95000 : 110000));
    base = _round(base * (0.95 + rng.nextDouble() * 0.1), 500);
    final tuition = _round(base * 0.8, 500);
    final hasMeal = rng.nextDouble() < 0.85;
    final meal = hasMeal ? _round(base * 0.12, 500) : 0.0;
    final books = _round(base * 0.07, 500);

    final items = <Map<String, dynamic>>[];
    final instCount = rng.nextDouble() < 0.75 ? 9 : 10;
    Map<String, dynamic> item(String name, double amt) => {
      'name': name,
      'amount': amt,
      'paymentType': 'installment',
      'installmentCount': instCount,
    };
    items.add(item('Eğitim Ücreti', tuition));
    if (hasMeal) items.add(item('Yemek Ücreti', meal));
    items.add(item('Kitap & Kırtasiye', books));
    final gross = tuition + meal + books;

    // İndirim
    final applied = <Map<String, dynamic>>[];
    double discount = 0;
    final dr = rng.nextDouble();
    if (dr < 0.35) {
      final dd = dr < 0.15
          ? discountDefs[1]
          : (dr < 0.25
                ? discountDefs[0]
                : (dr < 0.32 ? discountDefs[2] : discountDefs[3]));
      final pct = dd['pct'] as double;
      applied.add({
        'id': dd['id'],
        'name': dd['name'],
        'percentage': pct,
        'reason': dd['reason'],
      });
      discount = _round(gross * pct / 100, 10);
    }
    final net = gross - discount;
    final downPayment = _round(net * (0.12 + rng.nextDouble() * 0.1), 500);
    final remaining = net - downPayment;

    // Taksit tutarları
    final amounts = <double>[];
    final each = (remaining / instCount / 10).floor() * 10.0;
    for (int i = 0; i < instCount; i++) {
      amounts.add(each);
    }
    amounts[instCount - 1] = remaining - each * (instCount - 1);

    final dueDay = ctx.pick([5, 10, 15]);
    final dueDates = <DateTime>[
      for (int i = 0; i < instCount; i++) DateTime(y, 9 + i, dueDay),
    ];

    // Ödeme profili
    final pr = rng.nextDouble();
    final pastIdx = <int>[
      for (int i = 0; i < instCount; i++)
        if (dueDates[i].isBefore(today)) i,
    ];
    final unpaidIdx = <int>{};
    if (pastIdx.isNotEmpty) {
      if (pr >= 0.88) {
        final n = pastIdx.length < 3 ? pastIdx.length : 3;
        for (int k = 0; k < n; k++) {
          unpaidIdx.add(pastIdx[pastIdx.length - 1 - k]);
        }
      } else if (pr >= 0.68) {
        unpaidIdx.add(pastIdx.last);
      }
    }

    final planId = ctx.id('pp_${s.id}');
    final preferredMethod = ctx.pick(methods);

    // Peşinat
    final downDate = DateTime(y, 9, ctx.between(1, 10));
    final downPaid = !downDate.isAfter(today) && rng.nextDouble() < 0.93;
    String? downTxId;
    String? downKasaId;
    if (downPaid && txBudget > 0) {
      txBudget--;
      const dm = 'Nakit';
      final kasa = kasaFor(rng.nextBool() ? dm : 'Havale/EFT');
      downTxId = await addTx(
        type: 'income',
        category: 'Öğrenci Peşinat Tahsilatı',
        description: '${s.fullName} - Peşinat Tahsilatı',
        amount: downPayment,
        kasa: kasa,
        date: atTime(downDate),
        paymentMethod: kasa == kMain ? 'Nakit / Peşin' : 'Havale/EFT',
        extra: {'planId': planId, 'studentId': s.id},
      );
      downKasaId = kasa.id;
    }

    final installments = <Map<String, dynamic>>[];
    for (int i = 0; i < instCount; i++) {
      final due = dueDates[i];
      final m = <String, dynamic>{
        'no': i + 1,
        'title': '${i + 1}. Taksit (Konsolide)',
        'category': 'Genel',
        'amount': amounts[i],
        'dueDate': _fmt(due),
        'status': 'unpaid',
      };
      final isPast = !due.isAfter(today) && !unpaidIdx.contains(i);
      if (isPast && due.isBefore(today)) {
        // Kısmi ödeme: fark sonraki taksite eklenir (uygulamadaki davranış).
        if (i + 1 < instCount && rng.nextDouble() < 0.08) {
          final pay = _round(amounts[i] * (0.6 + rng.nextDouble() * 0.25), 10);
          amounts[i + 1] += amounts[i] - pay;
          amounts[i] = pay;
          m['amount'] = pay;
        }
        final paidDate = clampToday(
          due.add(Duration(days: ctx.between(-3, 6))),
        );
        final method = rng.nextDouble() < 0.6
            ? preferredMethod
            : ctx.pick(methods);
        final kasa = kasaFor(method);
        receiptCounter++;
        final receipt = 'MKB-$receiptCounter';
        m['status'] = 'paid';
        m['paidDate'] = _fmt(paidDate);
        m['paymentMethod'] = method;
        m['receiptNo'] = receipt;
        m['kasaId'] = kasa.id;
        m['kasaName'] = kasa.name;
        if (txBudget > 0) {
          txBudget--;
          m['transactionId'] = await addTx(
            type: 'income',
            category: 'Öğrenci Taksit Tahsilatı',
            description: '${s.fullName} - ${m['title']} Tahsilatı',
            amount: m['amount'] as double,
            kasa: kasa,
            date: atTime(paidDate),
            paymentMethod: method,
            receiptNo: receipt,
            extra: {'planId': planId, 'studentId': s.id, 'installmentIndex': i},
          );
        }
      }
      installments.add(m);
    }

    await ctx.set(ctx.col('payment_plans').doc(planId), {
      'studentId': s.id,
      'studentName': s.fullName,
      'studentNo': s.no,
      'institutionId': ctx.inst,
      'name': '$y-${y + 1} Eğitim Öğretim Yılı Sözleşmesi',
      'items': items,
      'appliedDiscounts': applied,
      'grossTotal': gross,
      'totalDiscount': discount,
      'netTotal': net,
      'downPayment': downPayment,
      'downPaymentPaid': downPaid,
      if (downPaid) 'downPaymentDate': _fmt(downDate),
      if (downTxId != null) 'downPaymentTransactionId': downTxId,
      if (downKasaId != null) 'downPaymentKasaId': downKasaId,
      'isUnifiedPlan': true,
      'installmentCount': instCount,
      'installments': installments,
      'createdAt': Timestamp.fromDate(DateTime(y, 8, ctx.between(1, 28))),
      'updatedAt': Timestamp.fromDate(today),
    });
    ctx.count('Ödeme planı');
  }

  // ───────────────────────── AYLIK GELİR / GİDERLER ─────────────────────────
  final sf0 = students.length / 150.0;
  final sf = sf0 < 0.6 ? 0.6 : (sf0 > 3.0 ? 3.0 : sf0);

  final months = <DateTime>[];
  var cur = yearStart;
  final lastMonth = DateTime(today.year, today.month, 1);
  while (!cur.isAfter(lastMonth) && months.length < 12) {
    months.add(cur);
    cur = DateTime(cur.year, cur.month + 1, 1);
  }

  Future<void> expense(
    DateTime month,
    int dayFrom,
    int dayTo,
    String category,
    String desc,
    double amount,
    _Kasa kasa,
  ) async {
    final dt = DateTime(month.year, month.month, ctx.between(dayFrom, dayTo));
    if (dt.isAfter(today)) return;
    await addTx(
      type: 'expense',
      category: category,
      description: desc,
      amount: _round(amount, 10),
      kasa: kasa,
      date: atTime(dt),
      paymentMethod: kasa.type == 'cash' ? 'Nakit' : 'Havale/EFT',
      receiptNo: kasa.type == 'cash'
          ? null
          : 'FTR-${ctx.between(10000, 99999)}',
    );
  }

  Future<void> income(
    DateTime month,
    String category,
    String desc,
    double amount,
    _Kasa kasa,
  ) async {
    final dt = DateTime(month.year, month.month, ctx.between(3, 26));
    if (dt.isAfter(today)) return;
    receiptCounter++;
    await addTx(
      type: 'income',
      category: category,
      description: desc,
      amount: _round(amount, 10),
      kasa: kasa,
      date: atTime(dt),
      paymentMethod: kasa.type == 'cash' ? 'Nakit' : 'Kredi Kartı',
      receiptNo: 'MKB-$receiptCounter',
    );
  }

  const monthNames = [
    '',
    'Ocak',
    'Şubat',
    'Mart',
    'Nisan',
    'Mayıs',
    'Haziran',
    'Temmuz',
    'Ağustos',
    'Eylül',
    'Ekim',
    'Kasım',
    'Aralık',
  ];

  for (final mo in months) {
    final mn = monthNames[mo.month];
    await expense(
      mo,
      1,
      5,
      'Kira / Bina Gideri',
      '$mn ayı bina kirası',
      85000 * (0.8 + sf * 0.2),
      kZiraat,
    );
    await expense(
      mo,
      10,
      18,
      'Elektrik, Su, Doğalgaz',
      '$mn ayı elektrik faturası',
      (14000 + rng.nextInt(5000)) * sf,
      kZiraat,
    );
    await expense(
      mo,
      10,
      18,
      'Elektrik, Su, Doğalgaz',
      '$mn ayı su faturası',
      (3500 + rng.nextInt(1500)) * sf,
      kZiraat,
    );
    final heating = mo.month >= 11 || mo.month <= 3;
    await expense(
      mo,
      12,
      20,
      'Elektrik, Su, Doğalgaz',
      '$mn ayı doğalgaz faturası',
      (heating ? 26000 : 6000) * (0.8 + rng.nextDouble() * 0.4) * sf,
      kZiraat,
    );
    await expense(
      mo,
      5,
      24,
      'Kırtasiye & Malzeme',
      'Sınıf kırtasiye ve ofis malzemesi alımı',
      (4000 + rng.nextInt(5000)) * sf,
      kSmall,
    );
    await expense(
      mo,
      5,
      24,
      'Kırtasiye & Malzeme',
      'Temizlik ve hijyen malzemesi alımı',
      (3000 + rng.nextInt(3000)) * sf,
      kSmall,
    );
    await expense(
      mo,
      2,
      26,
      'Yemek & Mutfak',
      'Mutfak gıda ve malzeme alımı',
      (30000 + rng.nextInt(12000)) * sf,
      kZiraat,
    );
    await expense(
      mo,
      20,
      28,
      'Servis & Yakıt',
      'Servis araçları yakıt gideri',
      (16000 + rng.nextInt(6000)) * sf,
      kZiraat,
    );
    if (rng.nextDouble() < 0.6) {
      await expense(
        mo,
        5,
        25,
        'Bakım & Onarım',
        'Bina ve ekipman bakım onarım gideri',
        3000 + rng.nextInt(9000).toDouble(),
        kSmall,
      );
    }
    if (rng.nextDouble() < 0.5) {
      await expense(
        mo,
        5,
        25,
        'Reklam & Tanıtım',
        'Sosyal medya ve tanıtım kampanyası',
        5000 + rng.nextInt(12000).toDouble(),
        kZiraat,
      );
    }
    await expense(
      mo,
      20,
      26,
      'Vergi / Resmi Harç',
      'KDV ve muhtasar vergi ödemesi',
      (12000 + rng.nextInt(5000)) * sf,
      kZiraat,
    );
    if (rng.nextDouble() < 0.5) {
      await expense(
        mo,
        5,
        25,
        'Genel Gider',
        'Çeşitli genel giderler',
        1500 + rng.nextInt(3500).toDouble(),
        kSmall,
      );
    }

    // Ek gelirler
    await income(
      mo,
      'Yemek / Kantin',
      '$mn ayı kantin geliri',
      (7000 + rng.nextInt(5000)) * sf,
      kMain,
    );
    if (rng.nextDouble() < 0.7) {
      await income(
        mo,
        'Kitap & Kırtasiye',
        'Kırtasiye ve ek kaynak satışı',
        (3000 + rng.nextInt(6000)) * sf,
        kMain,
      );
    }
    if (rng.nextDouble() < 0.35) {
      await income(
        mo,
        'Etkinlik / Organizasyon',
        'Okul etkinliği ve gezi katılım geliri',
        (6000 + rng.nextInt(9000)) * sf,
        kPos,
      );
    }
  }

  // ───────────────────────── MAAŞ TANIMLARI & BORDRO ─────────────────────────
  // Demo verisi şifrelenmez (CryptoService.decrypt düz metni olduğu gibi döndürür).
  String enc(double v) => v.toString();

  final salaryByTeacher = <String, List<double>>{}; // [base, extraRate]
  for (final t in ctx.teachers) {
    final base = _round(38000 + rng.nextInt(26000).toDouble(), 500);
    final rate = _round(250 + rng.nextInt(160).toDouble(), 10);
    salaryByTeacher[t.id] = [base, rate];
    await ctx.set(ctx.col('staff_salary').doc(t.id), {
      'staffId': t.id,
      'institutionId': ctx.inst,
      'baseSalary': enc(base),
      'salaryType': 'monthly',
      'extraHourRate': enc(rate),
      'overtimeHourRate': enc(0.0),
      'updatedAt': Timestamp.fromDate(yearStart),
    });
    ctx.count('Maaş tanımı');
  }

  for (final mo in months) {
    final isCurrent = mo.year == today.year && mo.month == today.month;
    final status = isCurrent
        ? (today.day >= 20 ? 'approved' : 'draft')
        : 'paid';
    double monthTotalNet = 0;

    for (final t in ctx.teachers) {
      final sal = salaryByTeacher[t.id]!;
      final base = sal[0];
      final extraLectures = rng.nextDouble() < 0.55
          ? ctx.between(2, 14).toDouble()
          : 0.0;
      final extraAmount = extraLectures * sal[1];
      final bonus = rng.nextDouble() < 0.1
          ? _round(1000 + rng.nextInt(2500).toDouble(), 100)
          : 0.0;
      final deduction = rng.nextDouble() < 0.12
          ? _round(500 + rng.nextInt(1500).toDouble(), 50)
          : 0.0;
      final earnings = base + extraAmount + bonus;
      final net = earnings - deduction;
      monthTotalNet += net;

      final pid = ctx.id('payroll_${t.id}_${mo.year}_${mo.month}');
      final created = clampToday(DateTime(mo.year, mo.month, 25, 10, 0));
      await ctx.set(ctx.col('payroll').doc(pid), {
        'staffId': t.id,
        'institutionId': ctx.inst,
        'month': mo.month,
        'year': mo.year,
        'baseSalary': enc(base),
        'totalEarnings': enc(earnings),
        'totalDeductions': enc(deduction),
        'netSalary': enc(net),
        'status': status,
        'createdAt': Timestamp.fromDate(created),
        if (status != 'draft') 'updatedAt': Timestamp.fromDate(created),
      });
      ctx.count('Bordro');

      Future<void> payItem(
        String key,
        String type,
        String title,
        double amt,
      ) async {
        await ctx.set(ctx.col('payroll_items').doc('${pid}_$key'), {
          'payrollId': pid,
          'institutionId': ctx.inst,
          'type': type,
          'title': title,
          'amount': enc(amt),
        });
      }

      await payItem('base', 'earning', 'Temel Maaş', base);
      if (extraAmount > 0) {
        await payItem(
          'extra',
          'earning',
          'Ek Ders Ücreti (${extraLectures.toStringAsFixed(1)} Saat)',
          extraAmount,
        );
      }
      if (bonus > 0)
        await payItem('bonus', 'earning', 'Ek Kazanç / Prim', bonus);
      if (deduction > 0)
        await payItem('ded', 'deduction', 'Diğer Kesintiler', deduction);
    }

    if (status == 'paid' && monthTotalNet > 0) {
      await addTx(
        type: 'expense',
        category: 'Personel & Maaş',
        description: '${monthNames[mo.month]} ${mo.year} personel maaş ödemesi',
        amount: monthTotalNet,
        kasa: kZiraat,
        date: atTime(clampToday(DateTime(mo.year, mo.month, 28))),
        paymentMethod: 'Havale/EFT',
        extra: {'source': 'payroll'},
      );
    }
  }

  // ───────────────────────── KASALAR (açılış bakiyesi + güncel bakiye) ─────────────────────────
  final openingDate = DateTime(y, 8, 31, 9, 0);
  for (final k in kasalar) {
    double opening;
    if (k == kSmall) {
      opening = 15000;
    } else {
      opening = 100000 + rng.nextInt(150000).toDouble();
    }
    // Bakiye negatif / çok düşük olmasın.
    if (k.movement + opening < 40000) {
      opening = _round(40000 - k.movement + rng.nextInt(60000), 100);
    }
    if (k == kSmall && k.movement + opening < 3000) {
      opening = _round(3000 - k.movement + 2000, 100);
    }
    await addTx(
      type: 'income',
      category: 'Diğer Gelir',
      description: 'Dönem açılış bakiyesi - ${k.name}',
      amount: opening,
      kasa: k,
      date: openingDate,
      paymentMethod: k.type == 'cash' ? 'Nakit' : 'Havale/EFT',
    );
    await ctx.set(ctx.col('cashes').doc(k.id), {
      'institutionId': ctx.inst,
      'name': k.name,
      'type': k.type,
      'balance': k.movement,
      'createdAt': Timestamp.fromDate(openingDate),
    });
    ctx.count('Kasa / hesap');
  }
}
