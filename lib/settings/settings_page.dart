import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../pi/session_store.dart';
import 'model_discovery.dart';
import 'pi_models.dart';
import 'pi_settings.dart';

/// Reduced-motion-aware duration, matching the rest of the app.
Duration _ms(BuildContext context, [int ms = 140]) =>
    MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : Duration(milliseconds: ms);

/// Sections of the settings page. Order here is the order in the nav rail.
enum SettingsSection {
  agent('Agent', Icons.smart_toy_outlined),
  providers('Providers', Icons.hub_outlined),
  tools('Tools', Icons.construction_outlined),
  compaction('Compaction', Icons.compress_outlined),
  sessions('Sessions', Icons.inventory_2_outlined),
  retry('Retry', Icons.replay_outlined),
  delivery('Delivery', Icons.swap_horiz_outlined),
  display('Interface', Icons.palette_outlined),
  resources('Resources', Icons.extension_outlined),
  network('Network', Icons.lan_outlined),
  about('About', Icons.info_outline);

  const SettingsSection(this.label, this.icon);

  final String label;
  final IconData icon;
}

const _thinkingLevels = [
  'off',
  'minimal',
  'low',
  'medium',
  'high',
  'xhigh',
  'max',
];

const _builtinTools = [
  'read',
  'bash',
  'powershell',
  'edit',
  'write',
  'grep',
  'find',
  'ls',
];

