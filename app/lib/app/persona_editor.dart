// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../rag/token_budget.dart';
import 'ios_widgets.dart';
import 'persona.dart';
import 'theme.dart';

/// 人设编辑器（全屏页）：六个短字段 + 实时 system 预览 + 预算表。
/// 返回 null = 取消；否则返回改好的卡。
Future<PersonaCard?> showPersonaEditor(
  BuildContext context, {
  required PersonaCard initial,
}) {
  return Navigator.of(context, rootNavigator: true).push<PersonaCard>(
    CupertinoPageRoute<PersonaCard>(
      fullscreenDialog: true,
      builder: (_) => PersonaEditorPage(initial: initial),
    ),
  );
}

/// 人设软上限：超过它就开始挤记忆，界面标红。
const int personaSoftBudgetTokens = 240;

/// 每项的输入上限（字）：字数就是 token，卡在能写清楚的程度。
class _Field {
  const _Field(this.label, this.hint, this.maxChars, this.maxLines);

  final String label;
  final String hint;
  final int maxChars;
  final int maxLines;
}

const _fields = <_Field>[
  _Field('名字', '如：小暖', 10, 1),
  _Field('性格', '如：温和、爱笑，先接住情绪，不急着给建议', 60, 3),
  _Field('说话方式', '如：口语，短句，一两句就停，不列点', 80, 3),
  _Field('常用的话', '如：嗯，我在；那你慢慢说 —— 口癖比形容词更像人', 40, 2),
  _Field('称呼', '如：你 / Danny；留空则不指定', 10, 1),
  _Field('不做的事', '如：不给医疗建议（可留空）', 60, 2),
];

class PersonaEditorPage extends StatefulWidget {
  const PersonaEditorPage({super.key, required this.initial});

  final PersonaCard initial;

  @override
  State<PersonaEditorPage> createState() => _PersonaEditorPageState();
}

class _PersonaEditorPageState extends State<PersonaEditorPage> {
  late final PersonaCard _base = widget.initial;
  late final List<TextEditingController> _ctrls = [
    TextEditingController(text: _base.name),
    TextEditingController(text: _base.personality),
    TextEditingController(text: _base.style),
    TextEditingController(text: _base.catchphrase),
    TextEditingController(text: _base.addressTerm),
    TextEditingController(text: _base.boundary),
  ];

  @override
  void initState() {
    super.initState();
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
    catchphrase: _v(3),
    addressTerm: _v(4),
    boundary: _v(5),
  );

  void _save() {
    if (_draft.name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('先给它起个名字')));
      return;
    }
    Navigator.of(context).pop(_draft);
  }

  void _useBuiltin(PersonaCard card) {
    _ctrls[0].text = card.name;
    _ctrls[1].text = card.personality;
    _ctrls[2].text = card.style;
    _ctrls[3].text = card.catchphrase;
    _ctrls[4].text = card.addressTerm;
    _ctrls[5].text = card.boundary;
  }

  @override
  Widget build(BuildContext context) {
    final cup = CupertinoTheme.of(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final used = estimateTokens(_draft.render());
    return Scaffold(
      backgroundColor: cup.scaffoldBackgroundColor,
      appBar: CupertinoNavigationBar(
        middle: const Text('编辑人设'),
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
            footer: '写得越短，手机端首字出得越快。形容词两三个就够，口癖比形容词更像人。',
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
          _budgetSection(used, secondary),
          const SizedBox(height: 16),
          IosSection(
            header: '写入 system 的原文',
            footer: '下一轮对话生效，不用重载模型。',
            child: Text(
              _draft.render().isEmpty ? '（空）' : _draft.render(),
              style: TextStyle(fontSize: kFontBody, color: secondary),
            ),
          ),
          const SizedBox(height: 16),
          IosSection(
            header: '内置样板',
            footer: '三个人设的写法差别在口癖：换一张，语气就不一样。',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final b in builtinPersonas)
                  CupertinoButton(
                    key: ValueKey('persona-preset-${b.id}'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    color: CupertinoColors.tertiarySystemFill.resolveFrom(
                      context,
                    ),
                    onPressed: () => _useBuiltin(b),
                    child: Text(
                      b.name,
                      style: TextStyle(fontSize: kFontCaption),
                    ),
                  ),
              ],
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
        Row(
          children: [
            Text(
              f.label,
              style: TextStyle(fontSize: kFontCaption, color: secondary),
            ),
            const Spacer(),
            Text(
              '${_ctrls[i].text.trim().length}/${f.maxChars}',
              style: TextStyle(fontSize: kFontCaption, color: secondary),
            ),
          ],
        ),
        const SizedBox(height: 4),
        CupertinoTextField(
          key: ValueKey('persona-field-$i'),
          controller: _ctrls[i],
          placeholder: f.hint,
          maxLines: f.maxLines,
          minLines: 1,
          inputFormatters: [LengthLimitingTextInputFormatter(f.maxChars)],
          style: TextStyle(fontSize: kFontBody),
          clearButtonMode: OverlayVisibilityMode.editing,
        ),
      ],
    );
  }

  /// 预算表：system 共 800，人设超过软上限就开始挤记忆。
  Widget _budgetSection(int used, Color secondary) {
    final ratio = (used / personaSoftBudgetTokens).clamp(0.0, 1.0).toDouble();
    final over = used > personaSoftBudgetTokens;
    final barColor = over
        ? CupertinoColors.systemRed.resolveFrom(context)
        : CupertinoTheme.of(context).primaryColor;
    final left = personaSoftBudgetTokens - used;
    return IosSection(
      header: 'system 预算',
      footer: over
          ? '超过软上限了：system 一共 800 token，人设占得多，长期记忆就挤不进去。'
          : 'system 一共 800 token，人设建议 ≤$personaSoftBudgetTokens，剩下留给长期记忆。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('人设 ≈ $used token', style: TextStyle(fontSize: kFontBody)),
              const Spacer(),
              Text(
                left >= 0 ? '建议余量 $left' : '超出 ${-left}',
                style: TextStyle(
                  fontSize: kFontCaption,
                  color: over ? barColor : secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Container(
              height: 6,
              color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: ratio,
                child: Container(color: barColor),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '按「1 字 ≈ 1 token」保守估算，实际多半更省。',
            style: TextStyle(fontSize: kFontCaption, color: secondary),
          ),
        ],
      ),
    );
  }
}
