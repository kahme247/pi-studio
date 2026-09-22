// Session chrome: rows, pills, title bar, menus, context ring.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform/window_controls.dart';
import '../state/session_controller.dart';
import 'app_theme.dart';
import 'primitives.dart';

/// Sidebar card indicator state.
enum CardStatus { idle, running, unread, saved }

/// Small footer chip under the composer: icon + label, interactive when given
/// an [onTap].
class FooterChip extends StatelessWidget {
  const FooterChip({
    super.key,
    required this.icon,
    required this.label,
    this.tooltip,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chip = HoverTint(
      radius: 6,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: theme.hintColor),
            const SizedBox(width: 5),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.hintColor,
              ),
            ),
          ],
        ),
      ),
    );
    final message = tooltip;
    return message == null ? chip : Tooltip(message: message, child: chip);
  }
}

/// One flat session row: title, then project + age, with hover/selection
/// states and a menu that only appears when the row is hovered or selected.
class SessionRow extends StatefulWidget {
  const SessionRow({
    super.key,
    required this.title,
    required this.folder,
    required this.time,
    required this.status,
    required this.selected,
    required this.onTap,
    required this.menu,
  });

  final String title;
  final String folder;
  final DateTime? time;
  final CardStatus status;
  final bool selected;
  final VoidCallback onTap;
  final Widget menu;

  @override
  State<SessionRow> createState() => _SessionRowState();
}

