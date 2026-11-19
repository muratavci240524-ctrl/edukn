import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';

/// Inherited scope to query whether the current subtree is in Read-Only (Viewer) mode.
class ReadOnlyPermissionScope extends InheritedWidget {
  final bool canEdit;
  final String? moduleName;

  const ReadOnlyPermissionScope({
    Key? key,
    required this.canEdit,
    this.moduleName,
    required Widget child,
  }) : super(key: key, child: child);

  static bool canEditOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ReadOnlyPermissionScope>();
    if (scope != null) return scope.canEdit;
    return !ReadOnlyPermissionWrapper.isGlobalReadOnlyActive;
  }

  @override
  bool updateShouldNotify(ReadOnlyPermissionScope oldWidget) =>
      canEdit != oldWidget.canEdit || moduleName != oldWidget.moduleName;
}

/// Wraps a module/sub-module screen to enforce Viewer (Görüntüleyen) vs Editor (Düzenleyen) permissions.
/// When [canEdit] is false:
/// - Shows a top banner indicating Viewer (Görüntüleme) mode.
/// - Intercepts taps on mutation controls (Save, Add, Create, Edit, Delete, Approve, Switches, Checkboxes, FABs)
///   while allowing scrolling, tab switching, searching, filtering, and viewing details.
class ReadOnlyPermissionWrapper extends StatefulWidget {
  final bool canEdit;
  final String? moduleName;
  final Widget child;

  const ReadOnlyPermissionWrapper({
    Key? key,
    required this.canEdit,
    this.moduleName,
    required this.child,
  }) : super(key: key);

  static final List<String?> _activeReadOnlyStack = [];

  static bool get isGlobalReadOnlyActive => _activeReadOnlyStack.isNotEmpty;

  static String? get activeModuleName =>
      _activeReadOnlyStack.isNotEmpty ? _activeReadOnlyStack.last : null;

  /// Helper to push a route wrapped with [ReadOnlyPermissionWrapper].
  static MaterialPageRoute<T> route<T>({
    required bool canEdit,
    String? moduleName,
    required Widget page,
    RouteSettings? settings,
  }) {
    return MaterialPageRoute<T>(
      settings: settings,
      builder: (_) => ReadOnlyPermissionWrapper(
        canEdit: canEdit,
        moduleName: moduleName,
        child: page,
      ),
    );
  }

  @override
  State<ReadOnlyPermissionWrapper> createState() =>
      _ReadOnlyPermissionWrapperState();
}

class _ReadOnlyPermissionWrapperState extends State<ReadOnlyPermissionWrapper> {
  bool _registeredInGlobalStack = false;
  DateTime? _lastSnackBarTime;

  @override
  void initState() {
    super.initState();
    _syncRegistration();
  }

