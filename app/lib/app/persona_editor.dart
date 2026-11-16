// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart';
import 'package:material_ui/material_ui.dart';

import '../rag/token_budget.dart';
import 'ios_widgets.dart';
import 'persona.dart';
import 'theme.dart';

/// 人设编辑器（全屏页）：名字 + 一大块自由正文 + system 预算表。
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

/// 结构模板：给「不知道怎么写」的人一个骨架，删掉不要的段落即可。
const String _template = '你是{{名字}}，一个……\n\n'
    '## 你是谁\n\n'
    '- 身份、性格两三条就够，别写成小说。\n\n'
    '## 怎么说话\n\n'
    '- 句子多长、语气、口头禅、要不要用表情。\n'
    '- 举个「用户说 X → 你答 Y」的短例子最省字。\n\n'
    '## 不做什么\n\n'
    '- 越界的事、编造、长篇说教。';

class PersonaEditorPage extends StatefulWidget {
  const PersonaEditorPage({super.key, required this.initial});

  final PersonaCard initial;

  @override
  State<PersonaEditorPage> createState() => _PersonaEditorPageState();
}

class _PersonaEditorPageState extends State<PersonaEditorPage> {
  late final PersonaCard _base = widget.initial;
  late final _name = TextEditingController(text: _base.name);
  late final _text = TextEditingController(text: _base.render());

  @override
  void initState() {
    super.initState();
    _name.addListener(_onChanged);
    _text.addListener(_onChanged);
  }

  @override
  void dispose() {
    _name.dispose();
    _text.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  PersonaCard get _draft => PersonaCard(
    id: _base.id,
    name: _name.text.trim(),
    text: _text.text.trim(),
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

  void _useTemplate() {
    _text.text = _template.replaceFirst('{{名字}}', _name.text.trim());
  }

  void _useBuiltin(PersonaCard card) {
    _name.text = card.name;
    _text.text = card.text;
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
            header: '名字',
            child: CupertinoTextField(
              key: const ValueKey('persona-name'),
              controller: _name,
              placeholder: '如：小暖',
              clearButtonMode: OverlayVisibilityMode.editing,
              style: TextStyle(fontSize: kFontBody),
            ),
          ),
          const SizedBox(height: 16),
          IosSection(
            header: '人设正文',
            footer: '整段写进 system（markdown 随便用）。写在 system 里的每个字，每轮对话都要重新付一次 token。',
            child: CupertinoTextField(
              key: const ValueKey('persona-text'),
              controller: _text,
              placeholder: '你是谁、怎么说话、不做什么……',
              minLines: 8,
              maxLines: 14,
              style: TextStyle(fontSize: kFontBody),
            ),
          ),
          const SizedBox(height: 16),
          _budgetSection(used, secondary),
          const SizedBox(height: 16),
          IosSection(
            header: '省事的起点',
            footer: '内置三段都是「够短」的样板；模板是骨架，改完记得删掉多余的话。',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                CupertinoButton(
                  key: const ValueKey('persona-template'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
                  onPressed: _useTemplate,
                  child: Text(
                    '结构模板',
                    style: TextStyle(fontSize: kFontCaption),
                  ),
                ),
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

  /// system 预算表：人设越长，长期记忆能被塞进去的越少。
  Widget _budgetSection(int used, Color secondary) {
    const budget = systemBudgetTokens;
    final ratio = (used / budget).clamp(0.0, 1.0).toDouble();
    final over = used > budget * 0.75;
    final barColor = over
        ? CupertinoColors.systemRed.resolveFrom(context)
        : CupertinoTheme.of(context).primaryColor;
    final left = budget - used;
    return IosSection(
      header: 'system 预算',
      footer: over
          ? '人设已经吃掉大半预算：记忆条目会被砍，回答也更容易「只记得人设、不记得你」。'
          : '人设与长期记忆共用这 800 token；想留更多记忆空间，就再删点话。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '人设 ≈ $used token',
                style: TextStyle(fontSize: kFontBody),
              ),
              const Spacer(),
              Text(
                left >= 0 ? '记忆剩 ≈ $left' : '超出 ${-left}',
                style: TextStyle(
                  fontSize: kFontCaption,
                  color: left >= 0 ? secondary : barColor,
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
