import 'package:flutter/material.dart';

/// Değerlendirme istatistiklerindeki (Eşleşen / Eşleşmeyen / Katılmayan)
/// listeleri alttan açılan menü (bottom sheet) olarak gösterir.
Future<T?> showStatsBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    constraints: const BoxConstraints(maxWidth: 900),
    builder: (ctx) => StatsBottomSheetFrame(child: builder(ctx)),
  );
}

class StatsBottomSheetFrame extends StatelessWidget {
  final Widget child;

  const StatsBottomSheetFrame({Key? key, required this.child})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.88;
    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, -2)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Tutamaç
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
