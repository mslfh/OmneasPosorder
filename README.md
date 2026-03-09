# omneas_posorder

A modern, cross-platform food ordering system designed for restaurants, cafés, and small businesses.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.


这里我还需要添加一个全新的模式，当点击appBar的Text('Omneas POS')五次的时候，即提示输入管理密码，
初始化密码为12345abc，验证通过之后就会进入管理模式。
在此模式下，appBar会提供修改密码的选项，密码存在本地即可。
并且额外有一个exit admin的按钮，点击即退出该模式，或者重启app也会退出管理模式，
即该模式是一次性的。无需总结文档
在管理模式下，app会提供额外的管理操作。目前先实现如下的需求：
order_page在管理模式下，需要提供
长按菜品即可进行编辑该菜品的code，title，acronym，sellingPrice，stock，还可以更改菜品的category。
长按拖动该菜品，即可更改菜品的sort进行排序。
Options提供一个管理的按钮，可以对menu option进行增删改操作
注：这些操作都需要与后端进行交互，后端使用的是标准的restful api,所以你正常调用即可，如果需要额外的api可以写出一个文档给我，此外不需要其他的总结文档