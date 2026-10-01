import type { ReportFormat } from '../report.types.js';
import { CsvReportExporter } from './csv.exporter.js';
import { JsonReportExporter } from './json.exporter.js';
import type { ReportExporter } from './report-exporter.js';
import { XlsxReportExporter } from './xlsx.exporter.js';

export { CsvReportExporter, JsonReportExporter, XlsxReportExporter };
export type { ReportExporter };

/** Looks up the exporter for a format. Adding PDF later = one new ReportExporter subclass registered here. */
export class ReportExporterRegistry {
  private readonly byFormat: Map<ReportFormat, ReportExporter>;

  constructor(
    exporters: ReportExporter[] = [new JsonReportExporter(), new XlsxReportExporter(), new CsvReportExporter()],
  ) {
    this.byFormat = new Map(exporters.map((exporter) => [exporter.format, exporter]));
  }

  get(format: ReportFormat): ReportExporter {
    const exporter = this.byFormat.get(format);
    if (!exporter) throw new Error(`No exporter registered for format ${format}`);
    return exporter;
  }
}