/// Full-page editor for pi's global `settings.json`.
///
/// Deliberately a page rather than a dialog: it is long, it is scrolled, and
/// edits need room to be reviewed before they are written to disk.
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    required this.settings,
    required this.models,
    required this.onClose,
    this.availableModels = const [],
    super.key,
  });

  final PiSettings settings;

  /// pi's custom-provider file, edited by the Providers section.
  final PiModels models;

  final VoidCallback onClose;

  /// Provider/model pairs harvested from a live session, when one is open.
  final List<({String provider, String id, String label})> availableModels;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  var _section = SettingsSection.agent;

  PiSettings get _s => widget.settings;
  PiModels get _m => widget.models;

  /// The page has one Save button, so it covers both files.
  bool get _dirty => _s.dirty || _m.dirty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_s.loading && _s.keys.isEmpty) _s.load();
      if (_m.loading && _m.keys.isEmpty) _m.load();
    });
  }

  Future<void> _save() async {
    await _s.save();
    await _m.save();
    if (!mounted) return;
    final error = _s.error ?? _m.error;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error ??
              'Saved. New pi sessions pick this up; running ones keep their '
                  'current settings.',
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _discard() async {
    await _s.discard();
    await _m.discard();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([_s, _m]),
      builder: (context, _) {
        return Column(
          children: [
            _header(theme),
            const Divider(height: 1),
            Expanded(
              // Only blank the page on the very first read. A refresh on
              // reopen keeps the current content up instead of flashing a
              // spinner over it.
              child: _s.loading && _m.loading && _s.keys.isEmpty && _m.keys.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _navRail(theme),
                        VerticalDivider(
                          width: 1,
                          color: theme.dividerColor,
                        ),
                        Expanded(child: _content(theme)),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  // ------------------------------------------------------------------ header

  Widget _header(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      color: theme.colorScheme.surfaceContainerLowest,
      child: Row(
        children: [
          TextButton.icon(
            onPressed: widget.onClose,
            icon: const Icon(Icons.arrow_back, size: 16),
            label: const Text('Back'),
          ),
          const SizedBox(width: 10),
          // The titles take the slack rather than a Spacer, so the Save/Discard
          // cluster keeps its natural width and can never be pushed off the
          // edge — which it was, by 65px, once "Unsaved changes" appeared in a
          // narrower window.
          Expanded(
            child: Row(
              children: [
                Text(
                  'Settings',
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    'pi configuration',
                    style: theme.textTheme.labelSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (_dirty) ...[
            Text('Unsaved changes', style: theme.textTheme.labelSmall),
            const SizedBox(width: 12),
            TextButton(
              onPressed: _discard,
              child: const Text('Discard'),
            ),
          ],
          const SizedBox(width: 4),
          FilledButton(
            onPressed: _dirty ? _save : null,
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- nav rail

  Widget _navRail(ThemeData theme) {
    return Container(
      width: 210,
      color: theme.colorScheme.surfaceContainerLowest,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: ListView(
        children: [
          for (final section in SettingsSection.values)
            _NavTile(
              section: section,
              selected: section == _section,
              onTap: () => setState(() => _section = section),
            ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- content

  Widget _content(ThemeData theme) {
    return AnimatedSwitcher(
      duration: _ms(context, 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.015, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(
        key: ValueKey(_section),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 40),
          children: _sectionBody(theme),
        ),
      ),
    );
  }

  List<Widget> _sectionBody(ThemeData theme) {
    switch (_section) {
      case SettingsSection.agent:
        return _agent(theme);
      case SettingsSection.providers:
        return _providers(theme);
      case SettingsSection.tools:
        return _tools(theme);
      case SettingsSection.compaction:
        return _compaction(theme);
      case SettingsSection.sessions:
        return _sessions(theme);
      case SettingsSection.retry:
        return _retry(theme);
      case SettingsSection.delivery:
        return _delivery(theme);
      case SettingsSection.display:
        return _display(theme);
      case SettingsSection.resources:
        return _resources(theme);
      case SettingsSection.network:
        return _network(theme);
      case SettingsSection.about:
        return _about(theme);
    }
  }

  // -------------------------------------------------------------------- agent

  List<Widget> _agent(ThemeData theme) {
    final models = widget.availableModels;
    return [
      _Card(
        title: 'Startup model',
        description:
            'What pi uses for a new session. A running session can still be '
            'switched from the composer.',
        children: [
          _Row(
            label: 'Default provider',
            hint: 'e.g. anthropic, openai, cliproxyapi',
            child: _Entry(
              value: _s.readString('defaultProvider') ?? '',
              hint: 'provider',
              onChanged: (v) => _s.write('defaultProvider', v.isEmpty ? null : v),
            ),
          ),
          _Row(
            label: 'Default model',
            hint: models.isEmpty
                ? 'Model ID, e.g. claude-sonnet-4-20250514'
                : 'From the models the open session reported',
            child: models.isEmpty
                ? _Entry(
                    value: _s.readString('defaultModel') ?? '',
                    hint: 'model id',
                    onChanged: (v) =>
                        _s.write('defaultModel', v.isEmpty ? null : v),
                  )
                : _Pick(
                    value: _s.readString('defaultModel'),
                    unsetLabel: '(pi default)',
                    options: models.map((m) => m.id).toList(),
                    labelFor: (id) => models
                        .firstWhere(
                          (m) => m.id == id,
                          orElse: () => (provider: '', id: id, label: id),
                        )
                        .label,
                    onChanged: (v) => _s.write('defaultModel', v),
                  ),
          ),
          _Row(
            label: 'Default thinking level',
            hint: 'How much the model reasons before answering',
            child: _Pick(
              value: _s.readString('defaultThinkingLevel'),
              unsetLabel: '(pi default)',
              options: _thinkingLevels,
              onChanged: (v) => _s.write('defaultThinkingLevel', v),
            ),
          ),
        ],
      ),
      _Card(
        title: 'Reasoning output',
        children: [
          _Row(
            label: 'Hide thinking blocks',
            hint: 'Collapse the model’s reasoning in the transcript',
            child: _Toggle(
              value: _s.readBool('hideThinkingBlock'),
              onChanged: (v) => _s.write('hideThinkingBlock', v),
            ),
          ),
          _Row(
            label: 'Show cache-miss notices',
            hint: 'Transcript notes for prompt-cache misses and compaction',
            child: _Toggle(
              value: _s.readBool('showCacheMissNotices'),
              onChanged: (v) => _s.write('showCacheMissNotices', v),
            ),
          ),
        ],
      ),
      _Card(
        title: 'Prompt cache warming',
        description:
            'Providers drop a cached prompt after a pause, so the first request '
            'afterwards pays full input price. Warming re-sends the last request '
            'with a one-token budget just before expiry.',
        children: [
          _Row(
            label: 'Cache warming',
            hint: 'Idle warming also refreshes while waiting for your next prompt',
            child: _Pick(
              value: _s.readString('cacheWarming'),
              unsetLabel: '(streaming — pi default)',
              options: const ['off', 'streaming', 'idle'],
              onChanged: (v) => _s.write('cacheWarming', v),
            ),
          ),
        ],
      ),
      _Card(
        title: 'Project trust',
        description:
            'Whether non-interactive runs may load a project’s own '
            '.pi/settings.json, extensions and packages.',
        children: [
          _Row(
            label: 'Default project trust',
            hint: 'ask / never ignore project resources; always trusts them',
            child: _Pick(
              value: _s.readString('defaultProjectTrust'),
              unsetLabel: '(ask — pi default)',
              options: const ['ask', 'always', 'never'],
              onChanged: (v) => _s.write('defaultProjectTrust', v),
            ),
          ),
        ],
      ),
    ];
  }

  // ---------------------------------------------------------------- providers

  List<Widget> _providers(ThemeData theme) {
    final ids = _m.providerIds;
    return [
      _Card(
        title: 'Custom providers',
        description:
            'Stored in models.json, which pi re-reads every time its model '
            'picker opens — edits take effect without restarting a session. '
            'Reusing a built-in id (anthropic, openai, openrouter…) reroutes '
            'that provider rather than adding a second one.',
        children: [
          _Row(
            label: 'Add a provider',
            hint: 'Lower-case id, e.g. local-llm or my-proxy',
            child: _AddProviderField(store: _m),
          ),
        ],
      ),
      if (ids.isEmpty)
        _Card(
          title: 'No custom providers yet',
          description:
              'models.json has an empty providers map. Anything added here '
              'shows up in pi’s model picker beside the providers pi and your '
              'extensions already register.',
          children: const [],
        ),
      for (final id in ids)
        _ProviderEditor(
          key: ValueKey('provider:$id'),
          store: _m,
          id: id,
          models: _m.modelsOf(id),
        ),
      _Card(
        title: 'How this file fits together',
        children: [
          _InfoRow(label: 'File', value: _m.path, copyable: true),
          _InfoRow(
            label: 'Reloads',
            value: 'Every time pi opens its model picker — no restart needed',
          ),
          _InfoRow(
            label: 'Extension providers',
            value:
                'Owned by their npm packages with their own schemas; this page '
                'leaves them untouched',
          ),
        ],
      ),
    ];
  }

  // -------------------------------------------------------------------- tools

  List<Widget> _tools(ThemeData theme) {
    final enabled = _s.readList('defaultTools');
    final isWindows = Platform.isWindows;
    return [
      _Card(
        title: 'Built-in tools',
        description:
            'Which built-in tools a session starts with. Extension and custom '
            'tools are unaffected. On Windows use powershell; bash needs a '
            'bash on PATH.',
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tool in _builtinTools)
                  _Chip(
                    label: tool,
                    selected: enabled.contains(tool),
                    // Nudges the platform-appropriate default without hiding
                    // the other option.
                    emphasise: isWindows && tool == 'powershell',
                    onTap: () {
                      final next = [...enabled];
                      if (!next.remove(tool)) next.add(tool);
                      _s.writeList('defaultTools', next);
                    },
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              enabled.isEmpty
                  ? 'Nothing selected — pi starts with its standard defaults.'
                  : '${enabled.length} selected.',
              style: theme.textTheme.labelSmall,
            ),
          ),
          if (enabled.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => _s.writeList('defaultTools', const []),
                child: const Text('Reset to pi defaults'),
              ),
            ),
        ],
      ),
    ];
  }

  // --------------------------------------------------------------- compaction

  List<Widget> _compaction(ThemeData theme) {
    return [
      _Card(
        title: 'Auto-compaction',
        description:
            'When a conversation approaches the context window, pi summarises '
            'the older part instead of failing.',
        children: [
          _Row(
            label: 'Enabled',
            child: _Toggle(
              value: _s.readBool('compaction.enabled', fallback: true),
              onChanged: (v) => _s.write('compaction.enabled', v),
            ),
          ),
          _Row(
            label: 'Reserve tokens',
            hint: 'Held back for the model’s own response',
            child: _Number(
              value: _s.readNumber('compaction.reserveTokens')?.round(),
              hint: '16384',
              onChanged: (v) => _s.write('compaction.reserveTokens', v),
            ),
          ),
          _Row(
            label: 'Keep recent tokens',
            hint: 'Most recent tokens left unsummarised',
            child: _Number(
              value: _s.readNumber('compaction.keepRecentTokens')?.round(),
              hint: '20000',
              onChanged: (v) => _s.write('compaction.keepRecentTokens', v),
            ),
          ),
        ],
      ),
      _Card(
        title: 'Branch summaries',
        children: [
          _Row(
            label: 'Reserve tokens',
            child: _Number(
              value: _s.readNumber('branchSummary.reserveTokens')?.round(),
              hint: '16384',
              onChanged: (v) => _s.write('branchSummary.reserveTokens', v),
            ),
          ),
          _Row(
            label: 'Skip the summarise prompt',
            hint: 'Navigating back through history summarises without asking',
            child: _Toggle(
              value: _s.readBool('branchSummary.skipPrompt'),
              onChanged: (v) => _s.write('branchSummary.skipPrompt', v),
            ),
          ),
        ],
      ),
    ];
  }

  // ----------------------------------------------------------------- sessions

  List<Widget> _sessions(ThemeData theme) {
    return [
      _Card(
        title: 'Session storage',
        description:
            'Where conversation transcripts are written. Pi Studio reads this '
            'folder to build the session list, so changing it moves where new '
            'sessions appear. Accepts ~ and forward slashes.',
        children: [
          _Row(
            label: 'Session directory',
            hint: 'Absolute or relative to the project',
            child: _Entry(
              value: _s.readString('sessionDir') ?? '',
              hint: '(pi default)',
              normalisePath: true,
              onChanged: (v) => _s.write('sessionDir', v.isEmpty ? null : v),
            ),
          ),
        ],
      ),
      _Card(
        title: 'Currently in use',
        children: [
          _InfoRow(
            label: 'Session folder',
            value: piSessionsDir().path,
            copyable: true,
          ),
        ],
      ),
    ];
  }

  // -------------------------------------------------------------------- retry

  List<Widget> _retry(ThemeData theme) {
    return [
      _Card(
        title: 'Agent retries',
        description:
            'Pi retries the turn itself on transient provider errors, with '
            'exponential backoff.',
        children: [
          _Row(
            label: 'Enabled',
            child: _Toggle(
              value: _s.readBool('retry.enabled', fallback: true),
              onChanged: (v) => _s.write('retry.enabled', v),
            ),
          ),
          _Row(
            label: 'Max attempts',
            child: _Number(
              value: _s.readNumber('retry.maxRetries')?.round(),
              hint: '3',
              onChanged: (v) => _s.write('retry.maxRetries', v),
            ),
          ),
          _Row(
            label: 'Base delay (ms)',
            hint: 'Backoff starts here: 2s, 4s, 8s …',
            child: _Number(
              value: _s.readNumber('retry.baseDelayMs')?.round(),
              hint: '2000',
              onChanged: (v) => _s.write('retry.baseDelayMs', v),
            ),
          ),
          _Row(
            label: 'Max delay (ms)',
            child: _Number(
              value: _s.readNumber('retry.maxAgentDelayMs')?.round(),
              hint: '60000',
              onChanged: (v) => _s.write('retry.maxAgentDelayMs', v),
            ),
          ),
        ],
      ),
      _Card(
        title: 'Provider-level retries',
        description:
            'Leave max retries at 0 unless you specifically need them: above 0 '
            'the SDK can swallow over-quota errors and stall the agent until '
            'the quota resets.',
        children: [
          _Row(
            label: 'Provider max retries',
            child: _Number(
              value: _s.readNumber('retry.provider.maxRetries')?.round(),
              hint: '0',
              onChanged: (v) => _s.write('retry.provider.maxRetries', v),
            ),
          ),
          _Row(
            label: 'Request timeout (ms)',
            hint: 'Blank uses the SDK default',
            child: _Number(
              value: _s.readNumber('retry.provider.timeoutMs')?.round(),
              hint: '',
              onChanged: (v) => _s.write('retry.provider.timeoutMs', v),
            ),
          ),
        ],
      ),
    ];
  }

  // ----------------------------------------------------------------- delivery

  List<Widget> _delivery(ThemeData theme) {
    return [
      _Card(
        title: 'Queued messages',
        description:
            'How messages sent while the agent is busy are handed over. '
            'Pi Studio steers into the running turn.',
        children: [
          _Row(
            label: 'Steering mode',
            child: _Pick(
              value: _s.readString('steeringMode'),
              unsetLabel: '(one-at-a-time)',
              options: const ['one-at-a-time', 'all'],
              onChanged: (v) => _s.write('steeringMode', v),
            ),
          ),
          _Row(
            label: 'Follow-up mode',
            child: _Pick(
              value: _s.readString('followUpMode'),
              unsetLabel: '(one-at-a-time)',
              options: const ['one-at-a-time', 'all'],
              onChanged: (v) => _s.write('followUpMode', v),
            ),
          ),
        ],
      ),
      _Card(
        title: 'Transport & timeouts',
        children: [
          _Row(
            label: 'Preferred transport',
            child: _Pick(
              value: _s.readString('transport'),
              unsetLabel: '(auto)',
              options: const ['auto', 'sse', 'websocket', 'websocket-cached'],
              onChanged: (v) => _s.write('transport', v),
            ),
          ),
          _Row(
            label: 'HTTP idle timeout (ms)',
            hint: '0 disables the timeout',
            child: _Number(
              value: _s.readNumber('httpIdleTimeoutMs')?.round(),
              hint: '300000',
              onChanged: (v) => _s.write('httpIdleTimeoutMs', v),
            ),
          ),
          _Row(
            label: 'WebSocket connect timeout (ms)',
            child: _Number(
              value: _s.readNumber('websocketConnectTimeoutMs')?.round(),
              hint: '15000',
              onChanged: (v) => _s.write('websocketConnectTimeoutMs', v),
            ),
          ),
        ],
      ),
    ];
  }

  // ------------------------------------------------------------------ display

  List<Widget> _display(ThemeData theme) {
    return [
      _Card(
        title: 'Appearance',
        children: [
          _Row(
            label: 'Theme',
            hint: 'Name of a pi theme, e.g. dark, light',
            child: _Entry(
              value: _s.readString('theme') ?? '',
              hint: 'dark',
              onChanged: (v) => _s.write('theme', v.isEmpty ? null : v),
            ),
          ),
          _Row(
            label: 'Quiet startup',
            hint: 'Hide the startup header in the CLI',
            child: _Toggle(
              value: _s.readBool('quietStartup'),
              onChanged: (v) => _s.write('quietStartup', v),
            ),
          ),
          _Row(
            label: 'Collapse changelog',
            hint: 'Condensed changelog after an update',
            child: _Toggle(
              value: _s.readBool('collapseChangelog'),
              onChanged: (v) => _s.write('collapseChangelog', v),
            ),
          ),
        ],
      ),
      _Card(
        title: 'Markdown',
        children: [
          _Row(
            label: 'Mermaid rendering',
            child: _Pick(
              value: _s.readString('markdown.mermaid'),
              unsetLabel: '(streaming)',
              options: const ['off', 'final', 'streaming'],
              onChanged: (v) => _s.write('markdown.mermaid', v),
            ),
          ),
          _Row(
            label: 'Code block indent',
            hint: 'Literal string, usually two spaces',
            child: _Entry(
              value: _s.readString('markdown.codeBlockIndent') ?? '',
              hint: '  ',
              onChanged: (v) => _s.write('markdown.codeBlockIndent', v),
            ),
          ),
        ],
      ),
      _Card(
        title: 'CLI editor',
        description:
            'These drive the interactive terminal TUI. Pi Studio has its own '
            'layout, but the values are shared so a terminal session behaves the '
            'way you expect.',
        children: [
          _Row(
            label: 'External editor',
            hint: 'Ctrl+G target, e.g. code --wait',
            child: _Entry(
              value: _s.readString('externalEditor') ?? '',
              hint: r'(from $VISUAL / $EDITOR)',
              onChanged: (v) => _s.write('externalEditor', v.isEmpty ? null : v),
            ),
          ),
          _Row(
            label: 'Double-escape action',
            child: _Pick(
              value: _s.readString('doubleEscapeAction'),
              unsetLabel: '(tree)',
              options: const ['tree', 'fork', 'none'],
              onChanged: (v) => _s.write('doubleEscapeAction', v),
            ),
          ),
          _Row(
            label: 'Tree filter',
            child: _Pick(
              value: _s.readString('treeFilterMode'),
              unsetLabel: '(default)',
              options: const [
                'default',
                'no-tools',
                'user-only',
                'labeled-only',
                'all',
              ],
              onChanged: (v) => _s.write('treeFilterMode', v),
            ),
          ),
          _Row(
            label: 'TUI mode',
            child: _Pick(
              value: _s.readString('tuiMode'),
              unsetLabel: '(regular)',
              options: const ['regular', 'fullscreen'],
              onChanged: (v) => _s.write('tuiMode', v),
            ),
          ),
        ],
      ),
    ];
  }

  // ---------------------------------------------------------------- resources

  List<Widget> _resources(ThemeData theme) {
    return [
      _Card(
        title: 'Packages',
        description:
            'npm or git packages pi loads resources from, e.g. '
            'npm:@scope/name or a repo URL.',
        children: [
          _List(
            values: _s.readList('packages'),
            hint: 'npm:package or git URL',
            onChanged: (v) => _s.writeList('packages', v),
          ),
        ],
      ),
      _Card(
        title: 'Local resources',
        description:
            'Paths resolve relative to ~/.pi/agent. Glob patterns and '
            '!exclusions are allowed.',
        children: [
          _List(
            values: _s.readList('extensions'),
            hint: 'extension file or directory',
            label: 'Extensions',
            onChanged: (v) => _s.writeList('extensions', v),
          ),
          _List(
            values: _s.readList('skills'),
            hint: 'skill file or directory',
            label: 'Skills',
            onChanged: (v) => _s.writeList('skills', v),
          ),
          _List(
            values: _s.readList('prompts'),
            hint: 'prompt template',
            label: 'Prompt templates',
            onChanged: (v) => _s.writeList('prompts', v),
          ),
          _List(
            values: _s.readList('themes'),
            hint: 'theme file or directory',
            label: 'Themes',
            onChanged: (v) => _s.writeList('themes', v),
          ),
          _Row(
            label: 'Register skills as /skill:name',
            child: _Toggle(
              value: _s.readBool('enableSkillCommands', fallback: true),
              onChanged: (v) => _s.write('enableSkillCommands', v),
            ),
          ),
        ],
      ),
    ];
  }

  // ------------------------------------------------------------------ network

  List<Widget> _network(ThemeData theme) {
    return [
      _Card(
        title: 'Proxy',
        description: 'Applied as HTTP_PROXY and HTTPS_PROXY for pi’s requests.',
        children: [
          _Row(
            label: 'HTTP proxy',
            hint: 'e.g. http://127.0.0.1:7890',
            child: _Entry(
              value: _s.readString('httpProxy') ?? '',
              hint: '(none)',
              onChanged: (v) => _s.write('httpProxy', v.isEmpty ? null : v),
            ),
          ),
        ],
      ),
      _Card(
        title: 'Telemetry',
        children: [
          _Row(
            label: 'Install telemetry',
            hint: 'Anonymous install ping and provider attribution headers',
            child: _Toggle(
              value: _s.readBool('enableInstallTelemetry', fallback: true),
              onChanged: (v) => _s.write('enableInstallTelemetry', v),
            ),
          ),
          _Row(
            label: 'Analytics',
            hint: 'Opt-in usage data sharing',
            child: _Toggle(
              value: _s.readBool('enableAnalytics'),
              onChanged: (v) => _s.write('enableAnalytics', v),
            ),
          ),
        ],
      ),
      _Card(
        title: 'Offline',
        description:
            'Not a settings.json key — set PI_OFFLINE=1 in the environment to '
            'skip update checks and startup network calls.',
        children: const [],
      ),
    ];
  }

  // -------------------------------------------------------------------- about

  List<Widget> _about(ThemeData theme) {
    final managed = {
      'defaultProvider',
      'defaultModel',
      'defaultThinkingLevel',
      'hideThinkingBlock',
      'showCacheMissNotices',
      'cacheWarming',
      'defaultProjectTrust',
      'defaultTools',
      'compaction',
      'branchSummary',
      'sessionDir',
      'retry',
      'steeringMode',
      'followUpMode',
      'transport',
      'httpIdleTimeoutMs',
      'websocketConnectTimeoutMs',
      'theme',
      'quietStartup',
      'collapseChangelog',
      'markdown',
      'externalEditor',
      'doubleEscapeAction',
      'treeFilterMode',
      'tuiMode',
      'packages',
      'extensions',
      'skills',
      'prompts',
      'themes',
      'enableSkillCommands',
      'httpProxy',
      'enableInstallTelemetry',
      'enableAnalytics',
    };
    final unmanaged =
        _s.keys.where((key) => !managed.contains(key)).toList();

    return [
      _Card(
        title: 'Files',
        children: [
          _InfoRow(label: 'Settings', value: _s.path, copyable: true),
          _InfoRow(
            label: 'Backup',
            value: '${_s.path}.bak — written on every save',
          ),
          _InfoRow(
            label: 'Project overrides',
            value: '.pi/settings.json in a project beats these values',
          ),
        ],
      ),
      _Card(
        title: 'Editing safety',
        description:
            'Only the keys shown here are written. Everything else in the file '
            'is preserved exactly as pi left it, and the previous revision is '
            'kept as settings.json.bak.',
        children: [
          _Row(
            label: 'Reveal settings.json',
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => Process.start('explorer', [
                  '/select,',
                  _s.path,
                ]),
                icon: const Icon(Icons.folder_open, size: 15),
                label: const Text('Show in Explorer'),
              ),
            ),
          ),
          if (_s.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _s.error!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ),
        ],
      ),
      if (unmanaged.isNotEmpty)
        _Card(
          title: 'Other keys in this file',
          description:
              'Read-only here — pi and its extensions own these. They are kept '
              'as-is when you save.',
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final key in unmanaged)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: theme.dividerColor),
                      ),
                      child: Text(
                        key,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(fontFamily: 'GeistMono'),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      _Card(
        title: 'Pi Studio',
        children: [
          const _InfoRow(label: 'Version', value: '1.0.0'),
          _InfoRow(
            label: 'Pi',
            value: 'Reads ~/.pi/agent  ·  drives pi --mode rpc',
          ),
        ],
      ),
    ];
  }
}

// ---------------------------------------------------------------- nav tile

class _NavTile extends StatefulWidget {
  const _NavTile({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final SettingsSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = widget.selected;
    final background = selected
        ? theme.colorScheme.primary.withValues(alpha: 0.14)
        : (_hovered
            ? theme.colorScheme.onSurface.withValues(alpha: 0.07)
            : Colors.transparent);
    final foreground = selected
        ? theme.colorScheme.primary
        : (_hovered
            ? theme.colorScheme.onSurface
            : theme.colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: _ms(context, 120),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Row(
              children: [
                Icon(widget.section.icon, size: 15, color: foreground),
                const SizedBox(width: 9),
                Text(
                  widget.section.label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: foreground,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- containers

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    this.description,
    required this.children,
  });

  final String title;
  final String? description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.dividerColor),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            if (description != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  description!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.hintColor),
                ),
              ),
            if (children.isNotEmpty) const SizedBox(height: 6),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, this.hint, required this.child});

  final String label;
  final String? hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodyMedium),
                if (hint != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      hint!,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.hintColor),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          SizedBox(
            width: 300,
            child: Align(alignment: Alignment.centerRight, child: child),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.copyable = false,
  });

  final String label;
  final String value;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontFamily: 'GeistMono', fontSize: 12),
            ),
          ),
          if (copyable)
            IconButton(
              tooltip: 'Copy',
              iconSize: 14,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied')),
                );
              },
              icon: const Icon(Icons.copy_outlined),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- controls

class _Toggle extends StatelessWidget {
  const _Toggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Switch(
        value: value,
        onChanged: onChanged,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _Pick extends StatelessWidget {
  const _Pick({
    required this.value,
    required this.options,
    required this.onChanged,
    this.unsetLabel,
    this.labelFor,
  });

  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  /// Shown when the key is absent — selecting it removes the key so pi falls
  /// back to its own default rather than pinning a value here.
  final String? unsetLabel;

  /// Display name for an option, when the stored value is an opaque id.
  final String Function(String value)? labelFor;

  String _label(String value) => labelFor?.call(value) ?? value;

  Widget _item(String text) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 230),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final known = value != null && options.contains(value);
    final items = <DropdownMenuItem<String?>>[
      if (unsetLabel != null)
        DropdownMenuItem<String?>(value: null, child: _item(unsetLabel!)),
      for (final option in options)
        DropdownMenuItem<String?>(value: option, child: _item(_label(option))),
      // A value pi accepts but this UI does not list (custom theme, unknown
      // level) still needs an entry, or the dropdown asserts.
      if (value != null && !known)
        DropdownMenuItem<String?>(value: value, child: _item(_label(value!))),
    ];
    return Align(
      alignment: Alignment.centerRight,
      child: DropdownButton<String?>(
        value: value,
        items: items,
        onChanged: onChanged,
        isDense: true,
        dropdownColor: theme.colorScheme.surfaceContainerHigh,
        underline: const SizedBox.shrink(),
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurface),
      ),
    );
  }
}

class _Entry extends StatefulWidget {
  const _Entry({
    required this.value,
    required this.onChanged,
    this.hint = '',
    this.normalisePath = false,
    this.obscure = false,
    this.commitOnBlur = false,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String hint;

  /// Rewrites Windows backslashes on blur; JSON treats `\` as an escape.
  final bool normalisePath;

  /// Hides the value behind a reveal toggle. Used for literal API keys;
  /// `$ENV_VAR` and `!command` references stay readable because they are not
  /// secret and hiding them makes them impossible to check.
  final bool obscure;

  /// Commits only on blur or submit. Needed where the value is a lookup key
  /// rather than a value, so a half-typed intermediate must not be written.
  final bool commitOnBlur;

  @override
  State<_Entry> createState() => _EntryState();
}

class _EntryState extends State<_Entry> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);
  final _focus = FocusNode();
  var _revealed = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_focus.hasFocus) return;
      final next = widget.normalisePath
          ? normalizeSettingsPath(_controller.text)
          : _controller.text.trim();
      if (next != _controller.text) _controller.text = next;
      widget.onChanged(next);
    });
  }

  @override
  void didUpdateWidget(_Entry old) {
    super.didUpdateWidget(old);
    // Reflect external changes (discard, reload) without stomping the caret
    // while the field is being typed in.
    if (!_focus.hasFocus && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focus,
      obscureText: widget.obscure && !_revealed,
      // Commit per keystroke so Save enables while typing. A disabled Save
      // button cannot take focus, so a blur-to-commit field would leave the
      // user unable to save what they just typed.
      onChanged: widget.commitOnBlur
          ? null
          : (text) => widget.onChanged(text.trim()),
      onSubmitted: (value) => widget.onChanged(value.trim()),
      decoration: InputDecoration(
        hintText: widget.hint,
        suffixIcon: widget.obscure
            ? IconButton(
                tooltip: _revealed ? 'Hide' : 'Reveal',
                iconSize: 15,
                onPressed: () => setState(() => _revealed = !_revealed),
                icon: Icon(
                  _revealed ? Icons.visibility_off : Icons.visibility,
                ),
              )
            : null,
      ),
      style: const TextStyle(fontSize: 13),
    );
  }
}

