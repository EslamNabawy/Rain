String supabasePreferredEmailFromUsername(
  String username, {
  required String projectUrl,
}) {
  return '$username@${supabaseAuthAliasDomain(projectUrl)}';
}

List<String> supabaseLoginEmailsFromUsername(
  String username, {
  required String projectUrl,
}) {
  return <String>[
    supabasePreferredEmailFromUsername(username, projectUrl: projectUrl),
    '$username@example.com',
    '$username@rain.example.com',
    '$username@rain.local',
    '$username@gmail.com',
  ];
}

String supabaseAuthAliasDomain(String projectUrl) {
  final host = Uri.tryParse(projectUrl)?.host.toLowerCase() ?? '';
  if (host.isEmpty) {
    throw ArgumentError.value(
      projectUrl,
      'projectUrl',
      'Expected an absolute Supabase project URL',
    );
  }
  return 'auth.$host';
}
