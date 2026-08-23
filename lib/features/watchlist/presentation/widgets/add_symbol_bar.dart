import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class AddSymbolBar extends StatefulWidget {
  final ValueChanged<String> onAddSymbol;

  const AddSymbolBar({Key? key, required this.onAddSymbol}) : super(key: key);

  @override
  _AddSymbolBarState createState() => _AddSymbolBarState();
}

class _AddSymbolBarState extends State<AddSymbolBar> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      widget.onAddSymbol(text);
      _controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.0),
            child: Icon(Icons.add_chart, color: AppColors.textSecondary),
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Añadir par (ej: SOL/USDT)...',
                hintStyle: TextStyle(color: AppColors.textMuted),
                border: InputBorder.none,
              ),
              onSubmitted: (_) => _submit(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle, color: AppColors.primary),
            onPressed: _submit,
          )
        ],
      ),
    );
  }
}
