from typing import Optional
from app.integrations.email import EmailProvider, get_email_provider


class EmailService:
    def __init__(self, provider: Optional[EmailProvider] = None):
        self.provider = provider or get_email_provider()

    @staticmethod
    def _render_email_html(
        title: str,
        greeting: str,
        purpose_desc: str,
        otp: str,
        security_warning: str,
        footer_note: str,
    ) -> str:
        """Renders responsive branded HTML email template for SMART GROUP PG'S OTP delivery."""
        return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{title}</title>
</head>
<body style="margin: 0; padding: 0; background-color: #f1f5f9; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background-color: #f1f5f9; padding: 40px 15px;">
    <tr>
      <td align="center">
        <table role="presentation" width="100%" style="max-width: 540px; background-color: #ffffff; border-radius: 12px; overflow: hidden; box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06); border: 1px solid #e2e8f0;" cellspacing="0" cellpadding="0">
          <tr>
            <td style="background: linear-gradient(135deg, #1e3a8a 0%, #2563eb 100%); padding: 30px 24px; text-align: center;">
              <h1 style="margin: 0; color: #ffffff; font-size: 22px; font-weight: 700; letter-spacing: 0.5px;">SMART GROUP PG'S</h1>
              <p style="margin: 6px 0 0 0; color: #bfdbfe; font-size: 13px; font-weight: 500; text-transform: uppercase; letter-spacing: 1px;">Smart Living &amp; Residence Management</p>
            </td>
          </tr>
          <tr>
            <td style="padding: 32px 28px;">
              <h2 style="margin: 0 0 16px 0; color: #0f172a; font-size: 18px; font-weight: 600;">{title}</h2>
              <p style="margin: 0 0 14px 0; color: #334155; font-size: 15px; line-height: 1.5;">{greeting}</p>
              <p style="margin: 0 0 24px 0; color: #475569; font-size: 14px; line-height: 1.6;">{purpose_desc}</p>
              <div style="background-color: #f8fafc; border: 2px dashed #93c5fd; border-radius: 8px; padding: 24px 16px; text-align: center; margin: 0 0 24px 0;">
                <div style="font-size: 11px; text-transform: uppercase; letter-spacing: 1.5px; color: #64748b; margin-bottom: 8px; font-weight: 600;">Your Verification Code</div>
                <div style="font-size: 38px; font-weight: 800; letter-spacing: 8px; color: #1e3a8a; font-family: 'Courier New', Courier, monospace;">{otp}</div>
                <div style="margin-top: 10px; font-size: 13px; font-weight: 600; color: #dc2626;">⏱ Valid for 10 minutes only</div>
              </div>
              <div style="background-color: #fef2f2; border-left: 4px solid #ef4444; border-radius: 4px; padding: 14px 16px; margin: 0 0 24px 0;">
                <p style="margin: 0; color: #991b1b; font-size: 13px; line-height: 1.5; font-weight: 500;">
                  <strong>⚠️ Security Warning:</strong> {security_warning}
                </p>
              </div>
              <p style="margin: 0; color: #64748b; font-size: 13px; line-height: 1.5;">{footer_note}</p>
            </td>
          </tr>
          <tr>
            <td style="background-color: #f8fafc; border-top: 1px solid #e2e8f0; padding: 20px 24px; text-align: center;">
              <p style="margin: 0 0 4px 0; color: #64748b; font-size: 12px; font-weight: 500;">SMART GROUP PG'S &bull; Origin PG Living</p>
              <p style="margin: 0; color: #94a3b8; font-size: 11px;">This is an automated system notification. Please do not reply to this email.</p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>"""

    def send_registration_otp(
        self,
        to_email: str,
        otp: str,
        full_name: Optional[str] = None,
    ) -> bool:
        """Dispatches 6-digit registration verification OTP via email."""
        name_greeting = f"Hello {full_name}," if full_name else "Hello,"
        title = "Resident Registration Verification Code"
        subject = "SMART GROUP PG'S — Resident Registration Verification Code"
        purpose_desc = (
            "Thank you for registering with SMART GROUP PG'S. "
            "Please use the one-time verification code (OTP) below to verify your email address and submit your registration application."
        )
        security_warning = (
            "Never share this OTP with anyone, including PG managers, caretakers, or staff. "
            "SMART GROUP PG'S team members will NEVER ask for your verification code."
        )
        footer_note = "If you did not initiate this resident registration, please disregard this email safely."

        body_text = (
            f"=================================================================\n"
            f"                    SMART GROUP PG'S\n"
            f"           Smart Living & Residence Management\n"
            f"=================================================================\n\n"
            f"{title}\n\n"
            f"{name_greeting}\n\n"
            f"{purpose_desc}\n\n"
            f"-----------------------------------------------------------------\n"
            f"YOUR VERIFICATION CODE:  {otp}\n"
            f"-----------------------------------------------------------------\n"
            f"(Valid for 10 minutes only)\n\n"
            f"SECURITY WARNING:\n"
            f"{security_warning}\n\n"
            f"{footer_note}\n\n"
            f"-----------------------------------------------------------------\n"
            f"SMART GROUP PG'S | Origin PG Living\n"
            f"This is an automated system notification. Please do not reply.\n"
            f"=================================================================\n"
        )

        body_html = self._render_email_html(
            title=title,
            greeting=name_greeting,
            purpose_desc=purpose_desc,
            otp=otp,
            security_warning=security_warning,
            footer_note=footer_note,
        )

        return self.provider.send_email(
            to_email=to_email,
            subject=subject,
            body_text=body_text,
            body_html=body_html,
        )

    def send_login_otp(
        self,
        to_email: str,
        otp: str,
        full_name: Optional[str] = None,
    ) -> bool:
        """Dispatches 6-digit mobile login OTP via email."""
        name_greeting = f"Hello {full_name}," if full_name else "Hello,"
        title = "Resident Login Verification Code"
        subject = "SMART GROUP PG'S — Resident Login Verification Code"
        purpose_desc = (
            "A login request was initiated for your SMART GROUP PG'S resident account. "
            "Please use the one-time verification code (OTP) below to securely authenticate into your resident portal."
        )
        security_warning = (
            "Never share this OTP with anyone, including PG managers, caretakers, or staff. "
            "SMART GROUP PG'S team members will NEVER ask for your verification code."
        )
        footer_note = (
            "If you did not request this verification code, please secure your account immediately "
            "and inform your PG administrator."
        )

        body_text = (
            f"=================================================================\n"
            f"                    SMART GROUP PG'S\n"
            f"           Smart Living & Residence Management\n"
            f"=================================================================\n\n"
            f"{title}\n\n"
            f"{name_greeting}\n\n"
            f"{purpose_desc}\n\n"
            f"-----------------------------------------------------------------\n"
            f"YOUR VERIFICATION CODE:  {otp}\n"
            f"-----------------------------------------------------------------\n"
            f"(Valid for 10 minutes only)\n\n"
            f"SECURITY WARNING:\n"
            f"{security_warning}\n\n"
            f"{footer_note}\n\n"
            f"-----------------------------------------------------------------\n"
            f"SMART GROUP PG'S | Origin PG Living\n"
            f"This is an automated system notification. Please do not reply.\n"
            f"=================================================================\n"
        )

        body_html = self._render_email_html(
            title=title,
            greeting=name_greeting,
            purpose_desc=purpose_desc,
            otp=otp,
            security_warning=security_warning,
            footer_note=footer_note,
        )

        return self.provider.send_email(
            to_email=to_email,
            subject=subject,
            body_text=body_text,
            body_html=body_html,
        )

    def send_admin_registration_super_key(
        self,
        to_email: str,
        super_key: str,
        business_name: Optional[str] = None,
    ) -> bool:
        """Dispatches 6-digit Admin Registration Super Key via email."""
        name_greeting = f"Hello Administrator ({business_name})," if business_name else "Hello Administrator,"
        title = "Admin Registration Super Key"
        subject = "SMART GROUP PG'S — Admin Registration Super Key"
        purpose_desc = (
            "Thank you for registering your property business on SMART GROUP PG'S Admin & Owner Portal. "
            "Please use the 6-digit Super Key below to verify your administrative ownership and activate your organization account."
        )
        security_warning = (
            "This Super Key grants full administrative control over properties, tenant records, and financials. "
            "Never disclose this code to anyone. Our support staff will never ask for your Super Key."
        )
        footer_note = "If you did not register this business account, please contact security immediately."

        body_text = (
            f"=================================================================\n"
            f"                    SMART GROUP PG'S\n"
            f"           Admin & Owner Management Console\n"
            f"=================================================================\n\n"
            f"{title}\n\n"
            f"{name_greeting}\n\n"
            f"{purpose_desc}\n\n"
            f"-----------------------------------------------------------------\n"
            f"YOUR SUPER KEY:  {super_key}\n"
            f"-----------------------------------------------------------------\n"
            f"(Valid for 10 minutes only)\n\n"
            f"SECURITY WARNING:\n"
            f"{security_warning}\n\n"
            f"{footer_note}\n\n"
            f"-----------------------------------------------------------------\n"
            f"SMART GROUP PG'S | Origin PG Living\n"
            f"This is an automated system notification. Please do not reply.\n"
            f"=================================================================\n"
        )

        body_html = self._render_email_html(
            title=title,
            greeting=name_greeting,
            purpose_desc=purpose_desc,
            otp=super_key,
            security_warning=security_warning,
            footer_note=footer_note,
        )

        return self.provider.send_email(
            to_email=to_email,
            subject=subject,
            body_text=body_text,
            body_html=body_html,
        )

    def send_admin_login_super_key(
        self,
        to_email: str,
        super_key: str,
        admin_name: Optional[str] = None,
    ) -> bool:
        """Dispatches 6-digit Admin Login Super Key 2FA via email."""
        name_greeting = f"Hello {admin_name}," if admin_name else "Hello Administrator,"
        title = "Admin Login 2FA — Super Key"
        subject = "SMART GROUP PG'S — Admin Login 2FA Super Key"
        purpose_desc = (
            "A login request was initiated for your SMART GROUP PG'S Admin / Owner account. "
            "Please enter the mandatory two-factor authentication Super Key below to complete your sign-in."
        )
        security_warning = (
            "This Super Key authorizes administrative session access to your PG management system. "
            "Never share this code with anyone. If you did not attempt to log in, please reset your password immediately."
        )
        footer_note = "If you did not request this login verification, your password may be compromised."

        body_text = (
            f"=================================================================\n"
            f"                    SMART GROUP PG'S\n"
            f"           Admin & Owner Management Console\n"
            f"=================================================================\n\n"
            f"{title}\n\n"
            f"{name_greeting}\n\n"
            f"{purpose_desc}\n\n"
            f"-----------------------------------------------------------------\n"
            f"YOUR SUPER KEY 2FA:  {super_key}\n"
            f"-----------------------------------------------------------------\n"
            f"(Valid for 10 minutes only)\n\n"
            f"SECURITY WARNING:\n"
            f"{security_warning}\n\n"
            f"{footer_note}\n\n"
            f"-----------------------------------------------------------------\n"
            f"SMART GROUP PG'S | Origin PG Living\n"
            f"This is an automated system notification. Please do not reply.\n"
            f"=================================================================\n"
        )

        body_html = self._render_email_html(
            title=title,
            greeting=name_greeting,
            purpose_desc=purpose_desc,
            otp=super_key,
            security_warning=security_warning,
            footer_note=footer_note,
        )

        return self.provider.send_email(
            to_email=to_email,
            subject=subject,
            body_text=body_text,
            body_html=body_html,
        )


    def send_resident_approval_notification(
        self,
        to_email: str,
        resident_name: str,
        property_name: str,
        room_number: Optional[str] = None,
        bed_number: Optional[str] = None,
    ) -> bool:
        """Dispatches an email notification when a resident's registration is approved."""
        name_greeting = f"Hello {resident_name},"
        title = "Registration Approved!"
        subject = f"Registration Approved — Welcome to {property_name}!"
        room_info = f"Room {room_number}" if room_number else "Your room allocation is confirmed."
        if bed_number:
            room_info += f", Bed {bed_number}"
        purpose_desc = (
            f"Great news! Your registration application for {property_name} has been approved by the property administrator. "
            f"{room_info} You can now log in to the Resident Mobile App using your registered phone number and email OTP."
        )
        security_warning = (
            "Open the Resident Mobile App, enter your registered phone number, and log in using the email OTP sent to your inbox."
        )
        footer_note = "If you have any questions, please contact the PG management team."

        body_text = (
            f"=================================================================\n"
            f"                    {property_name}\n"
            f"=================================================================\n\n"
            f"{title}\n\n"
            f"{name_greeting}\n\n"
            f"{purpose_desc}\n\n"
            f"NEXT STEPS:\n"
            f"{security_warning}\n\n"
            f"{footer_note}\n\n"
            f"=================================================================\n"
        )
        body_html = self._render_email_html(
            title=title,
            greeting=name_greeting,
            purpose_desc=purpose_desc,
            otp="APPROVED",
            security_warning=security_warning,
            footer_note=footer_note,
        )
        return self.provider.send_email(
            to_email=to_email,
            subject=subject,
            body_text=body_text,
            body_html=body_html,
        )

    def send_resident_rejection_notification(
        self,
        to_email: str,
        resident_name: str,
        property_name: str,
        reason: str,
    ) -> bool:
        """Dispatches an email notification when a resident's registration is rejected."""
        name_greeting = f"Hello {resident_name},"
        title = "Registration Update"
        subject = f"Registration Update — {property_name}"
        purpose_desc = (
            f"Thank you for your interest in {property_name}. After review, your registration could not be approved at this time.\n\n"
            f"Reason: {reason}"
        )
        security_warning = (
            "If you believe this decision was made in error or would like to submit corrected documentation, "
            "please contact the property administrator."
        )
        footer_note = "PG Management Administration"

        body_text = (
            f"=================================================================\n"
            f"                    {property_name}\n"
            f"=================================================================\n\n"
            f"{title}\n\n"
            f"{name_greeting}\n\n"
            f"{purpose_desc}\n\n"
            f"NOTE:\n"
            f"{security_warning}\n\n"
            f"{footer_note}\n\n"
            f"=================================================================\n"
        )
        body_html = self._render_email_html(
            title=title,
            greeting=name_greeting,
            purpose_desc=purpose_desc,
            otp="REJECTED",
            security_warning=security_warning,
            footer_note=footer_note,
        )
        return self.provider.send_email(
            to_email=to_email,
            subject=subject,
            body_text=body_text,
            body_html=body_html,
        )
