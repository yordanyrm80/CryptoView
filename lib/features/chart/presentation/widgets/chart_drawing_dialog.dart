import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class ChartDrawingDialog extends StatefulWidget {
  final double price;
  final Function(String label, String hexColor) onSave;

  const ChartDrawingDialog({
    Key? key,
    required this.price,
    required this.onSave,
  }) : super(key: key);

  @override
  _ChartDrawingDialogState createState() => _ChartDrawingDialogState();
}

class _ChartDrawingDialogState extends State<ChartDrawingDialog> {
  final TextEditingController _labelController = TextEditingController(text: 'Línea de Soporte/Resistencia');
  String _selectedColor = '#F0B90B'; // default gold

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Widget _colorOption(String hexColor) {
    final bool isSelected = hexColor == _selectedColor;
    final int colorVal = int.parse(hexColor.replaceFirst('#', '0xFF'));

    return GestureDetector(
      onTap: () => setState(() => _selectedColor = hexColor),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Color(colorVal),
          shape: BoxShape.circle,
          border: isSelected
              ? Border.all(color: Colors.white, width: 2)
              : Border.all(color: Colors.transparent),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      title: const Text(
        'Añadir Línea Horizontal',
        style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Precio: \$${widget.price.toStringAsFixed(2)}',
            style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _labelController,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Etiqueta',
              labelStyle: TextStyle(color: AppColors.textSecondary),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.border)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.primary)),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Color:', style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _colorOption('#F0B90B'),
              _colorOption('#F6465D'),
              _colorOption('#0ECB81'),
              _colorOption('#00E6B8'),
              _colorOption('#29B6F6'),
            ],
          )
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar', style: TextStyle(color: AppColors.textMuted)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.background,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () {
            widget.onSave(_labelController.text, _selectedColor);
            Navigator.pop(context);
          },
          child: const Text('Guardar'),
        )
      ],
    );
  }
}
