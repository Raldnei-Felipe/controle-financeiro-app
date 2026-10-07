import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/card_invoice.dart';
import '../models/expense.dart';
import '../repositories/card_invoice_repository.dart';
import '../repositories/card_repository.dart';
import '../repositories/expense_repository.dart';
import '../repositories/income_repository.dart';
import '../models/income.dart';

class PdfExportService {
  final IncomeRepository incomeRepository;
  final ExpenseRepository expenseRepository;
  final CardRepository cardRepository;
  final CardInvoiceRepository invoiceRepository;

  PdfExportService({
    IncomeRepository? incomeRepository,
    ExpenseRepository? expenseRepository,
    CardRepository? cardRepository,
    CardInvoiceRepository? invoiceRepository,
  })  : incomeRepository = incomeRepository ?? IncomeRepository(),
        expenseRepository = expenseRepository ?? ExpenseRepository(),
        cardRepository = cardRepository ?? CardRepository(),
        invoiceRepository = invoiceRepository ?? CardInvoiceRepository();

  Future<String?> exportAndShare({
    DateTime? referenceMonth,
  }) async {
    final month = _monthOf(referenceMonth ?? DateTime.now());


    // Mesma regra das telas: em mês futuro soma recorrentes + manuais do mês.
    final incomeTotal = await _incomeTotalFor(month);

    final allExpenses = await expenseRepository.findByMonth(month);
    final projectedExpenses =
    await expenseRepository.findByMonthWithProjectedFixed(month);

    // Fixas (reais + projetadas nos meses futuros).
    final fixedList = projectedExpenses
        .where((expense) => expense.isFixed)
        .toList();

    // Diárias: Pix/Débito/Dinheiro — sem cartão e sem fixas.
    final variableList = allExpenses
        .where(
          (expense) =>
      expense.paymentMethod != 'card' && !expense.isFixed,
    )
        .toList();

    final fixedTotal =
    fixedList.fold<double>(0, (sum, e) => sum + e.amount);
    final variableTotal =
    variableList.fold<double>(0, (sum, e) => sum + e.amount);

    // Faturas de cartão que vencem no mês (com status pago/pendente).
    final cardInvoices = await _cardInvoicesDueIn(month);
    final cardDueTotal = cardInvoices.fold<double>(
      0,
          (sum, invoice) => sum + invoice.total,
    );

    final expenseTotal = fixedTotal + variableTotal + cardDueTotal;

    final incomes = await incomeRepository.findByMonth(month);

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) {
          return [
            _header(month),
            _summary(
              incomeTotal: incomeTotal,
              expenseTotal: expenseTotal,
            ),
            _sectionTitle('Receitas'),
            _incomeTable(incomes),
            _sectionTitle('Despesas do mês — ${_monthLabel(month)}'),
            _expenseTable(
              month,
              fixedList,
              variableList,
            ),
            _sectionTitle('Cartões — faturas que vencem em ${_monthLabel(month)}'),
            _cardInvoicesSection(cardInvoices),
            _sectionTitle('Composição das despesas'),
            _composition(
              fixedTotal: fixedTotal,
              variableTotal: variableTotal,
              cardDueTotal: cardDueTotal,
              expenseTotal: expenseTotal,
            ),
          ];
        },
      ),
    );
    final bytes = await pdf.save();
    final fileName =
        'relatorio_financeiro_${month.year}-${month.month.toString().padLeft(2, '0')}.pdf';
    final savedPath = await FilePicker.saveFile(
      fileName: fileName,
      bytes: bytes,
    );
    return savedPath?.toString();
  }
  Future<double> _incomeTotalFor(DateTime month) async {
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month, 1);
    if (month.isAfter(currentMonth)) {
      final recurring = await incomeRepository.recurringTotal();
      final manual = await incomeRepository.nonRecurringTotalByMonth(month);
      return recurring + manual;
    }
    return incomeRepository.totalByMonth(month);
  }
  DateTime _monthOf(DateTime date) {
    return DateTime(date.year, date.month, 1);
  }

  // Faturas de cartão cuja DATA DE VENCIMENTO está no mês informado.
  Future<List<CardInvoice>> _cardInvoicesDueIn(DateTime month) async {
    final cards = await cardRepository.findAll();
    final invoices = <CardInvoice>[];
    for (final card in cards) {
      final cardInvoices = await invoiceRepository.findByCard(card);
      for (final invoice in cardInvoices) {
        if (invoice.dueDate.year == month.year &&
            invoice.dueDate.month == month.month) {
          invoices.add(invoice);
        }
      }
    }
    invoices.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return invoices;
  }

  pw.Widget _header(DateTime month) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Relatório Financeiro',
          style: pw.TextStyle(
            fontSize: 20,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.Text(
          'Mês de referência: ${_monthLabel(month)}',
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.Text(
          'Gerado em ${_date(DateTime.now())}',
          style: const pw.TextStyle(
            fontSize: 10,
            color: PdfColors.grey700,
          ),
        ),
        pw.SizedBox(height: 16),
      ],
    );
  }

  pw.Widget _summary({
    required double incomeTotal,
    required double expenseTotal,
  }) {
    final balance = incomeTotal - expenseTotal;
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          _summaryItem(
            'Receitas (total)',
            _money(incomeTotal),
            PdfColors.green700,
          ),
          _summaryItem(
            'Despesas (mês)',
            _money(expenseTotal),
            PdfColors.red700,
          ),
          _summaryItem(
            'Saldo',
            _money(balance),
            balance >= 0 ? PdfColors.green700 : PdfColors.red700,
          ),
        ],
      ),
    );
  }

  pw.Widget _summaryItem(String label, String value, PdfColor color) {
    return pw.Column(
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  pw.Widget _sectionTitle(String title) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 18, bottom: 8),
      child: pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: 14,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  pw.Widget _tableHeader(List<String> cells) {
    return pw.Container(
      color: PdfColors.grey300,
      padding: const pw.EdgeInsets.all(5),
      child: pw.Row(
        children: cells
            .map(
              (cell) => pw.Expanded(
            child: pw.Text(
              cell,
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        )
            .toList(),
      ),
    );
  }

  pw.Widget _tableRow(List<String> cells) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(5),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.grey300, width: .5),
        ),
      ),
      child: pw.Row(
        children: cells
            .map(
              (cell) => pw.Expanded(
            child: pw.Text(
              cell,
              style: const pw.TextStyle(fontSize: 9),
            ),
          ),
        )
            .toList(),
      ),
    );
  }

  pw.Widget _incomeTable(List<Income> incomes) {
    if (incomes.isEmpty) {
      return _empty('Nenhuma receita cadastrada no mês.');
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _tableHeader(['Descrição', 'Valor', 'Data', 'Status']),
        ...incomes.map((income) {
          return _tableRow([
            income.description,
            _money(income.amount),
            _date(income.date),
            income.status,
          ]);
        }),
      ],
    );
  }

  pw.Widget _expenseTable(
      DateTime month,
      List<Expense> fixedList,
      List<Expense> variableList,
      ) {
    final expenses = [...fixedList, ...variableList];
    if (expenses.isEmpty) {
      return _empty('Nenhuma despesa no mês selecionado.');
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _tableHeader([
          'Descrição',
          'Valor',
          'Data',
          'Tipo',
          'Status',
        ]),
        ...expenses.map((expense) {
          return _tableRow([
            expense.description,
            _money(expense.amount),
            _date(expense.date),
            expense.isVariable
                ? 'Fixa variável'
                : expense.isFixed
                ? 'Fixa'
                : 'Pix/Débito',
            expense.status == 'paid' ? 'Pago' : 'Pendente',
          ]);
        }),
      ],
    );
  }

  pw.Widget _cardInvoicesSection(List<CardInvoice> invoices) {
    if (invoices.isEmpty) {
      return _empty(
        'Nenhuma fatura de cartão vence neste mês.',
      );
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: invoices.map((invoice) {
        final status = invoice.isPaid ? 'Pago' : 'Em aberto';
        final statusColor =
        invoice.isPaid ? PdfColors.green700 : PdfColors.orange700;
        return pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 10),
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    invoice.cardName,
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    'Vencimento: ${_date(invoice.dueDate)}',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    _money(invoice.total),
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    status,
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  pw.Widget _composition({
    required double fixedTotal,
    required double variableTotal,
    required double cardDueTotal,
    required double expenseTotal,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _compositionLine('Despesas fixas', fixedTotal, expenseTotal),
        _compositionLine('Despesas diárias (Pix/Débito)', variableTotal, expenseTotal),
        _compositionLine('Cartões (faturas do mês)', cardDueTotal, expenseTotal),
        pw.SizedBox(height: 4),
        _compositionLine('Total', expenseTotal, expenseTotal),
      ],
    );
  }

  pw.Widget _compositionLine(String label, double value, double total) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
        pw.Text(
          _money(value),
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    );
  }

  pw.Widget _empty(String message) {
    return pw.Text(
      message,
      style: const pw.TextStyle(
        fontSize: 9,
        color: PdfColors.grey700,
      ),
    );
  }

  String _money(double value) {
    final integer = value.floor();
    final cents = ((value - integer) * 100).round();
    final integerText = integer.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
          (match) => '${match[1]}.',
    );
    return 'R\$ $integerText,${cents.toString().padLeft(2, '0')}';
  }

  String _date(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  String _monthLabel(DateTime month) {
    const months = [
      'Janeiro', 'Fevereiro', 'Março', 'Abril',
      'Maio', 'Junho', 'Julho', 'Agosto',
      'Setembro', 'Outubro', 'Novembro', 'Dezembro',
    ];
    return '${months[month.month - 1]}/${month.year}';
  }
}