class User {
  const User({
    required this.id,
    required this.phoneNumber,
    required this.displayName,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as String,
    phoneNumber: json['phoneNumber'] as String,
    displayName: json['displayName'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'phoneNumber': phoneNumber,
    'displayName': displayName,
  };

  final String id;

  /// E.164, e.g. `+14155550100`.
  final String phoneNumber;

  /// Null until the User sets one; show it through `displayName()` in
  /// `core/formatting`, which falls back to the phone number.
  final String? displayName;
}