class _SessionRowState extends State<SessionRow> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = widget.selected
        ? theme.colorScheme.primary.withValues(alpha: 0.12)
        : (_hovered
              ? theme.colorScheme.onSurface.withValues(alpha: 0.05)
              : null);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 1),
        child: AnimatedContainer(
          duration: motion(context),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: background ?? Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 7, 6, 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 14,
                        child: widget.status == CardStatus.running
                            ? const SizedBox(
                                width: 11,
                                height: 11,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: liveGreen,
                                ),
                              )
                            : widget.status == CardStatus.unread
                            ? Icon(
                                Icons.circle,
                                size: 7,
                                color: theme.colorScheme.primary,
                              )
                            : null,
                      ),
                      Expanded(
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: widget.selected
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.onSurface.withValues(
                                    alpha: 0.92,
                                  ),
                          ),
                        ),
                      ),
                      if (_hovered || widget.selected)
                        widget.menu
                      else
                        const SizedBox(width: 4),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          widget.folder,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.hintColor,
                          ),
                        ),
                      ),
                      if (widget.time != null)
                        Text(
                          _relativeTime(widget.time!),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.hintColor,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AccessPill extends StatefulWidget {
  const AccessPill({super.key, required this.session});

  final SessionController session;

  @override
  State<AccessPill> createState() => _AccessPillState();
}

class _AccessPillState extends State<AccessPill> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final full = widget.session.fullAccess;
    return Tooltip(
      message: full
          ? 'Full access: auto-executes tools'
          : 'Ask first: confirms tool calls',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.session.toggleAccess,
          child: AnimatedContainer(
            duration: motion(context, 120),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            // The pill paints its own background, so an Ink splash on the
            // Material behind it would be hidden — animate the fill instead.
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: _hovered ? 0.75 : 0.4,
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _hovered
                    ? theme.colorScheme.outline.withValues(alpha: 0.45)
                    : theme.dividerColor,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  full ? Icons.lock_open_outlined : Icons.pan_tool_outlined,
                  size: 13,
                  color: full ? theme.colorScheme.secondary : theme.hintColor,
                ),
                const SizedBox(width: 5),
                // Both labels stacked: the pill is always as wide as the
                // wider one, so toggling never moves the row's right side.
                Stack(
                  children: [
                    Opacity(
                      opacity: full ? 1 : 0,
                      child: Text(
                        'Full access',
                        maxLines: 1,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Opacity(
                      opacity: full ? 0 : 1,
                      child: Text(
                        'Ask first',
                        maxLines: 1,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.hintColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Context-window ring; click opens the session stats menu anchored to it.
class ContextRing extends StatefulWidget {
  const ContextRing({super.key, required this.session});

  final SessionController session;

  @override
  State<ContextRing> createState() => _ContextRingState();
}

class _ContextRingState extends State<ContextRing> {
  final _controller = MenuController();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = widget.session;
    final usage = session.stats?['contextUsage'];
    final percent = usage is Map && usage['percent'] is num
        ? (usage['percent'] as num).toDouble()
        : null;
    final color = percent != null && percent >= 85
        ? theme.colorScheme.error
        : theme.colorScheme.primary;

    return MenuAnchor(
      controller: _controller,
      menuChildren: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: SizedBox(
            width: 300,
            child: ListenableBuilder(
              listenable: session,
              builder: (context, _) => _StatsTable(session: session),
            ),
          ),
        ),
        const Divider(height: 1),
      ],
      builder: (context, controller, child) => Tooltip(
        message: percent == null
            ? 'Context usage'
            : 'Context ${percent.toStringAsFixed(0)}%',
        child: HoverTint(
          radius: 20,
          alpha: 0.08,
          onTap: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              // Always fetch fresh numbers when opening.
              session.refreshStats();
              controller.open();
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                value: percent == null ? 0 : (percent / 100).clamp(0.0, 1.0),
                strokeWidth: 3,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatsTable extends StatelessWidget {
  const _StatsTable({required this.session});

  final SessionController session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = session.stats;
    if (stats == null) {
      return Text(
        'No stats yet — send a message first.',
        style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
      );
    }
    final rows = <Widget>[];
    void add(String label, String value) {
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 108,
                child: Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.hintColor,
                  ),
                ),
              ),
              Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
            ],
          ),
        ),
      );
    }

    final usage = stats['contextUsage'];
    if (usage is Map) {
      final percent = usage['percent'];
      add(
        'Context',
        '${formatCount(usage['tokens'])} / ${formatCount(usage['contextWindow'])} tokens'
            '${percent is num ? '  (${percent.toStringAsFixed(0)}%)' : ''}',
      );
    }
    add(
      'Messages',
      '${formatCount(stats['totalMessages'])} '
          '(${formatCount(stats['userMessages'])} user · '
          '${formatCount(stats['assistantMessages'])} assistant)',
    );
    add(
      'Tool calls',
      '${formatCount(stats['toolCalls'])} '
          '(${formatCount(stats['toolResults'])} results)',
    );
    final tokens = stats['tokens'];
    if (tokens is Map) {
      add('Tokens in', formatCount(tokens['input']));
      add('Tokens out', formatCount(tokens['output']));
      add('Cache read', formatCount(tokens['cacheRead']));
      add('Cache write', formatCount(tokens['cacheWrite']));
      add('Total tokens', formatCount(tokens['total']));
    }
    final cost = stats['cost'];
    if (cost is num) add('Cost', '\$${cost.toStringAsFixed(4)}');
    final sessionFile = stats['sessionFile'];
    if (sessionFile is String && sessionFile.isNotEmpty) {
      rows.add(_SessionFileRow(path: sessionFile, theme: theme));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows,
    );
  }
}

/// Frameless-window title bar: drag anywhere, double-click to maximize,
/// Windows-style minimize/maximize/close on the right.
class TitleBar extends StatelessWidget {
  const TitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => beginWindowDrag(),
              onDoubleTap: toggleMaximizeWindow,
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Icon(
                    Icons.terminal,
                    size: 14,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text('Pi Studio', style: theme.textTheme.labelMedium),
                ],
              ),
            ),
          ),
          const _WindowButton(icon: Icons.remove, onTap: minimizeWindow),
          const _WindowButton(
            icon: Icons.crop_square,
            size: 13,
            onTap: toggleMaximizeWindow,
          ),
          const _WindowButton(
            icon: Icons.close,
            onTap: closeWindow,
            close: true,
          ),
        ],
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.icon,
    required this.onTap,
    this.size = 15,
    this.close = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;

  /// Close buttons get the Windows-style red hover.
  final bool close;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = !_hovered
        ? Colors.transparent
        : widget.close
        // Windows' own close-button red. Left out of the palette on
        // purpose: it is a platform convention, not a design choice.
        ? const Color(0xFFC42B1C)
        : theme.colorScheme.onSurface.withValues(alpha: 0.08);
    final foreground = _hovered && widget.close
        ? Colors.white
        : theme.colorScheme.onSurfaceVariant;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          width: 46,
          height: 34,
          color: background,
          child: Icon(widget.icon, size: widget.size, color: foreground),
        ),
      ),
    );
  }
}

/// Compact session-file row: truncated name, full path on hover, click copies.
class _SessionFileRow extends StatelessWidget {
  const _SessionFileRow({required this.path, required this.theme});

