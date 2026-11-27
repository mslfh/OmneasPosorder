import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../common/services/language_service.dart';
import '../utils/ui_helper.dart';

/// 堂食确认弹窗结果动作
enum DineInConfirmAction {
  cancel,
  pickTable,
  saveAndKitchen,
  checkoutNow,
}

/// 堂食确认弹窗返回数据
class DineInConfirmResult {
  final DineInConfirmAction action;
  final String tableName;
  final String customerName;
  final int? guestCount;
  final bool printKitchen;
  final bool printFrontDesk;
  final bool printCustomer;

  const DineInConfirmResult({
    required this.action,
    this.tableName = '',
    this.customerName = '',
    this.guestCount,
    this.printKitchen = true,
    this.printFrontDesk = true,
    this.printCustomer = false,
  });
}

/// 外卖确认弹窗结果动作
enum TakeAwayConfirmAction {
  cancel,
  saveAndKitchen,
  checkoutNow,
}

/// 外卖确认弹窗返回数据
class TakeAwayConfirmResult {
  final TakeAwayConfirmAction action;
  final String customerName;
  final String customerPhone;
  final String pickupOption;
  final TimeOfDay? customTime;
  final bool printKitchen;
  final bool printFrontDesk;
  final bool printCustomer;

  const TakeAwayConfirmResult({
    required this.action,
    this.customerName = '',
    this.customerPhone = '',
    this.pickupOption = 'Right Now',
    this.customTime,
    this.printKitchen = true,
    this.printFrontDesk = true,
    this.printCustomer = false,
  });
}

