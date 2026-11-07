import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor, fireEvent } from '@testing-library/react';
import { MemoryRouter, Routes, Route } from 'react-router-dom';
import { ResidentCheckoutPage } from '../pages/ResidentCheckoutPage';
import * as razorpayUtil from '../utils/razorpay';

describe('ResidentCheckoutPage UI Integration Tests', () => {
  const mockCheckoutData = {
    property_name: 'Origin Luxury PG',
    room_number: '302',
    invoice_number: 'INV-2026-0042',
    billing_month: '2026-10',
    amount: '12500.00',
    amount_paise: 1250000,
    currency: 'INR',
    gateway_order_id: 'order_test_998877',
    key_id: 'rzp_test_public_123',
    expires_at: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
  };

  beforeEach(() => {
    vi.restoreAllMocks();
  });

  const renderWithRoute = (token: string) => {
    return render(
      <MemoryRouter initialEntries={[`/pay/${token}`]}>
        <Routes>
          <Route path="/pay/:token" element={<ResidentCheckoutPage />} />
        </Routes>
      </MemoryRouter>
    );
  };

  it('1. Displays checkout details successfully', async () => {
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({
        success: true,
        data: mockCheckoutData,
      }),
    } as any);

    renderWithRoute('valid_secure_token_123');

    await waitFor(() => {
      expect(screen.getByText('Origin Luxury PG')).toBeDefined();
      expect(screen.getByText('302')).toBeDefined();
      expect(screen.getByText('INV-2026-0042')).toBeDefined();
      expect(screen.getByText('2026-10')).toBeDefined();
      expect(screen.getByText(/Pay ₹12,500\.00/i)).toBeDefined();
    });
  });

  it('2. Renders expired link state on 409 Expired error', async () => {
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok: false,
      status: 409,
      json: async () => ({
        success: false,
        error: {
          code: 'CONFLICT',
          message: 'Payment link has expired.',
        },
      }),
    } as any);

    renderWithRoute('expired_token_123');

    await waitFor(() => {
      expect(screen.getByText('Payment Link Expired')).toBeDefined();
      expect(screen.getByText(/Payment link has expired/i)).toBeDefined();
    });
  });

  it('3. Renders already paid state on 409 Already Paid error', async () => {
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok: false,
      status: 409,
      json: async () => ({
        success: false,
        error: {
          code: 'CONFLICT',
          message: 'Invoice payment has already been completed.',
        },
      }),
    } as any);

    renderWithRoute('already_paid_token');

    await waitFor(() => {
      expect(screen.getByText('Payment Already Received')).toBeDefined();
    });
  });

  it('4. Renders invalid link state on 404 error', async () => {
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok: false,
      status: 404,
      json: async () => ({
        success: false,
        error: {
          code: 'NOT_FOUND',
          message: 'Payment link not found or invalid.',
        },
      }),
    } as any);

    renderWithRoute('unknown_token_999');

    await waitFor(() => {
      expect(screen.getByText('Invalid Payment Link')).toBeDefined();
    });
  });

  it('5. Handles network failure gracefully with retry button', async () => {
    globalThis.fetch = vi.fn().mockRejectedValue(new Error('Network offline'));

    renderWithRoute('net_fail_token');

    await waitFor(() => {
      expect(screen.getByText('Payment Unavailable')).toBeDefined();
      expect(screen.getByText(/Unable to connect to payment server/i)).toBeDefined();
      expect(screen.getByRole('button', { name: /retry/i })).toBeDefined();
    });
  });

  it('6. Launches Razorpay modal and prevents multiple clicks', async () => {
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({
        success: true,
        data: mockCheckoutData,
      }),
    } as any);

    const mockOpen = vi.fn();
    let capturedOptions: any = null;

    window.Razorpay = vi.fn().mockImplementation((options) => {
      capturedOptions = options;
      return {
        open: mockOpen,
        on: vi.fn(),
      };
    }) as any;

    vi.spyOn(razorpayUtil, 'loadRazorpayScript').mockResolvedValue(true);

    renderWithRoute('pay_token_click');

    await waitFor(() => {
      expect(screen.getByTestId('pay-now-button')).toBeDefined();
    });

    const payButton = screen.getByTestId('pay-now-button');

    // First click
    fireEvent.click(payButton);

    // Rapid second click (should be ignored due to lock)
    fireEvent.click(payButton);

    await waitFor(() => {
      expect(mockOpen).toHaveBeenCalledTimes(1);
    });

    expect(capturedOptions.key).toBe('rzp_test_public_123');
    expect(capturedOptions.order_id).toBe('order_test_998877');
    expect(capturedOptions.amount).toBe(1250000);
  });

  it('7. Displays pending verification state on Razorpay client completion callback', async () => {
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({
        success: true,
        data: mockCheckoutData,
      }),
    } as any);

    window.Razorpay = vi.fn().mockImplementation((options) => {
      return {
        open: () => {
          // Trigger checkout success callback
          options.handler({
            razorpay_payment_id: 'pay_client_cb_123',
            razorpay_order_id: 'order_test_998877',
            razorpay_signature: 'sig_mock',
          });
        },
        on: vi.fn(),
      };
    }) as any;

    vi.spyOn(razorpayUtil, 'loadRazorpayScript').mockResolvedValue(true);

    renderWithRoute('verify_callback_token');

    await waitFor(() => {
      expect(screen.getByTestId('pay-now-button')).toBeDefined();
    });

    fireEvent.click(screen.getByTestId('pay-now-button'));

    // Verify UI switches to pending-verification status
    await waitFor(() => {
      expect(screen.getByText('Payment Verification in Progress')).toBeDefined();
      expect(screen.getByText(/Our system is verifying the webhook notification/i)).toBeDefined();
      expect(screen.getByRole('button', { name: /Refresh Status/i })).toBeDefined();
    });
  });

  it('8. Uses relative API URL when VITE_API_BASE_URL is not set', async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({
        success: true,
        data: mockCheckoutData,
      }),
    } as any);
    globalThis.fetch = fetchMock;

    renderWithRoute('token_relative_test');

    await waitFor(() => {
      expect(fetchMock).toHaveBeenCalled();
    });

    // When VITE_API_BASE_URL is empty, request URL starts with /api/v1/...
    const requestUrl = fetchMock.mock.calls[0][0];
    expect(requestUrl).toBe('/api/v1/payments/links/token_relative_test/checkout');
  });
});
