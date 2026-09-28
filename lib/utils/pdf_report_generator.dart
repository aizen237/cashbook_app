import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../providers/report_provider.dart';

Future<void> generateAndShareReportPdf({
  required ReportResult result,
  required String projectName,
  DateTime? fromDate,
  DateTime? toDate,
  String? descriptionQuery,
}) async {
  final doc = pw.Document();

  String formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  doc.addPage(
    pw.MultiPage(
      build: (context) => [
        pw.Header(
          level: 0,
          child: pw.Text('Cashbook Report', style: const pw.TextStyle(fontSize: 24)),
        ),
        pw.SizedBox(height: 8),
        pw.Text('Project: $projectName'),
        if (fromDate != null || toDate != null)
          pw.Text(
            'Date range: ${fromDate != null ? formatDate(fromDate) : 'Start'} to ${toDate != null ? formatDate(toDate) : 'Now'}',
          ),
        if (descriptionQuery != null && descriptionQuery.isNotEmpty)
          pw.Text('Description filter: "$descriptionQuery"'),
        pw.SizedBox(height: 16),

        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Total Income: ETB ${result.totalIncome.toStringAsFixed(2)}'),
            pw.Text('Total Expense: ETB ${result.totalExpense.toStringAsFixed(2)}'),
            pw.Text('Net: ETB ${result.netBalance.toStringAsFixed(2)}'),
          ],
        ),
        pw.SizedBox(height: 16),
        pw.Divider(),

        pw.Table(
          border: pw.TableBorder.all(width: 0.5),
          columnWidths: const {
            0: pw.FlexColumnWidth(2),
            1: pw.FlexColumnWidth(3),
            2: pw.FlexColumnWidth(2),
            3: pw.FlexColumnWidth(2),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey300),
              children: [
                pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Date', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Description', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Type', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Amount', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
              ],
            ),
            ...result.transactions.map(
                  (t) => pw.TableRow(
                children: [
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(formatDate(t.date))),
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(t.description ?? '')),
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(t.type)),
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(t.amount.toStringAsFixed(2))),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );

  await Printing.sharePdf(
    bytes: await doc.save(),
    filename: 'cashbook_report_${DateTime.now().millisecondsSinceEpoch}.pdf',
  );
}