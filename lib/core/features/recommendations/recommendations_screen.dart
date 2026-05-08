import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/theme/app_colors.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/models/management_plan.dart';

/// Tela de recomendações/plano de manejo.
///
/// Exibe ações priorizadas, fontes e alertas baseados na classe textural.
/// Quando acessada pela navegação inferior, exibe seletor de classe textural.
/// Quando acessada via rota com parâmetro, exibe diretamente o plano.
class RecommendationsScreen extends StatefulWidget {
  const RecommendationsScreen({
    super.key,
    this.textureClass,
  });

  /// Classe textural. Se null, exibe seletor de classes.
  final String? textureClass;

  @override
  State<RecommendationsScreen> createState() => _RecommendationsScreenState();
}

class _RecommendationsScreenState extends State<RecommendationsScreen>
    with TickerProviderStateMixin {
  TabController? _tabController;
  ManagementPlan? _plan;
  bool _isLoading = false;
  String _loadingStep = '';
  String? _selectedClass;

  static const List<String> _textureClasses = [
    'Arenosa',
    'Média',
    'Argilosa',
    'Muito Argilosa',
    'Siltosa',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.textureClass != null) {
      _selectedClass = widget.textureClass;
      _loadPlan(widget.textureClass!);
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _loadPlan(String textureClass) async {
    setState(() {
      _isLoading = true;
      _selectedClass = textureClass;
    });

    // Simula etapas de carregamento do research agent
    final steps = [
      'Analisando classe textural...',
      'Consultando base de conhecimento...',
      'Gerando recomendações...',
      'Organizando plano de manejo...',
    ];

    for (final step in steps) {
      if (!mounted) return;
      setState(() => _loadingStep = step);
      await Future.delayed(const Duration(milliseconds: 500));
    }

    if (!mounted) return;

    _tabController?.dispose();
    _tabController = TabController(length: 3, vsync: this);

    setState(() {
      _plan = ManagementPlan.forTextureClass(textureClass);
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isStandalone = widget.textureClass == null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Plano de Manejo'),
        leading: isStandalone
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/');
                  }
                },
              ),
        automaticallyImplyLeading: !isStandalone,
        bottom: (_plan != null && !_isLoading && _tabController != null)
            ? TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'Plano'),
                  Tab(text: 'Fontes'),
                  Tab(text: 'Alertas'),
                ],
              )
            : null,
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) {
      return _buildLoading(theme);
    }

    if (_plan == null) {
      return _buildClassSelector(theme);
    }

    return _buildContent(theme);
  }

  Widget _buildClassSelector(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.primaryContainer,
                  AppColors.primaryContainer.withValues(alpha: 0.7),
                ],
              ),
              borderRadius: AppRadius.borderRadiusLg,
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: AppRadius.borderRadiusMd,
                  ),
                  child: const Icon(
                    Icons.eco,
                    size: 28,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recomendações de Manejo',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Selecione uma classe textural para ver o plano de manejo recomendado',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // Section title
          Text(
            'Classe Textural',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Texture class cards
          ..._textureClasses.map((textureClass) => _TextureClassCard(
                textureClass: textureClass,
                isSelected: _selectedClass == textureClass,
                onTap: () => _loadPlan(textureClass),
              )),
        ],
      ),
    );
  }

  Widget _buildLoading(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated icon
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.8, end: 1.0),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeInOut,
              builder: (context, scale, child) {
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      size: 40,
                      color: AppColors.primary,
                    ),
                  ),
                );
              },
              onEnd: () {
                if (mounted && _isLoading) {
                  setState(() {});
                }
              },
            ),
            const SizedBox(height: AppSpacing.xxl),
            Text(
              _loadingStep,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            const SizedBox(
              width: 200,
              child: LinearProgressIndicator(),
            ),
            const SizedBox(height: AppSpacing.xxl),
            Text(
              'Preparando recomendações para\nsolo $_selectedClass',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    final plan = _plan!;

    return Column(
      children: [
        // Back to selector button (only in standalone mode)
        if (widget.textureClass == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              0,
            ),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _plan = null;
                      _tabController?.dispose();
                      _tabController = null;
                    });
                  },
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('Trocar classe'),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer,
                    borderRadius: AppRadius.borderRadiusPill,
                  ),
                  child: Text(
                    _selectedClass ?? '',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // Tab content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // Tab 1: Plano (ações)
              _ActionsTab(actions: plan.actions),
              // Tab 2: Fontes
              _SourcesTab(sources: plan.sources),
              // Tab 3: Alertas
              _AlertsTab(alerts: plan.alerts),
            ],
          ),
        ),
      ],
    );
  }
}

