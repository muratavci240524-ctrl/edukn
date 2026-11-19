import 'package:edukn/services/user_permission_service.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';
import 'package:flutter/material.dart';

import 'cafeteria/cafeteria_screen.dart';
import 'cleaning/cleaning_screen.dart';
import 'health/health_screen.dart';
import 'inventory/inventory_screen.dart';
import 'library/library_screen.dart';
import 'security/security_gate_screen.dart';
import 'transportation/transportation_screen.dart';

class SupportServicesHubScreen extends StatelessWidget {
  const SupportServicesHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = UserPermissionService.cachedUserData;
    final allItems = [
      _ServiceItem(
        'guvenlik_kapi',
        'Güvenlik Kapı & Misafir Giriş-Çıkış',
        'İzinli öğrenci kapı çıkış onayı ve okul misafir/ziyaretçi giriş-çıkış yönetimi',
        Icons.shield_rounded,
        const Color(0xFF0284C7),
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SecurityGateScreen()),
        ),
      ),
      _ServiceItem(
        'saglik_islemleri',
        'Sağlık İşlemleri (Revir)',
        'Açık revir sevk dosyaları, müdahale girişi ve ilaç takibi',
        Icons.local_hospital,
        Colors.red,
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const HealthScreen()),
        ),
      ),
      _ServiceItem(
        'yemekhane_islemleri',
        'Yemekhane İşlemleri',
        'Yemek listesi, öğün ve menü yönetimi',
        Icons.restaurant,
        Colors.orange,
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CafeteriaScreen()),
        ),
      ),
      _ServiceItem(
        'yemekhane_islemleri',
        'Kantin İşlemleri',
        'Kantin ürün ve satış yönetimi',
        Icons.store,
        Colors.teal,
        () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Kantin İşlemleri yakında eklenecek...'),
            ),
          );
        },
      ),
      _ServiceItem(
        'servis_islemleri',
        'Servis İşlemleri',
        'Araç tanımlama ve öğrenci ataması',
        Icons.directions_bus,
        Colors.blue,
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TransportationScreen()),
        ),
      ),
      _ServiceItem(
        'kutuphane_islemleri',
        'Kütüphane İşlemleri',
        'Kitap yönetimi ve ödünç takibi',
        Icons.menu_book,
        Colors.deepPurple,
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const LibraryScreen()),
        ),
      ),
      _ServiceItem(
        'temizlik_islemleri',
        'Temizlik İşlemleri',
        'Personel, alan ve izin yönetimi',
        Icons.cleaning_services,
        Colors.green,
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CleaningScreen()),
        ),
      ),
      _ServiceItem(
        'depo_satin_alma',
        'Depo Yönetimi ve Stok Takibi',
        'Çoklu depo stok takibi, malzeme giriş-çıkış, mal kabul ve öğretmen teslimatları',
        Icons.inventory_2_rounded,
        const Color(0xFF0D9488),
        () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const InventoryScreen(initialTabIndex: 0),
          ),
        ),
      ),
      _ServiceItem(
        'satin_alma_islemleri',
        'Satın Alma ve Teklif Yönetimi',
        'Malzeme satın alma talepleri, tedarikçi teklif karşılaştırma, amir onayı ve siparişler',
        Icons.request_quote_rounded,
        const Color(0xFF4F46E5),
        () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const InventoryScreen(initialTabIndex: 2),
          ),
        ),
      ),
    ];

    final items = allItems
        .where(
          (item) => UserPermissionService.hasSubModuleAccess(
            'hizmetler',
            item.subModuleKey,
            user,
          ),
        )
        .toList();

    return Scaffold(
      appBar: EduknAppBar(
        title: 'Destek Hizmetleri',
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 20,
            color: Colors.indigo,
          ),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              Navigator.pushReplacementNamed(context, '/school-dashboard');
            }
          },
        ),
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1400),
          padding: const EdgeInsets.all(16),
          child: ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _ServiceCard(item: items[i]),
          ),
        ),
      ),
    );
  }
}

class _ServiceItem {
  final String subModuleKey;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  _ServiceItem(
    this.subModuleKey,
    this.title,
    this.subtitle,
    this.icon,
    this.color,
    this.onTap,
  );
}

class _ServiceCard extends StatelessWidget {
  final _ServiceItem item;
  const _ServiceCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: item.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(item.icon, size: 28, color: item.color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
