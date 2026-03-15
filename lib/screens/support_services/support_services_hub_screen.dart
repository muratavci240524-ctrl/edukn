import 'package:flutter/material.dart';
import 'cafeteria/cafeteria_screen.dart';
import 'transportation/transportation_screen.dart';
import 'health/health_screen.dart';
import 'library/library_screen.dart';
import 'cleaning/cleaning_screen.dart';
import 'inventory/inventory_screen.dart';

class SupportServicesHubScreen extends StatelessWidget {
  const SupportServicesHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final items = [
      _ServiceItem(
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
        'Kantin İşlemleri',
        'Kantin ürün ve satış yönetimi',
        Icons.store,
        Colors.teal,
        () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Kantin İşlemleri yakında eklenecek...')),
          );
        },
      ),
      _ServiceItem(
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
        'Sağlık İşlemleri',
        'Revir ziyaretleri ve ilaç takibi',
        Icons.local_hospital,
        Colors.red,
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const HealthScreen()),
        ),
      ),
      _ServiceItem(
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
        'Depo ve Satın Alma',
        'Stok takibi, envanter ve satın alma talepleri',
        Icons.inventory,
        Colors.brown,
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const InventoryScreen()),
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              Navigator.pushReplacementNamed(context, '/school-dashboard');
            }
          },
        ),
        title: const Text('Destek Hizmetleri'),
        elevation: 1,
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
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  _ServiceItem(this.title, this.subtitle, this.icon, this.color, this.onTap);
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
                  color: item.color.withOpacity(0.1),
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