class _Number extends StatefulWidget {
  const _Number({
    required this.value,
    required this.onChanged,
    this.hint = '',
    this.decimal = false,
    this.width = 150,
  });

  final num? value;
  final ValueChanged<num?> onChanged;
  final String hint;

  /// Cost fields are fractions of a dollar per million tokens, so they need a
  /// decimal point.
  final bool decimal;
  final double width;

  @override
  State<_Number> createState() => _NumberState();
}

class _NumberState extends State<_Number> {
  late final TextEditingController _controller =
      TextEditingController(text: _format(widget.value));
  final _focus = FocusNode();

  static String _format(num? value) {
    if (value == null) return '';
    final asInt = value.toInt();
    return value == asInt ? '$asInt' : '$value';
  }

  num? _parse(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    return widget.decimal ? num.tryParse(trimmed) : int.tryParse(trimmed);
  }

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_focus.hasFocus) return;
      final text = _controller.text.trim();
      // Reject junk rather than writing a value pi would error on.
      if (text.isNotEmpty && _parse(text) == null) {
        _controller.text = _format(widget.value);
      }
    });
  }

  @override
  void didUpdateWidget(_Number old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus) {
      final next = _format(widget.value);
      if (next != _controller.text) _controller.text = next;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.allow(
            widget.decimal ? RegExp(r'[0-9.]') : RegExp(r'[0-9]'),
          ),
        ],
        textAlign: TextAlign.right,
        // Same reason as _Entry: bind as you type, clear means "use pi's
        // default", which drops the key.
        onChanged: (text) => widget.onChanged(_parse(text)),
        decoration: InputDecoration(
          hintText: widget.hint.isEmpty ? 'default' : widget.hint,
        ),
        style: const TextStyle(fontSize: 13, fontFamily: 'GeistMono'),
      ),
    );
  }
}

