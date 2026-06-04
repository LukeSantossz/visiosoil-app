import 'package:flutter/material.dart';

/// Plano de manejo com ações, fontes e alertas.
///
/// Gerado com base na classe textural do solo analisado.
/// Futuramente será alimentado por research agent.
class ManagementPlan {
  final String textureClass;
  final List<ManagementAction> actions;
  final List<Source> sources;
  final List<Alert> alerts;
  final DateTime generatedAt;

  const ManagementPlan({
    required this.textureClass,
    required this.actions,
    required this.sources,
    required this.alerts,
    required this.generatedAt,
  });

  /// Gera um plano mock baseado na classe textural.
  factory ManagementPlan.forTextureClass(String textureClass) {
    return ManagementPlan(
      textureClass: textureClass,
      actions: _mockActionsFor(textureClass),
      sources: _mockSources,
      alerts: _mockAlertsFor(textureClass),
      generatedAt: DateTime.now(),
    );
  }
}

/// Ação de manejo recomendada.
class ManagementAction {
  final String id;
  final String title;
  final String description;
  final ActionPriority priority;
  final String? deadline;
  final IconData icon;
  final List<String> citations;

  const ManagementAction({
    required this.id,
    required this.title,
    required this.description,
    required this.priority,
    this.deadline,
    required this.icon,
    this.citations = const [],
  });
}

/// Prioridade da ação.
enum ActionPriority {
  high('Alta', Color(0xFFDC2626), Color(0xFFFEE2E2)),
  medium('Média', Color(0xFFD97706), Color(0xFFFEF3C7)),
  low('Baixa', Color(0xFF059669), Color(0xFFD1FAE5));

  final String label;
  final Color foregroundColor;
  final Color backgroundColor;

  const ActionPriority(this.label, this.foregroundColor, this.backgroundColor);
}

/// Fonte/referência bibliográfica.
class Source {
  final String id;
  final String title;
  final String? author;
  final String? year;
  final String? url;
  final SourceType type;

  const Source({
    required this.id,
    required this.title,
    this.author,
    this.year,
    this.url,
    required this.type,
  });
}

/// Tipo de fonte.
enum SourceType {
  paper('Artigo', Icons.article_outlined),
  book('Livro', Icons.menu_book_outlined),
  manual('Manual', Icons.description_outlined),
  website('Site', Icons.language);

  final String label;
  final IconData icon;

  const SourceType(this.label, this.icon);
}

/// Alerta sobre condição do solo.
class Alert {
  final String id;
  final String title;
  final String description;
  final AlertSeverity severity;

  const Alert({
    required this.id,
    required this.title,
    required this.description,
    required this.severity,
  });
}

/// Severidade do alerta.
enum AlertSeverity {
  warning('Atenção', Icons.warning_amber_rounded, Color(0xFFD97706), Color(0xFFFEF3C7)),
  info('Informação', Icons.info_outline, Color(0xFF2563EB), Color(0xFFDBEAFE)),
  tip('Dica', Icons.lightbulb_outline, Color(0xFF059669), Color(0xFFD1FAE5));

  final String label;
  final IconData icon;
  final Color foregroundColor;
  final Color backgroundColor;

  const AlertSeverity(this.label, this.icon, this.foregroundColor, this.backgroundColor);
}

// --- Mock Data ---