// --- Texture Class Card ---

class _TextureClassCard extends StatelessWidget {
  const _TextureClassCard({
    required this.textureClass,
    required this.isSelected,
    required this.onTap,
  });

  final String textureClass;
  final bool isSelected;
  final VoidCallback onTap;

  IconData get _icon {
    switch (textureClass) {
      case 'Arenosa':
        return Icons.grain;
      case 'Siltosa':
        return Icons.water_drop;
      case 'Argilosa':
        return Icons.layers;
      case 'Muito Argilosa':
        return Icons.landscape;
      case 'Média':
      default:
        return Icons.eco;
    }
  }

  Color get _color {
    switch (textureClass) {
      case 'Arenosa':
        return AppColors.soilSandy;
      case 'Siltosa':
        return AppColors.soilSilt;
      case 'Argilosa':
        return AppColors.soilClay;
      case 'Muito Argilosa':
        return AppColors.soilVeryClay;
      case 'Média':
      default:
        return AppColors.soilMedium;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _color.withValues(alpha: 0.15),
                  borderRadius: AppRadius.borderRadiusSm,
                ),
                child: Icon(
                  _icon,
                  color: _color,
                  size: 24,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  textureClass,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: AppColors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Actions Tab ---

class _ActionsTab extends StatelessWidget {
  const _ActionsTab({required this.actions});

  final List<ManagementAction> actions;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: actions.length,
      itemBuilder: (context, index) => _ActionCard(action: actions[index]),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.action});

  final ManagementAction action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: icon, title, priority badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: action.priority.backgroundColor,
                    borderRadius: AppRadius.borderRadiusSm,
                  ),
                  child: Icon(
                    action.icon,
                    size: 20,
                    color: action.priority.foregroundColor,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        action.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (action.deadline != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Row(
                          children: [
                            Icon(
                              Icons.schedule,
                              size: 14,
                              color: AppColors.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              action.deadline!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                _PriorityBadge(priority: action.priority),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            // Description
            Text(
              action.description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            // Citations
            if (action.citations.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: action.citations
                    .map((citation) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceDim,
                            borderRadius: AppRadius.borderRadiusPill,
                          ),
                          child: Text(
                            citation,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PriorityBadge extends StatelessWidget {
  const _PriorityBadge({required this.priority});

  final ActionPriority priority;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: priority.backgroundColor,
        borderRadius: AppRadius.borderRadiusPill,
      ),
      child: Text(
        priority.label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: priority.foregroundColor,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

// --- Sources Tab ---

class _SourcesTab extends StatelessWidget {
  const _SourcesTab({required this.sources});

  final List<Source> sources;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: sources.length,
      itemBuilder: (context, index) => _SourceCard(source: sources[index]),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({required this.source});

  final Source source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: ListTile(
        contentPadding: const EdgeInsets.all(AppSpacing.md),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.surfaceDim,
            borderRadius: AppRadius.borderRadiusSm,
          ),
          child: Icon(
            source.type.icon,
            color: AppColors.onSurfaceVariant,
          ),
        ),
        title: Text(
          source.title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (source.author != null || source.year != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  [source.author, source.year].whereType<String>().join(', '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: AppRadius.borderRadiusPill,
              ),
              child: Text(
                source.type.label,
                style: theme.textTheme.labelSmall,
              ),
            ),
          ],
        ),
        trailing: source.url != null
            ? IconButton(
                icon: const Icon(Icons.open_in_new, size: 20),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Abrindo: ${source.url}')),
                  );
                },
              )
            : null,
      ),
    );
  }
}

// --- Alerts Tab ---

class _AlertsTab extends StatelessWidget {
  const _AlertsTab({required this.alerts});

  final List<Alert> alerts;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: alerts.length,
      itemBuilder: (context, index) => _AlertCard(alert: alerts[index]),
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert});

  final Alert alert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      color: alert.severity.backgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: alert.severity.foregroundColor.withValues(alpha: 0.15),
                borderRadius: AppRadius.borderRadiusSm,
              ),
              child: Icon(
                alert.severity.icon,
                size: 20,
                color: alert.severity.foregroundColor,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alert.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: alert.severity.foregroundColor,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    alert.description,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: alert.severity.foregroundColor.withValues(alpha: 0.8),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