class _List extends StatefulWidget {
  const _List({
    required this.values,
    required this.onChanged,
    this.hint = '',
    this.label,
  });

  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  final String hint;
  final String? label;

  @override
  State<_List> createState() => _ListState();
}

class _ListState extends State<_List> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) setState(() {});
    });
  }

  void _add() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onChanged([...widget.values, text]);
    _controller.clear();
    setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.label != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(widget.label!, style: theme.textTheme.bodySmall),
            ),
          for (final value in widget.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Container(
                padding: const EdgeInsets.fromLTRB(9, 3, 3, 3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: theme.dividerColor),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(fontFamily: 'GeistMono'),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove',
                      iconSize: 14,
                      onPressed: () => widget.onChanged(
                        widget.values.where((v) => v != value).toList(),
                      ),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _add(),
                  decoration: InputDecoration(hintText: widget.hint),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Add',
                onPressed: _controller.text.trim().isEmpty ? null : _add,
                icon: const Icon(Icons.add, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatefulWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.emphasise = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool emphasise;

  @override
  State<_Chip> createState() => _ChipState();
}

class _ChipState extends State<_Chip> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = widget.selected;
    final colour =
        widget.emphasise ? theme.colorScheme.secondary : theme.colorScheme.primary;
    final border = selected
        ? colour.withValues(alpha: 0.7)
        : (_hovered
            ? theme.colorScheme.outline.withValues(alpha: 0.55)
            : theme.dividerColor);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: _ms(context, 110),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: selected
                ? colour.withValues(alpha: 0.16)
                : theme.colorScheme.surfaceContainerHigh
                    .withValues(alpha: _hovered ? 0.9 : 0.55),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Icon(Icons.check, size: 12, color: colour),
                const SizedBox(width: 5),
              ],
              Text(
                widget.label,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontFamily: 'GeistMono',
                  color: selected
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------- providers & models (models.json)

/// Adds a provider to `models.json`, keyed by id.
class _AddProviderField extends StatefulWidget {
  const _AddProviderField({required this.store});

  final PiModels store;

  @override
  State<_AddProviderField> createState() => _AddProviderFieldState();
}

class _AddProviderFieldState extends State<_AddProviderField> {
  final _controller = TextEditingController();
  var _error = '';

  void _add() {
    final id = _controller.text.trim();
    if (id.isEmpty) return;
    if (widget.store.provider(id) != null) {
      setState(() => _error = '"$id" is already in this file');
      return;
    }
    widget.store.putProvider(id, <String, dynamic>{});
    _controller.clear();
    setState(() => _error = '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            SizedBox(
              width: 200,
              child: TextField(
                controller: _controller,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _add(),
                decoration: const InputDecoration(hintText: 'provider id'),
                style: const TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(width: 6),
            FilledButton(
              onPressed: _controller.text.trim().isEmpty ? null : _add,
              child: const Text('Add'),
            ),
          ],
        ),
        if (_error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _error,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ),
      ],
    );
  }
}

