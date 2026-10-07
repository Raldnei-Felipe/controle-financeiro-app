import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    _database = await _openDatabase();
    return _database!;
  }

  Future<Database> _openDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'app_financeiro.db');

    return openDatabase(
      path,
      version: 7,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _createDatabase,
      onUpgrade: (db, oldVersion, newVersion) async {
        await _ensureCurrentSchema(db);
      },
      onOpen: _ensureCurrentSchema,
    );
  }

  Future<void> _createDatabase(Database db, int version) async {
    await db.execute('''
      CREATE TABLE incomes (
        id TEXT PRIMARY KEY,
        description TEXT NOT NULL,
        amount REAL NOT NULL,
        date TEXT NOT NULL,
        is_recurring INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'received',
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        color_value INTEGER NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await _createCreditCardsTable(db);
    await _createFixedExpensePaymentsTable(db);

    await db.execute('''
      CREATE TABLE expenses (
        id TEXT PRIMARY KEY,
        description TEXT NOT NULL,
        amount REAL NOT NULL,
        date TEXT NOT NULL,
        category_id TEXT NOT NULL,
        is_fixed INTEGER NOT NULL DEFAULT 0,
        is_variable INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'pending',
        payment_method TEXT NOT NULL DEFAULT 'cash',
        card_id TEXT,
        installment_group_id TEXT,
        installment_number INTEGER NOT NULL DEFAULT 1,
        installment_count INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        FOREIGN KEY (category_id) REFERENCES categories(id),
        FOREIGN KEY (card_id) REFERENCES credit_cards(id)
      )
    ''');

    await _createCardInvoicesTable(db);
    await _insertDefaultCategories(db);
  }

  Future<void> _ensureCurrentSchema(Database db) async {
    await _createCreditCardsTableIfMissing(db);
    await _createFixedExpensePaymentsTableIfMissing(db);
    await _createCardInvoicesTableIfMissing(db);

    final columns = await db.rawQuery('PRAGMA table_info(expenses)');

    final columnNames = columns
        .map((column) => column['name'] as String)
        .toSet();

    if (!columnNames.contains('payment_method')) {
      await db.execute(
        "ALTER TABLE expenses "
            "ADD COLUMN payment_method TEXT NOT NULL DEFAULT 'cash'",
      );
    }

    if (!columnNames.contains('card_id')) {
      await db.execute('ALTER TABLE expenses ADD COLUMN card_id TEXT');
    }

    if (!columnNames.contains('installment_group_id')) {
      await db.execute(
        'ALTER TABLE expenses '
            'ADD COLUMN installment_group_id TEXT',
      );
    }

    if (!columnNames.contains('installment_number')) {
      await db.execute(
        'ALTER TABLE expenses '
            'ADD COLUMN installment_number INTEGER NOT NULL DEFAULT 1',
      );
    }

    if (!columnNames.contains('installment_count')) {
      await db.execute(
        'ALTER TABLE expenses '
            'ADD COLUMN installment_count INTEGER NOT NULL DEFAULT 1',
      );
    }

    // ── [NOVO v7] Despesa fixa com valor variável (ex.: água, luz) ──
    if (!columnNames.contains('is_variable')) {
      await db.execute(
        'ALTER TABLE expenses '
            'ADD COLUMN is_variable INTEGER NOT NULL DEFAULT 0',
      );
    }

    await db.execute('''
  CREATE TABLE IF NOT EXISTS recurring_rules (
    id TEXT PRIMARY KEY,
    transaction_type TEXT NOT NULL,
    description TEXT NOT NULL,
    amount REAL NOT NULL,
    category_id TEXT,
    is_fixed INTEGER NOT NULL DEFAULT 0,
    day_of_month INTEGER NOT NULL,
    start_date TEXT NOT NULL,
    next_due_date TEXT NOT NULL,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL
  )
''');

    final incomeColumns = await db.rawQuery('PRAGMA table_info(incomes)');

    final incomeColumnNames = incomeColumns
        .map((column) => column['name'] as String)
        .toSet();

    if (!incomeColumnNames.contains('recurrence_rule_id')) {
      await db.execute(
        'ALTER TABLE incomes ADD COLUMN recurrence_rule_id TEXT',
      );
    }

    if (!incomeColumnNames.contains('recurrence_month_key')) {
      await db.execute(
        'ALTER TABLE incomes ADD COLUMN recurrence_month_key TEXT',
      );
    }

    final expenseColumns = await db.rawQuery('PRAGMA table_info(expenses)');

    final expenseColumnNames = expenseColumns
        .map((column) => column['name'] as String)
        .toSet();

    if (!expenseColumnNames.contains('recurrence_rule_id')) {
      await db.execute(
        'ALTER TABLE expenses ADD COLUMN recurrence_rule_id TEXT',
      );
    }

    if (!expenseColumnNames.contains('recurrence_month_key')) {
      await db.execute(
        'ALTER TABLE expenses ADD COLUMN recurrence_month_key TEXT',
      );
    }

    // ── [NOVO v7] Valor mensal das despesas variáveis ──
    final paymentColumns =
    await db.rawQuery('PRAGMA table_info(fixed_expense_payments)');

    final paymentColumnNames = paymentColumns
        .map((column) => column['name'] as String)
        .toSet();

    if (!paymentColumnNames.contains('amount')) {
      await db.execute(
        'ALTER TABLE fixed_expense_payments '
            'ADD COLUMN amount REAL NOT NULL DEFAULT 0',
      );
    }

    await db.execute('''
  CREATE UNIQUE INDEX IF NOT EXISTS
  unique_income_recurrence_month
  ON incomes (recurrence_rule_id, recurrence_month_key)
''');

    await db.execute('''
  CREATE UNIQUE INDEX IF NOT EXISTS
  unique_expense_recurrence_month
  ON expenses (recurrence_rule_id, recurrence_month_key)
''');
  }

  Future<void> _createCreditCardsTable(Database db) async {
    await db.execute('''
      CREATE TABLE credit_cards (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        issuer TEXT NOT NULL,
        credit_limit REAL NOT NULL,
        closing_day INTEGER NOT NULL,
        due_day INTEGER NOT NULL,
        color_value INTEGER NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createCreditCardsTableIfMissing(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS credit_cards (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        issuer TEXT NOT NULL,
        credit_limit REAL NOT NULL,
        closing_day INTEGER NOT NULL,
        due_day INTEGER NOT NULL,
        color_value INTEGER NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createCardInvoicesTable(Database db) async {
    await db.execute('''
      CREATE TABLE card_invoices (
        card_id TEXT NOT NULL,
        month_key TEXT NOT NULL,
        due_date TEXT NOT NULL,
        is_paid INTEGER NOT NULL DEFAULT 0,
        paid_at TEXT,
        PRIMARY KEY (card_id, month_key),
        FOREIGN KEY (card_id) REFERENCES credit_cards(id)
      )
    ''');
  }

  Future<void> _createFixedExpensePaymentsTable(Database db) async {
    await db.execute('''
      CREATE TABLE fixed_expense_payments (
        expense_id TEXT NOT NULL,
        month_key TEXT NOT NULL,
        is_paid INTEGER NOT NULL DEFAULT 0,
        amount REAL NOT NULL DEFAULT 0,
        paid_at TEXT,
        PRIMARY KEY (expense_id, month_key),
        FOREIGN KEY (expense_id) REFERENCES expenses(id)
      )
    ''');
  }

  Future<void> _createFixedExpensePaymentsTableIfMissing(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS fixed_expense_payments (
        expense_id TEXT NOT NULL,
        month_key TEXT NOT NULL,
        is_paid INTEGER NOT NULL DEFAULT 0,
        amount REAL NOT NULL DEFAULT 0,
        paid_at TEXT,
        PRIMARY KEY (expense_id, month_key),
        FOREIGN KEY (expense_id) REFERENCES expenses(id)
      )
    ''');
  }

  Future<void> _createCardInvoicesTableIfMissing(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS card_invoices (
        card_id TEXT NOT NULL,
        month_key TEXT NOT NULL,
        due_date TEXT NOT NULL,
        is_paid INTEGER NOT NULL DEFAULT 0,
        paid_at TEXT,
        PRIMARY KEY (card_id, month_key),
        FOREIGN KEY (card_id) REFERENCES credit_cards(id)
      )
    ''');
  }

  Future<void> _insertDefaultCategories(Database db) async {
    await db.insert('categories', {
      'id': 'category-food',
      'name': 'Alimentação',
      'color_value': 0xFFFF9800,
      'is_active': 1,
    });

    await db.insert('categories', {
      'id': 'category-transport',
      'name': 'Transporte',
      'color_value': 0xFF2196F3,
      'is_active': 1,
    });

    await db.insert('categories', {
      'id': 'category-home',
      'name': 'Casa',
      'color_value': 0xFF4CAF50,
      'is_active': 1,
    });

    await db.insert('categories', {
      'id': 'category-other',
      'name': 'Outros',
      'color_value': 0xFF9E9E9E,
      'is_active': 1,
    });
  }

  Future<void> close() async {
    final currentDatabase = _database;

    if (currentDatabase == null) {
      return;
    }

    await currentDatabase.close();
    _database = null;
  }
}