  @override
  void didUpdateWidget(covariant ReadOnlyPermissionWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.canEdit != widget.canEdit ||
        oldWidget.moduleName != widget.moduleName) {
      _unregister();
      _syncRegistration();
    }
  }

  void _syncRegistration() {
    if (!widget.canEdit && !_registeredInGlobalStack) {
      ReadOnlyPermissionWrapper._activeReadOnlyStack.add(widget.moduleName);
      _registeredInGlobalStack = true;
    }
  }

  void _unregister() {
    if (_registeredInGlobalStack) {
      ReadOnlyPermissionWrapper._activeReadOnlyStack.remove(widget.moduleName);
      _registeredInGlobalStack = false;
    }
  }

  @override
  void dispose() {
    _unregister();
    super.dispose();
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (widget.canEdit) return;
    if ( ReadOnlyPointerInterceptor.shouldBlockPointerDown(context, event)) {
      _cancelPointerAndNotify(event.pointer);
    }
  }

  void _cancelPointerAndNotify(int pointer) {
    WidgetsBinding.instance.cancelPointer(pointer);
    scheduleMicrotask(() {
      WidgetsBinding.instance.cancelPointer(pointer);
    });

    final now = DateTime.now();
    if (_lastSnackBarTime != null &&
        now.difference(_lastSnackBarTime!).inMilliseconds < 1800) {
      return;
    }
    _lastSnackBarTime = now;

    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFB45309),
          duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          content: Row(
            children: [
              const Icon(
                Icons.lock_outline_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.moduleName != null && widget.moduleName!.isNotEmpty
                      ? 'Görüntüleme Modu (${widget.moduleName}): Yalnızca izleme yetkiniz var, işlem yapamazsınız.'
                      : 'Görüntüleme Modu: Bu alanda yalnızca izleme yetkiniz bulunmaktadır, işlem yapamazsınız.',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.canEdit) {
      return ReadOnlyPermissionScope(
        canEdit: true,
        moduleName: widget.moduleName,
        child: widget.child,
      );
    }

    return ReadOnlyPermissionScope(
      canEdit: false,
      moduleName: widget.moduleName,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _handlePointerDown,
        child: Column(
          children: [
            Material(
              color: const Color(0xFFFFFBEB),
              child: SafeArea(
                bottom: false,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFFBEB),
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFFDE68A), width: 1),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.visibility_outlined,
                          size: 16,
                          color: Color(0xFFB45309),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.moduleName != null &&
                                  widget.moduleName!.isNotEmpty
                              ? 'Görüntüleme Modu (${widget.moduleName}) — Bu modülde yalnızca inceleme yetkiniz bulunmaktadır; ekleme, düzenleme veya silme yapılamaz.'
                              : 'Görüntüleme Modu — Bu modülde yalnızca inceleme yetkiniz bulunmaktadır; ekleme, düzenleme veya silme yapılamaz.',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF92400E),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: widget.child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Global listener that can be placed in MaterialApp.builder so dialogs, bottom sheets,
/// and secondary routes opened while a [ReadOnlyPermissionWrapper] is active are also protected.
class ReadOnlyGlobalGuard extends StatefulWidget {
  final Widget child;

  const ReadOnlyGlobalGuard({Key? key, required this.child}) : super(key: key);

  @override
  State<ReadOnlyGlobalGuard> createState() => _ReadOnlyGlobalGuardState();
}

class _ReadOnlyGlobalGuardState extends State<ReadOnlyGlobalGuard> {
  DateTime? _lastSnackTime;

  void _onPointerDown(PointerDownEvent event) {
    if (!ReadOnlyPermissionWrapper.isGlobalReadOnlyActive) return;
    if (ReadOnlyPointerInterceptor.shouldBlockPointerDown(context, event)) {
      WidgetsBinding.instance.cancelPointer(event.pointer);
      scheduleMicrotask(() {
        WidgetsBinding.instance.cancelPointer(event.pointer);
      });

      final now = DateTime.now();
      if (_lastSnackTime != null &&
          now.difference(_lastSnackTime!).inMilliseconds < 1800) {
        return;
      }
      _lastSnackTime = now;

      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger != null) {
        final modName = ReadOnlyPermissionWrapper.activeModuleName;
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFFB45309),
            duration: const Duration(seconds: 2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            content: Row(
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    modName != null && modName.isNotEmpty
                        ? 'Görüntüleme Modu ($modName): Yalnızca izleme yetkiniz var, işlem yapamazsınız.'
                        : 'Görüntüleme Modu: Yalnızca izleme yetkiniz bulunmaktadır, işlem yapamazsınız.',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      child: widget.child,
    );
  }
}

class ReadOnlyPointerInterceptor {
  static const List<String> _mutationKeywords = [
    'kaydet',
    'ekle',
    'yeni ',
    'yeni\n',
    'oluştur',
    'olustur',
    'sil',
    'düzenle',
    'duzenle',
    'güncelle',
    'guncelle',
    'onayla',
    'reddet',
    'sıfırla',
    'sifirla',
    'atlat',
    'aktar',
    'tanımla',
    'tanimla',
    'yayınla',
    'yayinla',
    'gönder',
    'gonder',
    'yükle',
    'yukle',
    'kaldır',
    'kaldir',
    'arşivle',
    'arsivle',
    'tahsil',
    'ödeme al',
    'odeme al',
    'fatura',
    'iade',
    'satış',
    'satis',
    'bakiye',
    'atama',
    'ata',
    'kopyala ve',
    'toplu ',
    'şablon',
    'sablon',
  ];

  static const List<String> _allowedNavigationKeywords = [
    'geri',
    'kapat',
    'vazgeç',
    'vazgec',
    'iptal',
    'ara',
    'filtre',
    'detay',
    'incele',
    'görüntüle',
    'goruntule',
    'yazdır',
    'yazdir',
    'indir',
    'önizle',
    'onizle',
    'listele',
    'tümü',
    'tumu',
  ];

  static final Set<int> _mutationIconCodePoints = {
    Icons.add.codePoint,
    Icons.add_rounded.codePoint,
    Icons.add_circle.codePoint,
    Icons.add_circle_outline.codePoint,
    Icons.add_circle_rounded.codePoint,
    Icons.add_box.codePoint,
    Icons.add_box_outlined.codePoint,
    Icons.person_add.codePoint,
    Icons.person_add_alt.codePoint,
    Icons.person_add_alt_1.codePoint,
    Icons.person_add_rounded.codePoint,
    Icons.group_add.codePoint,
    Icons.post_add.codePoint,
    Icons.playlist_add.codePoint,
    Icons.library_add.codePoint,
    Icons.edit.codePoint,
    Icons.edit_rounded.codePoint,
    Icons.edit_outlined.codePoint,
    Icons.edit_note.codePoint,
    Icons.edit_note_rounded.codePoint,
    Icons.mode_edit.codePoint,
    Icons.mode_edit_outline.codePoint,
    Icons.drive_file_rename_outline.codePoint,
    Icons.delete.codePoint,
    Icons.delete_rounded.codePoint,
    Icons.delete_outline.codePoint,
    Icons.delete_outline_rounded.codePoint,
    Icons.delete_forever.codePoint,
    Icons.delete_forever_rounded.codePoint,
    Icons.remove_circle.codePoint,
    Icons.remove_circle_outline.codePoint,
    Icons.save.codePoint,
    Icons.save_rounded.codePoint,
    Icons.save_outlined.codePoint,
    Icons.save_as.codePoint,
    Icons.check.codePoint,
    Icons.check_rounded.codePoint,
    Icons.check_circle.codePoint,
    Icons.check_circle_outline.codePoint,
    Icons.done_all.codePoint,
    Icons.upload_file.codePoint,
    Icons.cloud_upload.codePoint,
    Icons.cloud_upload_outlined.codePoint,
    Icons.send.codePoint,
    Icons.send_rounded.codePoint,
    Icons.publish.codePoint,
    Icons.restart_alt.codePoint,
    Icons.restart_alt_rounded.codePoint,
  };

  static final Set<int> _allowedIconCodePoints = {
    Icons.arrow_back.codePoint,
    Icons.arrow_back_rounded.codePoint,
    Icons.arrow_back_ios.codePoint,
    Icons.arrow_back_ios_new.codePoint,
    Icons.close.codePoint,
    Icons.close_rounded.codePoint,
    Icons.clear.codePoint,
    Icons.clear_rounded.codePoint,
    Icons.search.codePoint,
    Icons.search_rounded.codePoint,
    Icons.filter_list.codePoint,
    Icons.filter_alt.codePoint,
    Icons.filter_alt_outlined.codePoint,
    Icons.visibility.codePoint,
    Icons.visibility_outlined.codePoint,
    Icons.visibility_off.codePoint,
    Icons.visibility_off_outlined.codePoint,
    Icons.remove_red_eye.codePoint,
    Icons.remove_red_eye_outlined.codePoint,
    Icons.print.codePoint,
    Icons.print_outlined.codePoint,
    Icons.download.codePoint,
    Icons.download_rounded.codePoint,
    Icons.chevron_right.codePoint,
    Icons.chevron_left.codePoint,
    Icons.expand_more.codePoint,
    Icons.expand_less.codePoint,
    Icons.keyboard_arrow_down.codePoint,
    Icons.keyboard_arrow_up.codePoint,
    Icons.keyboard_arrow_right.codePoint,
    Icons.keyboard_arrow_left.codePoint,
    Icons.info_outline.codePoint,
  };

  static bool shouldBlockPointerDown(
    BuildContext context,
    PointerDownEvent event,
  ) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return false;

    final result = BoxHitTestResult();
    final localPos = renderObject.globalToLocal(event.position);
    if (!renderObject.hitTest(result, position: localPos)) return false;

    final hitRenderObjects = <RenderObject>{};
    for (final entry in result.path) {
      if (entry.target is RenderObject) {
        hitRenderObjects.add(entry.target as RenderObject);
      }
    }
    if (hitRenderObjects.isEmpty) return false;

    final hitElements = <Element>[];
    void collectHitElements(Element element) {
      final ro = element.renderObject;
      if (ro != null && !hitRenderObjects.contains(ro)) {
        return;
      }
      hitElements.add(element);
      element.visitChildElements(collectHitElements);
    }

    if (context is Element) {
      collectHitElements(context);
    }

    // Never block TabBar, BottomNavigationBar, AppBar leading back button, or TextField focus for search
    for (final el in hitElements) {
      final w = el.widget;
      if (w is Tab ||
          w is TabBar ||
          w is BottomNavigationBar ||
          w is NavigationBar ||
          w is NavigationRail ||
          w is BackButton ||
          w is CloseButton) {
        return false;
      }
    }

    // Check if an interactive control on the hit path is a mutation control
    Element? interactiveElement;
    for (int i = hitElements.length - 1; i >= 0; i--) {
      final w = hitElements[i].widget;
      if (w is FloatingActionButton) {
        return true;
      }
      if (w is Switch ||
          w is Checkbox ||
          w is Radio ||
          w is SwitchListTile ||
          w is CheckboxListTile) {
        return true;
      }
      if (w is ButtonStyleButton ||
          w is IconButton ||
          w is MaterialButton ||
          w is PopupMenuItem ||
          w is InkWell ||
          w is GestureDetector) {
        interactiveElement ??= hitElements[i];
      }
    }

    if (interactiveElement == null) return false;

    // Collect text labels, tooltips, and icons inside the interactive element
    final labels = <String>[];
    final iconCodes = <int>[];

    void inspectSubtree(Element el) {
      final w = el.widget;
      if (w is Text) {
        final data = w.data ?? w.textSpan?.toPlainText();
        if (data != null && data.trim().isNotEmpty) {
          labels.add(data.trim().toLowerCase());
        }
      } else if (w is RichText) {
        final plain = w.text.toPlainText().trim();
        if (plain.isNotEmpty) {
          labels.add(plain.toLowerCase());
        }
      } else if (w is Tooltip && w.message != null) {
        labels.add(w.message!.trim().toLowerCase());
      } else if (w is IconButton && w.tooltip != null) {
        labels.add(w.tooltip!.trim().toLowerCase());
      } else if (w is Icon && w.icon != null) {
        iconCodes.add(w.icon!.codePoint);
      }
      el.visitChildElements(inspectSubtree);
    }

    inspectSubtree(interactiveElement);

    final combinedText = labels.join(' ');

    // Allow explicit cancel/close/back/search/view actions
    for (final allowWord in _allowedNavigationKeywords) {
      if (combinedText == allowWord ||
          combinedText.startsWith('$allowWord ') ||
          combinedText.endsWith(' $allowWord')) {
        return false;
      }
    }

    for (final code in iconCodes) {
      if (_allowedIconCodePoints.contains(code) && labels.isEmpty) {
        return false;
      }
    }

    // Block if any mutation keyword matches
    for (final kw in _mutationKeywords) {
      if (combinedText.contains(kw)) {
        return true;
      }
    }

    // Block if any mutation icon matches
    for (final code in iconCodes) {
      if (_mutationIconCodePoints.contains(code)) {
        return true;
      }
    }

    return false;
  }
}