/// Edits one entry under `providers` in models.json.
class _ProviderEditor extends StatefulWidget {
  const _ProviderEditor({
    required this.store,
    required this.id,
    required this.models,
    super.key,
  });

  final PiModels store;
  final String id;
  final List<Object?> models;

  @override
  State<_ProviderEditor> createState() => _ProviderEditorState();
}

class _ProviderEditorState extends State<_ProviderEditor> {
  var _discovering = false;
  String? _discoveryMessage;
  var _discoveryFailed = false;
  var _idError = '';

  PiModels get _store => widget.store;

  Map<String, dynamic> get _provider =>
      _store.provider(widget.id) ?? const <String, dynamic>{};

  void _renameTo(String next) {
    final id = next.trim();
    if (id.isEmpty || id == widget.id) return;
    if (_store.provider(id) != null) {
      setState(() => _idError = 'A provider called "$id" already exists');
      return;
    }
    setState(() => _idError = '');
    _store.renameProvider(widget.id, id);
  }

  /// Asks the provider what models it has and adds any that are missing.
  Future<void> _discover() async {
    final provider = _provider;
    final baseUrl = (provider['baseUrl'] as String?) ?? '';
    final api = (provider['api'] as String?) ?? piModelApis.first;

    String? apiKey;
    final rawKey = provider['apiKey'];
    if (rawKey is String && rawKey.trim().isNotEmpty) {
      final expanded = expandConfigValue(rawKey, Platform.environment);
      if (!expanded.ok) {
        setState(() {
          _discoveryFailed = true;
          _discoveryMessage =
              'Cannot use the stored API key: ${expanded.reason}';
        });
        return;
      }
      apiKey = expanded.value;
    }

    // Header values use the same syntax. Expand what resolves and skip the
    // rest, rather than sending a literal "$VAR" to the server.
    final headers = <String, String>{};
    final rawHeaders = provider['headers'];
    if (rawHeaders is Map) {
      for (final entry in rawHeaders.entries) {
        final value = entry.value;
        if (value is! String) continue;
        final expanded = expandConfigValue(value, Platform.environment);
        if (expanded.ok) headers['${entry.key}'] = expanded.value!;
      }
    }

    setState(() {
      _discovering = true;
      _discoveryMessage = null;
    });

    final result = await discoverModels(
      baseUrl: baseUrl,
      api: api,
      apiKey: apiKey,
      headers: headers,
    );
    if (!mounted) return;

    if (!result.ok) {
      setState(() {
        _discovering = false;
        _discoveryFailed = true;
        _discoveryMessage = result.error;
      });
      return;
    }

    final added = _store.addMissingModels(widget.id, result.ids);
    setState(() {
      _discovering = false;
      _discoveryFailed = false;
      _discoveryMessage = added == 0
          ? 'Found ${result.ids.length} models at ${result.endpoint} - all '
              'already listed.'
          : 'Added $added of ${result.ids.length} models from '
              '${result.endpoint}.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = _provider;
    final problems = _store.validate(widget.id, provider);
    final duplicated = _store.duplicatedModelIds(widget.id);

    final rawHeaders = provider['headers'];
    final headers = <String, String>{};
    if (rawHeaders is Map) {
      for (final entry in rawHeaders.entries) {
        if (entry.value is String) headers['${entry.key}'] = entry.value as String;
      }
    }

    final apiKey = (provider['apiKey'] as String?) ?? '';

    return _Card(
      title: widget.id,
      description: provider['name'] is String &&
              (provider['name'] as String).trim().isNotEmpty
          ? provider['name'] as String
          : null,
      children: [
        for (final problem in problems)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _Warning(text: problem),
          ),
        _Row(
          label: 'Provider id',
          hint: 'Key under providers in models.json. Changing it here renames '
              'the entry.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _Entry(
                value: widget.id,
                commitOnBlur: true,
                onChanged: _renameTo,
              ),
              if (_idError.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    _idError,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
        _Row(
          label: 'Base URL',
          hint: 'Where requests go, e.g. http://localhost:11434/v1',
          child: _Entry(
            value: (provider['baseUrl'] as String?) ?? '',
            hint: 'https://...',
            onChanged: (v) => _store.setProviderField(widget.id, 'baseUrl', v),
          ),
        ),
        _Row(
          label: 'API',
          hint: 'Which streaming shape this provider speaks',
          child: _Pick(
            value: provider['api'] as String?,
            unsetLabel: '(not set)',
            options: piModelApis,
            onChanged: (v) => _store.setProviderField(widget.id, 'api', v),
          ),
        ),
        _Row(
          label: 'API key',
          hint: r'A literal key, $ENV_VAR, or ${ENV_VAR}. Empty means pi uses '
              r'/login.',
          child: _Entry(
            value: apiKey,
            hint: r'$MY_API_KEY',
            // References are not secret and must stay readable; only literals
            // are worth hiding.
            obscure: apiKey.isNotEmpty &&
                !apiKey.startsWith(r'$') &&
                !apiKey.startsWith('!'),
            onChanged: (v) => _store.setProviderField(widget.id, 'apiKey', v),
          ),
        ),
        _Row(
          label: 'Send Authorization: Bearer',
          hint: 'For endpoints that take the key as a bearer header',
          child: _Toggle(
            value: provider['authHeader'] == true,
            onChanged: (v) => _store.setProviderField(
              widget.id,
              'authHeader',
              v ? true : null,
            ),
          ),
        ),
        _Row(
          label: 'Display name',
          hint: 'Shown where pi has room for a friendly name',
          child: _Entry(
            value: (provider['name'] as String?) ?? '',
            hint: widget.id,
            onChanged: (v) => _store.setProviderField(widget.id, 'name', v),
          ),
        ),
        _KeyValueEditor(
          label: 'Headers',
          hint: 'Same value syntax as the API key',
          values: headers,
          onChanged: (next) => _store.setProviderField(
            widget.id,
            'headers',
            next.isEmpty ? null : next,
          ),
        ),
        const Divider(height: 24),
        ..._modelsSection(theme, duplicated),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _store.removeProvider(widget.id),
            icon: const Icon(Icons.delete_outline, size: 15),
            label: Text('Remove ${widget.id}'),
          ),
        ),
      ],
    );
  }

