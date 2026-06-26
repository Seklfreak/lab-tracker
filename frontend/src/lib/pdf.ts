// Letter-sized PDF export via jsPDF. jsPDF + autotable are dynamically imported so
// they stay out of the main bundle and only load when a PDF is actually generated.

interface PdfOpts {
  filename: string;
  title: string;
  subtitle?: string;
  head: string[];
  rows: (string | number)[][];
  notesTitle?: string;
  notes?: string; // markdown-ish: headings/bullets rendered, other syntax stripped
}

// Strip inline markdown emphasis/code markers.
function clean(s: string): string {
  return s.replace(/\*\*/g, "").replace(/`/g, "").replace(/(?<!\w)[*_](?!\s)/g, "");
}

export async function exportTablePdf(opts: PdfOpts): Promise<void> {
  const { jsPDF } = await import("jspdf");
  const autoTable = (await import("jspdf-autotable")).default;

  const doc = new jsPDF({ unit: "pt", format: "letter" });
  const margin = 48;
  const pageW = doc.internal.pageSize.getWidth();
  const pageH = doc.internal.pageSize.getHeight();
  let y = margin;

  doc.setFont("helvetica", "bold");
  doc.setFontSize(16);
  doc.text(opts.title, margin, y);
  y += 18;
  if (opts.subtitle) {
    doc.setFont("helvetica", "normal");
    doc.setFontSize(10);
    doc.setTextColor(110);
    doc.text(opts.subtitle, margin, y);
    doc.setTextColor(0);
    y += 8;
  }

  autoTable(doc, {
    startY: y + 8,
    head: [opts.head],
    body: opts.rows,
    styles: { fontSize: 9, cellPadding: 4 },
    headStyles: { fillColor: [47, 111, 237] },
    margin: { left: margin, right: margin },
  });

  if (opts.notes && opts.notes.trim()) {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    let ny = (doc as any).lastAutoTable.finalY + 26;
    const writeBlock = (text: string, size: number, bold: boolean, gapAfter: number) => {
      doc.setFont("helvetica", bold ? "bold" : "normal");
      doc.setFontSize(size);
      for (const ln of doc.splitTextToSize(text, pageW - margin * 2)) {
        if (ny > pageH - margin) {
          doc.addPage();
          ny = margin;
        }
        doc.text(ln, margin, ny);
        ny += size + 4;
      }
      ny += gapAfter;
    };

    if (opts.notesTitle) writeBlock(opts.notesTitle, 13, true, 4);
    for (const raw of opts.notes.split("\n")) {
      const line = raw.trimEnd();
      if (!line.trim()) {
        ny += 6;
        continue;
      }
      const heading = line.match(/^#{1,6}\s+(.*)/);
      const bullet = line.match(/^\s*[-*]\s+(.*)/);
      if (heading) writeBlock(clean(heading[1]), 12, true, 2);
      else if (bullet) writeBlock("•  " + clean(bullet[1]), 10, false, 0);
      else writeBlock(clean(line), 10, false, 0);
    }
  }

  doc.save(opts.filename);
}
