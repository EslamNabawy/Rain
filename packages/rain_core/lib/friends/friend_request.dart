/// # friend_request.dart — rain_core package
///
/// Simple value class representing a friend request with sender, recipient, and timestamp fields.
///
/// **Key types:** FriendRequest
///
/// **Package:** rain_core
///
/// **Depends on:** None (pure Dart)
///
class FriendRequest {
  const FriendRequest({
    required this.from,
    required this.to,
    required this.sentAt,
  });

  final String from;
  final String to;
  final int sentAt;
}
