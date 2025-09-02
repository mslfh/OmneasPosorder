import '../../common/models/menu_item.dart';
import '../../common/models/menu_option.dart';

class SelectedProduct {
  final MenuItem product;
  List<SelectedOption> options;
  int quantity;
  SelectedProduct({
    required this.product,
    required this.options,
    this.quantity = 1,
  });
}

class SelectedOption {
  final String type;
  final MenuOption option;
  SelectedOption({required this.type, required this.option});
}

