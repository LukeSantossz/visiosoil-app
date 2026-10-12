import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Pins the privacy policy and the account deletion page that Google Play links
/// to, and the workflow that publishes them (SPEC 0156, #276, #278).
///
/// The pages state what the build does. These tests pin the claims, not the
/// code, so a change that sends data somewhere new still has to update the
/// policy by review.
void main() {
  // A Windows checkout may carry CRLF; every pattern below expects LF.
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');
  final policy = read('site/privacidade.html');
  final deletion = read('site/excluir-conta.html');
  final workflow = read('.github/workflows/pages.yml');

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

    // The address is looked up when a capture has a fix, before it is saved,
    // not only when a record is shown (capture_screen.dart, _defaultLocate).
    test('policy_says_geocoding_runs_at_capture', () {
      expect(policy, contains('Quando uma captura tem localização'));
    });

    // An address in an error message survives redaction; SPEC 0110 accepted
    // that risk on the condition that the policy says so.
    test('policy_says_an_error_report_may_carry_fragments', () {
      expect(policy, contains('pode conter trechos da mensagem do erro'));
    });

    // A JPEG the EXIF parser cannot read is stored as it came (ADR 0005).
    test('policy_does_not_overstate_the_exif_strip', () {
      expect(policy, contains('JPEG'));
      expect(policy, contains('guardada como veio'));
    });

    test('policy_says_there_is_no_analytics_or_advertising', () {
      expect(
        policy,
        contains('não usa ferramentas de análise de uso, não exibe publicidade'),
      );
    });

    // Google and the share recipients keep what they received under their
    // own policies, so neither page may claim nothing is kept anywhere.
    test('pages_do_not_claim_nothing_is_kept_elsewhere', () {
      expect(policy, contains('seguem as próprias políticas'));
      expect(deletion, contains('seguem as próprias políticas'));
      expect(policy, isNot(contains('Não há cópia em outro lugar')));
      expect(deletion, isNot(contains('<p>Nada.')));
    });

    // Deleting the account clears the session even when Google does not
    // confirm the revoke (SPEC 0113), so both pages say where to finish it.
    test('pages_say_what_to_do_when_the_revoke_is_not_confirmed', () {
      expect(policy, contains('não confirmar a revogação'));
      expect(deletion, contains('não confirmar a revogação'));
    });

    test('policy_says_how_to_delete_and_links_the_deletion_page', () {
      expect(policy, contains('Apagar todos os dados'));
      expect(policy, contains('Excluir conta'));
      expect(policy, contains('desinstalar'));
      expect(policy, contains('art. 18'));
      // Art. 18, VIII: what withholding consent means.
      expect(policy, contains('não fornecer consentimento'));
      expect(policy, contains('href="excluir-conta.html"'));
    });

    test('policy_carries_its_effective_date', () {
      expect(
        policy,
        matches(RegExp(
          r'Vigente desde \d{1,2} de (janeiro|fevereiro|março|abril|maio|junho|'
          r'julho|agosto|setembro|outubro|novembro|dezembro) de \d{4}',
        )),
      );
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
      // A link the reader follows is fine; a resource the page loads, or a
      // redirect, is not.
      const loaders = [
        '<script', '<link', '<base', '<iframe', '<object', '<embed', '<form',
        'src=', 'srcset', 'http-equiv', '@import', 'url(',
      ];
      for (final MapEntry(key: name, value: html) in pages.entries) {
        final lower = html.toLowerCase();
        for (final loader in loaders) {
          expect(lower, isNot(contains(loader)), reason: '$name has $loader');
        }
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
      for (final other in ['pull_request', 'schedule', 'workflow_run']) {
        expect(triggers, isNot(contains(other)), reason: other);
      }
      expect(
        RegExp(r'^\s+path: site$', multiLine: true).hasMatch(workflow),
        isTrue,
        reason: 'the artifact is not site/ alone',
      );
      expect(workflow, contains('uses: actions/upload-pages-artifact@'));
      expect(workflow, contains('uses: actions/deploy-pages@'));
      // workflow_dispatch can run from any branch, so the job refuses one.
      expect(workflow, contains("if: github.ref == 'refs/heads/main'"));
      expect(workflow, contains('name: github-pages'));
      expect(workflow, contains('persist-credentials: false'));

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
