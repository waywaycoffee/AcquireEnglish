class CosmeticItemDto {
  const CosmeticItemDto({
    required this.sku,
    required this.slot,
    required this.title,
    required this.pricePoints,
    required this.assetKey,
    required this.owned,
    required this.equipped,
    this.previewUrl,
  });

  factory CosmeticItemDto.fromJson(Map<String, dynamic> json) =>
      CosmeticItemDto(
        sku: (json['sku'] as String?) ?? '',
        slot: (json['slot'] as String?) ?? '',
        title: (json['title'] as String?) ?? '',
        pricePoints: (json['price_points'] as num?)?.toInt() ?? 0,
        assetKey: (json['asset_key'] as String?) ?? '',
        previewUrl: json['preview_url'] as String?,
        owned: json['owned'] == true,
        equipped: json['equipped'] == true,
      );

  final String sku;
  final String slot;
  final String title;
  final int pricePoints;
  final String assetKey;
  final String? previewUrl;
  final bool owned;
  final bool equipped;
}

class AvatarMeDto {
  const AvatarMeDto({
    required this.balance,
    required this.inventory,
    required this.loadout,
    required this.catalog,
  });

  factory AvatarMeDto.fromJson(Map<String, dynamic> json) => AvatarMeDto(
        balance: (json['balance'] as num?)?.toInt() ?? 0,
        inventory: ((json['inventory'] as List<dynamic>?) ?? <dynamic>[])
            .map((dynamic e) => e.toString())
            .toList(growable: false),
        loadout: Map<String, String>.from(
          (json['loadout'] as Map<String, dynamic>?) ?? <String, dynamic>{},
        ),
        catalog: ((json['catalog'] as List<dynamic>?) ?? <dynamic>[])
            .cast<Map<String, dynamic>>()
            .map(CosmeticItemDto.fromJson)
            .toList(growable: false),
      );

  final int balance;
  final List<String> inventory;
  final Map<String, String> loadout;
  final List<CosmeticItemDto> catalog;

  static const AvatarMeDto empty = AvatarMeDto(
    balance: 0,
    inventory: <String>[],
    loadout: <String, String>{},
    catalog: <CosmeticItemDto>[],
  );
}

class ReviewPointsEarnResult {
  const ReviewPointsEarnResult({
    required this.awarded,
    required this.delta,
    required this.balance,
    required this.reason,
  });

  factory ReviewPointsEarnResult.fromJson(Map<String, dynamic> json) =>
      ReviewPointsEarnResult(
        awarded: json['awarded'] == true,
        delta: (json['delta'] as num?)?.toInt() ?? 0,
        balance: (json['balance'] as num?)?.toInt() ?? 0,
        reason: (json['reason'] as String?) ?? '',
      );

  final bool awarded;
  final int delta;
  final int balance;
  final String reason;
}
