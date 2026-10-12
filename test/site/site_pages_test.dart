import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Pins the privacy policy and the account deletion page that Google Play links
/// to, and the workflow that publishes them (SPEC 0156, #276, #278).
///
/// The pages state what the build does. These tests pin the claims, not the
/// code, so a change that sends data somewhere new still has to update the
/// policy by review.
void main() {
  final policy = File('site/privacidade.html').readAsStringSync();
  final deletion = File('site/excluir-conta.html').readAsStringSync();
  final workflow = File('.github/workflows/pages.yml').readAsStringSync();

  final mailto = RegExp(r'mailto:([^"?\s]+@[^"?\s]+\.[A-Za-z]{2,})');

  group('privacy policy', () {
    test('policy_names_the_controller_and_the_contact', () {
      expect(policy, contains('Lucas Gonçalves'));
      expect(
        mailto.hasMatch(policy),
        isTrue,
        reason: 'the policy names no contact e-mail for data requests',
      );
    });

    test('policy_says_records_stay_on_the_device', () {
      for (final data in [
        'fotografias',
        'coordenadas',
        'endereço',
        'classe de textura',
      ]) {
        expect(policy, contains(data), reason: 'the policy omits "$data"');
      }
      expect(policy, contains('somente no seu aparelho'));
      expect(policy, contains('não tem servidor'));
    });

    test('policy_names_each_way_data_leaves_the_device', () {
      expect(policy, contains('geocodificação'));
      expect(policy, contains('Google'));
      expect(policy, contains('nome e e-mail'));
      expect(policy, contains('compartilhar'));
      expect(policy, contains('localização só'));
      expect(policy, contains('relatório de erros'));
    });

    test('policy_says_there_is_no_analytics_or_advertising', () {
      expect(policy, contains('análise de uso'));
      expect(policy, contains('publicidade'));
    });

    test('policy_says_how_to_delete_and_links_the_deletion_page', () {
      expect(policy, contains('Apagar todos os dados'));
      expect(policy, contains('Excluir conta'));
      expect(policy, contains('desinstalar'));
      expect(policy, contains('art. 18'));
      expect(policy, contains('href="excluir-conta.html"'));
    });

    test('policy_carries_its_effective_date', () {
      expect(policy, matches(RegExp(r'Vigente desde \d{1,2} de \S+ de \d{4}')));
    });
  });

  group('account deletion page', () {
    test('deletion_page_works_without_the_app', () {
      expect(deletion, contains('Excluir conta'));
      expect(deletion, contains('myaccount.google.com/connections'));
      expect(deletion, contains('desinstalar'));
      expect(deletion, contains('href="privacidade.html"'));
      final policyContact = mailto.firstMatch(policy)?.group(1);
      final deletionContact = mailto.firstMatch(deletion)?.group(1);
      expect(
        deletionContact,
        isNotNull,
        reason: 'the deletion page names no contact e-mail',
      );
      expect(
        deletionContact,
        policyContact,
        reason: 'the two pages name different contacts',
      );
    });
  });

  group('both pages', () {
    final pages = {'privacidade.html': policy, 'excluir-conta.html': deletion};

    test('pages_load_nothing_from_another_origin', () {
      // A link the reader follows is fine; a resource the page loads is not.
      for (final MapEntry(key: name, value: html) in pages.entries) {
        expect(html, isNot(contains('<script')), reason: '$name has a script');
        expect(html, isNot(contains('<link')), reason: '$name loads a file');
        expect(html, isNot(contains('src=')), reason: '$name embeds a file');
        expect(html, isNot(contains('@import')), reason: '$name imports CSS');
        expect(html, isNot(contains('url(')), reason: '$name loads a URL');
      }
    });

    test('pages_are_brazilian_portuguese', () {
      for (final MapEntry(key: name, value: html) in pages.entries) {
        expect(html, contains('<html lang="pt-BR">'), reason: name);
        expect(html, contains('<meta charset="utf-8">'), reason: name);
      }
    });
  });

  group('pages workflow', () {
    test('workflow_publishes_only_site_from_main', () {
      final triggers = RegExp(
        r'^on:\n((?:[ ]+.*\n|\n)*)',
        multiLine: true,
      ).firstMatch(workflow)?.group(1);
      expect(triggers, isNotNull, reason: 'the workflow has no "on:" block');
      expect(triggers, contains('push:'));
      expect(triggers, contains('branches: [main]'));
      expect(triggers, contains('workflow_dispatch:'));
      expect(triggers, isNot(contains('pull_request')));
      expect(workflow, contains('path: site'));

      final permissions =
          RegExp(r'^permissions:\n((?:[ ]+.*\n)*)', multiLine: true)
              .firstMatch(workflow)
              ?.group(1)
              ?.split('\n')
              .map((line) => line.trim())
              .where((line) => line.isNotEmpty)
              .toSet();
      expect(permissions, {
        'contents: read',
        'pages: write',
        'id-token: write',
      });
      expect(
        RegExp(r'^[ ]+permissions:', multiLine: true).hasMatch(workflow),
        isFalse,
        reason: 'a job widens the workflow token',
      );
    });

    test('workflow_pins_each_action_to_a_commit', () {
      final uses = RegExp(r'uses:\s*(\S+)').allMatches(workflow).toList();
      expect(uses, isNotEmpty);
      for (final use in uses) {
        expect(
          use.group(1),
          matches(RegExp(r'^[\w.-]+/[\w.-]+@[0-9a-f]{40}$')),
          reason: '${use.group(1)} is not pinned to a commit',
        );
      }
    });
  });
}
