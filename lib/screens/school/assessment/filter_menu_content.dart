import 'package:flutter/material.dart';

class FilterMenuContent extends StatefulWidget {
  final String label;
  final List<String> items;
  final List<String> selectedItems;
  final Function(List<String>) onChanged;

  const FilterMenuContent({
    Key? key,
    required this.label,
    required this.items,
    required this.selectedItems,
    required this.onChanged,
  }) : super(key: key);

  @override
  _FilterMenuContentState createState() => _FilterMenuContentState();
}

class _FilterMenuContentState extends State<FilterMenuContent> {
  late List<String> _currentSelection;

  @override
  void initState() {
    super.initState();
    _currentSelection = List.from(widget.selectedItems);
  }

  @override
  Widget build(BuildContext context) {
    // Logic: Empty list means ALL in parent logic usually, but here we manage selection explicitly.
    // If incoming selection is empty, and items are not empty, does it mean ALL or NONE?
    // In the parent logic: "if list.length == items.length -> _selected = [] (Reset to All)".
    // So if incoming is [], it means ALL are selected visually.

    // Correction: We need to sync our local state with "What Creates Is All".
    // If widget.selectedItems is empty, we treat it as ALL selected for the UI checkboxes.

    bool isAllSelectedLocally =
        _currentSelection.isEmpty ||
        _currentSelection.length == widget.items.length;

    // Wait, if _currentSelection is empty, does it mean ALL or NONE in *local* context?
    // Let's assume _currentSelection holds the ACTUAL IDs selected.
    // If parent passed [], it implies ALL. So we should initialize _currentSelection with ALL items.

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0, top: 4.0),
          child: Text(
            "${widget.label} Seçimi",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo),
          ),
        ),
        Divider(height: 1),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              CheckboxListTile(
                title: Text("Tümü"),
                value: isAllSelectedLocally,
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (val) {
                  setState(() {
                    if (val == true) {
                      _currentSelection = List.from(widget.items);
                    } else {
                      _currentSelection = [];
                    }
                  });
                  widget.onChanged(_currentSelection);
                },
              ),
              ...widget.items.map((item) {
                final isSelected = _currentSelection.contains(item);
                return CheckboxListTile(
                  title: Text(item),
                  value: isSelected,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _currentSelection.add(item);
                      } else {
                        _currentSelection.remove(item);
                      }
                    });
                    widget.onChanged(_currentSelection);
                  },
                );
              }).toList(),
            ],
          ),
        ),
      ],
    );
  }
}
