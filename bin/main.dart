import 'dart:io';
// import 'dart:js_interop';
import 'package:path/path.dart' as pp;
import 'package:pocketbase/pocketbase.dart';
import 'package:yaml/yaml.dart';
import 'package:args/args.dart';

/// Entry point of the application
/// Authenticates with PocketBase and generates Dart models for collections.
Future<void> main(List<String> arguments) async {
  // print('Done');
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

  print('Loading expansion mappings');
  final expansionMappings = await loadExpansionMappings(pb);

  print('Creating models directory at ${config.outputDirectory}');
  createModelsDirectory(config.outputDirectory);

  print('Generating models');
  generateModels(collections, config.outputDirectory, expansionMappings);

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

/// Represents an expansion mapping for a collection field
class ExpansionMapping {
  final String sourceCollectionName;
  final String sourceFieldName;
  final bool isSingle;
  final String targetCollectionName;

  ExpansionMapping({
    required this.sourceCollectionName,
    required this.sourceFieldName,
    required this.isSingle,
    required this.targetCollectionName,
  });
}

/// Loads expansion mappings from the _expansions collection
Future<List<ExpansionMapping>> loadExpansionMappings(PocketBase pb) async {
  try {
    final expansions = await pb.collection('_expansions').getFullList();
    return expansions.map((record) {
      return ExpansionMapping(
        sourceCollectionName: record.data['sourceCollectionName'] as String,
        sourceFieldName: record.data['sourceFieldName'] as String,
        isSingle: record.data['isSingle'] as bool,
        targetCollectionName: record.data['targetCollectionName'] as String,
      );
    }).toList();
  } catch (e) {
    print('Warning: Could not load expansion mappings: $e');
    return [];
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

// REPLACE the existing generateModels function with this
void generateModels(
  List<CollectionModel> collections,
  String outputDirectory,
  List<ExpansionMapping> expansionMappings,
) {
  for (var collection in collections) {
    if (collection.name.startsWith('_')) {
      continue;
    }
    String fileName = camelCaseToSnakeCase(singularizeWord(collection.name));
    final modelContent = generateModelForCollection(
      collection,
      collections,
      expansionMappings,
    );
    final filePath = pp.join(outputDirectory, '${fileName}_data.dart');
    File(filePath).writeAsStringSync(modelContent);
  }
  generateGeoPointModel(outputDirectory);
  generateBarrelFile(collections, outputDirectory);
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

String generateModelForCollection(
  CollectionModel collection,
  List<CollectionModel> collections,
  List<ExpansionMapping> expansionMappings,
) {
  final buffer = StringBuffer();
  String fileName = camelCaseToSnakeCase(singularizeWord(collection.name));
  String className = createCollectionClassName(collection.name);

  // Get expansions for this collection
  final collectionExpansions = expansionMappings
      .where((e) => e.sourceCollectionName == collection.name)
      .toList();

  // Add file documentation and imports
  buffer.writeln('// This file is auto-generated. Do not modify manually.');
  buffer.writeln('// Model for collection ${collection.name}');
  buffer.writeln('// ignore_for_file: constant_identifier_names');
  buffer.writeln();
  buffer.writeln("import 'package:json_annotation/json_annotation.dart';");

  // Import related collection models for expand
  if (collectionExpansions.isNotEmpty) {
    final importedCollections = <String>{};
    for (var expansion in collectionExpansions) {
      String targetFileName =
          camelCaseToSnakeCase(singularizeWord(expansion.targetCollectionName));
      // Avoid importing self
      if (targetFileName != fileName) {
        importedCollections.add("import '${targetFileName}_data.dart';");
      }
    }
    // Add imports in sorted order for consistency
    for (var import in importedCollections.toList()..sort()) {
      buffer.writeln(import);
    }
  }

  buffer.writeln("part '${fileName}_data.g.dart';");
  buffer.writeln();

  // Add enums for 'select' fields
  for (var field in collection.fields) {
    if (field.type == 'select') {
      generateEnumForField(buffer, field);
    }
  }

  // Add class declaration
  buffer.writeln("@JsonSerializable()");
  // buffer.writeln("@JsonSerializable(copyWith: true)");
  buffer.writeln("class $className {");

  generateClassFields(buffer, collection.fields, collections);

  // Add collection metadata as instance properties
  buffer.writeln("\n  @JsonKey(includeFromJson: false, includeToJson: false)");
  buffer.writeln(" final String collectionId = '${collection.id}';");
  buffer.writeln("\n  @JsonKey(includeFromJson: false, includeToJson: false)");
  buffer.writeln("  final String collectionName = '${collection.name}';");

  // Add expand property if there are expansions
  if (collectionExpansions.isNotEmpty) {
    buffer.writeln();
    buffer.writeln("  @JsonKey(name: 'expand')");
    buffer.writeln("  final ${className}Expand? expand;");
  }

  generateConstructor(
    collection.name,
    buffer,
    collection.fields,
    collectionExpansions.isNotEmpty,
  );
  generateJsonFactoryConstructor(buffer, collection);

  buffer.writeln("}"); // Close class
  buffer.writeln();

  // Generate expand class if needed
  if (collectionExpansions.isNotEmpty) {
    generateExpandClass(
      buffer,
      collection,
      collectionExpansions,
      collections,
    );
  }

  return buffer.toString();
}

// NEW function to generate the expand class
void generateExpandClass(
  StringBuffer buffer,
  CollectionModel collection,
  List<ExpansionMapping> expansions,
  List<CollectionModel> collections,
) {
  String className = createCollectionClassName(collection.name);
  String expandClassName = '${className}Expand';

  buffer.writeln("@JsonSerializable()");
  buffer.writeln("class $expandClassName {");

  // Generate fields for each expansion
  for (var expansion in expansions) {
    String targetClassName =
        createCollectionClassName(expansion.targetCollectionName);
    String fieldType =
        expansion.isSingle ? '$targetClassName?' : 'List<$targetClassName>?';

    buffer.writeln("  @JsonKey(name: '${expansion.sourceFieldName}')");
    buffer.writeln(
        "  final $fieldType ${removeSnake(expansion.sourceFieldName)};");
    buffer.writeln();
  }

  // Constructor
  buffer.writeln("  const $expandClassName({");
  for (var expansion in expansions) {
    buffer.writeln("    this.${removeSnake(expansion.sourceFieldName)},");
  }
  buffer.writeln("  });");
  buffer.writeln();

  // JSON methods
  buffer.writeln(
      "  factory $expandClassName.fromJson(Map<String, dynamic> json) =>");
  buffer.writeln("      _\$${expandClassName}FromJson(json);");
  buffer.writeln();
  buffer.writeln(
      "  Map<String, dynamic> toJson() => _\$${expandClassName}ToJson(this);");

  buffer.writeln("}");
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
    buffer.writeln("  final $fieldType ${removeSnake(field.name)};");
    buffer.writeln(
        "  static const String ${removeSnake(capName(field.name))} = '${field.name}';");
  }
}

void generateConstructor(
  String colName,
  StringBuffer buffer,
  List<CollectionField> schema,
  bool hasExpand,
) {
  String className = createCollectionClassName(colName);
  buffer.writeln("\n  const $className({");
  for (var field in schema) {
    buffer.writeln(
        "   ${field.required ? 'required' : ''} this.${removeSnake(field.name)},");
  }
  if (hasExpand) {
    buffer.writeln("    this.expand,");
  }
  buffer.writeln("  });");
}

/// Generates a standalone GeoPoint model file (geo_point_data.dart) for PocketBase geopoint fields.
void generateGeoPointModel(String outputDirectory) {
  final buffer = StringBuffer();
  buffer.writeln('// This file is auto-generated. Do not modify manually.');
  buffer.writeln('// GeoPoint model for PocketBase geopoint fields');
  buffer.writeln('// ignore_for_file: constant_identifier_names');
  buffer.writeln();
  buffer.writeln("import 'package:json_annotation/json_annotation.dart';");
  buffer.writeln();
  buffer.writeln("part 'geo_point_data.g.dart';");
  buffer.writeln();
  buffer.writeln('@JsonSerializable()');
  buffer.writeln('class GeoPointData {');
  buffer.writeln('  @JsonKey(name: \'lon\')');
  buffer.writeln('  final double longitude;');
  buffer.writeln('  @JsonKey(name: \'lat\')');
  buffer.writeln('  final double latitude;');
  buffer.writeln();
  buffer.writeln('  const GeoPointData({');
  buffer.writeln('    required this.longitude,');
  buffer.writeln('    required this.latitude,');
  buffer.writeln('  });');
  buffer.writeln();
  buffer
      .writeln('  factory GeoPointData.fromJson(Map<String, dynamic> json) =>');
  buffer.writeln('      _\$GeoPointDataFromJson(json);');
  buffer.writeln();
  buffer.writeln(
      '  Map<String, dynamic> toJson() => _\$GeoPointDataToJson(this);');
  buffer.writeln('}');
  final filePath = pp.join(outputDirectory, 'geo_point_data.dart');
  File(filePath).writeAsStringSync(buffer.toString());
}

/// Generates a barrel file (index.dart) that exports all generated collection models.
void generateBarrelFile(
    List<CollectionModel> collections, String outputDirectory) {
  final buffer = StringBuffer();
  buffer.writeln('// Auto-generated barrel file. Do not edit manually.');
  buffer.writeln('// Export all PocketBase data models');
  buffer.writeln();

  // Export GeoPoint model first (if any collection uses geoPoint fields)
  buffer.writeln("export 'geo_point_data.dart';");
  buffer.writeln();

  // Export each collection model
  for (var collection in collections) {
    if (collection.name.startsWith('_')) continue; // skip internal collections
    final fileName = camelCaseToSnakeCase(singularizeWord(collection.name));
    buffer.writeln("export '${fileName}_data.dart';");
  }

  final barrelPath = pp.join(outputDirectory, 'dto_generated.dart');
  File(barrelPath).writeAsStringSync(buffer.toString());
}

void generateJsonFactoryConstructor(
    StringBuffer buffer, CollectionModel collection) {
  String className = createCollectionClassName(collection.name);

  buffer.writeln(
      "\n  factory $className.fromJson(Map<String, dynamic> json) => _\$${className}FromJson(json);");
  buffer.writeln(
      "\n  Map<String, dynamic> toJson() => _\$${className}ToJson(this);");
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
  return "${removeSnake(capName(singularizeWord(collectionName)))}Data";
}

// ADD this helper function to detect integer field names
bool _isIntegerFieldName(String fieldName) {
  final integerSuffixes = [
    'count',
    'minutes',
    'seconds',
    'hours',
    'days',
    'weeks',
    'months',
    'years',
    'age',
    'quantity',
    'total',
    'index',
    'position',
    'rank',
    'level',
    'size',
    'length',
    'width',
    'height',
    'number',
    'score'
  ];

  final lowerFieldName = fieldName.toLowerCase();
  return integerSuffixes.any((suffix) => lowerFieldName.endsWith(suffix));
}

// REPLACE the existing getType function with this updated version
String getType(CollectionField field, List<CollectionModel> collections) {
  switch (field.type) {
    case 'text':
    case 'file':
    case 'email':
    case 'password':
    case 'url':
      return field.required ? 'String' : 'String?';
    case 'geoPoint':
      return field.required ? 'GeoPointData' : 'GeoPointData?';
    case 'number':
      // Check if field name suggests integer type
      if (_isIntegerFieldName(field.name)) {
        return field.required ? 'int' : 'int?';
      }
      return field.required ? 'double' : 'double?';
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
      // Check if it's a single or multiple relation
      final maxSelect = field.data['maxSelect'] as int?;
      final isSingle = maxSelect == 1;

      if (isSingle) {
        // Single relation: returns a string ID
        return field.required ? 'String' : 'String?';
      } else {
        // Multiple relation: returns array of string IDs
        return field.required ? 'List<String>' : 'List<String>?';
      }
    default:
      return 'dynamic';
  }
}
