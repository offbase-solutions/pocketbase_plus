import 'dart:io';
// import 'dart:js_interop';
import 'package:path/path.dart' as pp;
import 'package:pocketbase/pocketbase.dart';
import 'package:yaml/yaml.dart';
import 'package:args/args.dart';

/// Entry point of the application
/// Authenticates with PocketBase and generates Dart models for collections.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'config',
      abbr: 'c',
      defaultsTo: './pocketbase.yaml',
      help: 'Configuration file path.',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Show help information.',
    );

  final argResults = parser.parse(arguments);

  if (argResults['help'] as bool) {
    printHelp(parser);
    exit(0);
  }

  final configPath = argResults['config'] as String;

  print('Loading configuration from $configPath');
  Config config;
  try {
    config = loadConfiguration(configPath);
  } catch (e) {
    print('Error loading configuration: $e');
    printHelp(parser);
    exit(1);
  }

  print('Authenticating with PocketBase');
  final pb = PocketBase(config.domain);

  try {
    await authenticate(
      pb,
      config.email,
      config.password,
    );
  } catch (e) {
    print('Authentication failed: $e');
    print('Please check your email and password in the configuration file.');
    exit(1);
  }

  print('Fetching collections from PocketBase');
  final collections = await pb.collections.getFullList();

  print('Creating models directory at ${config.outputDirectory}');
  createModelsDirectory(config.outputDirectory);

  print('Generating models');
  generateModels(collections, config.outputDirectory);

  print('Formatting generated models');
  formatGeneratedModels(config.outputDirectory);

  print('Done');
}

/// Class representing the configuration.
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

/// Loads the PocketBase configuration from a YAML file.
Config loadConfiguration(String path) {
  final file = File(pp.normalize(path));
  if (!file.existsSync()) {
    throw Exception('Configuration file not found at $path');
  }
  final yamlString = file.readAsStringSync();
  final yaml = loadYaml(yamlString);
  return Config.fromYaml(yaml);
}

/// Prints help information.
void printHelp(ArgParser parser) {
  print('Pocketbase Plus Model Generator\n');
  print('Generates Dart models from your PocketBase collections.\n');
  print('Usage:');
  print('  dart run pocketbase_plus:main [options]\n');
  print('Options:');
  print(parser.usage);
  print('''
Expected configuration file in YAML format with the following structure:

pocketbase:
  hosting:
    domain: 'https://your-pocketbase-domain.com'
    email: 'your-email@example.com'
    password: 'your-password'
  output_directory: './lib/models'  # Optional, default is './lib/models'

Example configuration file:

pocketbase:
  hosting:
    domain: 'https://pocketbase.example.com'
    email: 'admin@example.com'
    password: 'your-password'
  output_directory: './lib/models'
''');
}

/// Authenticates an admin user with PocketBase.
Future<void> authenticate(PocketBase pb, String email, String password) async {
  await pb.admins.authWithPassword(email, password);
}

/// Ensures that the models directory exists; creates it if not.
void createModelsDirectory(String path) {
  final directory = Directory(path);
  if (!directory.existsSync()) {
    directory.createSync(recursive: true);
  }
}

/// Generates Dart models for all collections.
void generateModels(List<CollectionModel> collections, String outputDirectory) {
  for (var collection in collections) {
    // Skip collections whose name starts with an underscore
    if (collection.name.startsWith('_')) {
      continue;
    }
    String fileName = camelCaseToSnakeCase(singularizeWord(collection.name));
    final modelContent = generateModelForCollection(collection, collections);
    final filePath = pp.join(outputDirectory, '${fileName}_pb_data.dart');
    File(filePath).writeAsStringSync(modelContent);
  }
  generateGeoPointModel(outputDirectory);
}

String camelCaseToSnakeCase(String camelCaseString) {
  final RegExp exp = RegExp(r'(?<=[a-z0-9])[A-Z]');
  return camelCaseString
      .replaceAllMapped(exp, (Match m) => '_${m.group(0)}')
      .toLowerCase();
}

