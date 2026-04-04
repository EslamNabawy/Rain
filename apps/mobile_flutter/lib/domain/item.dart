class Item {
  final int userId;
  final int id;
  final String title;
  final bool completed;

  Item({
    required this.userId,
    required this.id,
    required this.title,
    required this.completed,
  });

  factory Item.fromJson(Map<String, dynamic> json) {
    return Item(
      userId: json['userId'] as int,
      id: json['id'] as int,
      title: json['title'] as String,
      completed: json['completed'] as bool,
    );
  }
}
