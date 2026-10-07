# 💰 [app_financeiro] — Controle Financeiro Pessoal

Aplicativo mobile em Flutter para controle financeiro pessoal: despesas fixas,
despesas variáveis (água, luz), cartões de crédito com faturas, projeção de
saldo em meses futuros e relatórios em PDF.

## ✨ Funcionalidades

- 📊 Resumo financeiro por mês (receitas, despesas, saldo)
- 🔁 Despesas fixas e fixas de valor variável (água, luz)
- 💳 Cartões de crédito com limite, faturas e parcelas
- 📅 Projeção de saldo em meses futuros
- 📈 Gráficos de gastos por categoria
- 📄 Exportação de relatório em PDF

## 🛠️ Tecnologias

- Flutter / Dart
- SQLite (sqflite)

## 🚀 Como rodar

```bash
flutter pub get
flutter run

📁 Estrutura
lib/screens/ — telas do app
lib/models/ — modelos de dados
lib/repositories/ — acesso ao banco de dados
lib/database/ — criação e migração do banco
lib/services/ — serviços (exportação PDF)