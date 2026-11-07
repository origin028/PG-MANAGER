"""Minimal dependency-free PDF generation utilities.

Produces standards-compliant PDF 1.4 documents (correct cross-reference table
offsets) for simple text based documents such as payment receipts.
"""

from __future__ import annotations

from typing import List, Sequence, Tuple


def _escape_pdf_text(value: str) -> bytes:
    """Escapes a string for use inside a PDF literal string operand."""
    text = value.encode("latin-1", errors="replace").decode("latin-1")
    text = text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")
    return text.encode("latin-1", errors="replace")


def build_text_pdf(
    lines: Sequence[Tuple[str, int, bool]],
    *,
    title: str = "Document",
    page_width: int = 612,
    page_height: int = 792,
) -> bytes:
    """Builds a single page PDF containing left-aligned text lines.

    Args:
        lines: sequence of ``(text, font_size, bold)`` tuples rendered top-down.
        title: document title stored in PDF metadata.
        page_width: page width in points.
        page_height: page height in points.

    Returns:
        Raw PDF bytes beginning with the ``%PDF-`` signature.
    """
    left_margin = 56
    # Leave room for a footer.
    y = page_height - 72
    content_parts: List[bytes] = []
    for text, size, bold in lines:
        if y < 72:
            break
        font = b"/F2" if bold else b"/F1"
        content_parts.append(
            b"BT " + font + b" " + str(int(size)).encode() + b" Tf "
            + str(left_margin).encode() + b" " + str(int(y)).encode() + b" Td ("
            + _escape_pdf_text(text) + b") Tj ET"
        )
        y -= int(size * 1.6)
    content_stream = b"\n".join(content_parts) + b"\n"

    objects: List[bytes] = []
    objects.append(b"<< /Type /Catalog /Pages 2 0 R >>")
    objects.append(b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>")
    objects.append(
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 "
        + str(page_width).encode() + b" " + str(page_height).encode()
        + b"] /Resources << /Font << /F1 << /Type /Font /Subtype /Type1 "
        + b"/BaseFont /Helvetica /Encoding /WinAnsiEncoding >> "
        + b"/F2 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold "
        + b"/Encoding /WinAnsiEncoding >> >> >> /Contents 4 0 R >>"
    )
    objects.append(
        b"<< /Length " + str(len(content_stream)).encode() + b" >>\nstream\n"
        + content_stream + b"endstream"
    )

    header = b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n"
    out = bytearray(header)
    offsets: List[int] = []
    for index, body in enumerate(objects, start=1):
        offsets.append(len(out))
        out += str(index).encode() + b" 0 obj\n" + body + b"\nendobj\n"

    xref_offset = len(out)
    count = len(objects) + 1
    out += b"xref\n0 " + str(count).encode() + b"\n"
    out += b"0000000000 65535 f \n"
    for offset in offsets:
        out += f"{offset:010d} 00000 n \n".encode()

    info_title = _escape_pdf_text(title)
    out += (
        b"trailer\n<< /Size " + str(count).encode() + b" /Root 1 0 R /Info "
        + b"<< /Title (" + info_title + b") /Producer (Origin PG Management) >> >>\n"
    )
    out += b"startxref\n" + str(xref_offset).encode() + b"\n%%EOF\n"
    return bytes(out)


def build_receipt_pdf(invoice, *, payments: Sequence = ()) -> bytes:
    """Builds a payment/invoice receipt PDF from an invoice detail payload."""
    total = getattr(invoice, "total_amount", None)
    paid = getattr(invoice, "paid_amount", None)
    balance = getattr(invoice, "balance_amount", None)

    lines: List[Tuple[str, int, bool]] = [
        ("Origin PG Management", 18, True),
        ("Payment Receipt", 14, True),
        ("", 8, False),
        (f"Invoice Number: {invoice.invoice_number}", 11, False),
        (f"Invoice Type: {invoice.invoice_type}", 11, False),
        (f"Billing Month: {invoice.billing_month}", 11, False),
        (f"Issue Date: {invoice.issue_date}", 11, False),
        (f"Due Date: {invoice.due_date}", 11, False),
        ("", 8, False),
        (f"Resident: {invoice.resident_name or '-'}", 11, False),
        (f"Property: {invoice.property_name or '-'}", 11, False),
        (
            "Room / Bed: "
            f"{invoice.room_number or '-'} / {invoice.bed_number or '-'}",
            11,
            False,
        ),
        ("", 8, False),
        (f"Total Amount: {total}", 11, False),
        (f"Amount Paid: {paid}", 11, False),
        (f"Balance Due: {balance}", 11, False),
        (f"Invoice Status: {invoice.status}", 11, False),
    ]

    if payments:
        lines.append(("", 8, False))
        lines.append(("Payments Received", 12, True))
        for payment in payments:
            lines.append(
                (
                    f"- {payment.payment_number} | {payment.payment_date} | "
                    f"{payment.payment_method} | {payment.amount} | {payment.status}",
                    10,
                    False,
                )
            )

    lines.append(("", 8, False))
    lines.append(("This is a system generated receipt.", 9, False))

    return build_text_pdf(lines, title=f"Receipt {invoice.invoice_number}")
