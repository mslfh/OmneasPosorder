import 'package:flutter_test/flutter_test.dart';
import 'package:omneas_posorder/common/models/order_model.dart';
import 'package:omneas_posorder/common/models/server_order_model.dart';
import 'package:omneas_posorder/common/models/menu_item.dart';
import 'package:omneas_posorder/common/models/report_models.dart';

void main() {
  group('POS Business Logic & Models Unit Tests', () {
    test('OrderModel isPaid logic tests', () {
      final paidOrder = OrderModel(
        id: 'B001-1025120000',
        orderNo: 'B001',
        orderTime: DateTime.now(),
        createdAt: DateTime.now(),
        items: '[]',
        totalAmount: 28.80,
        cashAmount: 28.80,
        orderStatus: OrderStatus.confirmed,
      );
      expect(paidOrder.isPaid, true);

      final unpaidOrder = OrderModel(
        id: 'B002-1025120000',
        orderNo: 'B002',
        orderTime: DateTime.now(),
        createdAt: DateTime.now(),
        items: '[]',
        totalAmount: 50.00,
        cashAmount: 0.00,
        orderStatus: OrderStatus.pending,
      );
      expect(unpaidOrder.isPaid, false);

      final freeOrder = OrderModel(
        id: 'B003-1025120000',
        orderNo: 'B003',
        orderTime: DateTime.now(),
        createdAt: DateTime.now(),
        items: '[]',
        totalAmount: 0.00,
        cashAmount: 0.00,
        orderStatus: OrderStatus.pending,
      );
      expect(freeOrder.isPaid, true);
    });

    test('ServerOrderModel isPaid & customerMetadata parsing tests', () {
      final serverOrderMap = {
        'id': 146,
        'order_number': 'B005-1025195549',
        'order_no': 'B005',
        'type': 'takeaway',
        'print_status': 'skipped',
        'sync_status': 'synced',
        'status': 'completed',
        'total_amount': '43.30',
        'tax_rate': '10.00',
        'tax_amount': '3.93',
        'discount_amount': '0.00',
        'final_amount': '43.30',
        'paid_amount': '43.30',
        'payment_method': 'cash',
        'place_in': 'online',
        'items': [
          {
            'id': 268,
            'product_title': 'Sweet Box',
            'product_selling_price': 21.50,
            'final_amount': 21.50,
            'quantity': 1,
          }
        ],
        'additions': [
          {
            'customer_name': 'Test User',
            'customer_phone': '123456789',
            'pickup_time': '2026-10-26 12:00:00',
            'extend_info': 'Table: A-01',
          }
        ],
      };

      final serverOrder = ServerOrderModel.fromMap(serverOrderMap);
      expect(serverOrder.isPaid, true);
      expect(serverOrder.customerName, 'Test User');
      expect(serverOrder.customerPhone, '123456789');
      expect(serverOrder.extendInfo, 'Table: A-01');
    });

    test('MenuItem displaySoldOutLabel tests', () {
      final itemNormal = MenuItem(
        id: 1,
        code: 'A001',
        title: 'Noodle',
        acronym: 'NDL',
        sellingPrice: 15.00,
        stock: 10,
        sort: 1,
        categoryIds: [1],
        isPrintable: true,
        isSoldOut: false,
      );
      expect(itemNormal.isSoldOut, false);

      final itemSoldOutCustom = MenuItem(
        id: 2,
        code: 'A002',
        title: 'Soup',
        acronym: 'SOP',
        sellingPrice: 12.00,
        stock: 0,
        sort: 2,
        categoryIds: [1],
        isPrintable: true,
        isSoldOut: true,
        soldOutLabel: '今日售罄',
      );
      expect(itemSoldOutCustom.isSoldOut, true);
      expect(itemSoldOutCustom.displaySoldOutLabel, '今日售罄');
    });

    test('DailySettlementModel JSON serialization tests', () {
      final settlement = DailySettlementModel(
        settlementId: 'Z-20261026',
        date: DateTime(2026, 10, 26),
        createdAt: DateTime.now(),
        totalRevenue: 500.00,
        cashRevenue: 300.00,
        posRevenue: 200.00,
        totalOrders: 10,
        completedOrders: 9,
        cancelledOrders: 1,
        averageOrderValue: 55.55,
      );

      final json = settlement.toJson();
      expect(json['settlement_id'], 'Z-20261026');
      expect(json['total_revenue'], 500.00);
      expect(json['completed_orders'], 9);
    });
  });
}