  List<Widget> _modelsSection(ThemeData theme, Set<String> duplicated) {
    final models = widget.models;
    return [
      Row(
        children: [
          Text('Models', style: theme.textTheme.titleSmall),
          const SizedBox(width: 8),
          Text('${models.length}', style: theme.textTheme.labelSmall),
          const Spacer(),
          if (_discovering)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton.icon(
              onPressed: _discover,
              icon: const Icon(Icons.cloud_download_outlined, size: 15),
              label: const Text('Discover'),
            ),
          TextButton.icon(
            onPressed: () => _store.addModel(widget.id),
            icon: const Icon(Icons.add, size: 15),
            label: const Text('Add model'),
          ),
        ],
      ),
      if (_discoveryMessage != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _Warning(text: _discoveryMessage!, error: _discoveryFailed),
        ),
      if (models.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            'No models listed. Without a models array pi keeps whatever this '
            'provider already had, which is what you want when you are only '
            'rerouting a built-in one.',
            style: theme.textTheme.labelSmall,
          ),
        ),
      for (var i = 0; i < models.length; i++)
        if (models[i] is Map<String, dynamic>)
          _ModelEditor(
            key: ValueKey('model:$i'),
            store: _store,
            providerId: widget.id,
            index: i,
            model: models[i] as Map<String, dynamic>,
            duplicate: duplicated.contains((models[i] as Map)['id']),
          ),
    ];
  }
}