/// 订单确认弹窗组件类（包含堂食和外卖弹窗）
class OrderConfirmDialog {
  /// 显示堂食确认弹窗
  static Future<DineInConfirmResult?> showDineIn({
    required BuildContext context,
    required String initialTableName,
    String initialCustomerName = '',
    int? initialGuestCount,
    required int itemQuantity,
    required double totalPrice,
  }) {
    return showDialog<DineInConfirmResult>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return _DineInConfirmDialogWidget(
          parentContext: context,
          initialTableName: initialTableName,
          initialCustomerName: initialCustomerName,
          initialGuestCount: initialGuestCount,
          itemQuantity: itemQuantity,
          totalPrice: totalPrice,
        );
      },
    );
  }

  /// 显示外卖确认弹窗
  static Future<TakeAwayConfirmResult?> showTakeAway({
    required BuildContext context,
    required String initialCustomerName,
    required String initialCustomerPhone,
    required String initialPickupOption,
    required TimeOfDay? initialCustomTime,
    required int itemQuantity,
    required double totalPrice,
  }) {
    return showDialog<TakeAwayConfirmResult>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return _TakeAwayConfirmDialogWidget(
          initialCustomerName: initialCustomerName,
          initialCustomerPhone: initialCustomerPhone,
          initialPickupOption: initialPickupOption,
          initialCustomTime: initialCustomTime,
          itemQuantity: itemQuantity,
          totalPrice: totalPrice,
        );
      },
    );
  }

  static String _getPickupTimeDisplayText(String option, TimeOfDay? customTime) {
    final now = DateTime.now();
    if (option == 'Right Now') return 'Right Now';
    if (option == 'Custom' && customTime != null) {
      final hour = customTime.hour.toString().padLeft(2, '0');
      final minute = customTime.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    }
    if (option.endsWith('min')) {
      final mins = int.tryParse(option.replaceAll('min', '')) ?? 0;
      final targetTime = now.add(Duration(minutes: mins));
      final hour = targetTime.hour.toString().padLeft(2, '0');
      final minute = targetTime.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    }
    return option;
  }

  /// 简单的 HH:MM 数字输入时间选择弹窗
  static Future<TimeOfDay?> _showCustomTimeInputDialog(
    BuildContext context,
    TimeOfDay initialTime,
  ) {
    final hourController = TextEditingController(
      text: initialTime.hour.toString().padLeft(2, '0'),
    );
    final minuteController = TextEditingController(
      text: initialTime.minute.toString().padLeft(2, '0'),
    );
    final hourFocusNode = FocusNode();
    final minuteFocusNode = FocusNode();

    return showDialog<TimeOfDay>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Text(
            'Custom Time / 自定义时间 (HH:MM)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: 220,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 70,
                  child: TextField(
                    controller: hourController,
                    focusNode: hourFocusNode,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 2,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(
                      labelText: 'HH (时)',
                      counterText: '',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                    onChanged: (val) {
                      if (val.length == 2) {
                        minuteFocusNode.requestFocus();
                      }
                    },
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8.0),
                  child: Text(':', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                ),
                SizedBox(
                  width: 70,
                  child: TextField(
                    controller: minuteController,
                    focusNode: minuteFocusNode,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 2,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(
                      labelText: 'MM (分)',
                      counterText: '',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                    onSubmitted: (_) {
                      final h = int.tryParse(hourController.text.trim()) ?? initialTime.hour;
                      final m = int.tryParse(minuteController.text.trim()) ?? initialTime.minute;
                      final validH = h.clamp(0, 23);
                      final validM = m.clamp(0, 59);
                      Navigator.of(ctx).pop(TimeOfDay(hour: validH, minute: validM));
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final h = int.tryParse(hourController.text.trim()) ?? initialTime.hour;
                final m = int.tryParse(minuteController.text.trim()) ?? initialTime.minute;
                final validH = h.clamp(0, 23);
                final validM = m.clamp(0, 59);
                Navigator.of(ctx).pop(TimeOfDay(hour: validH, minute: validM));
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }
}

class _DineInConfirmDialogWidget extends StatefulWidget {
  final BuildContext parentContext;
  final String initialTableName;
  final String initialCustomerName;
  final int? initialGuestCount;
  final int itemQuantity;
  final double totalPrice;

  const _DineInConfirmDialogWidget({
    required this.parentContext,
    required this.initialTableName,
    required this.initialCustomerName,
    required this.initialGuestCount,
    required this.itemQuantity,
    required this.totalPrice,
  });

  @override
  State<_DineInConfirmDialogWidget> createState() => _DineInConfirmDialogWidgetState();
}

class _DineInConfirmDialogWidgetState extends State<_DineInConfirmDialogWidget> {
  late final TextEditingController _tableController;
  late final TextEditingController _nameController;
  late final TextEditingController _guestCountController;

  bool _printKitchen = true;
  bool _printFrontDesk = true;
  bool _printCustomer = false;

  @override
  void initState() {
    super.initState();
    _tableController = TextEditingController(text: widget.initialTableName);
    _nameController = TextEditingController(text: widget.initialCustomerName);
    _guestCountController = TextEditingController(
      text: widget.initialGuestCount != null && widget.initialGuestCount! > 0
          ? widget.initialGuestCount.toString()
          : '',
    );
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _tableController.dispose();
    _nameController.dispose();
    _guestCountController.dispose();
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
        _doCheckoutNow();
        return true;
      } else if (key == LogicalKeyboardKey.backslash) {
        _doSaveAndOrder();
        return true;
      }
    }
    return false;
  }

  void _doSaveAndOrder() {
    final tableInput = _tableController.text.trim();
    if (tableInput.isEmpty) {
      UIHelper.showSnackBar(
        widget.parentContext,
        'Please enter Table Number',
        backgroundColor: Colors.orange,
      );
      return;
    }
    final customerNameInput = _nameController.text.trim();
    final guestCountInput = int.tryParse(_guestCountController.text.trim());
    Navigator.of(context).pop(
      DineInConfirmResult(
        action: DineInConfirmAction.saveAndKitchen,
        tableName: tableInput,
        customerName: customerNameInput,
        guestCount: guestCountInput,
        printKitchen: _printKitchen,
        printFrontDesk: _printFrontDesk,
        printCustomer: _printCustomer,
      ),
    );
  }

  void _doCheckoutNow() {
    final tableInput = _tableController.text.trim();
    if (tableInput.isEmpty) {
      UIHelper.showSnackBar(
        widget.parentContext,
        'Please enter Table Number',
        backgroundColor: Colors.orange,
      );
      return;
    }
    final customerNameInput = _nameController.text.trim();
    final guestCountInput = int.tryParse(_guestCountController.text.trim());
    Navigator.of(context).pop(
      DineInConfirmResult(
        action: DineInConfirmAction.checkoutNow,
        tableName: tableInput,
        customerName: customerNameInput,
        guestCount: guestCountInput,
        printKitchen: _printKitchen,
        printFrontDesk: _printFrontDesk,
        printCustomer: true,
      ),
    );
  }

  void _doPickTable() {
    final customerNameInput = _nameController.text.trim();
    final guestCountInput = int.tryParse(_guestCountController.text.trim());
    Navigator.of(context).pop(
      DineInConfirmResult(
        action: DineInConfirmAction.pickTable,
        tableName: _tableController.text.trim(),
        customerName: customerNameInput,
        guestCount: guestCountInput,
        printKitchen: _printKitchen,
        printFrontDesk: _printFrontDesk,
        printCustomer: _printCustomer,
      ),
    );
  }

  Widget _buildPrintOptionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Print Options / 小票打印:',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            FilterChip(
              label: const Text('Kitchen Ticket'),
              selected: _printKitchen,
              selectedColor: Colors.blue.shade100,
              checkmarkColor: Colors.blue.shade800,
              labelStyle: TextStyle(
                fontSize: 13,
                color: _printKitchen ? Colors.blue.shade900 : Colors.black87,
                fontWeight: _printKitchen ? FontWeight.bold : FontWeight.normal,
              ),
              onSelected: (val) {
                setState(() => _printKitchen = val);
              },
            ),
            FilterChip(
              label: const Text('Front Desk Ticket'),
              selected: _printFrontDesk,
              selectedColor: Colors.purple.shade100,
              checkmarkColor: Colors.purple.shade800,
              labelStyle: TextStyle(
                fontSize: 13,
                color: _printFrontDesk ? Colors.purple.shade900 : Colors.black87,
                fontWeight: _printFrontDesk ? FontWeight.bold : FontWeight.normal,
              ),
              onSelected: (val) {
                setState(() => _printFrontDesk = val);
              },
            ),
            FilterChip(
              label: const Text('Customer Receipt'),
              selected: _printCustomer,
              selectedColor: Colors.green.shade100,
              checkmarkColor: Colors.green.shade800,
              labelStyle: TextStyle(
                fontSize: 13,
                color: _printCustomer ? Colors.green.shade900 : Colors.black87,
                fontWeight: _printCustomer ? FontWeight.bold : FontWeight.normal,
              ),
              onSelected: (val) {
                setState(() => _printCustomer = val);
              },
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.restaurant, color: Colors.blue[800]),
          const SizedBox(width: 8),
          Text('${'dine_in'.tr} - ${'confirm'.tr}'),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${'selected_items_count'.trParams({'count': '${widget.itemQuantity}'})} (\$${widget.totalPrice.toStringAsFixed(2)})',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tableController,
                    autofocus: true,
                    keyboardType: TextInputType.text,
                    decoration: InputDecoration(
                      labelText: 'Table Number',
                      hintText: 'Optional',
                      prefixIcon: const Icon(Icons.table_restaurant),
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: _tableController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                setState(() {
                                  _tableController.clear();
                                });
                              },
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _doPickTable,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                    backgroundColor: Colors.blueGrey[700],
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Pick Table'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Customer Name',
                      hintText: 'Enter name (optional)',
                      prefixIcon: Icon(Icons.person, size: 20),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: TextField(
                    controller: _guestCountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Guests',
                      hintText: 'Optional',
                      prefixIcon: Icon(Icons.people, size: 20),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildPrintOptionsSection(),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.all(16),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(
            const DineInConfirmResult(action: DineInConfirmAction.cancel),
          ),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.save, size: 18),
          label: const Text('Save & Order'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.amber[800],
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          onPressed: _doSaveAndOrder,
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.shopping_cart_checkout, size: 18),
          label: const Text('Checkout Now'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green[700],
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          onPressed: _doCheckoutNow,
        ),
      ],
    );
  }
}