  final String path;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final fileName = path.split(RegExp(r'[\\/]')).last;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(
              'Session',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.hintColor,
              ),
            ),
          ),
          Expanded(
            child: Tooltip(
              message: path,
              child: HoverTint(
                radius: 4,
                onTap: () {
                  Clipboard.setData(ClipboardData(text: path));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Session file path copied'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                child: Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Circular send button, like the arrow in the reference composer.
class SendButton extends StatefulWidget {
  const SendButton({super.key, required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  State<SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<SendButton> {
  var _pressed = false;
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = widget.enabled;
    final lifted = enabled && _hovered;
    final duration = motion(context, 120);

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _pressed ? 0.94 : (lifted ? 1.05 : 1),
        duration: duration,
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: duration,
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: lifted
                ? [
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(alpha: 0.36),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ]
                : const [],
          ),
          child: Material(
            color: enabled
                ? theme.colorScheme.primary
                : theme.colorScheme.surfaceContainerHighest,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTapDown: enabled
                  ? (_) => setState(() => _pressed = true)
                  : null,
              onTapCancel: enabled
                  ? () => setState(() => _pressed = false)
                  : null,
              onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
              onTap: enabled ? widget.onTap : null,
              child: SizedBox(
                width: 36,
                height: 36,
                child: Icon(
                  Icons.arrow_upward,
                  size: 18,
                  color: enabled
                      ? theme.colorScheme.onPrimary
                      : theme.hintColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuLabel extends StatelessWidget {
  const _MenuLabel({required this.label, this.secondary});

  final String label;
  final String? secondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trailing = secondary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge,
            ),
          ),
          if (trailing != null)
            Text(
              ' · $trailing',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.hintColor,
              ),
            ),
          Icon(Icons.arrow_drop_down, size: 18, color: theme.hintColor),
        ],
      ),
    );
  }
}

/// One menu for model + reasoning effort: reasoning levels first, then
/// models grouped into a submenu per provider.
class AgentSettingsMenu extends StatefulWidget {
  const AgentSettingsMenu({super.key, required this.session});

  final SessionController session;

  @override
  State<AgentSettingsMenu> createState() => _AgentSettingsMenuState();
}

class _AgentSettingsMenuState extends State<AgentSettingsMenu> {
  final _search = TextEditingController();

  /// Model whose reasoning levels are expanded inline in the menu.
  String? _expandedModel;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = widget.session;
    final modelName =
        session.modelName ?? (session.isStarted ? 'model' : 'default model');
    final level = session.thinkingLevel;
    final label = level == null ? modelName : '$modelName · $level';

    final byProvider = <String, List<Map<String, dynamic>>>{};
    for (final model in session.models) {
      final provider = '${model['provider'] ?? 'other'}';
      byProvider.putIfAbsent(provider, () => []).add(model);
    }
    for (final models in byProvider.values) {
      models.sort(
        (a, b) =>
            '${a['name'] ?? a['id']}'.compareTo('${b['name'] ?? b['id']}'),
      );
    }
    final providers = byProvider.keys.toList()..sort();

    if (providers.isEmpty && session.thinkingLevels.isEmpty) {
      return _MenuLabel(label: label);
    }

    return MenuAnchor(
      onOpen: () {
        _search.clear();
        _expandedModel = null;
      },
      menuChildren: [
        SizedBox(
          width: 320,
          child: StatefulBuilder(
            builder: (context, setMenuState) {
              final query = _search.text.trim().toLowerCase();
              final matches = session.models
                  .where(
                    (model) =>
                        '${model['name'] ?? model['id']}'
                            .toLowerCase()
                            .contains(query) ||
                        '${model['provider'] ?? ''}'.toLowerCase().contains(
                          query,
                        ),
                  )
                  .toList();

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Search: borderless, separated by a hairline — no filled box.
                  Container(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: theme.dividerColor),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
                    child: TextField(
                      controller: _search,
                      onChanged: (_) => setMenuState(() {}),
                      style: theme.textTheme.bodySmall,
                      decoration: const InputDecoration(
                        hintText: 'Search models',
                        filled: false,
                        border: InputBorder.none,
                        isDense: true,
                        prefixIcon: Icon(Icons.search, size: 15),
                        prefixIconConstraints: BoxConstraints(
                          minWidth: 26,
                          minHeight: 26,
                        ),
                      ),
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: query.isEmpty
                            ? _grouped(
                                session,
                                level,
                                providers,
                                byProvider,
                                setMenuState,
                              )
                            : _searchResults(session, matches),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
      builder: (context, controller, child) => HoverTint(
        radius: 8,
        alpha: 0.08,
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        child: child ?? const SizedBox.shrink(),
      ),
      child: _MenuLabel(label: modelName, secondary: level),
    );
  }

  List<Widget> _searchResults(
    SessionController session,
    List<Map<String, dynamic>> matches,
  ) {
    final theme = Theme.of(context);
    if (matches.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 22),
          child: Column(
            children: [
              Icon(Icons.search_off, size: 18, color: theme.hintColor),
              const SizedBox(height: 8),
              Text(
                'No models match',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.hintColor,
                ),
              ),
            ],
          ),
        ),
      ];
    }
    return [
      for (final model in matches)
        _menuItem(
          selected: '${model['name']}' == session.modelName,
          onPressed: () =>
              session.setModel('${model['provider']}', '${model['id']}'),
          child: Row(
            children: [
              Expanded(child: Text('${model['name'] ?? model['id']}')),
              Text(
                '${model['provider'] ?? ''}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.hintColor,
                ),
              ),
            ],
          ),
        ),
    ];
  }

  /// Provider groups separated by hairlines. Selecting a model keeps the menu
  /// open and expands its reasoning levels inline, so model + effort is one
  /// continuous flow instead of two menu visits.
  List<Widget> _grouped(
    SessionController session,
    String? level,
    List<String> providers,
    Map<String, List<Map<String, dynamic>>> byProvider,
    void Function(VoidCallback) setMenuState,
  ) {
    final theme = Theme.of(context);
    final widgets = <Widget>[];
    for (var i = 0; i < providers.length; i++) {
      if (i > 0) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Divider(height: 1, color: theme.dividerColor),
          ),
        );
      }
      widgets.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 3),
          child: Text(
            providers[i],
            style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor),
          ),
        ),
      );
      for (final model in byProvider[providers[i]]!) {
        final name = '${model['name'] ?? model['id']}';
        final isCurrent = name == session.modelName;
        final hasLevels = session.thinkingLevels.isNotEmpty;
        final expanded = _expandedModel == name;

        widgets.add(
          MenuItemButton(
            // Keep the menu open so the reasoning picker can follow.
            closeOnActivate: false,
            onPressed: () {
              if (!isCurrent) {
                session.setModel('${model['provider']}', '${model['id']}');
              }
              setMenuState(() {
                _expandedModel = expanded ? null : name;
              });
            },
            leadingIcon: Icon(
              Icons.check,
              size: 15,
              color: isCurrent ? theme.colorScheme.primary : Colors.transparent,
            ),
            style: _menuItemStyle(context),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: isCurrent
                        ? TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          )
                        : null,
                  ),
                ),
                if (hasLevels)
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 15,
                    color: theme.hintColor,
                  ),
              ],
            ),
          ),
        );

        if (expanded && hasLevels) {
          widgets.add(
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 4, 10, 2),
                    child: Text(
                      'Reasoning',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.hintColor,
                      ),
                    ),
                  ),
                  for (final option in session.thinkingLevels)
                    _menuItem(
                      selected: option == level,
                      onPressed: () => session.setThinkingLevel(option),
                      child: Text(option),
                    ),
                ],
              ),
            ),
          );
        }
      }
    }
    return widgets;
  }

  ButtonStyle _menuItemStyle(BuildContext context) {
    final theme = Theme.of(context);
    return MenuItemButton.styleFrom(
      minimumSize: const Size(0, 32),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      textStyle: theme.textTheme.bodySmall,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    );
  }

  /// Compact menu row with a fixed check slot so labels stay aligned.
  Widget _menuItem({
    required bool selected,
    required VoidCallback onPressed,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return MenuItemButton(
      onPressed: onPressed,
      leadingIcon: Icon(
        Icons.check,
        size: 15,
        color: selected ? theme.colorScheme.primary : Colors.transparent,
      ),
      style: _menuItemStyle(context),
      child: child,
    );
  }
}

/// Compact relative age: now, 5m, 3h, 2d, 1w, 4mo, 1y.
/// The exact timestamp lives in the row's tooltip.
String _relativeTime(DateTime time) {
  final delta = DateTime.now().difference(time.toLocal());
  if (delta.inMinutes < 1) return 'now';
  if (delta.inHours < 1) return '${delta.inMinutes}m';
  if (delta.inDays < 1) return '${delta.inHours}h';
  if (delta.inDays < 7) return '${delta.inDays}d';
  if (delta.inDays < 30) return '${delta.inDays ~/ 7}w';
  if (delta.inDays < 365) return '${delta.inDays ~/ 30}mo';
  return '${delta.inDays ~/ 365}y';
}
