import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../providers/tracker_provider.dart';

class AddExpenseDialog extends StatefulWidget {
  final TrackerProvider provider;
  final String defaultCurrency;
  final String defaultExchange;

  const AddExpenseDialog({
    super.key,
    required this.provider,
    required this.defaultCurrency,
    required this.defaultExchange,
  });

  @override
  State<AddExpenseDialog> createState() => _AddExpenseDialogState();
}

class _AddExpenseDialogState extends State<AddExpenseDialog> {
  late TextEditingController _currencyController;
  late TextEditingController _amountController;
  late TextEditingController _descriptionController;
  late String _selectedExchange;
  String _selectedCategory = 'Gasto Personal';
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _currencyController = TextEditingController(text: widget.defaultCurrency.toUpperCase());
    _amountController = TextEditingController();
    _descriptionController = TextEditingController();
    _selectedExchange = widget.defaultExchange;
  }

  @override
  void dispose() {
    _currencyController.dispose;
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: ColorScheme.dark(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: AppColors.surface,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      title: const Row(
        children: [
          Icon(Icons.add_shopping_cart, color: Colors.orange, size: 22),
          SizedBox(width: 8),
          Text(
            'Registrar Gasto o Retiro',
            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Exchange & Currency Row
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Exchange', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      const SizedBox(height: 4),
                      DropdownButtonFormField<String>(
                        value: _selectedExchange,
                        dropdownColor: AppColors.surface,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          filled: true,
                          fillColor: AppColors.card,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                        ),
                        items: ['KuCoin', 'Binance', 'BingX', 'Bitrefill', 'Billetera Externa']
                            .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _selectedExchange = v);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Moneda', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _currencyController,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'BTC, LTC, etc.',
                          hintStyle: const TextStyle(color: AppColors.textMuted),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          filled: true,
                          fillColor: AppColors.card,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Amount Field
            const Text('Cantidad Consumida / Retirada', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const SizedBox(height: 4),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: '0.00',
                hintStyle: const TextStyle(color: AppColors.textMuted),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                filled: true,
                fillColor: AppColors.card,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
              ),
            ),

            const SizedBox(height: 12),

            // Description / Note Field
            const Text('Descripción / Concepto', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const SizedBox(height: 4),
            TextField(
              controller: _descriptionController,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Ej. Amazon México 1000 MXN, Cashi Walmart, etc.',
                hintStyle: const TextStyle(color: AppColors.textMuted),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                filled: true,
                fillColor: AppColors.card,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
              ),
            ),

            const SizedBox(height: 12),

            // Category & Date Row
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Categoría', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      const SizedBox(height: 4),
                      DropdownButtonFormField<String>(
                        value: _selectedCategory,
                        dropdownColor: AppColors.surface,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          filled: true,
                          fillColor: AppColors.card,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                        ),
                        items: ['Gasto Personal', 'Compra Amazon', 'Walmart / Cashi', 'Retiro Billetera', 'Otros']
                            .map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _selectedCategory = v);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Fecha', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      const SizedBox(height: 4),
                      InkWell(
                        onTap: _pickDate,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${_selectedDate.day.toString().padLeft(2, '0')}/${_selectedDate.month.toString().padLeft(2, '0')}/${_selectedDate.year}',
                                style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                              ),
                              const Icon(Icons.calendar_today, color: AppColors.textMuted, size: 14),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar', style: TextStyle(color: AppColors.textMuted)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () async {
            final curr = _currencyController.text.trim().toUpperCase();
            final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
            if (curr.isEmpty || amount <= 0) return;

            await widget.provider.addManualExpense(
              exchange: _selectedExchange,
              currency: curr,
              amount: amount,
              date: _selectedDate,
              description: _descriptionController.text.trim(),
              category: _selectedCategory,
            );

            if (context.mounted) {
              Navigator.pop(context);
            }
          },
          child: const Text('Guardar Gasto', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
