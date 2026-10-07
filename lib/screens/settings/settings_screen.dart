import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../services/backup_service.dart';
import '../../services/security_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final BackupService backupService = BackupService();
  final SecurityService securityService = SecurityService();

  bool isWorking = false;

  bool hasPin = false;
  bool biometricEnabled = false;
  bool isLoadingSecurity = true;

  @override
  void initState() {
    super.initState();
    _loadSecurityState();
  }

  Future<void> _loadSecurityState() async {
    final pinExists = await securityService.hasPin();
    final biometric = await securityService.isBiometricEnabled();

    if (!mounted) {
      return;
    }

    setState(() {
      hasPin = pinExists;
      biometricEnabled = biometric;
      isLoadingSecurity = false;
    });
  }

  Future<void> _backup() async {
    await _runAction(
      action: backupService.createAndShareBackup,
      successMessage: 'Backup gerado.',
    );
  }

  Future<void> _restore() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Restaurar backup'),
          content: const Text(
            'Todos os dados atuais serão substituídos '
            'pelos dados do arquivo de backup. '
            'Deseja continuar?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Restaurar'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    await _runAction(
      action: backupService.restoreFromBackup,
      successMessage: 'Backup restaurado. Reinicie o aplicativo.',
    );
  }

  Future<void> _runAction({
    required Future<void> Function() action,
    required String successMessage,
  }) async {
    if (isWorking) {
      return;
    }

    setState(() {
      isWorking = true;
    });

    try {
      await action();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (error) {
      if (!mounted) {
        return;
      }

      final message = error is StateError
          ? error.message
          : 'Não foi possível concluir a operação.';

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() {
          isWorking = false;
        });
      }
    }
  }

  Future<void> _definePin() async {
    final pinController = TextEditingController();
    final confirmController = TextEditingController();

    String? newPin;

    try {
      newPin = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          void save() {
            final pin = pinController.text.trim();
            final confirm = confirmController.text.trim();

            if (pin.length != 4) {
              _showMessage('O PIN deve ter 4 dígitos.');
              return;
            }

            if (pin != confirm) {
              _showMessage('Os PINs digitados não são iguais.');
              return;
            }

            Navigator.of(dialogContext).pop(pin);
          }

          return AlertDialog(
            title: Text(hasPin ? 'Alterar PIN' : 'Definir PIN'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: pinController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'PIN (4 dígitos)',
                    ),
                  ),
                  TextField(
                    controller: confirmController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Confirmar PIN',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton(onPressed: save, child: const Text('Salvar')),
            ],
          );
        },
      );

      if (newPin == null || !mounted) {
        return;
      }

      await securityService.savePin(newPin);

      await _loadSecurityState();

      if (!mounted) {
        return;
      }

      _showMessage('PIN salvo com sucesso.');
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage('Não foi possível salvar o PIN.');
    } finally {
      pinController.dispose();
      confirmController.dispose();
    }
  }

  Future<void> _removePin() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Remover PIN'),
          content: const Text(
            'O app deixará de pedir PIN e biometria '
            'ao ser aberto. Deseja continuar?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Remover'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    await securityService.removePin();

    await _loadSecurityState();

    if (!mounted) {
      return;
    }

    _showMessage('Proteção removida.');
  }

  Future<void> _toggleBiometric(bool value) async {
    if (value) {
      final canUse = await securityService.canUseBiometrics();

      if (!canUse) {
        _showMessage('Este dispositivo não suporta biometria.');
        return;
      }

      final authenticated = await securityService.authenticateWithBiometrics();

      if (!authenticated) {
        _showMessage('Biometria não confirmada. Tente novamente.');
        return;
      }
    }

    await securityService.setBiometricEnabled(value);

    await _loadSecurityState();
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildBackupCard(),
          const SizedBox(height: 16),
          _buildSecurityCard(),
        ],
      ),
    );
  }

  Widget _buildBackupCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.backup_outlined, color: AppColors.orange),
                SizedBox(width: 10),
                Text(
                  'Backup e restauração',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'O backup inclui receitas, despesas, '
              'categorias, cartões e faturas em um '
              'único arquivo. Guarde-o em local seguro.',
              style: TextStyle(color: AppColors.gray),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: isWorking ? null : _backup,
                icon: const Icon(Icons.save_alt),
                label: const Text('Gerar backup'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: isWorking ? null : _restore,
                icon: const Icon(Icons.restore),
                label: const Text('Restaurar backup'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecurityCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.security_outlined, color: AppColors.orange),
                SizedBox(width: 10),
                Text(
                  'Segurança',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Proteja a abertura do app com um PIN de '
              '4 dígitos e, se preferir, desbloqueie '
              'com a digital.',
              style: TextStyle(color: AppColors.gray),
            ),
            const SizedBox(height: 16),
            if (isLoadingSecurity)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _definePin,
                  icon: const Icon(Icons.pin_outlined),
                  label: Text(hasPin ? 'Alterar PIN' : 'Definir PIN'),
                ),
              ),
              if (hasPin) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Desbloquear com biometria'),
                  subtitle: const Text('Usa digital ou reconhecimento facial'),
                  value: biometricEnabled,
                  onChanged: _toggleBiometric,
                ),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _removePin,
                    icon: const Icon(Icons.lock_open),
                    label: const Text('Remover PIN'),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
