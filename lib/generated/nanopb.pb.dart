// This is a generated file - do not edit.
//
// Generated from nanopb.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'google/protobuf/descriptor.pbenum.dart' as $0;
import 'nanopb.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'nanopb.pbenum.dart';

/// This is the inner options message, which basically defines options for
/// a field. When it is used in message or file scope, it applies to all
/// fields.
class NanoPBOptions extends $pb.GeneratedMessage {
  factory NanoPBOptions({
    $core.int? maxSize,
    $core.int? maxCount,
    FieldType? type,
    $core.bool? longNames,
    $core.bool? packedStruct,
    $core.bool? skipMessage,
    IntSize? intSize,
    $core.bool? noUnions,
    $core.int? msgid,
    $core.bool? packedEnum,
    $core.bool? anonymousOneof,
    $core.bool? proto3,
    $core.bool? enumToString,
    $core.int? maxLength,
    $core.bool? fixedLength,
    $core.bool? fixedCount,
    TypenameMangling? mangleNames,
    $core.String? callbackDatatype,
    $core.String? callbackFunction,
    DescriptorSize? descriptorsize,
    $core.bool? proto3SingularMsgs,
    $core.bool? submsgCallback,
    $core.bool? defaultHas,
    $core.Iterable<$core.String>? include,
    $core.String? package,
    $core.Iterable<$core.String>? exclude,
    $0.FieldDescriptorProto_Type? typeOverride,
    $core.bool? sortByTag,
    FieldType? fallbackType,
  }) {
    final result = NanoPBOptions._();
    if (maxSize != null) result.maxSize = maxSize;
    if (maxCount != null) result.maxCount = maxCount;
    if (type != null) result.type = type;
    if (longNames != null) result.longNames = longNames;
    if (packedStruct != null) result.packedStruct = packedStruct;
    if (skipMessage != null) result.skipMessage = skipMessage;
    if (intSize != null) result.intSize = intSize;
    if (noUnions != null) result.noUnions = noUnions;
    if (msgid != null) result.msgid = msgid;
    if (packedEnum != null) result.packedEnum = packedEnum;
    if (anonymousOneof != null) result.anonymousOneof = anonymousOneof;
    if (proto3 != null) result.proto3 = proto3;
    if (enumToString != null) result.enumToString = enumToString;
    if (maxLength != null) result.maxLength = maxLength;
    if (fixedLength != null) result.fixedLength = fixedLength;
    if (fixedCount != null) result.fixedCount = fixedCount;
    if (mangleNames != null) result.mangleNames = mangleNames;
    if (callbackDatatype != null) result.callbackDatatype = callbackDatatype;
    if (callbackFunction != null) result.callbackFunction = callbackFunction;
    if (descriptorsize != null) result.descriptorsize = descriptorsize;
    if (proto3SingularMsgs != null)
      result.proto3SingularMsgs = proto3SingularMsgs;
    if (submsgCallback != null) result.submsgCallback = submsgCallback;
    if (defaultHas != null) result.defaultHas = defaultHas;
    if (include != null) result.include.addAll(include);
    if (package != null) result.package = package;
    if (exclude != null) result.exclude.addAll(exclude);
    if (typeOverride != null) result.typeOverride = typeOverride;
    if (sortByTag != null) result.sortByTag = sortByTag;
    if (fallbackType != null) result.fallbackType = fallbackType;
    return result;
  }

  NanoPBOptions._();

