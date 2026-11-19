import 'demo_seed_accounting.dart';
import 'demo_seed_communication.dart';
import 'demo_seed_daily_report.dart';
import 'demo_seed_guidance.dart';
import 'demo_seed_portfolio.dart';
import 'demo_seed_registry.dart';
import 'demo_seed_schedule.dart';
import 'demo_seed_staff_ops.dart';
import 'demo_seed_support.dart';
import 'demo_seed_transport.dart';

bool _registered = false;

/// Tüm alan demo üreticilerini kayıt defterine ekler (bir kez çalışır).
void registerAllDemoSeeders() {
  if (_registered) return;
  _registered = true;

  DemoSeedRegistry.seeders.addAll([
    MapEntry('Ders programı ve çalışma takvimi', seedDemoSchedule),
    MapEntry(
      'Personel işlemleri (izin, nöbet, gezi, proje, görev)',
      seedDemoStaffOps,
    ),
    MapEntry(
      'Rehberlik (anket, görüşme, envanter, gelişim raporu)',
      seedDemoGuidance,
    ),
    MapEntry(
      'Haberleşme (duyuru, sosyal medya, mesajlar)',
      seedDemoCommunication,
    ),
    MapEntry(
      'Destek hizmetleri (sağlık, kütüphane, stok, güvenlik)',
      seedDemoSupport,
    ),
    MapEntry('Muhasebe ve ücretler', seedDemoAccounting),
    MapEntry('Anaokulu günlük karneleri', seedDemoDailyReport),
    MapEntry('Servis işlemleri', seedDemoTransport),
    MapEntry(
      'Portfolyo (etkinlik, test, etüt, kitap, eylem planı)',
      seedDemoPortfolio,
    ),
  ]);

  final top = <String>{
    ...demoScheduleTopCollections,
    ...demoStaffOpsTopCollections,
    ...demoGuidanceTopCollections,
    ...demoCommunicationTopCollections,
    ...demoSupportTopCollections,
    ...demoAccountingTopCollections,
    ...demoDailyReportTopCollections,
    ...demoPortfolioTopCollections,
    ...demoTransportTopCollections,
  };
  DemoSeedRegistry.topCollections.addAll(top);

  final sub = <String>{
    ...demoScheduleSchoolSubcollections,
    ...demoStaffOpsSchoolSubcollections,
    ...demoGuidanceSchoolSubcollections,
    ...demoCommunicationSchoolSubcollections,
    ...demoSupportSchoolSubcollections,
    ...demoAccountingSchoolSubcollections,
    ...demoDailyReportSchoolSubcollections,
    ...demoPortfolioSchoolSubcollections,
    ...demoTransportSchoolSubcollections,
  };
  DemoSeedRegistry.schoolSubcollections.addAll(sub);

  DemoSeedRegistry.extraCleaners.addAll([
    cleanDemoScheduleExtras,
    cleanDemoStaffOpsExtras,
    cleanDemoGuidanceExtras,
    cleanDemoCommunicationExtras,
    cleanDemoSupportExtras,
    cleanDemoAccountingExtras,
    cleanDemoDailyReportExtras,
    cleanDemoPortfolioExtras,
    cleanDemoTransportExtras,
  ]);
}
