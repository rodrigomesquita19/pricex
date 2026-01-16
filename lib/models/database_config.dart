class DatabaseConfig {
  final String host;
  final int port;
  final String database;
  final String username;
  final String password;

  DatabaseConfig({
    required this.host,
    this.port = 3306,
    required this.database,
    required this.username,
    required this.password,
  });

  Map<String, dynamic> toJson() => {
    'host': host,
    'port': port,
    'database': database,
    'username': username,
    'password': password,
  };

  factory DatabaseConfig.fromJson(Map<String, dynamic> json) => DatabaseConfig(
    host: json['host'] ?? '',
    port: json['port'] ?? 3306,
    database: json['database'] ?? '',
    username: json['username'] ?? '',
    password: json['password'] ?? '',
  );

  bool get isConfigured =>
    host.isNotEmpty &&
    database.isNotEmpty &&
    username.isNotEmpty;
}
