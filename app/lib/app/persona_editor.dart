// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../rag/token_budget.dart';
import 'app_state.dart';
import 'ios_widgets.dart';
import 'paper.dart';
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

  /// 长人设（傲娇鱼）走整段文本模式；短人设走六字段模式。
  late final bool _useRaw = _base.text.trim().isNotEmpty;
  late final _raw = TextEditingController(text: _base.text);

  @override
  void initState() {
    super.initState();
    for (final c in _ctrls) {
      c.addListener(_onChanged);
    }
    _raw.addListener(_onChanged);
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    _raw.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  String _v(int i) => _ctrls[i].text.trim();

  PersonaCard get _draft => _useRaw
      ? PersonaCard(id: _base.id, name: _v(0), text: _raw.text.trim())
      : PersonaCard(
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

  @override
  Widget build(BuildContext context) {
    final secondary = paperOf(context).muted;
    final used = estimateTokens(_draft.render());
    return PaperScaffold(
      title: '编辑人设',
      code: '03 / PERSONA',
      leading: GlassTextButton(
        label: '取消',
        onPressed: () => Navigator.of(context).pop(),
      ),
      actions: [
        GlassTextButton(label: '保存', onPressed: _save),
      ],
      body: Column(
        children: [
          IosSection(
            header: '人设卡',
            footer: _useRaw
                ? '长人设整段塞进 system，适合云端；本地 2B/4B 会被预算截断，建议切回短人设。'
                : '写得越短，手机端首字出得越快。形容词两三个就够，口癖比形容词更像人。',
            child: Column(
              children: [
                _field(0, secondary),
                if (_useRaw) ...[
                  const Divider(height: 20),
                  CupertinoTextField(
                    key: const ValueKey('persona-raw'),
                    controller: _raw,
                    minLines: 12,
                    maxLines: 24,
                    style: TextStyle(fontSize: kFontBody),
                    placeholder: '整段人设（可以参考「傲娇鱼」的写法）',
                  ),
                ],
                if (!_useRaw)
                  for (var i = 1; i < _fields.length; i++) ...[
                    const Divider(height: 20),
                    _field(i, secondary),
                  ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          _budgetSection(context, used, secondary),
          const SizedBox(height: 16),
          IosSection(
            header: '写入 system 的原文',
            footer: '下一轮对话生效，不用重载模型。',
            child: Text(
              _draft.render().isEmpty ? '（空）' : _draft.render(),
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
  Widget _budgetSection(BuildContext context, int used, Color secondary) {
    // 预算跟着后端走：本地 800，云端 6000（ADR-0013/0014）。
    final cloud =
        AppStateScope.maybeOf(context)?.settings.backend == 'cloud';
    final budget = cloud
        ? AppState.cloudSystemBudget
        : systemBudgetTokens;
    final soft = cloud ? (budget * 0.6).round() : personaSoftBudgetTokens;
    final ratio = (used / soft).clamp(0.0, 1.0).toDouble();
    final over = used > soft;
    final barColor = over
        ? CupertinoColors.systemRed.resolveFrom(context)
        : paperOf(context).ink;
    final left = soft - used;
    final where = cloud ? '云端' : '本地';
    return IosSection(
      header: 'system 预算（$where）',
      footer: over
          ? '超过软上限了：$where system 一共 $budget token，人设占得多，长期记忆就挤不进去。'
          : '$where system 一共 $budget token，人设建议 ≤$soft，剩下留给长期记忆。',
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
