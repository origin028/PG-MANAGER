"""Minimal dependency-free PDF generation utilities for receipts and invoices.

Produces standards-compliant PDF 1.4 documents (with correct cross-reference table offsets)
without requiring heavy external dependencies such as ReportLab or WeasyPrint.
"""

from __future__ import annotations

import uuid
from typing import List, Optional, Sequence, Tuple


def _escape_pdf_text(value: str) -> bytes:
    """Escapes a string for use inside a PDF literal string operand."""
    text = str(value).encode("latin-1", errors="replace").decode("latin-1")
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
        lines: sequence of (text, font_size, bold) tuples rendered top-down.
        title: document title stored in PDF metadata.
        page_width: page width in points (standard US Letter = 612x792).
        page_height: page height in points.

    Returns:
        Raw PDF bytes beginning with the %PDF-1.4 signature.
    """
    left_margin = 56
    y = page_height - 72
    content_parts: List[bytes] = []

    for text, size, bold in lines:
        if y < 72:
            break
        font = b"/F2" if bold else b"/F1"
        if text:  # non-empty line
            content_parts.append(
                b"BT " + font + b" " + str(int(size)).encode() + b" Tf "
                + str(left_margin).encode() + b" " + str(int(y)).encode() + b" Td ("
                + _escape_pdf_text(text) + b") Tj ET"
            )
        y -= int(size * 1.5) if size > 10 else int(size * 1.8)

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
        + b"<< /Title (" + info_title + b") /Producer (Origin PG Management System) >> >>\n"
    )
    out += b"startxref\n" + str(xref_offset).encode() + b"\n%%EOF\n"
    return bytes(out)


def build_receipt_pdf(
    receipt_number: str,
    amount: float,
    payment_mode: str,
    payment_number: str,
    invoice_number: str,
    resident_name: str,
    property_name: str,
    issued_at: str,
    transaction_ref: Optional[str] = None,
    billing_month: Optional[str] = None,
) -> bytes:
    """Builds a formatted official payment receipt PDF."""
    lines: List[Tuple[str, int, bool]] = [
        ("SMART GROUP PG'S — OFFICIAL PAYMENT RECEIPT", 16, True),
        ("--------------------------------------------------------------------------------", 10, False),
        ("", 8, False),
        (f"Receipt Number:       {receipt_number}", 12, True),
        (f"Date & Time:          {issued_at}", 10, False),
        (f"Property:             {property_name}", 11, False),
        (f"Resident Name:        {resident_name}", 11, False),
        ("", 8, False),
        ("PAYMENT DETAILS", 13, True),
        ("--------------------------------------------------------------------------------", 10, False),
        (f"Invoice Number:       {invoice_number}", 11, False),
        (f"Billing Cycle:        {billing_month or 'N/A'}", 11, False),
        (f"Payment Mode:         {payment_mode}", 11, False),
        (f"Payment Number:       {payment_number}", 11, False),
        (f"Transaction / UTR:    {transaction_ref or 'Verified System Credit'}", 11, False),
        (f"Amount Paid:          INR {amount:,.2f}", 13, True),
        ("", 8, False),
        ("STATUS: PAID / SETTLED", 12, True),
        ("", 8, False),
        ("--------------------------------------------------------------------------------", 10, False),
        ("This is a computer-generated digital receipt and requires no physical signature.", 9, False),
        ("For questions regarding this receipt, please contact your Property Manager.", 9, False),
    ]

    return build_text_pdf(lines, title=f"Receipt {receipt_number}")