class _TakeAwayConfirmDialogWidget extends StatefulWidget {
  final String initialCustomerName;
  final String initialCustomerPhone;
  final String initialPickupOption;
  final TimeOfDay? initialCustomTime;
  final int itemQuantity;
  final double totalPrice;

  const _TakeAwayConfirmDialogWidget({
    required this.initialCustomerName,
    required this.initialCustomerPhone,
    required this.initialPickupOption,
    required this.initialCustomTime,
    required this.itemQuantity,
    required this.totalPrice,
  });

  @override
  State<_TakeAwayConfirmDialogWidget> createState() => _TakeAwayConfirmDialogWidgetState();
}

class _TakeAwayConfirmDialogWidgetState extends State<_TakeAwayConfirmDialogWidget> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late String _pickupOption;
  TimeOfDay? _customTime;

  bool _printKitchen = true;
  bool _printFrontDesk = true;
  bool _printCustomer = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialCustomerName);
    _phoneController = TextEditingController(text: widget.initialCustomerPhone);
    _pickupOption = widget.initialPickupOption;
    _customTime = widget.initialCustomTime;
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
        _doCheckoutNow();
        return true;
      } else if (key == LogicalKeyboardKey.backslash) {
        _doSaveAndOrder();
        return true;
      } else if (key == LogicalKeyboardKey.space) {
        _cyclePickupTimeOption();
        return true;
      }
    }
    return false;
  }

  void _cyclePickupTimeOption() {
    const options = ['Right Now', '10min', '15min', '20min', '25min', '30min', 'Custom'];
    final currentIndex = options.indexOf(_pickupOption);
    final nextIndex = (currentIndex == -1 || currentIndex == options.length - 1)
        ? 0
        : currentIndex + 1;
    setState(() {
      _pickupOption = options[nextIndex];
      if (_pickupOption == 'Custom' && _customTime == null) {
        _customTime = TimeOfDay.now();
      }
    });
  }

  void _doSaveAndOrder() {
    Navigator.of(context).pop(
      TakeAwayConfirmResult(
        action: TakeAwayConfirmAction.saveAndKitchen,
        customerName: _nameController.text.trim(),
        customerPhone: _phoneController.text.trim(),
        pickupOption: _pickupOption,
        customTime: _customTime,
        printKitchen: _printKitchen,
        printFrontDesk: _printFrontDesk,
        printCustomer: _printCustomer,
      ),
    );
  }

  void _doCheckoutNow() {
    Navigator.of(context).pop(
      TakeAwayConfirmResult(
        action: TakeAwayConfirmAction.checkoutNow,
        customerName: _nameController.text.trim(),
        customerPhone: _phoneController.text.trim(),
        pickupOption: _pickupOption,
        customTime: _customTime,
        printKitchen: _printKitchen,
        printFrontDesk: _printFrontDesk,
        printCustomer: true,
      ),
    );
  }

  Widget _buildPickupChip(String option) {
    final bool isSelected = _pickupOption == option;
    String label = option;
    if (option == 'Right Now') label = 'Now';
    if (option == 'Custom') {
      if (isSelected && _customTime != null) {
        final hour = _customTime!.hour.toString().padLeft(2, '0');
        final minute = _customTime!.minute.toString().padLeft(2, '0');
        label = 'Custom ($hour:$minute)';
      } else {
        label = 'Custom';
      }
    }

    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 15,
          color: isSelected ? Colors.white : Colors.black87,
        ),
      ),
      selected: isSelected,
      selectedColor: Colors.blue,
      backgroundColor: Colors.grey[200],
      visualDensity: VisualDensity.compact,
      onSelected: (selected) async {
        if (!selected && isSelected) return;
        if (option == 'Custom') {
          final now = TimeOfDay.now();
          final picked = await OrderConfirmDialog._showCustomTimeInputDialog(
            context,
            _customTime ?? now,
          );
          if (picked != null) {
            setState(() {
              _pickupOption = 'Custom';
              _customTime = picked;
            });
          }
        } else {
          setState(() {
            _pickupOption = option;
          });
        }
      },
    );
  }

  Widget _buildPrintOptionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Print Options / 小票打印:',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            FilterChip(
              label: const Text('Kitchen Ticket'),
              selected: _printKitchen,
              selectedColor: Colors.blue.shade100,
              checkmarkColor: Colors.blue.shade800,
              labelStyle: TextStyle(
                fontSize: 13,
                color: _printKitchen ? Colors.blue.shade900 : Colors.black87,
                fontWeight: _printKitchen ? FontWeight.bold : FontWeight.normal,
              ),
              onSelected: (val) {
                setState(() => _printKitchen = val);
              },
            ),
            FilterChip(
              label: const Text('Front Desk Ticket'),
              selected: _printFrontDesk,
              selectedColor: Colors.purple.shade100,
              checkmarkColor: Colors.purple.shade800,
              labelStyle: TextStyle(
                fontSize: 13,
                color: _printFrontDesk ? Colors.purple.shade900 : Colors.black87,
                fontWeight: _printFrontDesk ? FontWeight.bold : FontWeight.normal,
              ),
              onSelected: (val) {
                setState(() => _printFrontDesk = val);
              },
            ),
            FilterChip(
              label: const Text('Customer Receipt'),
              selected: _printCustomer,
              selectedColor: Colors.green.shade100,
              checkmarkColor: Colors.green.shade800,
              labelStyle: TextStyle(
                fontSize: 13,
                color: _printCustomer ? Colors.green.shade900 : Colors.black87,
                fontWeight: _printCustomer ? FontWeight.bold : FontWeight.normal,
              ),
              onSelected: (val) {
                setState(() => _printCustomer = val);
              },
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    String pickupText = OrderConfirmDialog._getPickupTimeDisplayText(_pickupOption, _customTime);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.takeout_dining, color: Colors.orange[800]),
          const SizedBox(width: 8),
          Text('${'takeaway'.tr} - ${'confirm'.tr}'),
        ],
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${'selected_items_count'.trParams({'count': '${widget.itemQuantity}'})} (\$${widget.totalPrice.toStringAsFixed(2)})',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Customer Name',
                  hintText: 'Enter name (optional)',
                  prefixIcon: Icon(Icons.person, size: 20),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Customer Phone',
                  hintText: 'Enter phone (optional)',
                  prefixIcon: Icon(Icons.phone, size: 20),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.access_time, size: 18, color: Colors.brown),
                  const SizedBox(width: 6),
                  Text(
                    'Pickup: $pickupText',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.brown,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildPickupChip('Right Now'),
                    const SizedBox(width: 6),
                    _buildPickupChip('10min'),
                    const SizedBox(width: 6),
                    _buildPickupChip('15min'),
                    const SizedBox(width: 6),
                    _buildPickupChip('20min'),
                    const SizedBox(width: 6),
                    _buildPickupChip('25min'),
                    const SizedBox(width: 6),
                    _buildPickupChip('30min'),
                    const SizedBox(width: 6),
                    _buildPickupChip('Custom'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _buildPrintOptionsSection(),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.all(16),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(
            const TakeAwayConfirmResult(action: TakeAwayConfirmAction.cancel),
          ),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.save, size: 18),
          label: const Text('Save & Order'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.amber[800],
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          onPressed: _doSaveAndOrder,
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.shopping_cart_checkout, size: 18),
          label: const Text('Checkout Now'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green[700],
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          onPressed: _doCheckoutNow,
        ),
      ],
    );
  }
}