/// Formats the generated model files using Dart's formatter.
void formatGeneratedModels(String modelsPath) {
  Process.runSync('dart', ['format', modelsPath]);
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
      return 'sheep'; // Irregular, singular and plural are the same
    case 'fish':
      return 'fish'; // Irregular, singular and plural are the same
  }

  // Handle words ending in "ies" (e.g., "families" -> "family")
  if (pluralWord.endsWith('ies')) {
    return '${pluralWord.substring(0, pluralWord.length - 3)}y';
  }

  // Handle words ending in "ves" (e.g., "wolves" -> "wolf")
  if (pluralWord.endsWith('ves')) {
    return '${pluralWord.substring(0, pluralWord.length - 3)}f';
  }

  // Handle words ending in "es" (e.g., "boxes" -> "box")
  if (pluralWord.endsWith('es')) {
    // Check for "ch", "sh", "s", "x", "z" before "es"
    if (pluralWord.endsWith('ches') ||
        pluralWord.endsWith('shes') ||
        pluralWord.endsWith('ses') ||
        pluralWord.endsWith('xes') ||
        pluralWord.endsWith('zes')) {
      return pluralWord.substring(0, pluralWord.length - 2);
    }
  }

  // Handle regular plurals ending in "s"
  if (pluralWord.endsWith('s') && pluralWord.length > 1) {
    // Ensure it's not a word that naturally ends in 's' in singular form (e.g., "bus")
    // This is a basic check and might not cover all cases.
    if (!['bus', 'gas', 'lens'].contains(pluralWord.toLowerCase())) {
      return pluralWord.substring(0, pluralWord.length - 1);
    }
  }

  // If no rule matches, return the original word
  return pluralWord;
}

/// Generates the Dart model code for a single collection.
String generateModelForCollection(
    CollectionModel collection, List<CollectionModel> collections) {
  final buffer = StringBuffer();
  String fileName = camelCaseToSnakeCase(singularizeWord(collection.name));
  String className = createCollectionClassName(collection.name);
  // Add file documentation and imports
  buffer.writeln('// This file is auto-generated. Do not modify manually.');
  buffer.writeln('// Model for collection ${collection.name}');
  buffer.writeln('// ignore_for_file: constant_identifier_names');
  buffer.writeln();
  buffer.writeln("import 'package:json_annotation/json_annotation.dart';");
  buffer.writeln("import 'package:pocketbase/pocketbase.dart';");
  buffer.writeln("part '${fileName}_pb_data.g.dart';");
  buffer.writeln();

  // Add enums for 'select' fields
  for (var field in collection.fields) {
    if (field.type == 'select') {
      generateEnumForField(buffer, field);
    }
  }

  // Add class declaration
  buffer.writeln("@JsonSerializable()");
  buffer.writeln("class $className {");

  generateClassFields(buffer, collection.fields, collections);
  generateConstructor(collection.name, buffer, collection.fields);
  generateJsonFactoryConstructor(buffer, collection);

  buffer.writeln("}"); // Close class

  return buffer.toString();
}

/// Generates an enum for a 'select' field in the collection schema.
void generateEnumForField(StringBuffer buffer, CollectionField field) {
  // Start the enum definition with constructor
  buffer.writeln('enum ${capName(removeSnake(field.name))}Enum {');

  for (var option in field.data['values']) {
    buffer.writeln('${removeSnake(option)}("$option"),');
  }

  buffer.writeln(';\n');

  // Add a final String field and the constructor
  buffer.writeln('final String value;\n');
  buffer
      .writeln('const ${capName(removeSnake(field.name))}Enum(this.value);\n');

  // Add fromValue static method
  buffer.writeln(
      'static ${capName(removeSnake(field.name))}Enum fromValue(String value) {');
  buffer.writeln(
      '  return ${capName(removeSnake(field.name))}Enum.values.firstWhere(');
  buffer.writeln('    (enumValue) => enumValue.value == value,');
  buffer.writeln(
      '    orElse: () => throw ArgumentError("Invalid value: \$value"),');
  buffer.writeln('  );');
  buffer.writeln('}\n');

  buffer.writeln('}');
  buffer.writeln();
}

/// Generates the fields and their corresponding constants for the class.
void generateClassFields(StringBuffer buffer, List<CollectionField> schema,
    List<CollectionModel> collections) {
  for (var field in schema) {
    String fieldType = getType(field, collections);
    String requiredString = field.required ? ", required: true" : "";
    buffer.writeln("\n  @JsonKey(name: '${field.name}'$requiredString)");
    buffer.writeln("   final $fieldType ${removeSnake(field.name)};");
  }
}

/// Generates the constructor for the class.
void generateConstructor(
    String colName, StringBuffer buffer, List<CollectionField> schema) {
  String className = createCollectionClassName(colName);
  buffer.writeln("\n  const $className({");
  for (var field in schema) {
    buffer.writeln(
        "${field.required ? 'required' : ''} this.${removeSnake(field.name)},");
  }
  buffer.writeln("  });");
}