List<ManagementAction> _mockActionsFor(String textureClass) {
  final baseActions = <ManagementAction>[
    ManagementAction(
      id: '1',
      title: 'Análise de fertilidade',
      description: 'Realizar análise completa de macro e micronutrientes para definir a adubação correta.',
      priority: ActionPriority.high,
      deadline: '15 dias',
      icon: Icons.science_outlined,
      citations: ['EMBRAPA, 2021', 'IAC, 2020'],
    ),
    ManagementAction(
      id: '2',
      title: 'Correção de pH',
      description: 'Verificar necessidade de calagem com base na saturação de bases.',
      priority: ActionPriority.high,
      deadline: '30 dias',
      icon: Icons.straighten,
      citations: ['EMBRAPA, 2021'],
    ),
  ];

  // Ações específicas por textura
  switch (textureClass.toLowerCase()) {
    case 'arenosa':
      return [
        ...baseActions,
        const ManagementAction(
          id: '3',
          title: 'Adubação parcelada',
          description: 'Dividir a adubação em mais parcelas para evitar lixiviação em solo arenoso.',
          priority: ActionPriority.high,
          deadline: 'Antes do plantio',
          icon: Icons.calendar_today,
          citations: ['EMBRAPA, 2021', 'Raij et al., 2017'],
        ),
        const ManagementAction(
          id: '4',
          title: 'Cobertura do solo',
          description: 'Manter palhada para reduzir evaporação e erosão.',
          priority: ActionPriority.medium,
          icon: Icons.grass,
          citations: ['IAC, 2020'],
        ),
        const ManagementAction(
          id: '5',
          title: 'Irrigação frequente',
          description: 'Solo arenoso retém menos água. Considerar irrigação mais frequente em menor volume.',
          priority: ActionPriority.medium,
          icon: Icons.water_drop_outlined,
        ),
      ];
    case 'argilosa':
    case 'muito argilosa':
      return [
        ...baseActions,
        const ManagementAction(
          id: '3',
          title: 'Evitar compactação',
          description: 'Reduzir tráfego de máquinas quando o solo estiver úmido.',
          priority: ActionPriority.high,
          icon: Icons.do_not_disturb_alt,
          citations: ['EMBRAPA, 2021'],
        ),
        const ManagementAction(
          id: '4',
          title: 'Subsolagem',
          description: 'Avaliar necessidade de descompactação caso haja camada adensada.',
          priority: ActionPriority.medium,
          deadline: 'Pré-plantio',
          icon: Icons.layers,
        ),
        const ManagementAction(
          id: '5',
          title: 'Drenagem',
          description: 'Verificar drenagem da área para evitar encharcamento.',
          priority: ActionPriority.low,
          icon: Icons.waves,
        ),
      ];
    default: // Media, Siltosa
      return [
        ...baseActions,
        const ManagementAction(
          id: '3',
          title: 'Manutenção da estrutura',
          description: 'Preservar matéria orgânica para manter boa estrutura do solo.',
          priority: ActionPriority.medium,
          icon: Icons.eco,
          citations: ['IAC, 2020'],
        ),
        const ManagementAction(
          id: '4',
          title: 'Rotação de culturas',
          description: 'Alternar culturas para melhorar a saúde do solo.',
          priority: ActionPriority.low,
          icon: Icons.autorenew,
        ),
      ];
  }
}

const _mockSources = <Source>[
  Source(
    id: '1',
    title: 'Manual de Calagem e Adubação para o Estado de São Paulo',
    author: 'IAC',
    year: '2020',
    type: SourceType.manual,
  ),
  Source(
    id: '2',
    title: 'Sistema Brasileiro de Classificação de Solos',
    author: 'EMBRAPA',
    year: '2021',
    type: SourceType.book,
  ),
  Source(
    id: '3',
    title: 'Recomendações de Adubação e Calagem',
    author: 'Raij et al.',
    year: '2017',
    type: SourceType.paper,
  ),
  Source(
    id: '4',
    title: 'Guia Prático de Manejo de Solo',
    author: 'ESALQ/USP',
    year: '2019',
    url: 'https://esalq.usp.br',
    type: SourceType.website,
  ),
];

List<Alert> _mockAlertsFor(String textureClass) {
  final alerts = <Alert>[
    const Alert(
      id: '1',
      title: 'Época ideal para amostragem',
      description: 'A melhor época para coleta de solo é 3-4 meses antes do plantio.',
      severity: AlertSeverity.info,
    ),
  ];

  switch (textureClass.toLowerCase()) {
    case 'arenosa':
      alerts.add(const Alert(
        id: '2',
        title: 'Risco de lixiviação',
        description: 'Solos arenosos têm alta lixiviação. Evite aplicar todo o fertilizante de uma vez.',
        severity: AlertSeverity.warning,
      ));
      break;
    case 'argilosa':
    case 'muito argilosa':
      alerts.add(const Alert(
        id: '2',
        title: 'Risco de compactação',
        description: 'Evite tráfego de máquinas com o solo muito úmido.',
        severity: AlertSeverity.warning,
      ));
      break;
    default:
      alerts.add(const Alert(
        id: '2',
        title: 'Solo equilibrado',
        description: 'Esta textura oferece bom equilíbrio entre drenagem e retenção de nutrientes.',
        severity: AlertSeverity.tip,
      ));
  }

  return alerts;
}
