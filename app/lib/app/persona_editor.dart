// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart';
import 'package:material_ui/material_ui.dart';

import 'ios_widgets.dart';
import 'persona.dart';
import 'theme.dart';

/// 人设编辑器（全屏页）：五个字段 + 实时 system 预览。
/// 返回 null = 取消；否则返回改好的卡（新建卡的 id 已在 [PersonaCard.blank] 生成）。
Future<PersonaCard?> showPersonaEditor(
  BuildContext context, {
  PersonaCard? initial,
}) {
  return Navigator.of(context, rootNavigator: true).push<PersonaCard>(
    CupertinoPageRoute<PersonaCard>(
      fullscreenDialog: true,
      builder: (_) => PersonaEditorPage(initial: initial),
    ),
  );
}

/// 五个可编辑字段。顺序 = 渲染进 system 的顺序（ADR-0007：越短越稳）。
class _Field {
  const _Field(this.label, this.hint, this.maxLines);

  final String label;
  final String hint;
  final int maxLines;
}

const _fields = <_Field>[
  _Field('名字', '如：小暖', 1),
  _Field('性格', '如：温柔耐心，善于倾听', 3),
  _Field('说话风格', '如：口语化，短句，偶尔用表情符号', 3),
  _Field('对用户的称呼', '如：你 / Danny；留空则不指定', 1),
  _Field('边界', '如：不给医疗建议；不确定时明说', 3),
];

class PersonaEditorPage extends StatefulWidget {
  const PersonaEditorPage({super.key, this.initial});

  /// null = 新建。
  final PersonaCard? initial;

  @override
  State<PersonaEditorPage> createState() => _PersonaEditorPageState();
}

class _PersonaEditorPageState extends State<PersonaEditorPage> {
  late final PersonaCard _base = widget.initial ?? PersonaCard.blank();
  late final List<TextEditingController> _ctrls = [
    TextEditingController(text: _base.name),
    TextEditingController(text: _base.personality),
    TextEditingController(text: _base.style),
    TextEditingController(text: _base.addressTerm),
    TextEditingController(text: _base.boundary),
  ];

  bool get _isNew => widget.initial == null;

  @override
  void initState() {
    super.initState();
    // 预览随输入实时刷新。
    for (final c in _ctrls) {
      c.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _onChanged() => setState(() {});

  String _v(int i) => _ctrls[i].text.trim();

  PersonaCard get _draft => PersonaCard(
    id: _base.id,
    name: _v(0),
    personality: _v(1),
    style: _v(2),
    addressTerm: _v(3),
    boundary: _v(4),
  );

  void _save() {
    if (_v(0).isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('先给它起个名字')));
      return;
    }
    Navigator.of(context).pop(_draft);
  }

  @override
  Widget build(BuildContext context) {
    final cup = CupertinoTheme.of(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final preview = _draft.render();
    return Scaffold(
      backgroundColor: cup.scaffoldBackgroundColor,
      appBar: CupertinoNavigationBar(
        middle: Text(_isNew ? '新建人设' : '编辑人设'),
        border: null,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          onPressed: _save,
          child: const Text('保存'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 16, bottom: 32),
        children: [
          IosSection(
            header: '人设卡',
            footer: '空字段不写进 system；每项百字以内——小模型指令遵循有限，越短越稳。',
            child: Column(
              children: [
                for (var i = 0; i < _fields.length; i++) ...[
                  if (i > 0) const Divider(height: 20),
                  _field(i, secondary),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          IosSection(
            header: '写入 system 的内容',
            footer: '下一轮对话生效，无需重载模型。',
            child: Text(
              preview.isEmpty ? '（空）' : preview,
              style: TextStyle(fontSize: kFontBody, color: secondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(int i, Color secondary) {
    final f = _fields[i];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          f.label,
          style: TextStyle(fontSize: kFontCaption, color: secondary),
        ),
        const SizedBox(height: 4),
        CupertinoTextField(
          key: ValueKey('persona-field-$i'),
          controller: _ctrls[i],
          placeholder: f.hint,
          maxLines: f.maxLines,
          minLines: 1,
          style: TextStyle(fontSize: kFontBody),
          clearButtonMode: OverlayVisibilityMode.editing,
        ),
      ],
    );
  }
}
