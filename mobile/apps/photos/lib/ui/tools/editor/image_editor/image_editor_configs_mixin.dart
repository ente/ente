import 'package:flutter/material.dart';
import 'package:pro_image_editor/core/mixins/converted_configs.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

mixin SimpleConfigsAccess on StatefulWidget {
  ProImageEditorConfigs get configs;
  ProImageEditorCallbacks get callbacks;
}

mixin SimpleConfigsAccessState<T extends StatefulWidget>
    on State<T>, ImageEditorConvertedConfigs {
  SimpleConfigsAccess get _widget => (widget as SimpleConfigsAccess);

  @override
  ProImageEditorConfigs get configs => _widget.configs;

  ProImageEditorCallbacks get callbacks => _widget.callbacks;
}