/// Generates a standalone GeoPoint model file (geo_point_pb_data.dart) for PocketBase geopoint fields.
void generateGeoPointModel(String outputDirectory) {
  final buffer = StringBuffer();
  buffer.writeln('// This file is auto-generated. Do not modify manually.');
  buffer.writeln('// GeoPoint model for PocketBase geopoint fields');
  buffer.writeln('// ignore_for_file: constant_identifier_names');
  buffer.writeln();
  buffer.writeln("import 'package:json_annotation/json_annotation.dart';");
  buffer.writeln();
  buffer.writeln("part 'geo_point_pb_data.g.dart';");
  buffer.writeln();
  buffer.writeln('@JsonSerializable()');
  buffer.writeln('class GeoPointPbData {');
  buffer.writeln('  @JsonKey(name: \'lon\')');
  buffer.writeln('  final double longitude;');
  buffer.writeln('  @JsonKey(name: \'lat\')');
  buffer.writeln('  final double latitude;');
  buffer.writeln();
  buffer.writeln('  const GeoPointPbData({');
  buffer.writeln('    required this.longitude,');
  buffer.writeln('    required this.latitude,');
  buffer.writeln('  });');
  buffer.writeln();
  buffer.writeln(
      '  factory GeoPointPbData.fromJson(Map<String, dynamic> json) =>');
  buffer.writeln('      _GeoPointPbDataFromJson(json);');
  buffer.writeln();
  buffer.writeln(
      '  Map<String, dynamic> toJson() => _GeoPointPbDataToJson(this);');
  buffer.writeln('}');
  final filePath = pp.join(outputDirectory, 'geo_point_pb_data.dart');
  File(filePath).writeAsStringSync(buffer.toString());
}

// void generateJsonFactoryConstructor(
//     StringBuffer buffer, CollectionModel collection) {
//   String className = createCollectionClassName(collection.name);

//   buffer.writeln(
//       "\n    factory $className.fromJson(Map<String, dynamic> json) => _\$${className}FromJson(json);");
//   buffer.writeln(
//       "\n    Map<String, dynamic> toJson() => _\$${className}ToJson(this);");
// }

void generateJsonFactoryConstructor(
    StringBuffer buffer, CollectionModel collection) {
  String className = createCollectionClassName(collection.name);

  buffer.writeln(
      "\n  factory $className.fromJson(Map<String, dynamic> json) => _\$${className}FromJson(json);");
  buffer.writeln(
      "  Map<String, dynamic> toJson() => _\$${className}ToJson(this);");
}

/// Capitalizes the first letter of a string.
String capName(String str) {
  if (str == 'date_time' || str == 'datetime' || str == 'dateTime') {
    return 'DateTimez';
  }
  return str[0].toUpperCase() + str.substring(1);
}

/// Converts a snake_case string to camelCase.
String removeSnake(String str) {
  final parts = str.split('_');
  return parts.fold(
      '',
      (previous, element) =>
          previous.isEmpty ? element : previous + capName(element));
}

/// Function to get a collection by its field name from List<CollectionModel> and return the class name
String getCollectionClassName(
    String collectionId, List<CollectionModel> collections) {
  for (var collection in collections) {
    if (collection.id == collectionId) {
      return createCollectionClassName(collection.name);
    }
  }
  return 'UnknownClass';
}

/// Creates the class name for a collection based on its name.
String createCollectionClassName(String collectionName) {
  return "${removeSnake(capName(singularizeWord(collectionName)))}PbData";
}

/// Maps the schema field type to a Dart type.
String getType(CollectionField field, List<CollectionModel> collections) {
  switch (field.type) {
    case 'text':
    case 'file':
    case 'email':
    case 'url':
      return field.required ? 'String' : 'String?';
    case 'geoPoint':
      return field.required ? 'GeoPointPbData' : 'GeoPointPbData?';
    case 'number':
      return field.required ? 'num' : 'num?';
    case 'json':
      return field.required ? 'Map<String, dynamic>?' : 'Map<String, dynamic>?';
    case 'bool':
      return field.required ? 'bool' : 'bool?';
    case 'date':
    case 'autodate':
      return field.required ? 'DateTime' : 'DateTime?';
    case 'select':
      return field.required
          ? '${capName(removeSnake(field.name))}Enum'
          : '${capName(removeSnake(field.name))}Enum?';
    case 'relation':
      return field.required
          ? 'String'
          : 'String?'; //TODO: Need to check targetCollectionId, so I can build the className for the property
    // return field.required
    //     ? 'List<${getCollectionClassName(field., collections)}>'
    //     : 'List<${getCollectionClassName(field.targetCollectionId!, collections)}>?';
    default:
      return 'dynamic';
  }
}
