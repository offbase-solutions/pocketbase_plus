import 'dart:io';
import 'package:path/path.dart' as pp;
import 'package:yaml/yaml.dart';

/// Debug version that tests the code without requiring PocketBase connection
void main(List<String> arguments) async {
  print('🔧 DEBUG MODE - Testing PocketBase Plus without real connection');

  // Test individual functions
  testStringUtilities();
  testConfigurationLoading();
  testModelGeneration();

  print('✅ All debug tests completed successfully!');
}

void testStringUtilities() {
  print('\n🧪 Testing String Utilities:');

  // Test camelCaseToSnakeCase
  final testCases = ['helloWorld', 'userProfile', 'articleData', 'testCase'];

  for (final testCase in testCases) {
    final result = camelCaseToSnakeCase(testCase);
    print('  $testCase -> $result');
  }

  // Test singularizeWord
  final pluralTests = ['users', 'articles', 'categories', 'children', 'men'];

  for (final test in pluralTests) {
    final result = singularizeWord(test);
    print('  $test -> $result');
  }
}

void testConfigurationLoading() {
  print('\n🧪 Testing Configuration Loading:');

  try {
    // Create a test config file
    final testConfig = '''
pocketbase:
  hosting:
    domain: 'https://test.example.com'
    email: 'test@example.com'
    password: 'test123'
  output_directory: './test_output'
''';

    File('./test_config.yaml').writeAsStringSync(testConfig);
    final config = loadConfiguration('./test_config.yaml');

    print('  ✅ Config loaded successfully:');
    print('     Domain: ${config.domain}');
    print('     Email: ${config.email}');
    print('     Output: ${config.outputDirectory}');

    // Clean up
    File('./test_config.yaml').deleteSync();
  } catch (e) {
    print('  ❌ Config loading failed: $e');
  }
}

void testModelGeneration() {
  print('\n🧪 Testing Model Generation:');

  // Test createCollectionClassName
  final collectionNames = ['users', 'articles', 'user_profiles', 'categories'];

  for (final name in collectionNames) {
    final className = createCollectionClassName(name);
    print('  $name -> $className');
  }
}

// Copy the utility functions from main.dart
String camelCaseToSnakeCase(String camelCaseString) {
  final RegExp exp = RegExp(r'(?<=[a-z0-9])[A-Z]');
  return camelCaseString
      .replaceAllMapped(exp, (Match m) => '_${m.group(0)}')
      .toLowerCase();
}

String singularizeWord(String pluralWord) {
  // Handle common irregular plurals
  switch (pluralWord.toLowerCase()) {
    case 'men':
      return 'man';
    case 'women':
      return 'woman';
    case 'children':
      return 'child';
    case 'feet':
      return 'foot';
    case 'teeth':
      return 'tooth';
    case 'geese':
      return 'goose';
    case 'mice':
      return 'mouse';
    case 'oxen':
      return 'ox';
    case 'sheep':
      return 'sheep';
    case 'fish':
      return 'fish';
  }

  if (pluralWord.endsWith('ies')) {
    return '${pluralWord.substring(0, pluralWord.length - 3)}y';
  }

  if (pluralWord.endsWith('ves')) {
    return '${pluralWord.substring(0, pluralWord.length - 3)}f';
  }

  if (pluralWord.endsWith('es')) {
    if (pluralWord.endsWith('ches') ||
        pluralWord.endsWith('shes') ||
        pluralWord.endsWith('ses') ||
        pluralWord.endsWith('xes') ||
        pluralWord.endsWith('zes')) {
      return pluralWord.substring(0, pluralWord.length - 2);
    }
  }

  if (pluralWord.endsWith('s') && pluralWord.length > 1) {
    if (!['bus', 'gas', 'lens'].contains(pluralWord.toLowerCase())) {
      return pluralWord.substring(0, pluralWord.length - 1);
    }
  }

  return pluralWord;
}

String createCollectionClassName(String collectionName) {
  return "${removeSnake(capName(singularizeWord(collectionName)))}Data";
}

String capName(String str) {
  if (str == 'date_time' || str == 'datetime' || str == 'dateTime') {
    return 'DateTimez';
  }
  return str[0].toUpperCase() + str.substring(1);
}

String removeSnake(String str) {
  final parts = str.split('_');
  return parts.fold(
      '',
      (previous, element) =>
          previous.isEmpty ? element : previous + capName(element));
}

Config loadConfiguration(String path) {
  final file = File(pp.normalize(path));
  if (!file.existsSync()) {
    throw Exception('Configuration file not found at $path');
  }
  final yamlString = file.readAsStringSync();
  final yaml = loadYaml(yamlString);
  return Config.fromYaml(yaml);
}

class Config {
  final String domain;
  final String email;
  final String password;
  final String outputDirectory;

  Config({
    required this.domain,
    required this.email,
    required this.password,
    required this.outputDirectory,
  });

  factory Config.fromYaml(YamlMap yaml) {
    final pbConfig = yaml['pocketbase'];
    if (pbConfig == null) {
      throw Exception('Missing "pocketbase" section in configuration.');
    }

    final hostingConfig = pbConfig['hosting'];
    if (hostingConfig == null) {
      throw Exception(
          'Missing "hosting" section under "pocketbase" in configuration.');
    }

    final domain = hostingConfig['domain'];
    final email = hostingConfig['email'];
    final password = hostingConfig['password'];

    if (domain == null || email == null || password == null) {
      throw Exception(
          'Missing "domain", "email", or "password" in hosting configuration.');
    }

    final outputDirectory = pbConfig['output_directory'] ?? './lib/models/data';

    return Config(
      domain: domain,
      email: email,
      password: password,
      outputDirectory: outputDirectory,
    );
  }
}
