import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/item.dart';

class ApiService {
  final String _url = 'https://jsonplaceholder.typicode.com/todos?_limit=20';
  Future<List<Item>> fetchItems() async {
    final res = await http.get(Uri.parse(_url));
    if (res.statusCode != 200) throw Exception('Failed to fetch items');
    final List data = jsonDecode(res.body) as List;
    return data.map((e) => Item.fromJson(e as Map<String, dynamic>)).toList();
  }
}
