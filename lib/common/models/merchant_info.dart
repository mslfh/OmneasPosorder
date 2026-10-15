class MerchantInfo {
  final String name;
  final String address;
  final String phone;
  final String abn;

  MerchantInfo({
    this.name = '',
    this.address = '',
    this.phone = '',
    this.abn = '',
  });

  factory MerchantInfo.fromJson(Map<String, dynamic> json) {
    // 兼容接口响应格式（支持 json['data'] 包装或直接在根对象）
    final Map<String, dynamic> map = (json['data'] is Map<String, dynamic>)
        ? json['data'] as Map<String, dynamic>
        : json;

    return MerchantInfo(
      name: map['name']?.toString() ?? '',
      address: map['address']?.toString() ?? '',
      phone: map['phone']?.toString() ?? '',
      abn: map['abn']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'address': address,
      'phone': phone,
      'abn': abn,
    };
  }

  MerchantInfo copyWith({
    String? name,
    String? address,
    String? phone,
    String? abn,
  }) {
    return MerchantInfo(
      name: name ?? this.name,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      abn: abn ?? this.abn,
    );
  }

  factory MerchantInfo.defaultProfile() {
    return MerchantInfo(
      name: "DAVE'S NOODLES",
      address: "Shop 2/129 Wilson St, Burnie Tas. 7320",
      phone: "03 6431 8818",
      abn: "76 147 759 135",
    );
  }

  bool get isEmpty =>
      name.trim().isEmpty &&
      address.trim().isEmpty &&
      phone.trim().isEmpty &&
      abn.trim().isEmpty;
}