/// One model inside a provider's `models` array.
///
/// Identity is the array index, which is why the parent keys these by index:
/// the id itself can be typed through empty on the way to a real value.
class _ModelEditor extends StatelessWidget {
  const _ModelEditor({
    required this.store,
    required this.providerId,
    required this.index,
    required this.model,
    required this.duplicate,
    super.key,
  });

  final PiModels store;
  final String providerId;
  final int index;
  final Map<String, dynamic> model;
  final bool duplicate;

  void _set(String key, Object? value) =>
      store.setModelField(providerId, index, key, value);

  /// `cost` is a nested object, so writing one rate has to merge with the
  /// others rather than replace the map.
  void _setCost(String key, num? value) {
    final next = <String, dynamic>{};
    final current = model['cost'];
    if (current is Map) {
      current.forEach((k, v) => next['$k'] = v);
    }
    if (value == null) {
      next.remove(key);
    } else {
      next[key] = value;
    }
    _set('cost', next.isEmpty ? null : next);
  }

  num? _cost(String key) {
    final current = model['cost'];
    if (current is! Map) return null;
    final value = current[key];
    return value is num ? value : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final input = model['input'];
    final supportsImages = input is List && input.contains('image');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: duplicate
              ? theme.colorScheme.error.withValues(alpha: 0.6)
              : theme.dividerColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                flex: 3,
                child: _Labelled(
                  label: 'Model id',
                  child: _Entry(
                    value: (model['id'] as String?) ?? '',
                    hint: 'llama3.1:8b',
                    onChanged: (v) => _set('id', v),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: _Labelled(
                  label: 'Display name',
                  child: _Entry(
                    value: (model['name'] as String?) ?? '',
                    hint: 'optional',
                    onChanged: (v) => _set('name', v),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Remove model',
                iconSize: 15,
                onPressed: () => store.removeModelAt(providerId, index),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _Chip(
                label: 'reasoning',
                selected: model['reasoning'] == true,
                onTap: () => _set(
                  'reasoning',
                  model['reasoning'] == true ? null : true,
                ),
              ),
              const SizedBox(width: 6),
              _Chip(
                label: 'vision',
                selected: supportsImages,
                onTap: () => _set(
                  'input',
                  supportsImages ? null : <String>['text', 'image'],
                ),
              ),
              const Spacer(),
              SizedBox(
                width: 110,
                child: _Labelled(
                  label: 'Context',
                  child: _Number(
                    value: model['contextWindow'] as num?,
                    hint: '128000',
                    width: 110,
                    onChanged: (v) => _set('contextWindow', v),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 100,
                child: _Labelled(
                  label: 'Max output',
                  child: _Number(
                    value: model['maxTokens'] as num?,
                    hint: '16384',
                    width: 100,
                    onChanged: (v) => _set('maxTokens', v),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                r'Cost per million tokens',
                style: theme.textTheme.labelSmall,
              ),
              const Spacer(),
              SizedBox(
                width: 96,
                child: _Labelled(
                  label: 'input \$',
                  child: _Number(
                    value: _cost('input'),
                    decimal: true,
                    width: 96,
                    hint: '0',
                    onChanged: (v) => _setCost('input', v),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 96,
                child: _Labelled(
                  label: 'output \$',
                  child: _Number(
                    value: _cost('output'),
                    decimal: true,
                    width: 96,
                    hint: '0',
                    onChanged: (v) => _setCost('output', v),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Ordered key/value rows, for provider `headers`.
class _KeyValueEditor extends StatefulWidget {
  const _KeyValueEditor({
    required this.label,
    required this.hint,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final Map<String, String> values;
  final ValueChanged<Map<String, String>> onChanged;

  @override
  State<_KeyValueEditor> createState() => _KeyValueEditorState();
}

class _KeyValueEditorState extends State<_KeyValueEditor> {
  final _new = TextEditingController();

  void _renameKey(int index, String next) {
    final key = next.trim();
    final entries = widget.values.entries.toList();
    if (index >= entries.length) return;
    if (key.isEmpty || entries[index].key == key) return;
    // Ignore a collision rather than silently dropping the other header.
    if (widget.values.containsKey(key)) return;

    final rebuilt = <String, String>{};
    for (var i = 0; i < entries.length; i++) {
      rebuilt[i == index ? key : entries[i].key] = entries[i].value;
    }
    widget.onChanged(rebuilt);
  }

  void _add() {
    final key = _new.text.trim();
    if (key.isEmpty || widget.values.containsKey(key)) return;
    widget.onChanged({...widget.values, key: ''});
    _new.clear();
    setState(() {});
  }

  @override
  void dispose() {
    _new.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.values.entries.toList();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.label, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 4),
          for (var i = 0; i < entries.length; i++)
            Padding(
              key: ValueKey('header:$i'),
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _Entry(
                      value: entries[i].key,
                      hint: 'header',
                      commitOnBlur: true,
                      onChanged: (v) => _renameKey(i, v),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 3,
                    child: _Entry(
                      value: entries[i].value,
                      hint: widget.hint,
                      onChanged: (v) => widget.onChanged({
                        ...widget.values,
                        entries[i].key: v,
                      }),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove header',
                    iconSize: 15,
                    onPressed: () {
                      final next = {...widget.values}..remove(entries[i].key);
                      widget.onChanged(next);
                    },
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _new,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _add(),
                  decoration: const InputDecoration(hintText: 'Add header'),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Add',
                onPressed: _new.text.trim().isEmpty ? null : _add,
                icon: const Icon(Icons.add, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A label stacked above its control, for the compact model rows.
class _Labelled extends StatelessWidget {
  const _Labelled({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor),
          ),
        ),
        child,
      ],
    );
  }
}

/// Inline note for validation problems and discovery results.
class _Warning extends StatelessWidget {
  const _Warning({required this.text, this.error = false});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour =
        error ? theme.colorScheme.error : theme.colorScheme.secondary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: colour.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            error ? Icons.error_outline : Icons.info_outline,
            size: 14,
            color: colour,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}