  factory NanoPBOptions.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      NanoPBOptions()..mergeFromBuffer(data, registry);
  factory NanoPBOptions.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      NanoPBOptions()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'NanoPBOptions',
      createEmptyInstance: NanoPBOptions.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'maxSize')
    ..aI(2, _omitFieldNames ? '' : 'maxCount')
    ..aE<FieldType>(3, _omitFieldNames ? '' : 'type',
        defaultOrMaker: FieldType.FT_DEFAULT, enumValues: FieldType.values)
    ..a<$core.bool>(4, _omitFieldNames ? '' : 'longNames', $pb.PbFieldType.OB,
        defaultOrMaker: true)
    ..aOB(5, _omitFieldNames ? '' : 'packedStruct')
    ..aOB(6, _omitFieldNames ? '' : 'skipMessage')
    ..aE<IntSize>(7, _omitFieldNames ? '' : 'intSize',
        defaultOrMaker: IntSize.IS_DEFAULT, enumValues: IntSize.values)
    ..aOB(8, _omitFieldNames ? '' : 'noUnions')
    ..aI(9, _omitFieldNames ? '' : 'msgid', fieldType: $pb.PbFieldType.OU3)
    ..aOB(10, _omitFieldNames ? '' : 'packedEnum')
    ..aOB(11, _omitFieldNames ? '' : 'anonymousOneof')
    ..aOB(12, _omitFieldNames ? '' : 'proto3')
    ..aOB(13, _omitFieldNames ? '' : 'enumToString')
    ..aI(14, _omitFieldNames ? '' : 'maxLength')
    ..aOB(15, _omitFieldNames ? '' : 'fixedLength')
    ..aOB(16, _omitFieldNames ? '' : 'fixedCount')
    ..aE<TypenameMangling>(17, _omitFieldNames ? '' : 'mangleNames',
        defaultOrMaker: TypenameMangling.M_NONE,
        enumValues: TypenameMangling.values)
    ..a<$core.String>(
        18, _omitFieldNames ? '' : 'callbackDatatype', $pb.PbFieldType.OS,
        defaultOrMaker: 'pb_callback_t')
    ..a<$core.String>(
        19, _omitFieldNames ? '' : 'callbackFunction', $pb.PbFieldType.OS,
        defaultOrMaker: 'pb_default_field_callback')
    ..aE<DescriptorSize>(20, _omitFieldNames ? '' : 'descriptorsize',
        defaultOrMaker: DescriptorSize.DS_AUTO,
        enumValues: DescriptorSize.values)
    ..aOB(21, _omitFieldNames ? '' : 'proto3SingularMsgs')
    ..aOB(22, _omitFieldNames ? '' : 'submsgCallback')
    ..aOB(23, _omitFieldNames ? '' : 'defaultHas')
    ..pPS(24, _omitFieldNames ? '' : 'include')
    ..aOS(25, _omitFieldNames ? '' : 'package')
    ..pPS(26, _omitFieldNames ? '' : 'exclude')
    ..aE<$0.FieldDescriptorProto_Type>(
        27, _omitFieldNames ? '' : 'typeOverride',
        enumValues: $0.FieldDescriptorProto_Type.values)
    ..a<$core.bool>(28, _omitFieldNames ? '' : 'sortByTag', $pb.PbFieldType.OB,
        defaultOrMaker: true)
    ..aE<FieldType>(29, _omitFieldNames ? '' : 'fallbackType',
        defaultOrMaker: FieldType.FT_CALLBACK, enumValues: FieldType.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NanoPBOptions clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NanoPBOptions copyWith(void Function(NanoPBOptions) updates) =>
      super.copyWith((message) => updates(message as NanoPBOptions))
          as NanoPBOptions;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use NanoPBOptions() / NanoPBOptions.new instead')
  static NanoPBOptions create() => NanoPBOptions._();
  static $pb.GeneratedMessage $_createMessage() => NanoPBOptions._();
  @$core.override
  NanoPBOptions createEmptyInstance() => NanoPBOptions._();
  @$core.pragma('dart2js:noInline')
  static NanoPBOptions getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<NanoPBOptions>(
          NanoPBOptions.$_createMessage);
  static NanoPBOptions? _defaultInstance;

  /// Allocated size for 'bytes' and 'string' fields.
  /// For string fields, this should include the space for null terminator.
  @$pb.TagNumber(1)
  $core.int get maxSize => $_getIZ(0);
  @$pb.TagNumber(1)
  set maxSize($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMaxSize() => $_has(0);
  @$pb.TagNumber(1)
  void clearMaxSize() => $_clearField(1);

  /// Allocated number of entries in arrays ('repeated' fields)
  @$pb.TagNumber(2)
  $core.int get maxCount => $_getIZ(1);
  @$pb.TagNumber(2)
  set maxCount($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMaxCount() => $_has(1);
  @$pb.TagNumber(2)
  void clearMaxCount() => $_clearField(2);

  /// Force type of field (callback or static allocation)
  @$pb.TagNumber(3)
  FieldType get type => $_getN(2);
  @$pb.TagNumber(3)
  set type(FieldType value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasType() => $_has(2);
  @$pb.TagNumber(3)
  void clearType() => $_clearField(3);

  /// Use long names for enums, i.e. EnumName_EnumValue.
  @$pb.TagNumber(4)
  $core.bool get longNames => $_getB(3, true);
  @$pb.TagNumber(4)
  set longNames($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasLongNames() => $_has(3);
  @$pb.TagNumber(4)
  void clearLongNames() => $_clearField(4);

  /// Add 'packed' attribute to generated structs.
  /// Note: this cannot be used on CPUs that break on unaligned
  /// accesses to variables.
  @$pb.TagNumber(5)
  $core.bool get packedStruct => $_getBF(4);
  @$pb.TagNumber(5)
  set packedStruct($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasPackedStruct() => $_has(4);
  @$pb.TagNumber(5)
  void clearPackedStruct() => $_clearField(5);

  /// Skip this message
  @$pb.TagNumber(6)
  $core.bool get skipMessage => $_getBF(5);
  @$pb.TagNumber(6)
  set skipMessage($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasSkipMessage() => $_has(5);
  @$pb.TagNumber(6)
  void clearSkipMessage() => $_clearField(6);

  /// Size of integer fields. Can save some memory if you don't need
  /// full 32 bits for the value.
  @$pb.TagNumber(7)
  IntSize get intSize => $_getN(6);
  @$pb.TagNumber(7)
  set intSize(IntSize value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasIntSize() => $_has(6);
  @$pb.TagNumber(7)
  void clearIntSize() => $_clearField(7);

  /// Generate oneof fields as normal optional fields instead of union.
  @$pb.TagNumber(8)
  $core.bool get noUnions => $_getBF(7);
  @$pb.TagNumber(8)
  set noUnions($core.bool value) => $_setBool(7, value);
  @$pb.TagNumber(8)
  $core.bool hasNoUnions() => $_has(7);
  @$pb.TagNumber(8)
  void clearNoUnions() => $_clearField(8);

  /// integer type tag for a message
  @$pb.TagNumber(9)
  $core.int get msgid => $_getIZ(8);
  @$pb.TagNumber(9)
  set msgid($core.int value) => $_setUnsignedInt32(8, value);
  @$pb.TagNumber(9)
  $core.bool hasMsgid() => $_has(8);
  @$pb.TagNumber(9)
  void clearMsgid() => $_clearField(9);

  /// Add 'packed' attribute to generated enums.
  @$pb.TagNumber(10)
  $core.bool get packedEnum => $_getBF(9);
  @$pb.TagNumber(10)
  set packedEnum($core.bool value) => $_setBool(9, value);
  @$pb.TagNumber(10)
  $core.bool hasPackedEnum() => $_has(9);
  @$pb.TagNumber(10)
  void clearPackedEnum() => $_clearField(10);

  /// decode oneof as anonymous union
  @$pb.TagNumber(11)
  $core.bool get anonymousOneof => $_getBF(10);
  @$pb.TagNumber(11)
  set anonymousOneof($core.bool value) => $_setBool(10, value);
  @$pb.TagNumber(11)
  $core.bool hasAnonymousOneof() => $_has(10);
  @$pb.TagNumber(11)
  void clearAnonymousOneof() => $_clearField(11);

  /// Proto3 singular field does not generate a "has_" flag
  @$pb.TagNumber(12)
  $core.bool get proto3 => $_getBF(11);
  @$pb.TagNumber(12)
  set proto3($core.bool value) => $_setBool(11, value);
  @$pb.TagNumber(12)
  $core.bool hasProto3() => $_has(11);
  @$pb.TagNumber(12)
  void clearProto3() => $_clearField(12);

  /// Generate an enum->string mapping function (can take up lots of space).
  @$pb.TagNumber(13)
  $core.bool get enumToString => $_getBF(12);
  @$pb.TagNumber(13)
  set enumToString($core.bool value) => $_setBool(12, value);
  @$pb.TagNumber(13)
  $core.bool hasEnumToString() => $_has(12);
  @$pb.TagNumber(13)
  void clearEnumToString() => $_clearField(13);

  /// Maximum length for 'string' fields. Setting this is equivalent
  /// to setting max_size to a value of length+1.
  @$pb.TagNumber(14)
  $core.int get maxLength => $_getIZ(13);
  @$pb.TagNumber(14)
  set maxLength($core.int value) => $_setSignedInt32(13, value);
  @$pb.TagNumber(14)
  $core.bool hasMaxLength() => $_has(13);
  @$pb.TagNumber(14)
  void clearMaxLength() => $_clearField(14);

  /// Generate bytes arrays with fixed length
  @$pb.TagNumber(15)
  $core.bool get fixedLength => $_getBF(14);
  @$pb.TagNumber(15)
  set fixedLength($core.bool value) => $_setBool(14, value);
  @$pb.TagNumber(15)
  $core.bool hasFixedLength() => $_has(14);
  @$pb.TagNumber(15)
  void clearFixedLength() => $_clearField(15);

  /// Generate repeated field with fixed count
  @$pb.TagNumber(16)
  $core.bool get fixedCount => $_getBF(15);
  @$pb.TagNumber(16)
  set fixedCount($core.bool value) => $_setBool(15, value);
  @$pb.TagNumber(16)
  $core.bool hasFixedCount() => $_has(15);
  @$pb.TagNumber(16)
  void clearFixedCount() => $_clearField(16);

  /// Shorten or remove package names from type names.
  /// This option applies only on the file level.
  @$pb.TagNumber(17)
  TypenameMangling get mangleNames => $_getN(16);
  @$pb.TagNumber(17)
  set mangleNames(TypenameMangling value) => $_setField(17, value);
  @$pb.TagNumber(17)
  $core.bool hasMangleNames() => $_has(16);
  @$pb.TagNumber(17)
  void clearMangleNames() => $_clearField(17);

  /// Data type for storage associated with callback fields.
  @$pb.TagNumber(18)
  $core.String get callbackDatatype => $_getS(17, 'pb_callback_t');
  @$pb.TagNumber(18)
  set callbackDatatype($core.String value) => $_setString(17, value);
  @$pb.TagNumber(18)
  $core.bool hasCallbackDatatype() => $_has(17);
  @$pb.TagNumber(18)
  void clearCallbackDatatype() => $_clearField(18);

  /// Callback function used for encoding and decoding.
  /// Prior to nanopb-0.4.0, the callback was specified in per-field pb_callback_t
  /// structure. This is still supported, but does not work inside e.g. oneof or pointer
  /// fields. Instead, a new method allows specifying a per-message callback that
  /// will be called for all callback fields in a message type.
  @$pb.TagNumber(19)
  $core.String get callbackFunction => $_getS(18, 'pb_default_field_callback');
  @$pb.TagNumber(19)
  set callbackFunction($core.String value) => $_setString(18, value);
  @$pb.TagNumber(19)
  $core.bool hasCallbackFunction() => $_has(18);
  @$pb.TagNumber(19)
  void clearCallbackFunction() => $_clearField(19);

  /// Select the size of field descriptors. This option has to be defined
  /// for the whole message, not per-field. Usually automatic selection is
  /// ok, but if it results in compilation errors you can increase the field
  /// size here.
  @$pb.TagNumber(20)
  DescriptorSize get descriptorsize => $_getN(19);
  @$pb.TagNumber(20)
  set descriptorsize(DescriptorSize value) => $_setField(20, value);
  @$pb.TagNumber(20)
  $core.bool hasDescriptorsize() => $_has(19);
  @$pb.TagNumber(20)
  void clearDescriptorsize() => $_clearField(20);

  /// Force proto3 messages to have no "has_" flag.
  /// This was default behavior until nanopb-0.4.0.
  @$pb.TagNumber(21)
  $core.bool get proto3SingularMsgs => $_getBF(20);
  @$pb.TagNumber(21)
  set proto3SingularMsgs($core.bool value) => $_setBool(20, value);
  @$pb.TagNumber(21)
  $core.bool hasProto3SingularMsgs() => $_has(20);
  @$pb.TagNumber(21)
  void clearProto3SingularMsgs() => $_clearField(21);

  /// Generate message-level callback that is called before decoding submessages.
  /// This can be used to set callback fields for submsgs inside oneofs.
  @$pb.TagNumber(22)
  $core.bool get submsgCallback => $_getBF(21);
  @$pb.TagNumber(22)
  set submsgCallback($core.bool value) => $_setBool(21, value);
  @$pb.TagNumber(22)
  $core.bool hasSubmsgCallback() => $_has(21);
  @$pb.TagNumber(22)
  void clearSubmsgCallback() => $_clearField(22);

  /// Set default value for has_ fields.
  @$pb.TagNumber(23)
  $core.bool get defaultHas => $_getBF(22);
  @$pb.TagNumber(23)
  set defaultHas($core.bool value) => $_setBool(22, value);
  @$pb.TagNumber(23)
  $core.bool hasDefaultHas() => $_has(22);
  @$pb.TagNumber(23)
  void clearDefaultHas() => $_clearField(23);

  /// Extra files to include in generated `.pb.h`
  @$pb.TagNumber(24)
  $pb.PbList<$core.String> get include => $_getList(23);

  /// Package name that applies only for nanopb.
  @$pb.TagNumber(25)
  $core.String get package => $_getSZ(24);
  @$pb.TagNumber(25)
  set package($core.String value) => $_setString(24, value);
  @$pb.TagNumber(25)
  $core.bool hasPackage() => $_has(24);
  @$pb.TagNumber(25)
  void clearPackage() => $_clearField(25);

  /// Automatic includes to exclude from generated `.pb.h`
  /// Same as nanopb_generator.py command line flag -x.
  @$pb.TagNumber(26)
  $pb.PbList<$core.String> get exclude => $_getList(25);

  /// Override type of the field in generated C code. Only to be used with related field types
  @$pb.TagNumber(27)
  $0.FieldDescriptorProto_Type get typeOverride => $_getN(26);
  @$pb.TagNumber(27)
  set typeOverride($0.FieldDescriptorProto_Type value) => $_setField(27, value);
  @$pb.TagNumber(27)
  $core.bool hasTypeOverride() => $_has(26);
  @$pb.TagNumber(27)
  void clearTypeOverride() => $_clearField(27);

  /// Due to historical reasons, nanopb orders fields in structs by their tag number
  /// instead of the order in .proto. Set this to false to keep the .proto order.
  /// The default value will probably change to false in nanopb-0.5.0.
  @$pb.TagNumber(28)
  $core.bool get sortByTag => $_getB(27, true);
  @$pb.TagNumber(28)
  set sortByTag($core.bool value) => $_setBool(27, value);
  @$pb.TagNumber(28)
  $core.bool hasSortByTag() => $_has(27);
  @$pb.TagNumber(28)
  void clearSortByTag() => $_clearField(28);

  /// Set the FT_DEFAULT field conversion strategy.
  /// A field that can become a static member of a c struct (e.g. int, bool, etc)
  /// will be a a static field.
  /// Fields with dynamic length are converted to either a pointer or a callback.
  @$pb.TagNumber(29)
  FieldType get fallbackType => $_getN(28);
  @$pb.TagNumber(29)
  set fallbackType(FieldType value) => $_setField(29, value);
  @$pb.TagNumber(29)
  $core.bool hasFallbackType() => $_has(28);
  @$pb.TagNumber(29)
  void clearFallbackType() => $_clearField(29);
}

class Nanopb {
  static final nanopbFileopt = $pb.Extension<NanoPBOptions>(
      _omitMessageNames ? '' : 'google.protobuf.FileOptions',
      _omitFieldNames ? '' : 'nanopbFileopt',
      1010,
      $pb.PbFieldType.OM,
      defaultOrMaker: NanoPBOptions.getDefault,
      subBuilder: NanoPBOptions.$_createMessage);
  static final nanopbMsgopt = $pb.Extension<NanoPBOptions>(
      _omitMessageNames ? '' : 'google.protobuf.MessageOptions',
      _omitFieldNames ? '' : 'nanopbMsgopt',
      1010,
      $pb.PbFieldType.OM,
      defaultOrMaker: NanoPBOptions.getDefault,
      subBuilder: NanoPBOptions.$_createMessage);
  static final nanopbEnumopt = $pb.Extension<NanoPBOptions>(
      _omitMessageNames ? '' : 'google.protobuf.EnumOptions',
      _omitFieldNames ? '' : 'nanopbEnumopt',
      1010,
      $pb.PbFieldType.OM,
      defaultOrMaker: NanoPBOptions.getDefault,
      subBuilder: NanoPBOptions.$_createMessage);
  static final nanopb = $pb.Extension<NanoPBOptions>(
      _omitMessageNames ? '' : 'google.protobuf.FieldOptions',
      _omitFieldNames ? '' : 'nanopb',
      1010,
      $pb.PbFieldType.OM,
      defaultOrMaker: NanoPBOptions.getDefault,
      subBuilder: NanoPBOptions.$_createMessage);
  static void registerAllExtensions($pb.ExtensionRegistry registry) {
    registry.add(nanopbFileopt);
    registry.add(nanopbMsgopt);
    registry.add(nanopbEnumopt);
    registry.add(nanopb);
  }
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
