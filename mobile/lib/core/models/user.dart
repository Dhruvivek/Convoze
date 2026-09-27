class User {
  const User({
    required this.id,
    required this.phoneNumber,
    required this.displayName,
    this.about,
    this.avatarUrl,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as String,
    phoneNumber: json['phoneNumber'] as String,
    displayName: json['displayName'] as String?,
    about: json['about'] as String?,
    avatarUrl: json['avatarUrl'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'phoneNumber': phoneNumber,
    'displayName': displayName,
    'about': about,
    'avatarUrl': avatarUrl,
  };

  final String id;

  /// E.164, e.g. `+14155550100`.
  final String phoneNumber;

  /// Null until the User sets one; show it through `displayName()` in
  /// `core/formatting`, which falls back to the phone number.
  final String? displayName;

  /// A short status line (#43). Null until the User sets one.
  final String? about;

  /// The public Cloudinary delivery URL for the User's avatar (#43). Null
  /// until they set one.
  final String? avatarUrl;
}
